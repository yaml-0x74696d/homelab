#!/usr/bin/env python3
"""Check that apps.yml and everything wired to it agree. Usage: check_wiring.py [repo]

Reads the files only, no network. apps.yml is the source; homepage's
tiles, the pbs jobs and the unit templates have to match it.
"""
import re
import sys
from pathlib import Path

import yaml

UID_MIN = 2000           # svc uids, below are login users
UID_MAX = 65534          # subuid range = uid * 65536 has to stay in 32 bit
PORT_MIN_ROOTLESS = 1024
APPS_MAP = "ansible/group_vars/all/apps.yml"
APP_SETTINGS = "ansible/group_vars/all/app_settings.yml"
INVENTORY = "ansible/inventory.yml"
HOST_VARS = "ansible/host_vars"
APPS_DIR = "ansible/apps"
HOMEPAGE = "ansible/apps/homepage/services.yaml.j2"

errors, warnings = [], []
TILES_RE = re.compile(r"\{\{\s*tiles\('([A-Za-z]+)'\)\s*\}\}")
HREF_RE = re.compile(r"href:\s*https://([a-z0-9-]+)\.\{\{\s*domain\s*\}\}(/[^\s\"']*)?")


def load(repo, rel):
    return yaml.safe_load((repo / rel).read_text()) or {}


def inventory_hosts(node):
    hosts = set((node.get("hosts") or {}).keys())
    for child in (node.get("children") or {}).values():
        hosts |= inventory_hosts(child or {})
    return hosts


