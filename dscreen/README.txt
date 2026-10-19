D-Screen
a desktop partner for Digimon World 1

D-Screen is an unofficial fan project, not affiliated with or endorsed by Bandai Namco or Toei
Animation. Digimon is their trademark. No game data is included: it reads your own copy of
Digimon World 1.


WHAT IT IS
Your Digimon World 1 partner lives on your desktop: they walk along the taskbar and the tops of
your windows, sleep when you're away, get hungry, need the toilet and train at File City's
gym. They're drawn with DW1's own model, animations, sounds and text box, all read from your
disc image each time D-Screen starts.

If you play DW1 in DuckStation, they're the partner from your memory card save. What they gain
on the desktop can be written into that save (the Apply window: Yes, No, or No, stop asking).
When you load their save in DuckStation they say goodbye and go into the game; when DuckStation
closes they come back as the save left them.


WHAT YOU NEED
- Windows 10 or 11.
- Your own Digimon World (USA) disc image (SLUS-01032), the original, unmodified game:
  .cue/.bin, .iso, .chd (CHD v5) or .m3u. If DuckStation's game list has it, D-Screen finds it
  by itself. Modded discs that move the game's tables aren't supported.
- For the save bridge: DuckStation with DW1 saves on its memory cards. Without one your partner
  is a Ninjamon just for the desktop, and their care isn't kept between launches.


INSTALLING
The installer isn't code-signed, so Windows SmartScreen may say "Windows protected your PC":
click More info, then Run anyway. Each release on https://github.com/TavernCrasher/D-Screen
lists its installer's SHA-256 and a VirusTotal report. To check your download, in PowerShell:
  Get-FileHash D-Screen-Setup-0.1.0.exe
and compare the Hash with the release's.


FIRST RUN
The setup window shows this notice, finds or asks for the disc image and checks it, then lists
the DW1 saves on DuckStation's memory cards so you can pick your partner. You can change both
later in their menu: Settings > About (the disc and the save), or Settings > DW1 Save.


THEIR MENU
Click them: Talk, Praise, Scold, Train (the props: the Meat, the toilet and the six gym
stations), Sleep, Settings, Bye. Drag them to move them; throw them if you like.
Settings: Speech (Text, Mixed, Digi), Quiet, Stay Put, Name, Sounds, Gym Sounds, Volume,
DW1 Save, Apply to DW1, Ask to Apply, About.


THE SAVE BRIDGE AND SAVE STATES
- Gains are written into the save only while DuckStation is closed, after a backup of the card
  (the last 5 per card, in D-Screen's folder, card_backup).
- If you resume a DuckStation save state made before the desktop gains were applied and then
  save in DW1, the old save is written back. The gains are offered again later; they're never
  applied twice.
- A save state from before a rebirth brings back the old partner: the desktop gains the reborn
  one hadn't applied yet are set aside, not applied to anyone.


CLAUDE CODE (optional)
If you use Claude Code, the installer can let your partner react to it: they cheer when a long
task finishes, look up when Claude Code asks for permission, and sulk when something fails. It adds
five small async hooks (dscreen-hook.exe) to ~/.claude/settings.json, after a backup beside it
(settings.json.bak-dscreen-<date>; every install and uninstall keeps one, delete old ones when
you like). Restart Claude Code for it to pick them up. Uninstalling removes them again, and only
them. By hand:
  "%LOCALAPPDATA%\Programs\D-Screen\dscreen-hook.exe" --install
  "%LOCALAPPDATA%\Programs\D-Screen\dscreen-hook.exe" --uninstall


WHERE THINGS ARE
- The app: %LOCALAPPDATA%\Programs\D-Screen
- Their files (settings, their desktop progress, the sound cache, card backups): %APPDATA%\D-Screen
D-Screen never goes online. It reads DuckStation's memory read-only to know which save is being
played, and writes your memory card only when you answer Yes in the Apply window.


SOURCE CODE
D-Screen's source is public, so you can read what it does and build it yourself:
https://github.com/TavernCrasher/D-Screen (its README lists everything it does on your PC).


CREDITS
D-Screen's code: (c) 2026 Tav, under the MIT License (THIRD-PARTY-NOTICES.txt). Its fat dragon
icon, the partners' lines and the gym props: (c) 2026 Tav, all rights reserved.
Thanks to SydMontague, whose Digimon World 1 research made much of this possible, and to
jype's dw_decomp (MIT). D-Screen's CHD reader is a port of MAME's (Aaron Giles,
BSD-3-Clause); it runs on the Godot Engine (MIT). Their notices: THIRD-PARTY-NOTICES.txt.


UNINSTALL
Windows Settings > Apps > D-Screen. It asks whether to keep their files (keep them if your
partner has desktop gains you haven't applied yet).
