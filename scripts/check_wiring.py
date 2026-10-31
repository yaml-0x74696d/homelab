#!/usr/bin/env python3
"""Check that apps.yml and everything wired to it agree. Usage: check_wiring.py [repo]

Reads the files only, no network. apps.yml is the source; traefik's routers, homepage's
tiles, app_ports, the pbs jobs and the unit templates have to match it.
"""
import re
import sys
from pathlib import Path

import yaml

UID_MAX = 65534          # svc uids, subuid range = uid * 65536
PORT_MIN_ROOTLESS = 1024
APPS_MAP = "ansible/group_vars/all/apps.yml"
APP_SETTINGS = "ansible/group_vars/all/app_settings.yml"
PORTS = "ansible/group_vars/all/ports.yml"
INVENTORY = "ansible/inventory.yml"
HOST_VARS = "ansible/host_vars"
APPS_DIR = "ansible/apps"
TRAEFIK_DIR = "ansible/apps/proxy/traefik/dynamic"
HOMEPAGE = "ansible/apps/dashboard/homepage/config/services.yaml.j2"

errors, warnings = [], []
ROUTE_RE = re.compile(r"Host\(`([a-z0-9-]+)\.[^`]*`\)(?:\s*&&\s*PathPrefix\(`([^`]+)`\))?")
HREF_RE = re.compile(r"href:\s*https://([a-z0-9-]+)\.\{\{\s*domain\s*\}\}(/[^\s\"']*)?")


def load(repo, rel):
    return yaml.safe_load((repo / rel).read_text()) or {}


def inventory_hosts(node):
    hosts = set((node.get("hosts") or {}).keys())
    for child in (node.get("children") or {}).values():
        hosts |= inventory_hosts(child or {})
    return hosts


def traefik_routes(repo):
    """(host, path) of every router, plus the middleware names defined anywhere."""
    routes, mws = {}, set()
    # go templates inside the strings make these invalid yaml until traefik renders them: read lines
    for f in (repo / TRAEFIK_DIR).glob("*.yml"):
        section, current = None, None
        for line in f.read_text().splitlines():
            top = re.match(r"^  (\w+):\s*$", line)
            if top:
                section, current = top[1], None
                continue
            if section == "middlewares":
                m = re.match(r"^    ([\w-]+):\s*$", line)
                if m:
                    mws.add(m[1])
            elif section == "routers":
                m = ROUTE_RE.search(line) if "rule:" in line else None
                if m:
                    current = (m[1], m[2])
                    routes[current] = []
                m = re.search(r"middlewares:\s*\[([^\]]*)\]", line)
                if m and current:
                    routes[current] = [x.strip().strip("\"'").split("@")[0] for x in m[1].split(",") if x.strip()]
    for f in (repo / APPS_DIR).glob("*/docker-compose.yml"):
        labels = re.findall(r"traefik\.http\.routers\.([\w-]+)\.(rule|middlewares)=([^\"'\n]+)", f.read_text())
        rules = {r: v for r, k, v in labels if k == "rule"}
        mw = {r: [x.split("@")[0] for x in v.split(",")] for r, k, v in labels if k == "middlewares"}
        for r, rule in rules.items():
            m = ROUTE_RE.search(rule.replace("${DOMAIN}", "d"))
            if m:
                routes[(m[1], m[2])] = mw.get(r, [])
    return routes, mws


