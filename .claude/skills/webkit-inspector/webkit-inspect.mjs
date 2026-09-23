#!/usr/bin/env node
// Drive the kiosk's WebKit remote inspector from the workstation, over an SSH tunnel.
//
//   node webkit-inspect.mjs eval '<js>'      Runtime.evaluate, print the value
//   node webkit-inspect.mjs gc <seconds>     log every GC (full/eden) with wall-clock gaps
//   node webkit-inspect.mjs census [topN]     heap object census: count + bytes per class
//   node webkit-inspect.mjs diff <seconds>    census, wait, census again -> what GREW (names churn)
//
// Port defaults to 2999; override with WEBKIT_INSPECT_PORT. Point it at a LOCAL forwarded port:
//   ssh -L 2999:127.0.0.1:2999 -N root@<board>
//
// This is the instrument in-page JS cannot be on this board: performance.memory is absent,
// FinalizationRegistry callbacks never fire under a saturated core, and JSC_* logging is compiled
// out. The inspector reports GC type/timing and the heap census straight from the engine. It DOES
// perturb frame timing, so use the in-page probes (measure-first) for fps/stall rate and this only
// for GC and heap ground truth. See SKILL.md for enabling the server (the HTTP-vs-WS gotcha) and the
// protocol. Requires Node >= 20 (global fetch + WebSocket).
const PORT = Number(process.env.WEBKIT_INSPECT_PORT || 2999);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The target list is HTML at /, NOT JSON at /json/list, and the WebSocket path is embedded in the
// Inspect button as "ws=' + window.location.host + '<path>'".
async function targetWs() {
  const res = await fetch(`http://127.0.0.1:${PORT}/`, { signal: AbortSignal.timeout(10000) });
  if (!res.ok) throw new Error(`/ -> HTTP ${res.status} (is WEBKIT_INSPECTOR_HTTP_SERVER set, not the WS-only WEBKIT_INSPECTOR_SERVER? see SKILL.md)`);
  const html = await res.text();
  const m = html.match(/ws=' \+ window\.location\.host \+ '([^']+)'/);
  if (!m) throw new Error(`no socket path in target list: ${html.slice(0, 300)}`);
  return `ws://127.0.0.1:${PORT}${m[1]}`;
}

// Every inspector call is wrapped in Target.sendMessageToTarget and every reply/event arrives inside
// a Target.dispatchMessageFromTarget event, so ids and event methods are read on the INNER message.
function connect(url) {
  const ws = new WebSocket(url);
  const pending = new Map();
  const listeners = [];
  let next = 1, targetId = null, onTarget;
  const gotTarget = new Promise((r) => (onTarget = r));
  const ready = new Promise((ok, fail) => {
    ws.addEventListener('open', () => ok());
    ws.addEventListener('error', (e) => fail(new Error(`ws error: ${e.message ?? e}`)));
  });
  const settle = (inner) => {
    const p = pending.get(inner.id);
    if (p) { pending.delete(inner.id); inner.error ? p.fail(new Error(JSON.stringify(inner.error))) : p.ok(inner.result); }
  };
  ws.addEventListener('message', (ev) => {
    let msg; try { msg = JSON.parse(ev.data); } catch { return; }
    if (msg.method === 'Target.targetCreated') { targetId = msg.params?.targetInfo?.targetId; onTarget(targetId); return; }
    if (msg.method === 'Target.dispatchMessageFromTarget') {
      let inner; try { inner = JSON.parse(msg.params.message); } catch { return; }
      if (inner.id !== undefined) settle(inner);
      else if (inner.method) listeners.forEach((fn) => fn(inner));
      return;
    }
    if (msg.id !== undefined) settle(msg);
  });
  const send = (method, params = {}) => new Promise((ok, fail) => {
    const id = next++;
    pending.set(id, { ok, fail });
    ws.send(JSON.stringify({ id: 100000 + id, method: 'Target.sendMessageToTarget',
      params: { targetId, message: JSON.stringify({ id, method, params }) } }));
    setTimeout(() => { if (pending.delete(id)) fail(new Error(`${method} timed out`)); }, 60000);
  });
  return { ready, gotTarget, send, on: (fn) => listeners.push(fn), close: () => ws.close(), tid: () => targetId };
}

async function evaluate(c, expression) {
  const r = await c.send('Runtime.evaluate', { expression, returnByValue: true });
  if (r.wasThrown) throw new Error(`threw: ${JSON.stringify(r.result)}`);
  return r.result?.value;
}

// HeapSnapshot v2: nodes is a flat array of 4-int records [id, size, classNameIndex, flags];
// className = nodeClassNames[classNameIndex]. Census = count + total bytes per class.
function census(data) {
  const { nodes, nodeClassNames } = data;
  const cen = new Map();
  for (let i = 0; i < nodes.length; i += 4) {
    const cls = nodeClassNames[nodes[i + 2]];
    const size = nodes[i + 1];
    const e = cen.get(cls) || { count: 0, size: 0 };
    e.count++; e.size += size; cen.set(cls, e);
  }
  return cen;
}
async function snapshot(c) {
  await c.send('Heap.gc').catch(() => {});
  const snap = await c.send('Heap.snapshot');
  const raw = snap.snapshotData ?? snap.snapshot ?? snap;
  return census(typeof raw === 'string' ? JSON.parse(raw) : raw);
}

async function main() {
  const [mode, arg] = process.argv.slice(2);
  const ws = await targetWs();
  const c = connect(ws);
  await c.ready;
  await Promise.race([c.gotTarget, sleep(5000)]);
  if (!c.tid()) throw new Error('no targetId announced by the inspector');
  console.error(`connected tid=${c.tid()}`);

  if (mode === 'eval') {
    console.log(JSON.stringify(await evaluate(c, arg)));
  } else if (mode === 'gc') {
    const secs = Number(arg ?? 90);
    const t0 = performance.now();
    let lastFull = null;
    const rows = [];
    c.on((ev) => {
      if (ev.method !== 'Heap.garbageCollected') return;
      const type = ev.params.collection?.type ?? '?';
      const at = +((performance.now() - t0) / 1000).toFixed(2);   // engine timestamps read 0 here; use arrival
      let gap = '';
      if (type === 'full') { if (lastFull !== null) gap = ` gap=${(at - lastFull).toFixed(1)}s`; lastFull = at; }
      rows.push({ t: at, type });
      console.error(`GC ${type.padEnd(6)} t=${at}s${gap}`);
    });
    await c.send('Heap.enable');
    await c.send('Heap.startTracking');   // garbageCollected events only flow while tracking
    console.error(`tracking ${secs}s...`);
    await sleep(secs * 1000);
    await c.send('Heap.stopTracking').catch(() => {});
    const full = rows.filter((r) => r.type === 'full');
    console.log(JSON.stringify({ seconds: secs, total: rows.length, full: full.length,
      eden: rows.length - full.length, fullTimes: full.map((r) => r.t) }));
  } else if (mode === 'census') {
    const topN = Number(arg ?? 15);
    await c.send('Heap.enable');
    const cen = [...(await snapshot(c)).entries()].sort((a, b) => b[1].size - a[1].size);
    console.log(`${'bytes'.padStart(10)} ${'count'.padStart(7)}  class`);
    for (const [cls, { count, size }] of cen.slice(0, topN)) console.log(`${String(size).padStart(10)} ${String(count).padStart(7)}  ${cls}`);
  } else if (mode === 'diff') {
    const secs = Number(arg ?? 30);
    await c.send('Heap.enable');
    const a = await snapshot(c);
    console.error(`baseline snapshot; waiting ${secs}s...`);
    await sleep(secs * 1000);
    const b = await snapshot(c);   // snapshot() forces a GC first, so survivors only = promoted growth
    const rows = [];
    for (const [cls, e] of b) {
      const was = a.get(cls) || { count: 0, size: 0 };
      rows.push({ cls, dCount: e.count - was.count, dSize: e.size - was.size });
    }
    rows.sort((x, y) => y.dSize - x.dSize);
    console.log(`ΔThe classes that GREW over ${secs}s (survived a forced GC each snapshot = promoted):`);
    console.log(`${'Δbytes'.padStart(10)} ${'Δcount'.padStart(7)}  class`);
    for (const r of rows.slice(0, 15)) if (r.dSize !== 0 || r.dCount !== 0) console.log(`${String(r.dSize).padStart(10)} ${String(r.dCount).padStart(7)}  ${r.cls}`);
  } else {
    console.error('usage: webkit-inspect.mjs eval <js> | gc [seconds] | census [topN] | diff [seconds]');
    process.exitCode = 2;
  }
  c.close();
}
main().then(() => process.exit(process.exitCode ?? 0)).catch((e) => { console.error(e.message); process.exit(1); });
