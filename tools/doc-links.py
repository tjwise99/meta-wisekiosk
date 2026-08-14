#!/usr/bin/env python3
"""Validate Markdown cross-references: file targets, #anchors, and section-name refs.

    doc-links.py <dir>

Exits non-zero if any reference does not resolve. Three classes are checked:

  [text](path)          -> the file exists
  [text](path#anchor)   -> the file exists AND has a heading slugging to that anchor
  file.md SS"Heading"    -> the file exists AND carries that exact heading text

The third is what makes the "reference by name, never by number" convention
enforceable. Ordinal references ("open item 3") are reported separately as
warnings: they resolve today and silently repoint when a list is reordered,
which has already happened once in this repo.
"""
import re
import sys
from pathlib import Path

LINK = re.compile(r'(?<!\!)\[(?:[^\]]*)\]\(([^)]+)\)')
# Section-name reference: `file.md` §"Exact Heading"  (quotes may be typographic)
#
# The optional `](path)` group is load-bearing. Every section reference in this
# repo is written as a full Markdown link -- [`file.md`](file.md) §"Heading" --
# so the link tail sits between the filename and the §. Without that group the
# pattern never matched ANY reference in the tree, and this check silently
# validated nothing: a CLAUDE.md reference to a section that did not exist
# passed `just verify` on 2026-08-13.
_MARKER = re.compile(r'^(?:[\s#*_\u26d4\u26a0\u2705\u2b50\u2757\u2049\U0001F6A8]|`?\[[^\]]*\]`?)+')


def _stem(h):
    """Heading text with leading markers removed, for prefix matching against
    the readable stem prose actually cites. Strips emoji, heading punctuation
    and `[Yocto]` / `[SL16G]` card tags."""
    return _MARKER.sub('', h.strip()).strip()


SECREF = re.compile(r'`?([\w./-]+\.md)`?(?:\]\([^)]*\))?\s*§\s*["“]([^"”]+)["”]')
HEADING = re.compile(r'^(#{1,6})\s+(.*?)\s*#*$')
ORDINAL = re.compile(r'\b(?:open )?item\s+#?\d+\b|\bdecision\s+\d+\b|\bfault\s+#?\d+\b'
                     r'|\bstep[s]?\s+\d+(?:\s*[-–]\s*\d+)?\b', re.I)


def slug(text):
    """GitHub-flavoured heading slug."""
    s = re.sub(r'`|\*|_', '', text).strip().lower()
    s = re.sub(r'[^\w\s-]', '', s)
    return re.sub(r'\s+', '-', s)


def headings(path):
    out = []
    in_fence = False
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        if line.lstrip().startswith('```'):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEADING.match(line)
        if m:
            out.append(m.group(2))
    return out


def main(root):
    root = Path(root)
    files = sorted(p for p in root.rglob('*.md') if '.git' not in p.parts)
    # Key by resolved path: lookups below resolve, and a mismatch here silently
    # empties every heading list, which reads as "no such heading" on valid refs.
    head_cache = {p.resolve(): headings(p) for p in files}
    broken, warned, checked = [], [], 0

    for f in files:
        rel = f.relative_to(root)
        text = f.read_text(encoding='utf-8', errors='replace')

        for lineno, line in enumerate(text.splitlines(), 1):
            for target in LINK.findall(line):
                if target.startswith(('http://', 'https://', 'mailto:')):
                    continue
                checked += 1
                path_part, _, anchor = target.partition('#')
                if path_part:
                    tgt = (f.parent / path_part).resolve()
                    if not tgt.exists():
                        broken.append(f'{rel}:{lineno}  missing file -> {target}')
                        continue
                else:
                    tgt = f.resolve()
                if anchor:
                    known = {slug(h) for h in head_cache.get(tgt, headings(tgt))}
                    if slug(anchor) not in known:
                        broken.append(f'{rel}:{lineno}  no such heading -> {target}')

            for tgt_name, heading in SECREF.findall(line):
                checked += 1
                tgt = (f.parent / tgt_name).resolve()
                if not tgt.exists():
                    # The captured name comes from the LINK TEXT, which is often
                    # bare ("STATUS.md") while the real target is relative
                    # ("../STATUS.md"), so fall back to matching by filename.
                    tgt = next((p for p in files if p.name == Path(tgt_name).name), None)
                    # head_cache is keyed by RESOLVED paths; an unresolved
                    # fallback silently yields an empty heading list and fails
                    # every reference to that file for the wrong reason.
                    if tgt is not None:
                        tgt = tgt.resolve()
                if tgt is None:
                    broken.append(f'{rel}:{lineno}  section-ref to missing file -> {tgt_name}')
                # PREFIX match, after stripping leading markers. Headings here
                # carry emoji, dates and subtitles ("ROOT CAUSE, 2026-08-13: ...")
                # while prose cites the readable stem ("ROOT CAUSE"). Demanding
                # the full string would break every reference on any heading
                # edit; a prefix still catches the real error -- a reference to a
                # section that does not exist at all.
                elif not any(_stem(h).startswith(heading.strip()) for h in head_cache.get(tgt, [])):
                    broken.append(f'{rel}:{lineno}  section-ref heading not found -> '
                                  f'{tgt_name} §"{heading}"')

            for m in ORDINAL.finditer(line):
                if line.lstrip().startswith(('#', '|')):
                    continue
                # Use vs mention: a quoted or backticked ordinal is an example
                # being discussed, not a live reference. The line teaching "never
                # cite by number" necessarily quotes one, and flagging it invites
                # someone to "fix" the lesson into vagueness.
                before_ctx, after_ctx = line[:m.start()], line[m.end():]
                quoted = (before_ctx.rstrip().endswith(('"', '“', '`', "'"))
                          and after_ctx.lstrip().startswith(('"', '”', '`', "'")))
                if not quoted:
                    warned.append(f'{rel}:{lineno}  ordinal reference: "{m.group(0)}"')

    print(f'{checked} references checked across {len(files)} files')
    if broken:
        print(f'\nBROKEN ({len(broken)}):')
        for b in broken:
            print(f'  {b}')
    else:
        print('  all resolve')
    if warned:
        print(f'\nORDINAL WARNINGS ({len(warned)}) - resolve today, repoint silently on reorder:')
        for w in warned:
            print(f'  {w}')
    return 1 if broken else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
