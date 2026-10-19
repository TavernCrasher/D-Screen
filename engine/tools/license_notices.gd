extends SceneTree
## Godot's own license notices (the engine and its third-party parts), as an exported game must
## carry them (docs.godotengine.org "Complying with licenses"). Written for D-Screen's
## THIRD-PARTY-NOTICES.txt by tools/pet_export.py --dscreen.
## godot --headless --path engine -s res://tools/license_notices.gd -- <out.txt>


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "notices.txt"
	var t := "Godot Engine\n\n" + Engine.get_license_text() + "\n\nGodot Engine's third-party components\n"
	for c in Engine.get_copyright_info():
		t += "\n- %s\n" % c["name"]
		for p in c["parts"]:
			for line in p["copyright"]:
				t += "  Copyright %s\n" % line
			t += "  License: %s\n" % p["license"]
	var lic := Engine.get_license_info()
	t += "\n\nLicense texts\n"
	for k in lic:
		t += "\n----- %s -----\n%s\n" % [k, lic[k]]
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(t)
	f.close()
	quit()
