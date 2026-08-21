# What build am I looking at?
#
# TestFlight will not answer this from inside the game, and the App Store
# version on the phone is whatever was last *installed*, not what was last
# uploaded -- so the honest way to know a change reached the device is for the
# build to say so itself. Without that, "I don't see my change" and "I forgot
# to press Update" look identical, and both cost an afternoon.
#
# ship.sh writes build_info.json next to project.godot at export time. It is
# generated and git-ignores itself out of the repo, so nothing here is ever
# committed stale, and a run from the editor -- where the file does not exist
# -- simply says "dev".
class_name BuildID
extends RefCounted

const PATH := "res://build_info.json"

static func label() -> String:
	var info := read()
	if info.is_empty():
		return "dev"
	return "v%s (%s)" % [info.get("version", "?"), info.get("build", "?")]

static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
