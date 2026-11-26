#!/usr/bin/env python3
"""Write the Settings table of every role README. Usage: gen_role_settings.py [--check]

The table goes between <!-- settings:start --> and <!-- settings:end -->.
Rows come from meta/argument_specs.yml (description), the default from
defaults/main.yml. Vars that are only in defaults/main.yml get its trailing
comment (or the comment block right above) as the description. --check writes nothing and exits 1 when a README is stale.
"""
import re
import sys
from pathlib import Path

import yaml

START, END = "<!-- settings:start -->", "<!-- settings:end -->"
MAX_DEFAULT = 60
ROLES = Path(__file__).resolve().parent.parent / "ansible" / "roles"


def comments(path):
    """top-level key -> its trailing comment, else the comment block right above it"""
    out, above = {}, []
    for line in path.read_text().splitlines():
        if line.startswith("#"):
            above.append(line.lstrip("# ").strip())
            continue
        m = re.match(r"^([A-Za-z0-9_]+):(.*)$", line)
        if m:
            quote = None
            for i, ch in enumerate(m.group(2)):
                if quote:
                    quote = None if ch == quote else quote
                elif ch in "\"'":
                    quote = ch
                elif ch == "#" and (i == 0 or m.group(2)[i - 1] == " "):
                    out[m.group(1)] = m.group(2)[i + 1:].strip()
                    break
            else:
                if above:
                    out[m.group(1)] = " ".join(above)
        above = []
    return out


def show(value):
    if isinstance(value, str):
        m = re.fullmatch(r"\{\{\s*([^{}]+?)\s*\}\}", value)
        text = m.group(1) if m else (value or '""')
    elif isinstance(value, bool):
        text = "true" if value else "false"
    elif value is None:
        text = "null"
    elif isinstance(value, (list, dict)):
        text = yaml.safe_dump(value, default_flow_style=True, width=10**6).strip()
    else:
        text = str(value)
    if len(text) > MAX_DEFAULT:
        return "see `defaults/main.yml`"
    return f"`{text}`"


def cell(text):
    # a pipe would end the cell, <x> outside backticks would read as html
    parts = " ".join(str(text).split()).replace("|", "\\|").split("`")
    parts[::2] = [p.replace("<", "\\<") for p in parts[::2]]
    return "`".join(parts)


def rows(role):
    spec_file = role / "meta" / "argument_specs.yml"
    defaults_file = role / "defaults" / "main.yml"
    defaults = (yaml.safe_load(defaults_file.read_text()) or {}) if defaults_file.exists() else {}
    notes = comments(defaults_file) if defaults_file.exists() else {}
    options = {}
    if spec_file.exists():
        specs = (yaml.safe_load(spec_file.read_text()) or {}).get("argument_specs", {})
        # main first, other entry points only add what main lacks
        for entry in sorted(specs, key=lambda e: e != "main"):
            for name, opt in (specs[entry].get("options") or {}).items():
                options.setdefault(name, opt)
    out = []
    for name, opt in options.items():
        if name in defaults:
            default = show(defaults[name])
        elif "default" in opt:
            default = show(opt["default"])
        else:
            default = "required" if opt.get("required") else "-"
        out.append((name, default, opt.get("description", "")))
    for name, value in defaults.items():
        if name not in options:
            out.append((name, show(value), notes.get(name, "")))
    return out


def table(role):
    r = rows(role)
    if not r:
        return None
    lines = ["| Variable | Default | What |", "|---|---|---|"]
    lines += [f"| `{n}` | {cell(d)} | {cell(w)} |" for n, d, w in r]
    return "\n".join(lines)


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for role in sorted(p for p in ROLES.iterdir() if p.is_dir()):
        readme = role / "README.md"
        if not readme.exists():
            continue
        text = readme.read_text()
        if START not in text or END not in text:
            if table(role):
                stale.append(f"{readme}: no {START} / {END} markers")
            continue
        head, rest = text.split(START, 1)
        _, tail = rest.split(END, 1)
        new = f"{head}{START}\n{table(role) or '(none)'}\n{END}{tail}"
        if new != text:
            stale.append(f"{readme}: Settings table out of date")
            if not check:
                readme.write_text(new)
    for line in stale:
        print(line)
    if check and stale:
        print("run scripts/gen_role_settings.py", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
