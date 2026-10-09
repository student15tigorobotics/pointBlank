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
Installs the offline speech stack used by the game: the Piper CLI and the en_US "amy" (low) VITS voice.

Files go to the Godot user folder for this project (Linux):
    ~/.local/share/godot/app_userdata/PointBlank Swarm/voice/
        piper/piper            CLI binary (plus its bundled libraries)
        en_US-amy-low.onnx     voice model
        en_US-amy-low.onnx.json

Nothing is sent anywhere at runtime; this script only downloads once.
"""
import os
import pathlib
import stat
import sys
import tarfile
import urllib.request

PIPER_URL = "https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_amd64.tar.gz"
VOICE_BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/low/"
VOICE_FILES = ["en_US-amy-low.onnx", "en_US-amy-low.onnx.json"]


def voice_dir() -> pathlib.Path:
    base = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return pathlib.Path(base) / "godot" / "app_userdata" / "PointBlank Swarm" / "voice"


def download(url: str, dest: pathlib.Path) -> None:
    print(f"  {url}")
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    tmp.replace(dest)


def main() -> int:
    out = voice_dir()
    out.mkdir(parents=True, exist_ok=True)
    print(f"Installing offline voice into {out}")

    piper_dir = out / "piper"
    if not (piper_dir / "piper").exists():
        archive = out / "piper_amd64.tar.gz"
        download(PIPER_URL, archive)
        with tarfile.open(archive, "r:gz") as tar:
            # The release archive contains a top-level "piper/" folder.
            tar.extractall(out, filter="data")
        archive.unlink()
        binary = piper_dir / "piper"
        if binary.exists():
            binary.chmod(binary.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    else:
        print("Piper already installed")

    for name in VOICE_FILES:
        target = out / name
        if target.exists():
            print(f"{name} already present")
            continue
        download(VOICE_BASE + name, target)

    binary = piper_dir / "piper"
    ok = binary.exists() and (out / VOICE_FILES[0]).exists()
    print("Ready." if ok else "Install incomplete: check the messages above.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
