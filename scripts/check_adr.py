#!/usr/bin/env python3
"""Check docs/adr structure and links. Usage: check_adr.py [repo-or-adr-dir]

File names, numbering, status line, sections, the index and relative links.
Wording is not checked.
"""
import re
import sys
from pathlib import Path

STATUSES = ("Accepted", "Proposed", "Superseded")
SECTIONS = ("Context", "Decision", "Consequences")
FILE_RE = re.compile(r"^(\d{4})-[a-z0-9]+(?:-[a-z0-9]+)*\.md$")
SUPERSEDED_RE = re.compile(r"^ by \[(\d{4})\]\((\d{4}-[^)]+\.md)\)$")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)#\s]+)(?:#[^)]*)?\)")

errors = []


def err(f, msg):
    errors.append(f"{f}: {msg}")


def check_adr(path, num, adr_dir):
    name = path.name
    text = path.read_text()
    lines = text.splitlines()

    m = re.match(r"^# (\d+)\. ", lines[0] if lines else "")
    if not m:
        err(name, "first line must be '# N. Title'")
    elif int(m.group(1)) != num:
        err(name, f"heading number {m.group(1)} != file number {num}")

    sm = re.search(r"^Status: (\S+)(.*)$", text, re.M)
    if not sm:
        err(name, "missing 'Status: ...' line")
    elif sm.group(1) not in STATUSES:
        err(name, f"status '{sm.group(1)}' not in {STATUSES}")
    else:
        sup = SUPERSEDED_RE.match(sm.group(2))
        if sm.group(1) == "Superseded":
            if not sup:
                err(name, "Superseded must name its successor: ' by [NNNN](NNNN-....md)'")
            elif not (adr_dir / sup.group(2)).exists():
                err(name, f"successor {sup.group(2)} does not exist")
        elif sm.group(2).strip():
            err(name, "only Superseded takes a suffix")

    found = [l[3:].strip() for l in lines if l.startswith("## ")]
    for s in SECTIONS:
        if s not in found:
            err(name, f"missing section '## {s}'")

    for target in LINK_RE.findall(text):
        if not re.match(r"^[a-z]+:", target) and not (path.parent / target).exists():
            err(name, f"broken link {target}")

    return int(m.group(1)) if m else None


def check_index(adr_dir, files):
    readme = adr_dir / "README.md"
    if not readme.exists():
        err("README.md", "missing")
        return
    text = readme.read_text()
    listed = re.findall(r"^- \[[^\]]+\]\(([^)]+)\)", text, re.M)
    for f in files:
        if listed.count(f) != 1:
            err("README.md", f"{f} listed {listed.count(f)} times, want 1")
    for target in LINK_RE.findall(text):
        if not re.match(r"^[a-z]+:", target) and not (adr_dir / target).exists():
            err("README.md", f"broken link {target}")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    adr_dir = root if root.name == "adr" else root / "docs" / "adr"
    if not adr_dir.is_dir():
        sys.exit(f"no adr dir at {adr_dir}")

    nums, files = [], []
    for p in sorted(adr_dir.glob("*.md")):
        if p.name == "README.md":
            continue
        m = FILE_RE.match(p.name)
        if not m:
            err(p.name, "file name must be NNNN-lowercase-kebab.md")
            continue
        files.append(p.name)
        nums.append(int(m.group(1)))
        check_adr(p, int(m.group(1)), adr_dir)

    if nums != list(range(1, len(nums) + 1)):
        err("docs/adr", f"numbering has gaps or dupes: {nums}")
    check_index(adr_dir, files)

    for line in errors:
        print(f"ERROR {line}")
    print(f"{len(files)} adrs, {len(errors)} errors")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
