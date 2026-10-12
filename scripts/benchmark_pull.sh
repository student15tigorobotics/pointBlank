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
# The game prints to logcat one sample line every 2 s:
#   PBBENCH,<elapsed_s>,<alive>,<visible>,<avg_frame_ms>,<graphics_tier>
# and one RESULT line when the run ends:
#   PBBENCH,RESULT,<alive>,<visible>,<graphics_tier>,<budget_ms>,<stop_code>
# stop_code (battle_controller.gd): 0 frames stayed over budget, 1 enemy cap reached, 2 time limit, 3 aborted.
#
# Usage: scripts/benchmark_pull.sh [samples.csv]
# Writes two files next to each other:
#   samples.csv          header elapsed_s,alive,visible,avg_frame_ms,graphics_tier, then one row per sample
#   samples.result.csv   header device,alive,visible,graphics_tier,budget_ms,stop_code, then the RESULT row
#                        (header only if the benchmark has not finished yet)
# logcat -d returns the whole buffer, so samples from an earlier run still in it are included, as before.
set -euo pipefail

OUT="${1:-benchmark_$(date +%Y%m%d_%H%M%S).csv}"
case "$OUT" in
  *.csv) RESULT_OUT="${OUT%.csv}.result.csv" ;;
  *)     RESULT_OUT="$OUT.result.csv" ;;
esac

MODEL="$(adb shell getprop ro.product.model | tr -d '\r')"
LOG="$(adb logcat -d | tr -d '\r' || true)"

# Sample rows have five fields after the tag; the RESULT row has its own tag, so the two never match each other.
SAMPLE_RE='PBBENCH,[0-9.]+,[0-9]+,[0-9]+,[0-9.]+,[0-9]+'
RESULT_RE='PBBENCH,RESULT,[0-9]+,[0-9]+,[0-9]+,[0-9.]+,[0-9]+'
SAMPLES="$(printf '%s\n' "$LOG" | grep -oE "$SAMPLE_RE" | sed 's/^PBBENCH,//' || true)"
RESULT="$(printf '%s\n' "$LOG" | grep -oE "$RESULT_RE" | tail -n 1 | sed 's/^PBBENCH,RESULT,//' || true)"

{
  echo "elapsed_s,alive,visible,avg_frame_ms,graphics_tier"
  if [ -n "$SAMPLES" ]; then printf '%s\n' "$SAMPLES"; fi
} > "$OUT"

{
  echo "device,alive,visible,graphics_tier,budget_ms,stop_code"
  if [ -n "$RESULT" ]; then echo "$MODEL,$RESULT"; fi
} > "$RESULT_OUT"

ROWS=$(( $(wc -l < "$OUT") - 1 ))
echo "Wrote $OUT ($ROWS samples)"
if [ -n "$RESULT" ]; then
  echo "Wrote $RESULT_OUT: $MODEL, $RESULT (alive, visible, graphics_tier, budget_ms, stop_code)"
else
  echo "No RESULT line yet: the benchmark has not finished on the headset. $RESULT_OUT has its header only."
fi
