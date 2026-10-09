#!/usr/bin/env bash
# Builds the Android APK for the VIVE XR Elite, installs it over adb, and launches it.
#
# Run this on your own machine. It needs:
#   - Godot 4.7 (standard build, not .NET) with the matching Android export templates
#   - JDK 17, the Android SDK (platform-tools, build-tools, platforms;android-35) and ANDROID_HOME set
#   - adb on PATH, and the XR Elite in developer mode with USB debugging on
#
# Usage: GODOT=/path/to/godot scripts/deploy_android.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
PKG="com.pointblank.swarm"
MODE="${1:-debug}"
APK="$ROOT/build/pointblank-$MODE.apk"

command -v "$GODOT" >/dev/null || { echo "Godot not found. Set GODOT=/path/to/godot" >&2; exit 1; }
command -v adb >/dev/null || { echo "adb not found on PATH" >&2; exit 1; }

if [ ! -f "$ROOT/godot/android/build/build.gradle" ]; then
  echo "Installing the Android Gradle build template..."
  "$GODOT" --headless --path "$ROOT/godot" --install-android-build-template
fi

mkdir -p "$ROOT/build"
if [ "$MODE" = "release" ]; then
  "$GODOT" --headless --path "$ROOT/godot" --export-release "Android" "$APK"
else
  "$GODOT" --headless --path "$ROOT/godot" --export-debug "Android" "$APK"
fi
echo "Built $APK"

adb wait-for-device
echo "Headset: $(adb shell getprop ro.product.model | tr -d '\r')"
adb install -r "$APK"
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Launched $PKG. Run SWARM BENCHMARK in OPTIONS, then run scripts/benchmark_pull.sh"
