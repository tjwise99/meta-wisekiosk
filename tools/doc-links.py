#!/usr/bin/env python3
"""Validate cross-references: file targets, #anchors, section names, and code citations.

    doc-links.py

Exits non-zero if any reference does not resolve. Four classes are checked:

  [text](path)          -> the file exists
  [text](path#anchor)   -> the file exists AND has a heading slugging to that anchor
  file.md §"Heading"    -> the file exists AND carries that exact heading text
  # See docs/README.md  -> the cited path exists, from ANY tracked text file

The third is what makes the "reference by name, never by number" convention
enforceable. Ordinal references ("open item 3") are reported separately as
warnings: they resolve today and silently repoint when a list is reordered,
which has already happened once in this repo.

The fourth exists because the first three are Markdown-only and the citations
that go stale most often are not in Markdown: a comment in a `.c`, a `.bb`, a
justfile or a shell script pointing at a document. Three such citations were
dangling and had to be found by hand.

Per-class counts are printed rather than one total, so a regex that quietly
stops matching shows up as a zero instead of disappearing into a sum.

Markdown scope is every git-tracked *.md in the repository, not a directory
argument; the citation class widens that to every git-tracked file that decodes
as text. Documentation in this layer lives beside the code it explains, so a
recipe's README is as much in scope as anything under docs/, and git tracking
excludes build/ and sources/ for free -- the same discovery ci-guards.sh uses.
"""
import re
import subprocess
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
    and a leading bracketed tag.

    The bracket branch is deliberately generic and deliberately blunt: it also
    eats the `[Foo]` of a heading written as a link (`## [Foo](bar)`, leaving
    `(bar)`) and the leading `_` of `## _private_ field`. No heading in the tree
    is written either way; a reference that mismatches for that reason is the
    signal to narrow the pattern, not to rewrite the heading."""
    return _MARKER.sub('', h.strip()).strip()


SECREF = re.compile(r'`?([\w./-]+\.md)`?(?:\]\([^)]*\))?\s*§\s*["“]([^"”]+)["”]')
HEADING = re.compile(r'^(#{1,6})\s+(.*?)\s*#*$')
ORDINAL = re.compile(r'\b(?:open )?item\s+#?\d+\b|\bdecision\s+\d+\b|\bfault\s+#?\d+\b'
                     r'|\bstep[s]?\s+\d+(?:\s*[-–]\s*\d+)?\b', re.I)

# A repo-relative path with an extension, under one of the three directories
# source files point into. Glob and placeholder characters are matched here and
# rejected below, so `tools/kiosk-*.sh` is recognised as a pattern rather than
# silently truncated to something that looks like a path.
_CITED_PATH = r'(?:docs|tools|justfiles)/[A-Za-z0-9_./+*?<>{}%-]*\.[A-Za-z0-9]+'
_PLACEHOLDER = set('*?<>{}%')

# Only a path in CITATION FORM is treated as a reference to this tree: one that
# opens a line or a comment, or follows see/at/in/under/per, an arrow, a label
# colon, an interpreter word, or an opening bracket or quote.
#
# The form is what separates a citation from provenance. Three comments in this
# tree name a file in the upstream project a recipe was ported from, in the
# shapes "ported from <path>", "the Raspbian <path>" and "Ported from <path> in
# the kiosk-reference project". Those paths are correct where they stand, and
# resolving them here would report three failures no edit to this repository
# could fix.
CITATION = re.compile(
    r'(?:^[\s>]*(?:[#*;]+|//|--)?\s*'
    r'|\b(?:see|at|in|under|per)\s+'
    r'|(?:->|→)\s*'
    r'|:\s+'
    r'|\b(?:python3?|bash|sh|exec)\s+'
    r'|[(\[\'"])'
    r'`?(' + _CITED_PATH + r')', re.I)


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


def _ls_files(top, *args):
    listing = subprocess.run(['git', 'ls-files', *args], cwd=top,
                             capture_output=True, text=True, check=True).stdout
    return sorted(top / line for line in listing.splitlines() if line)


def tracked_markdown():
    """Repo top and its git-tracked *.md files, as absolute paths."""
    top = Path(subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                              capture_output=True, text=True, check=True).stdout.strip())
    return top, _ls_files(top, '--', '*.md')


def tracked_text(top):
    """(path, text) for every git-tracked file that decodes as UTF-8. A strict
    decode is the filter: it takes the captured oops logs and the recipe sources
    and leaves out anything binary, without a suffix list to keep current."""
    for p in _ls_files(top):
        try:
            yield p, p.read_text(encoding='utf-8')
        except (UnicodeDecodeError, OSError):
            continue


def main():
    root, files = tracked_markdown()
    # A tree with no tracked Markdown reports "0 references checked" and exits
    # clean, which is indistinguishable from a passing run. Say so instead.
    if not files:
        print('no git-tracked Markdown files -- discovery is broken, not the docs',
              file=sys.stderr)
        return 2
    # Key by resolved path: lookups below resolve, and a mismatch here silently
    # empties every heading list, which reads as "no such heading" on valid refs.
    head_cache = {p.resolve(): headings(p) for p in files}
    broken, warned = [], []
    # Counted per class, not summed. A total hides a regex that stopped matching:
    # the SECREF pattern once matched nothing at all and the run still printed a
    # healthy-looking count, because the file links carried it.
    n_file = n_anchor = n_section = n_cited = 0

    for f in files:
        rel = f.relative_to(root)
        text = f.read_text(encoding='utf-8', errors='replace')

        for lineno, line in enumerate(text.splitlines(), 1):
            for target in LINK.findall(line):
                if target.startswith(('http://', 'https://', 'mailto:')):
                    continue
                n_file += 1
                path_part, _, anchor = target.partition('#')
                if path_part:
                    tgt = (f.parent / path_part).resolve()
                    if not tgt.exists():
                        broken.append(f'{rel}:{lineno}  missing file -> {target}')
                        continue
                else:
                    tgt = f.resolve()
                if anchor:
                    n_anchor += 1
                    # An anchored DIRECTORY link is the violation CONTRIBUTING.md
                    # names ("never anchor a directory link -- anchor its
                    # README.md"), and it exists, so the check above passes it
                    # through. Reading it as a file raised IsADirectoryError and
                    # killed the run: the contributor got a traceback instead of
                    # a diagnostic, every later link in the file went unreported,
                    # and the citation scan never ran at all. Name the violation
                    # the rule already forbids.
                    if tgt.is_dir():
                        broken.append(f'{rel}:{lineno}  anchored directory link '
                                      f'(anchor its README.md instead) -> {target}')
                        continue
                    known = {slug(h) for h in head_cache.get(tgt, headings(tgt))}
                    if slug(anchor) not in known:
                        broken.append(f'{rel}:{lineno}  no such heading -> {target}')

            for tgt_name, heading in SECREF.findall(line):
                n_section += 1
                tgt = (f.parent / tgt_name).resolve()
                if not tgt.exists():
                    # The captured name comes from the LINK TEXT, which is often
                    # bare ("README.md") while the real target is relative
                    # ("../README.md"), so fall back to matching by filename.
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

    scanned = 0
    for f, text in tracked_text(root):
        scanned += 1
        rel = f.relative_to(root)
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in CITATION.finditer(line):
                target = m.group(1)
                if _PLACEHOLDER & set(target):
                    continue
                n_cited += 1
                if not (root / target).exists():
                    broken.append(f'{rel}:{lineno}  cited path does not exist -> {target}')

    print(f'{n_file} file / {n_anchor} anchor / {n_section} section references '
          f'across {len(files)} Markdown files')
    print(f'{n_cited} cited paths across {scanned} tracked text files')
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
    sys.exit(main())
