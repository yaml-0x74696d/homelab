#!/usr/bin/env python3
"""Check docs/adr against the house style. Usage: check_adr.py [repo-or-adr-dir]"""
import re
import sys
from pathlib import Path

STATUSES = ("Accepted", "Proposed", "Superseded")
# superseded ones name their successor: "Status: Superseded by [0021](0021-....md)"
SUPERSEDED_RE = re.compile(r"^ by \[(\d{4})\]\(\1-[^)]+\.md\)$")
SECTIONS = ["Context", "Decision", "Consequences"]
CONSEQUENCE_ORDER = ["Easier", "Harder", "Accepted"]
FILE_RE = re.compile(r"^(\d{4})-[a-z0-9]+(?:-[a-z0-9]+)*\.md$")
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)#\s]+)(?:#[^)]*)?\)")
BANNED = {"—": "em dash, use a comma, colon or new bullet", "–": "en dash outside a number range"}

errors, warnings = [], []


def err(f, msg):
    errors.append(f"{f}: {msg}")


def warn(f, msg):
    warnings.append(f"{f}: {msg}")


def sections(lines):
    out, cur = {}, None
    for line in lines:
        m = re.match(r"^## (.+)$", line)
        if m:
            cur = m.group(1).strip()
            out[cur] = []
        elif cur:
            out[cur].append(line)
    return out


def check_adr(path, num):
    name = path.name
    text = path.read_text()
    lines = text.splitlines()

    m = re.match(r"^# (\d+)\. (.+)$", lines[0] if lines else "")
    if not m:
        err(name, "first line must be '# N. Title'")
        return None, (None, None)
    if int(m.group(1)) != num:
        err(name, f"heading number {m.group(1)} != file number {num}")
    title = m.group(2)

    status, by = None, None
    sm = re.search(r"^Status: (\S+)(.*)$", text, re.M)
    if not sm:
        err(name, "missing 'Status: ...' line")
    else:
        status = sm.group(1)
        sup = SUPERSEDED_RE.match(sm.group(2))
        by = sup.group(1) if sup else None
        if status not in STATUSES:
            err(name, f"status '{status}' not in {STATUSES} (new status = ask Tim)")
        elif (status == "Superseded") != bool(sup):
            err(name, "only Superseded takes a suffix, and it must be ' by [NNNN](NNNN-....md)'")
        if lines.index(sm.group(0)) != 2:
            err(name, "status must be line 3, right under the title")

    found = [l[3:].strip() for l in lines if l.startswith("## ")]
    if found != SECTIONS:
        err(name, f"sections {found} != {SECTIONS}")
    if any(l.startswith("### ") for l in lines):
        err(name, "no ### headings, use a plain 'Label:' line")

    sec = sections(lines)
    ctx = sec.get("Context", [])
    if "- Alternatives:" not in ctx:
        err(name, "Context needs a '- Alternatives:' bullet")
    else:
        alts = []
        for l in ctx[ctx.index("- Alternatives:") + 1:]:
            if not l.startswith("  - "):
                break
            alts.append(l)
        if not alts:
            err(name, "Alternatives has no nested items")
        for a in alts:
            if "(why not:" not in a and "(chosen)" not in a:
                err(name, f"alternative without '(why not: ...)': {a.strip()}")

    if not any(l.startswith("- Enforced by:") for l in sec.get("Decision", [])):
        err(name, "Decision needs a '- Enforced by: ...' bullet")

    cons = sec.get("Consequences", [])
    seen = [k for l in cons for k in CONSEQUENCE_ORDER if l.startswith(f"- {k}:")]
    firsts = list(dict.fromkeys(seen))
    if firsts != [k for k in CONSEQUENCE_ORDER if k in firsts]:
        err(name, f"consequence groups out of order {firsts}, want Easier, Harder, Accepted")
    bullets = [l for l in cons if l.startswith("- ")]
    if not bullets or not bullets[-1].startswith("- Related:"):
        err(name, "last Consequences bullet must be '- Related: ...'")

    for i, l in enumerate(lines, 1):
        for ch, why in BANNED.items():
            if ch in l and not (ch == "–" and re.search(r"\d–\d", l)):
                err(name, f"line {i}: {why}")
        if l != l.rstrip():
            err(name, f"line {i}: trailing whitespace")

    for label, target in LINK_RE.findall(text):
        if re.match(r"^[a-z]+:", target):
            continue
        if not (path.parent / target).exists():
            err(name, f"broken link {target}")
        lm = re.match(r"^(\d{4})$", label)
        if lm and not target.startswith(lm.group(1) + "-"):
            err(name, f"link text [{label}] points at {target}")

    return title, (status, by)


def check_readme(adr_dir, adrs):
    readme = adr_dir / "README.md"
    if not readme.exists():
        err("README.md", "missing")
        return
    entries = re.findall(r"^- \[(\d+)\. (.+?)\]\(([^)]+)\)(.*)$", readme.read_text(), re.M)
    listed = [e[2] for e in entries]
    for num, (fname, title, (status, by)) in sorted(adrs.items()):
        hits = [e for e in entries if e[2] == fname]
        if len(hits) != 1:
            err("README.md", f"{fname} listed {len(hits)} times, want 1")
            continue
        n, t, _, tail = hits[0]
        if int(n) != num or t != title:
            err("README.md", f"entry '{n}. {t}' != heading '{num}. {title}'")
        want = " (proposed)" if status == "Proposed" else f" (superseded by {int(by)})" if status == "Superseded" else ""
        if tail.strip() != want.strip():
            err("README.md", f"{fname}: suffix '{tail.strip()}' should be '{want.strip()}'")
    if listed != sorted(listed):
        err("README.md", "entries not in number order")
    for f in listed:
        if not (adr_dir / f).exists():
            err("README.md", f"lists missing file {f}")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    adr_dir = root if root.name == "adr" else root / "docs" / "adr"
    if not adr_dir.is_dir():
        sys.exit(f"no adr dir at {adr_dir}")

    adrs = {}
    for p in sorted(adr_dir.glob("*.md")):
        if p.name == "README.md":
            continue
        m = FILE_RE.match(p.name)
        if not m:
            err(p.name, "file name must be NNNN-lowercase-kebab.md")
            continue
        num = int(m.group(1))
        title, status = check_adr(p, num)
        adrs[num] = (p.name, title, status)

    nums = sorted(adrs)
    if nums and nums != list(range(1, nums[-1] + 1)):
        err("docs/adr", f"numbering has gaps or dupes: {nums}")
    check_readme(adr_dir, adrs)

    for line in errors:
        print(f"ERROR {line}")
    for line in warnings:
        print(f"WARN  {line}")
    print(f"{len(adrs)} adrs, {len(errors)} errors, {len(warnings)} warnings")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