def main():
    repo = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    amap = load(repo, APPS_MAP)
    apps, infra = amap.get("apps") or {}, amap.get("infra_routes") or []
    sources = set((load(repo, APP_SETTINGS).get("app_sources") or {}).keys())
    hosts = inventory_hosts(load(repo, INVENTORY).get("all", {}))

    # --- the map itself
    uids, routes_map, ports_by_host = {}, {}, {}
    for name, a in apps.items():
        podman = a.get("runtime", "podman") == "podman"
        if a.get("host") not in hosts:
            errors.append(f"{name}: host '{a.get('host')}' is not in the inventory")
        for r in a.get("routes", []):
            key = (r["host"], r.get("path"))
            if key in routes_map:
                errors.append(f"{name}: route {r['host']}{r.get('path') or ''} also in {routes_map[key][0]}")
            routes_map[key] = (name, r.get("middlewares", []))
        ports = ([a["port"]] if "port" in a else []) + [p["port"] for p in a.get("extra_ports", [])]
        for p in ports:
            other = ports_by_host.setdefault(a["host"], {}).get(p)
            if other:
                errors.append(f"{name}: port {p} on {a['host']} also used by {other}")
            ports_by_host[a["host"]][p] = name
        if not podman:
            continue
        uid = a.get("uid")
        if not isinstance(uid, int) or not 0 < uid <= UID_MAX:
            errors.append(f"{name}: uid {uid} missing or out of 1..{UID_MAX}")
        elif uid in uids:
            errors.append(f"{name}: uid {uid} also used by {uids[uid]}")
        else:
            uids[uid] = name
        for p in ports:
            if p < PORT_MIN_ROOTLESS:
                errors.append(f"{name}: port {p} < {PORT_MIN_ROOTLESS}, rootless can't bind it")
        for src in a.get("allow_from", []) + [s for p in a.get("extra_ports", []) for s in p.get("allow_from", [])]:
            if src not in sources and src not in apps:
                errors.append(f"{name}: allow_from '{src}' is neither in app_sources nor an app")
        for c in a.get("containers", []):
            if "." not in c.get("image", "").split("/")[0]:
                errors.append(f"{name}/{c.get('name')}: image '{c.get('image')}' isn't fully qualified")
            unit = repo / APPS_DIR / name / f"{c['name']}.container.j2"
            if not unit.exists():
                errors.append(f"{name}/{c['name']}: {unit.relative_to(repo)} missing")
                continue
            for n, line in enumerate(unit.read_text().splitlines(), 1):
                if re.match(r"^[A-Za-z]+=.*\s#", line):
                    errors.append(f"{unit.relative_to(repo)}:{n}: comment at the end of a line, systemd reads it as part of the value")
        for s in a.get("secrets", []):
            if "template" in s and not (repo / APPS_DIR / name / s["template"]).exists():
                errors.append(f"{name}: secret template {s['template']} missing")

    # --- traefik: every route served is in the map, every map route is served
    served, mws_defined = traefik_routes(repo)
    infra_hosts = {r["host"] for r in infra}
    for (h, path), mws in served.items():
        if (h, path) not in routes_map and h not in infra_hosts:
            errors.append(f"traefik serves {h}{path or ''}, but it's neither in apps.yml nor infra_routes (gatus won't check it)")
    for (h, path), (name, mws) in routes_map.items():
        if (h, path) not in served:
            errors.append(f"{name}: route {h}{path or ''} has no traefik router")
        for mw in mws:
            if mw not in mws_defined:
                errors.append(f"{name}: middleware '{mw}' isn't defined in traefik")

    # --- app_ports: one source, the map
    for key, val in (load(repo, PORTS).get("app_ports") or {}).items():
        name = key.replace("_", "-")
        if name in apps and "port" in apps[name] and f"apps['{name}'].port" not in str(val):
            errors.append(f"app_ports.{key}: literal {val}, take it from apps['{name}'].port")

    # --- pbs: a podman app's sqlite lives under podman_apps_root
    for hv in (repo / HOST_VARS).glob("*.yml"):
        for j in (yaml.safe_load(hv.read_text()) or {}).get("pbs_jobs", []):
            if j.get("type") != "sqlite":
                continue
            name = j["path"].split("/")[0]
            if name in apps and (apps[name].get("runtime", "podman") == "podman") != bool(j.get("podman")):
                errors.append(f"{hv.name}: pbs job {j['name']} needs podman: {apps[name].get('runtime', 'podman') == 'podman'}")

    # --- homepage: a tile per routed app, no tile for an unknown route
    hrefs = {(h, p) for h, p in HREF_RE.findall((repo / HOMEPAGE).read_text())}
    hrefs = {(h, p or None) for h, p in hrefs}
    tiled_hosts = {h for h, _ in hrefs}
    for name, a in apps.items():
        rs = a.get("routes", [])
        if rs and not any(r["host"] in tiled_hosts for r in rs):
            warnings.append(f"{name}: no homepage tile links to {rs[0]['host']}")
    for h, p in sorted(hrefs, key=str):
        if h not in {k[0] for k in routes_map} and h not in infra_hosts:
            warnings.append(f"homepage links {h}{p or ''}, which isn't a route in apps.yml or infra_routes")

    for line in errors:
        print(f"ERROR {line}")
    for line in warnings:
        print(f"WARN  {line}")
    print(f"{len(apps)} apps, {len(routes_map)} routes, {len(served)} traefik routers, "
          f"{len(errors)} errors, {len(warnings)} warnings")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
