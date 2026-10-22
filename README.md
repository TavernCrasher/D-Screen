# D-Screen

A desktop partner for Digimon World 1.

D-Screen is an unofficial fan project, not affiliated with or endorsed by Bandai Namco or Toei
Animation. Digimon is their trademark. No game data is included: it reads your own copy of
Digimon World 1.

Your DW1 partner lives on your desktop: they walk along the taskbar and the tops of your windows,
sleep when you're away, get hungry, need the toilet and train at File City's gym. They're drawn
with DW1's own model, animations, sounds and text box, all read from your disc image each time
D-Screen starts. If you play DW1 in DuckStation, they're the partner from your memory card save.
The app's own README, with everything it does, is [dscreen/README.txt](dscreen/README.txt).

This repository is D-Screen's source code, so you can read what it does and build it yourself.

## What it does on your PC

- **It never goes online.** There is no network code in it.
- **It reads your disc image** (.cue/.bin, .iso, .chd or .m3u) for the models, animations, sounds,
  text and the game's tables. Only the original, unmodified Digimon World (USA) is supported.
- **It builds a small helper** on first run, from the C# sources in `engine/pet/*.cs`, with the C#
  compiler that comes with Windows (.NET Framework 4's `csc.exe`). The helper:
  - lists your windows and taskbars (their positions only), so your partner can stand on them;
    tells the app how long ago you last used the keyboard or mouse (Windows' `GetLastInputInfo`,
    a time, not what you typed), so they can fall asleep; and checks whether the left or right
    mouse button is down (`GetAsyncKeyState` for those two buttons only, never keys), so a click
    elsewhere closes their menu (`pet_helper.cs`);
  - reads CHD disc images (`pet_chd.cs`, a port of MAME's CHD reader);
  - watches DuckStation **read-only** to know which save is being played: it opens DuckStation's
    process with `PROCESS_QUERY_INFORMATION | PROCESS_VM_READ` only, and never writes to it
    (`pet_duck.cs`).
- **It writes your memory card only when you answer Yes** in its Apply window, only while
  DuckStation is closed, and after a backup of the card.
- **Its files** (settings, your partner's desktop progress, the sound cache, card backups and the
  compiled helper) are in `%APPDATA%\D-Screen`.
- **The optional Claude Code hook** (`engine/dscreen/dscreen_hook.cs`): if you tick it in the
  installer, it adds five async hooks to `~/.claude/settings.json` after a backup; each one
  appends a line to a file in `%APPDATA%\D-Screen` that the app reads. Uninstalling removes them.

The installer isn't signed, so Windows SmartScreen may warn you before it runs. Each
[release](https://github.com/TavernCrasher/D-Screen/releases) lists its installer's SHA-256 and a
VirusTotal report; check your download with `Get-FileHash D-Screen-Setup-<version>.exe` in
PowerShell.

### If Windows Defender or your browser flags it

A few antivirus engines, Microsoft Defender among them, flag the installer with a
machine-learning guess (Defender's is a `Trojan:Win32/Wacatac` name ending in `!ml`, which it gives
many unsigned installers; each release lists its scan). Nothing in it matches known malware: it's flagged for what's listed
above, building a helper on first run and reading another program's memory. If your browser
blocks the download or Defender quarantines it, you can check the file's SHA-256 against the
release, read the source here, and allow it in Windows Security > Virus & threat protection >
Protection history. Only do that for a file whose hash matches the release.

## Known issues

- If you answer **No** (or **No, stop asking**) in the Apply window, new desktop training doesn't count until those gains are in your save (the next Apply window's **Yes**, or Settings > **Apply to DW1**). Your partner doesn't say so yet: the only sign is that the stat ("Offense +1") is missing from what they say after a session. A clearer message is planned for the next update.

## Building

You need Windows, [Godot 4.7.2](https://godotengine.org/) with its export templates, Python 3 and,
for the installer, [Inno Setup 6](https://jrsoftware.org/isinfo.php).

```
python tools/build.py
```

This exports `build/dscreen/app/D-Screen.exe`, checks that the exported pack holds only this
repository's files, writes the third-party notices, compiles `dscreen-hook.exe` and builds
`build/dscreen/D-Screen-Setup-<version>.exe`. If Godot isn't installed with winget, set `GODOT`
to `Godot_v4.7.2-stable_win64_console.exe`. Run the exported `D-Screen.exe`: the code expects the
export's feature tags (`pet`, `dscreen`), which a plain run from the editor doesn't set.

## What this repository never holds

No game data from Digimon World 1 or any other game, no disc or memory card images, no decompiled
code. `tools/check_tree.py` enforces it: every file must be on its allowlist. CI runs it on every
push; turn on the same check before each commit with:

```
git config core.hooksPath .githooks
```

## License

D-Screen's code is under the [MIT License](LICENSE), (c) 2026 Tav. Not covered by it:

- the fat dragon icon (`engine/dscreen/icon*`), the partners' lines (`engine/pet/lines/`) and the
  gym props (`engine/pet/props/`): (c) 2026 Tav, all rights reserved;
- `engine/pet/pet_chd.cs`, a port of MAME's CHD code: BSD-3-Clause, Aaron Giles (see its header
  and [dscreen/notices_head.txt](dscreen/notices_head.txt)).

## Credits

Thanks to SydMontague, whose Digimon World 1 research made much of this possible, and to jype's
[dw_decomp](https://github.com/jype0/dw_decomp) (MIT). D-Screen runs on the
[Godot Engine](https://godotengine.org/) (MIT).
