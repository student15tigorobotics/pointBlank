#!/usr/bin/env bash
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