def main():
    repo = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    if re.search(r"\{\{|\{%", (repo / APPS_MAP).read_text()):
        errors.append(f"{APPS_MAP}: jinja found, it has to stay pure data (edge and ci read it with yq)")
    amap = load(repo, APPS_MAP)
    apps, infra = amap.get("apps") or {}, amap.get("infra_routes") or []
    sources = set((load(repo, APP_SETTINGS).get("app_sources") or {}).keys())
    hosts = inventory_hosts(load(repo, INVENTORY).get("all", {}))

    # --- the map itself
    uids, routes_map, ports_by_host, cifs_by_host = {}, {}, {}, {}
    for name, a in apps.items():
        podman = a.get("runtime", "podman") == "podman"
        if not isinstance(a, dict):
            errors.append(f"{name}: entry isn't a mapping")
            continue
        # hosts: one copy per host, only for apps nothing reaches (podman_app checks that at deploy)
        for h in a.get("hosts") or [a.get("host")]:
            if h not in hosts:
                errors.append(f"{name}: host '{h}' is not in the inventory")
        for r in a.get("routes", []):
            if "host" not in r:
                errors.append(f"{name}: route without host")
                continue
            key = (r["host"], r.get("path"))
            if key in routes_map:
                errors.append(f"{name}: route {r['host']}{r.get('path') or ''} also in {routes_map[key][0]}")
            routes_map[key] = (name, r.get("middlewares", []))
        # tcp and udp on the same number are two ports
        ports = ([(a["port"], "tcp")] if "port" in a else []) + [(p["port"], p.get("proto", "tcp")) for p in a.get("extra_ports", [])]
        for p in ports:
            other = ports_by_host.setdefault(a.get("host"), {}).get(p)
            if other:
                errors.append(f"{name}: port {p[0]}/{p[1]} on {a['host']} also used by {other}")
            ports_by_host[a.get("host")][p] = name
        if not podman:
            continue
        uid = a.get("uid")
        if not isinstance(uid, int) or not UID_MIN <= uid <= UID_MAX:
            errors.append(f"{name}: uid {uid} missing or out of {UID_MIN}..{UID_MAX}")
        elif uid in uids:
            errors.append(f"{name}: uid {uid} also used by {uids[uid]}")
        else:
            uids[uid] = name
        for p, _ in ports:
            if p < PORT_MIN_ROOTLESS:
                errors.append(f"{name}: port {p} < {PORT_MIN_ROOTLESS}, rootless can't bind it")
        for src in a.get("allow_from", []) + [s for p in a.get("extra_ports", []) for s in p.get("allow_from", [])]:
            if src not in sources and src not in apps:
                errors.append(f"{name}: allow_from '{src}' is neither in app_sources nor an app")
        # more than one container = a pod, which owns ports, hosts and the network
        pod = len(a.get("containers", [])) > 1
        units = []
        if pod:
            unit = repo / APPS_DIR / name / f"{name}.pod.j2"
            if unit.exists():
                units.append(unit)
            else:
                errors.append(f"{name}: {unit.relative_to(repo)} missing (more than one container = a pod)")
        for c in a.get("containers", []):
            if "name" not in c:
                errors.append(f"{name}: container without name")
                continue
            if c["name"] != name and not c["name"].startswith(f"{name}-"):
                errors.append(f"{name}/{c['name']}: name it {name}-<role>")
            if "." not in c.get("image", "").split("/")[0]:
                errors.append(f"{name}/{c.get('name')}: image '{c.get('image')}' isn't fully qualified")
            unit = repo / APPS_DIR / name / f"{c['name']}.container.j2"
            if not unit.exists():
                errors.append(f"{name}/{c['name']}: {unit.relative_to(repo)} missing")
                continue
            units.append(unit)
            if pod:
                for n, line in enumerate(unit.read_text().splitlines(), 1):
                    if re.match(r"^(PublishPort|AddHost|Network)=", line):
                        errors.append(f"{unit.relative_to(repo)}:{n}: {line.split('=')[0]} goes in {name}.pod.j2, podman refuses it in a pod")
        for unit in units:
            for n, line in enumerate(unit.read_text().splitlines(), 1):
                if re.match(r"^[A-Za-z]+=.*\s#", line):
                    errors.append(f"{unit.relative_to(repo)}:{n}: comment at the end of a line, systemd reads it as part of the value")
        # one fstab line per mount point and host
        for m in a.get("cifs", []):
            other = cifs_by_host.setdefault(a.get("host"), {}).get(m.get("path"))
            if other:
                errors.append(f"{name}: cifs path {m.get('path')} on {a['host']} also used by {other}")
            cifs_by_host[a.get("host")][m.get("path")] = name
        for s in a.get("secrets", []):
            if "template" in s and not (repo / APPS_DIR / name / s["template"]).exists():
                errors.append(f"{name}: secret template {s['template']} missing")

    infra_hosts = {r["host"] for r in infra}

    # --- pbs: sqlite paths live under podman_apps_root/<app>, postgres is dumped as svc-<app>
    for hv in (repo / HOST_VARS).glob("*.yml"):
        for j in (yaml.safe_load(hv.read_text()) or {}).get("pbs_jobs", []):
            name = j["path"].split("/")[0] if j.get("type") == "sqlite" else j.get("app")
            if name not in apps:
                errors.append(f"{hv.name}: pbs job {j['name']} doesn't point at an app from apps.yml")
            elif "podman" in j:
                errors.append(f"{hv.name}: pbs job {j['name']}: drop podman:, every job runs on podman now")

    # --- homepage: app tiles are generated from homepage: blocks, the rest is hand-written
    tpl = (repo / HOMEPAGE).read_text()
    groups = set(TILES_RE.findall(tpl))
    for name, entry in list(apps.items()) + [(r["host"], r) for r in infra]:
        hp = entry.get("homepage")
        if hp is None:
            continue
        if hp.get("group") not in groups:
            errors.append(f"{name}: homepage group {hp.get('group')} isn't rendered (known: {', '.join(sorted(groups))})")
        if not hp.get("icon"):
            errors.append(f"{name}: homepage block without icon")
        if name in apps and not entry.get("routes"):
            errors.append(f"{name}: homepage tile needs a route to link to")
    hrefs = {(h, p or None) for h, p in HREF_RE.findall(tpl)}
    for h, p in sorted(hrefs, key=str):
        if h not in {k[0] for k in routes_map} and h not in infra_hosts:
            warnings.append(f"homepage links {h}{p or ''}, which isn't a route in apps.yml or infra_routes")

    for line in errors:
        print(f"ERROR {line}")
    for line in warnings:
        print(f"WARN  {line}")
    print(f"{len(apps)} apps, {len(routes_map)} routes, "
          f"{len(errors)} errors, {len(warnings)} warnings")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
