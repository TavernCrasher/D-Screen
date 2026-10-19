class_name WinHelper
extends RefCounted
## The pet's Windows helper (pet/pet_helper.cs, with pet/pet_chd.cs for Dw1Disc's CHD images and
## pet/pet_duck.cs for D-Screen's read-only DuckStation watch),
## compiled with Windows' own C# compiler (.NET Framework 4, on every Windows 10/11) into
## user://pet_helper_<md5 of the sources>.exe: named after its sources, so a new build never
## collides with an old helper still running; older builds are removed when they aren't in use.

const SOURCES := ["res://pet/pet_helper.cs", "res://pet/pet_chd.cs", "res://pet/pet_duck.cs"]

static var error := ""           # why exe() returned ""


## The helper's path, built first when it's missing or its sources changed; "" if it can't be.
static func exe() -> String:
	var texts: Array[String] = []
	for s in SOURCES:
		texts.append(FileAccess.get_file_as_string(s))
		if texts[-1].is_empty():
			error = "missing %s" % s
			return ""
	var name := "pet_helper_%s.exe" % "".join(texts).md5_text().substr(0, 8)
	var exe_path := ProjectSettings.globalize_path("user://" + name)
	for old in DirAccess.get_files_at("user://"):
		if old.begins_with("pet_helper") and old.ends_with(".exe") and old != name:
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + old))
	if FileAccess.file_exists(exe_path):
		return exe_path
	var csc := OS.get_environment("WINDIR").path_join("Microsoft.NET/Framework64/v4.0.30319/csc.exe")
	if not FileAccess.file_exists(csc):
		error = "no C# compiler (%s)" % csc
		return ""
	# built under this process's own names, then renamed into place: the pet and the game can
	# both find it missing at once (CHD-6)
	var tmp := ProjectSettings.globalize_path("user://build_%d_" % OS.get_process_id())
	var args := ["-nologo", "-optimize", "-target:winexe", "-out:" + (tmp + "helper.exe").replace("/", "\\")]
	var made: Array[String] = [tmp + "helper.exe"]
	for i in SOURCES.size():
		var src: String = tmp + SOURCES[i].get_file()
		var f := FileAccess.open(src, FileAccess.WRITE)
		if f == null:
			error = "can't write %s" % src
			return ""
		f.store_string(texts[i])
		f.close()
		made.append(src)
		args.append(src.replace("/", "\\"))        # csc reads "C:/x/y" as options after the drive
	var out := []
	var ok := OS.execute(csc, args, out, true) == 0
	if ok and DirAccess.rename_absolute(made[0], exe_path) != OK and not FileAccess.file_exists(exe_path):
		ok = false
		out = ["can't move the build to %s" % exe_path]
	for p in made:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if not ok:
		error = "couldn't build the helper: %s" % "".join(out)
		return ""
	return exe_path
