#!/usr/bin/env python3
"""Render the *.sh.j2 templates with dummy vars and shellcheck the result.
Usage: shellcheck_templates.py [template ...]   (default: every tracked ansible/**/*.sh.j2)

Plain jinja2, not ansible: unknown vars render empty, ansible-only filters fail.
Line numbers in findings are the rendered file's, the snippet shows where.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import jinja2

SHELLCHECK = "shellcheck"
TEMPLATE_GLOB = "ansible/**/*.sh.j2"   # git pathspec, only tracked files (not installed collections)

# fill every branch the templates have, values only need to look plausible
DUMMY_VARS = {
    "ntfy_url": "https://ntfy.example/alerts",
    "ntfy_token": "tk_dummy",
    "ntfy_timeout": 10,
    "pbs_ntfy_url": "https://ntfy.example/backup",
    "pbs_ntfy_token": "tk_dummy",
    "pbs_staging_dir": "/var/backups/pbs-staging",
    "pbs_id": "docker-1",
    "pbs_exclude": ["cache"],
    "pbs_jobs": [
        {"name": "pg", "type": "postgres", "container": "pg-db", "data_dir": "pg/data"},
        {"name": "lite", "type": "sqlite", "path": "lite/app.db"},
        {"name": "lite-podman", "type": "sqlite", "path": "lite/app.db", "podman": True},
    ],
    "apps_root": "/opt/apps",
    "podman_apps_root": "/srv/podman-apps",
    "podman_svc_prefix": "svc-",
    "podman_svc_group": "podman-svc",
}


def main():
    tracked = subprocess.run(["git", "ls-files", "--", f":(glob){TEMPLATE_GLOB}"],
                             capture_output=True, text=True, check=True).stdout.split()
    templates = [Path(p) for p in sys.argv[1:]] or [Path(p) for p in sorted(tracked)]
    env = jinja2.Environment(trim_blocks=True, keep_trailing_newline=True)   # as ansible renders
    failed = []
    with tempfile.TemporaryDirectory() as tmp:
        for t in templates:
            out = Path(tmp) / t.name.removesuffix(".j2")
            try:
                out.write_text(env.from_string(t.read_text()).render(DUMMY_VARS))
            except jinja2.TemplateError as e:
                print(f"{t}: render failed: {e}")
                failed.append(t)
                continue
            r = subprocess.run([SHELLCHECK, out.name], cwd=tmp, capture_output=True, text=True)
            if r.returncode:
                print(f"=== {t}\n{r.stdout}{r.stderr}")
                failed.append(t)
    print(f"{len(templates)} templates, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
