#!/usr/bin/env python3
# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.
"""
Downloads the third-party assets listed in godot/assets/manifest.json.

Each asset entry names a URL, a destination inside godot/assets/, a SHA-256 checksum and a licence.
The script refuses any licence not on the manifest's allowlist, refuses destinations outside
godot/assets/, and checks each download against its checksum. It then rewrites godot/assets/CREDITS.md
from the manifest so attribution stays in step with the files.

Usage:
  python3 scripts/fetch_assets.py --list        # show the manifest
  python3 scripts/fetch_assets.py --dry-run     # show what would be downloaded
  python3 scripts/fetch_assets.py               # download missing or changed assets
  python3 scripts/fetch_assets.py --force       # re-download everything
Standard library only.
"""
import argparse
import hashlib
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "godot" / "assets"
MANIFEST = ASSETS / "manifest.json"
CREDITS = ASSETS / "CREDITS.md"


def sha256_of(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest() -> dict:
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def check_entry(entry: dict, allow: set) -> list:
    problems = []
    for key in ("id", "url", "path", "license", "source", "author"):
        if not entry.get(key):
            problems.append(f"missing '{key}'")
    if entry.get("license") and entry["license"] not in allow:
        problems.append(f"licence '{entry['license']}' is not on the allowlist")
    if entry.get("path"):
        dest = (ROOT / entry["path"]).resolve()
        if ASSETS.resolve() not in dest.parents:
            problems.append("path must be inside godot/assets/")
    return problems


def download(url: str, dest: pathlib.Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "pointblank-fetch/1"})
    with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            f.write(chunk)
    tmp.replace(dest)


def write_credits(entries: list) -> None:
    lines = [
        "# Asset credits",
        "",
        "Generated from godot/assets/manifest.json by scripts/fetch_assets.py. Do not edit by hand.",
        "",
    ]
    for e in entries:
        attribution = "required" if e["license"] == "CC-BY-4.0" else "not required"
        lines += [
            f"## {e['id']}",
            f"- File: `{e['path']}`",
            f"- Author: {e['author']}",
            f"- Source: {e['source']}",
            f"- Licence: {e['license']} (attribution {attribution})",
            "",
        ]
    CREDITS.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    manifest = load_manifest()
    allow = set(manifest.get("license_allowlist", []))
    entries = manifest.get("assets", [])

    if args.list:
        for e in entries:
            print(f"{e.get('id', '?'):32s} {e.get('license', '?'):12s} {e.get('path', '?')}")
        print(f"{len(entries)} assets")
        return 0

    failures = 0
    for e in entries:
        problems = check_entry(e, allow)
        if problems:
            print(f"SKIP {e.get('id', '?')}: " + "; ".join(problems))
            failures += 1
            continue

        dest = ROOT / e["path"]
        want = e.get("sha256", "")
        present = dest.exists()
        if present and not args.force and (not want or sha256_of(dest) == want):
            print(f"ok   {e['id']} (present)")
            continue
        if args.dry_run:
            print(f"get  {e['id']} <- {e['url']}")
            continue

        print(f"get  {e['id']} <- {e['url']}")
        try:
            download(e["url"], dest)
        except Exception as exc:  # network or HTTP error: report and continue
            print(f"FAIL {e['id']}: {exc}")
            failures += 1
            continue
        digest = sha256_of(dest)
        if want and digest != want:
            dest.unlink()
            print(f"FAIL {e['id']}: sha256 {digest} does not match manifest")
            failures += 1
            continue
        if not want:
            print(f"     {e['id']} has no sha256 in the manifest; add this value: {digest}")
        print(f"ok   {e['id']}")

    if not args.dry_run:
        write_credits([e for e in entries if not check_entry(e, allow)])
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
