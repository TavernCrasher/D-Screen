"""Builds D-Screen from this repository into build/dscreen/:
- app/D-Screen.exe, Godot's export of engine/ (the "D-Screen" preset), then a check that its pack
  holds nothing but this repository's code, shaders, lines, props and icon;
- app/THIRD-PARTY-NOTICES.txt: ours and MAME's (dscreen/notices_head.txt), then Godot's;
- app/dscreen-hook.exe, the optional Claude Code hook, with Windows' own C# compiler;
- D-Screen-Setup-<version>.exe with Inno Setup 6, if it's installed.

Needs Windows, Godot 4.7.2 with its export templates (set GODOT to its console exe, or install it
with winget) and the .NET Framework 4 that ships with Windows.

  python tools/build.py
"""
import glob
import os
import re
import shutil
import struct
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ENGINE = os.path.join(ROOT, "engine")
OUT = os.path.join(ROOT, "build", "dscreen", "app")
# what the pack may hold: our code, shaders, the pet's lines and props, the icon, and Godot's own
# engine files (.godot/, project.binary, the class and uid caches)
ALLOWED = ("scripts/", "shaders/", "pet/", "dscreen/", ".godot/", "project.binary", "uid_cache.bin")


def godot_exe():
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    pk = glob.glob(os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages",
                                "GodotEngine.GodotEngine_*", "Godot_v4.7.2-stable_win64_console.exe"))
    if pk:
        return pk[0]
    found = shutil.which("godot")
    if not found:
        sys.exit("no Godot 4.7.2: set GODOT to Godot_v4.7.2-stable_win64_console.exe")
    return found


def version():
    m = re.search(r'application/product_version="(\d+\.\d+\.\d+)', open(os.path.join(ENGINE, "export_presets.cfg"),
                                                                       encoding="utf-8").read())
    return m.group(1)


def pck_files(exe):
    """The paths in the pack embedded at the end of a Godot 4 exe (pack format 2, 3 or 4)."""
    with open(exe, "rb") as f:
        f.seek(-12, 2)
        size, magic = struct.unpack("<Q4s", f.read(12))
        assert magic == b"GDPC", "no embedded pack"
        f.seek(-12 - size, 2)
        start = f.tell()
        magic, fmt, _maj, _min, _pat, _flags, _base = struct.unpack("<4sIIIIIQ", f.read(32))
        assert magic == b"GDPC" and fmt in (2, 3, 4), (magic, fmt)
        if fmt >= 3:                           # 3 and 4 (Godot 4.7) keep the directory's offset
            (dir_off,) = struct.unpack("<Q", f.read(8))
            f.seek(start + dir_off)
        else:
            f.read(16 * 4)
        (count,) = struct.unpack("<I", f.read(4))
        out = []
        for _ in range(count):
            (n,) = struct.unpack("<I", f.read(4))
            out.append(f.read(n).rstrip(b"\0").decode("utf-8"))
            f.read(8 + 8 + 16 + 4)
        return out


def main():
    godot = godot_exe()
    os.makedirs(OUT, exist_ok=True)
    subprocess.run([godot, "--headless", "--path", ENGINE, "--import"], capture_output=True)
    exe = os.path.join(OUT, "D-Screen.exe")
    r = subprocess.run([godot, "--headless", "--path", ENGINE, "--export-release", "D-Screen", exe],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0 or not os.path.isfile(exe):
        sys.exit("export failed:\n" + r.stdout[-3000:] + r.stderr[-3000:])
    paths = pck_files(exe)
    bad = [p for p in (q.removeprefix("res://") for q in paths) if not p.startswith(ALLOWED)]
    if bad:
        sys.exit("the pack holds files it must not ship:\n  " + "\n  ".join(sorted(bad)[:40]))
    print("D-Screen.exe: %d files in the pack, %.1f MB" % (len(paths), os.path.getsize(exe) / 1e6))

    godot_notes = os.path.join(OUT, "godot_notices.tmp")
    subprocess.run([godot, "--headless", "--path", ENGINE, "-s", "res://tools/license_notices.gd", "--", godot_notes],
                   check=True, capture_output=True)
    with open(os.path.join(OUT, "THIRD-PARTY-NOTICES.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(open(os.path.join(ROOT, "dscreen", "notices_head.txt"), encoding="utf-8").read())
        f.write(open(godot_notes, encoding="utf-8").read())
    os.remove(godot_notes)

    csc = os.path.join(os.environ["WINDIR"], "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe")
    subprocess.run([csc, "-nologo", "-optimize", "-target:winexe", "-out:" + os.path.join(OUT, "dscreen-hook.exe"),
                    "-win32icon:" + os.path.join(ENGINE, "dscreen", "icon.ico"),
                    os.path.join(ENGINE, "dscreen", "dscreen_hook.cs")], check=True)

    iscc = [p for p in (os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "Inno Setup 6", "ISCC.exe"),
                        os.path.join(os.environ.get("ProgramFiles(x86)", ""), "Inno Setup 6", "ISCC.exe"))
            if os.path.isfile(p)]
    if not iscc:
        print("no Inno Setup 6 (ISCC.exe): the app is in build/dscreen/app, the installer isn't built")
        return
    subprocess.run([iscc[0], "/Q", "/DAppVersion=" + version(), os.path.join(ROOT, "dscreen", "installer.iss")],
                   check=True)
    print("->", os.path.join("build", "dscreen", "D-Screen-Setup-%s.exe" % version()))


if __name__ == "__main__":
    main()
