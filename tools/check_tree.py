"""Refuses anything this repository must never hold: game data from Digimon World 1 (or any other
game), disc or memory card images, decompiled code, builds. Every file must match the allowlist
below, stay under 1 MB and avoid the forbidden names and extensions; anything else fails.

  python tools/check_tree.py           the files git tracks (CI runs this)
  python tools/check_tree.py --staged  the files about to be committed (.githooks/pre-commit)
  python tools/check_tree.py --all     every file in the folder, tracked or not (but .git, .godot, build)

Turn the hook on once per clone: git config core.hooksPath .githooks
"""
import os
import re
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MAX_BYTES = 1 << 20

ALLOW = [re.compile(p) for p in (
    r"^(README\.md|LICENSE|\.gitignore|\.gitattributes)$",
    r"^\.githooks/pre-commit$",
    r"^\.github/workflows/[\w.-]+\.yml$",
    r"^tools/[\w.-]+\.py$",
    r"^dscreen/(installer\.iss|README\.txt|notices_head\.txt)$",
    r"^engine/(project\.godot|export_presets\.cfg)$",
    r"^engine/(scripts|shaders|pet)/[\w/.-]+\.(gd|gd\.uid|gdshader|gdshaderinc|gdshaderinc\.uid|gdshader\.uid|tscn|cs)$",
    r"^engine/pet/lines/[\w.-]+\.json$",
    r"^engine/pet/props/[\w.-]+\.(glb|png)(\.import)?$",
    r"^engine/dscreen/(icon\.ico|icon_256\.png(\.import)?|dscreen_hook\.cs)$",
    r"^engine/tools/license_notices\.gd(\.uid)?$",
)]
# never, wherever they are: the remake's data and asset folders, disc / card / save images,
# executables and packs, decompiled C
FORBIDDEN_DIRS = {"game_data", "models", "extracted", "data", "decomp", "original", "showcase",
                  "ghidra", "build", ".godot"}
FORBIDDEN_EXT = (".bin", ".cue", ".iso", ".chd", ".m3u", ".img", ".ecm", ".pbp", ".mcd", ".mcr",
                 ".mcs", ".gme", ".vmp", ".psv", ".sav", ".sstate", ".exe", ".dll", ".pck", ".zip",
                 ".7z", ".rar", ".c", ".h", ".tim", ".tmd", ".vh", ".vb", ".vhb", ".mlx", ".elf",
                 ".wav", ".mp3", ".ogg", ".avi", ".mp4")


def git(*args):
    return subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True, text=True,
                          check=True).stdout.splitlines()


def files(mode):
    if mode == "--staged":
        return git("diff", "--cached", "--name-only", "--diff-filter=ACMR")
    if mode == "--all":
        out = []
        for d, dirs, fs in os.walk(ROOT):
            dirs[:] = [x for x in dirs if x not in (".git", ".godot", "build")]
            out += [os.path.relpath(os.path.join(d, f), ROOT).replace("\\", "/") for f in fs]
        return out
    return git("ls-files")


def problems(path):
    parts = path.split("/")
    if FORBIDDEN_DIRS & set(parts[:-1]):
        return "a forbidden folder"
    if path.lower().endswith(FORBIDDEN_EXT):
        return "a forbidden file type"
    if not any(p.match(path) for p in ALLOW):
        return "not on the allowlist (tools/check_tree.py)"
    full = os.path.join(ROOT, path)
    if os.path.isfile(full) and os.path.getsize(full) > MAX_BYTES:
        return "over 1 MB"
    return ""


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    paths = files(mode)
    bad = [(p, why) for p in paths if (why := problems(p))]
    for p, why in bad:
        print("refused: %s (%s)" % (p, why))
    if bad:
        sys.exit("check_tree: %d of %d files refused" % (len(bad), len(paths)))
    print("check_tree: %d files ok" % len(paths))


if __name__ == "__main__":
    main()
