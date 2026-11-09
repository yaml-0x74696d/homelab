#!/usr/bin/env python3
"""Check architecture/*.c4 against the house style. Usage: check_c4.py [repo-or-architecture-dir]

Runs `likec4 export json` and checks the parsed model, so syntax errors surface
from likec4 itself. Run `likec4 validate` first.
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

LIKEC4 = "likec4"
EXPORT_TIMEOUT_S = 120
ID_RE = re.compile(r"^[a-z][a-z0-9-]*$")
# kinds that must run somewhere unless #parked
DEPLOYABLE = {"container", "ui", "db", "cache", "store", "app"}
SKIP_TAGS = {"parked"}
# whole system is abstract plumbing (controller, proxmox api, ...)
ABSTRACT_SYSTEM_TAG = "ops"

errors, warnings = [], []


def load(arch):
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "model.json"
        r = subprocess.run([LIKEC4, "export", "json", "-o", str(out), str(arch)],
                           capture_output=True, text=True, timeout=EXPORT_TIMEOUT_S)
        if r.returncode or not out.exists():
            sys.exit(f"likec4 export failed:\n{r.stdout}{r.stderr}")
        data = json.loads(out.read_text())
    return data[0] if isinstance(data, list) else data


def ancestors(eid):
    parts = eid.split(".")
    return [".".join(parts[:i]) for i in range(1, len(parts))]


def parent(eid):
    return eid.rsplit(".", 1)[0] if "." in eid else None


def text(v):
    return v.get("txt", v.get("md", "")) if isinstance(v, dict) else (v or "")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    arch = root if (root / "likec4.config.json").exists() else root / "architecture"
    p = load(arch)
    els, rels = p["elements"], p["relations"]
    tags = {k: set(v.get("tags") or []) for k, v in els.items()}

    for eid, e in els.items():
        for seg in eid.split("."):
            if not ID_RE.match(seg):
                err(eid, f"id segment '{seg}' must be lowercase kebab")
        d = text(e.get("description"))
        if d.rstrip().endswith("."):
            err(eid, "description ends with a period")
        # hostnames like pod-1/2/3 may lead lowercase
        if d and d[0].islower() and not re.match(r"^\S*[-0-9/]", d):
            err(eid, "description should start uppercase")

    for r in rels.values():
        s, t = r["source"]["model"], r["target"]["model"]
        title = r.get("title") or ""
        if not title and parent(s) != parent(t):
            err(f"{s} -> {t}", "relationship between different parents needs a label")
        if title:
            first = title.split()[0]
            if first[0].isupper() and not first.isupper():
                err(f"{s} -> {t}", f"label '{title}' should start lowercase")

    deployed = {inst["element"] for inst in p["deployments"]["elements"].values() if "element" in inst}
    for eid, e in els.items():
        if e["kind"] not in DEPLOYABLE or tags[eid] & SKIP_TAGS:
            continue
        if any(ABSTRACT_SYSTEM_TAG in tags[a] and els[a]["kind"] == "system" for a in ancestors(eid)):
            continue
        linked = {eid, *ancestors(eid)}
        if not linked & deployed and not any(d.startswith(eid + ".") for d in deployed):
            warn(eid, "not deployed anywhere (instanceOf) and not #parked")

    systems = [k for k, v in els.items() if v["kind"] == "system" and ABSTRACT_SYSTEM_TAG not in tags[k]]
    view_of = {v.get("viewOf") for v in p["views"].values() if v["_type"] == "element"}
    for s in systems:
        if s not in view_of:
            warn(s, "system has no container view (view ... of ...)")

    for vid, v in p["views"].items():
        if v["_type"] != "element":
            continue
        for n in v["nodes"]:
            if not n["children"] and not n["inEdges"] and not n["outEdges"]:
                warn(f"view {vid}", f"'{n['id']}' has no edges in this view")

    for line in errors:
        print(f"ERROR {line}")
    for line in warnings:
        print(f"WARN  {line}")
    print(f"{len(els)} elements, {len(rels)} relations, {len(errors)} errors, {len(warnings)} warnings")
    sys.exit(1 if errors else 0)


def err(where, msg):
    errors.append(f"{where}: {msg}")


def warn(where, msg):
    warnings.append(f"{where}: {msg}")


if __name__ == "__main__":
    main()
