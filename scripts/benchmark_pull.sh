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
# Pulls the in-game swarm benchmark from the headset.
# The game prints each benchmark sample as a line that starts with "PBBENCH," into logcat.
# Usage: scripts/benchmark_pull.sh [output.csv]
set -euo pipefail

OUT="${1:-benchmark_$(date +%Y%m%d_%H%M%S).csv}"
MODEL="$(adb shell getprop ro.product.model | tr -d '\r')"
echo "device,${MODEL}" > "$OUT"
echo "elapsed_s,alive,visible,avg_frame_ms,stage" >> "$OUT"
adb logcat -d | grep -F "PBBENCH," | sed 's/^.*PBBENCH,//' >> "$OUT" || true
ROWS=$(($(wc -l < "$OUT") - 2))
echo "Wrote $OUT ($ROWS samples)"
grep -F "RESULT" "$OUT" || echo "No RESULT line yet: the benchmark has not finished on the headset."
