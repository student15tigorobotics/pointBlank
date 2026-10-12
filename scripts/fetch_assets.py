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
Downloads the third-party assets listed in godot/assets/manifest.json and builds the generated ones.

Each asset entry names a destination inside godot/assets/, a licence and either a URL to download
(with a SHA-256 checksum) or a "generator": a script under scripts/ that writes the file locally.
The script refuses any licence not on the manifest's allowlist, refuses destinations outside
godot/assets/ and generators outside scripts/, and checks each download against its checksum.
A missing generated file is produced by its generator and the SHA-256 it produced is printed.
It then rewrites godot/assets/CREDITS.md from the manifest so attribution stays in step with the files.

Usage:
  python3 scripts/fetch_assets.py --list                 # show the manifest
  python3 scripts/fetch_assets.py --dry-run              # show what would be downloaded or generated
  python3 scripts/fetch_assets.py                        # download missing or changed assets, build missing generated ones
  python3 scripts/fetch_assets.py --force                # re-download (or regenerate) everything
  python3 scripts/fetch_assets.py --force --only music.battle --only music.hub   # only the named ids
This script uses the standard library only. A generator may need more: gen_menu_ambience.py needs numpy.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "godot" / "assets"
SCRIPTS = ROOT / "scripts"
MANIFEST = ASSETS / "manifest.json"
CREDITS = ASSETS / "CREDITS.md"

# Licence links written into CREDITS.md. CC-BY-4.0 entries are attribution-required.
LICENCE_URLS = {
    "CC-BY-4.0": "https://creativecommons.org/licenses/by/4.0/",
}


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
    for key in ("id", "path", "license", "source", "author"):
        if not entry.get(key):
            problems.append(f"missing '{key}'")
    has_url = bool(entry.get("url"))
    has_generator = bool(entry.get("generator"))
    if has_url == has_generator:
        problems.append("needs exactly one of 'url' or 'generator'")
    if entry.get("license") == "CC-BY-4.0" and not entry.get("source_url"):
        problems.append("CC-BY-4.0 needs 'source_url' for the credits")
    if entry.get("license") and entry["license"] not in allow:
        problems.append(f"licence '{entry['license']}' is not on the allowlist")
    if entry.get("path"):
        dest = (ROOT / entry["path"]).resolve()
        if ASSETS.resolve() not in dest.parents:
            problems.append("path must be inside godot/assets/")
    if has_generator:
        gen = (ROOT / entry["generator"]).resolve()
        if SCRIPTS.resolve() not in gen.parents or not gen.is_file():
            problems.append("generator must be an existing script inside scripts/")
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


def generate(entry: dict, dest: pathlib.Path) -> str:
    """Runs the entry's generator script, which must write dest. Returns the script's last output line."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    gen = ROOT / entry["generator"]
    proc = subprocess.run([sys.executable, str(gen)], cwd=ROOT, capture_output=True, text=True, timeout=900)
    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout).strip().splitlines()[-3:]
        raise RuntimeError(f"{entry['generator']} exited {proc.returncode}: " + " | ".join(tail))
    if not dest.exists():
        raise RuntimeError(f"{entry['generator']} did not write {entry['path']}")
    out = proc.stdout.strip().splitlines()
    return out[-1] if out else ""


def write_credits(entries: list) -> None:
    lines = [
        "# Asset credits",
        "",
        "Generated from godot/assets/manifest.json by scripts/fetch_assets.py. Do not edit by hand.",
        "",
    ]
    for e in entries:
        lic = e["license"]
        lines += [
            f"## {e['id']}",
            f"- File: `{e['path']}`",
            f"- Author: {e['author']}",
            f"- Source: {e['source']}",
        ]
        if lic == "CC-BY-4.0":
            lines += [
                f"- Source URL: {e['source_url']}",
                f"- Track URL: {e['url']}",
                f"- Licence: {lic} (attribution required)",
                f"- Licence URL: {LICENCE_URLS[lic]}",
            ]
        else:
            lines.append(f"- Licence: {lic} (attribution not required)")
        lines.append("")
    CREDITS.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", action="append", default=[], metavar="ID",
                    help="limit downloads and generation to this asset id (repeatable)")
    args = ap.parse_args()

    manifest = load_manifest()
    allow = set(manifest.get("license_allowlist", []))
    entries = manifest.get("assets", [])

    if args.list:
        for e in entries:
            print(f"{e.get('id', '?'):32s} {e.get('license', '?'):12s} {e.get('path', '?')}")
        print(f"{len(entries)} assets")
        return 0

    selected = entries
    if args.only:
        known = {e.get("id") for e in entries}
        unknown = [i for i in args.only if i not in known]
        if unknown:
            print("unknown asset id(s): " + ", ".join(unknown))
            return 2
        selected = [e for e in entries if e.get("id") in args.only]

    failures = 0
    for e in selected:
        problems = check_entry(e, allow)
        if problems:
            print(f"SKIP {e.get('id', '?')}: " + "; ".join(problems))
            failures += 1
            continue

        dest = ROOT / e["path"]
        want = e.get("sha256", "")
        present = dest.exists()

        if "generator" in e:
            if present and not args.force:
                if want and sha256_of(dest) != want:
                    print(f"ok   {e['id']} (present; sha256 differs from manifest, rerun with --force to regenerate)")
                else:
                    print(f"ok   {e['id']} (present)")
                continue
            print(f"gen  {e['id']} <- {e['generator']}")
            if args.dry_run:
                continue
            try:
                summary = generate(e, dest)
            except Exception as exc:  # generator missing a dependency or failing: report and continue
                print(f"FAIL {e['id']}: {exc}")
                failures += 1
                continue
            digest = sha256_of(dest)
            if summary:
                print(f"     {summary}")
            if want and digest != want:
                print(f"     {e['id']} sha256 {digest} differs from the manifest value {want}; "
                      "generator output can vary with numpy or platform, so the file is kept")
            elif not want:
                print(f"     {e['id']} generated; add this sha256 to the manifest: {digest}")
            print(f"ok   {e['id']} (generated, sha256 {digest})")
            continue

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
