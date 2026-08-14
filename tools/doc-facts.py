#!/usr/bin/env python3
"""Extract fact-atoms from Markdown so a restructure can be proved lossless.

    doc-facts.py snapshot <dir> <out.json>
    doc-facts.py diff <before.json> <after.json>

`diff` exits non-zero if any atom present in `before` is absent from `after`.
Atoms are content-addressed, not location-addressed, so moving a fact between
files is silent and losing it is loud -- which is the point during a restructure.
"""
import json
import re
import sys
from pathlib import Path

# Numbers carrying a unit are the ones that cost device time to obtain.
UNIT = (r'(?:MB/s|MiB/s|GB/s|Mb/s|kB/s|B/s|MiB|GiB|KiB|MB|GB|kB|bytes|byte|'
        r'dBm|°C|ms|s\b|MHz|GHz|x\b|×|%|blocks|sectors|packages|connections)')
PATTERNS = {
    'measure': re.compile(r'(?<![\w.])(\d[\d,._]*)\s*(' + UNIT + r')', re.I),
    'version': re.compile(r'\b(?:v|version\s+)?(\d+\.\d+[\w.+~-]*)\b'),
    'path':    re.compile(r'(?<![\w`])(/(?:dev|opt|boot|etc|usr|var|home|sbin|bin|proc|tmp)/[\w./+-]*)'),
    'host':    re.compile(r'\b((?:[\w-]+\.)+(?:org|com|net|io|cn|se|uk)(?:/[\w./+-]*)?)'),
    'ipaddr':  re.compile(r'\b(\d{1,3}(?:\.\d{1,3}){3}(?:/\d{1,2})?)\b'),
    'hexid':   re.compile(r'\b(0x[0-9a-fA-F]{4,})\b'),
}
FENCE = re.compile(r'^\s*```')
CODESPAN = re.compile(r'`([^`\n]{2,120})`')


def atoms(text):
    """Yield (kind, normalized_value) for one document."""
    out = set()
    in_fence = False
    for line in text.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            s = line.strip()
            if s and not s.startswith('#'):
                out.add(('cmd', re.sub(r'\s+', ' ', s)))
            continue
        for span in CODESPAN.findall(line):
            out.add(('span', re.sub(r'\s+', ' ', span.strip())))
        for kind, pat in PATTERNS.items():
            for m in pat.finditer(line):
                if kind == 'measure':
                    num = m.group(1).replace(',', '').rstrip('.')
                    out.add((kind, f'{num} {m.group(2).lower()}'))
                else:
                    out.add((kind, m.group(1).rstrip('.,;:')))
    return out


def snapshot(root, out_path):
    index = {}
    for f in sorted(Path(root).rglob('*.md')):
        if '.git' in f.parts:
            continue
        rel = str(f.relative_to(root))
        for kind, val in atoms(f.read_text(encoding='utf-8', errors='replace')):
            index.setdefault(f'{kind}\t{val}', []).append(rel)
    Path(out_path).write_text(json.dumps(index, indent=0, sort_keys=True))
    kinds = {}
    for k in index:
        kinds[k.split('\t')[0]] = kinds.get(k.split('\t')[0], 0) + 1
    print(f'{len(index)} atoms from {len(list(Path(root).rglob("*.md")))} files -> {out_path}')
    for k in sorted(kinds):
        print(f'  {k:10s} {kinds[k]}')


def diff(before_path, after_path):
    before = json.loads(Path(before_path).read_text())
    after = json.loads(Path(after_path).read_text())
    lost = sorted(set(before) - set(after))
    added = sorted(set(after) - set(before))
    moved = [k for k in set(before) & set(after) if sorted(before[k]) != sorted(after[k])]

    # An atom that is a prefix/suffix of a surviving one was edited, not deleted --
    # appending `# comment` to a command is the common case. Reporting those as
    # losses is noise, and a gate people learn to ignore protects nothing.
    added_vals = [k.split('\t', 1)[1] for k in added]
    modified = []
    for k in list(lost):
        kind, val = k.split('\t', 1)
        if len(val) < 12:
            continue
        for av in added_vals:
            if (val in av or av in val) and min(len(val), len(av)) / max(len(val), len(av)) > 0.5:
                modified.append((k, av))
                lost.remove(k)
                break

    print(f'atoms: {len(before)} before, {len(after)} after')
    print(f'  lost     {len(lost)}\n  modified {len(modified)}\n  added    {len(added)}\n  moved    {len(moved)}')
    if modified and '-v' in sys.argv:
        print('\n--- MODIFIED (edited, not deleted) ---')
        for k, av in modified:
            print(f'  {k.split(chr(9))[1][:70]}\n    -> {av[:70]}')
    if lost:
        print('\n--- LOST (each needs a justification) ---')
        for k in lost:
            kind, val = k.split('\t', 1)
            print(f'  [{kind}] {val}\n      was in: {", ".join(sorted(set(before[k])))}')
    return 1 if lost else 0


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == 'snapshot':
        snapshot(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'diff':
        sys.exit(diff(sys.argv[2], sys.argv[3]))
    else:
        sys.exit(__doc__)
