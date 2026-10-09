#!/usr/bin/env bash
# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.
# Installs the godot_openxr_vendors plugin into godot/addons/godotopenxrvendors.
# The plugin provides the HTC passthrough wrapper (OpenXRHtcPassthroughExtension, v3.0.0 or later)
# and the Khronos/HTC export options used by export_presets.cfg.
# Release 5.1.0-stable targets Godot 4.6 and later. Run on your own machine.
#
# Usage: scripts/fetch_openxr_vendors.sh [tag]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-5.1.0-stable}"
API="https://api.github.com/repos/GodotVR/godot_openxr_vendors/releases/tags/$TAG"

URL="$(curl -fsSL "$API" | python3 -c '
import json, sys
assets = [a for a in json.load(sys.stdin)["assets"] if a["name"].endswith(".zip")]
print(assets[0]["browser_download_url"] if assets else "")
')"
[ -n "$URL" ] || { echo "No .zip asset found on release $TAG" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fL -o "$TMP/vendors.zip" "$URL"
unzip -q "$TMP/vendors.zip" -d "$TMP/x"

SRC="$(find "$TMP/x" -type d -name godotopenxrvendors | head -1)"
[ -n "$SRC" ] || { echo "godotopenxrvendors folder not found in the archive" >&2; exit 1; }

rm -rf "$ROOT/godot/addons/godotopenxrvendors"
mkdir -p "$ROOT/godot/addons"
cp -r "$SRC" "$ROOT/godot/addons/"
echo "Installed godot_openxr_vendors $TAG into godot/addons/godotopenxrvendors"
