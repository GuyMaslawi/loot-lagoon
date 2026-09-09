extends Node
# Temporary QA harness -- proves the plaintext->encrypted save migration.
# Not shipped. An existing tester's device has a PLAINTEXT coinvillage_save.json
# written by a build before encryption; this checks the first launch after the
# update reads it (nothing lost) and re-writes it encrypted.

var m: Control
var fails := 0

func _chk(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])

func _ready() -> void:
	var path := "user://coinvillage_save.json"
	# Clear any leftovers from a previous run, plus the .bak/.tmp siblings.
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

	# Seed an OLD-FORMAT (plaintext) save, exactly what a pre-encryption build left.
	var seeded := {"schema": 1, "coins": 424242, "spins": 17, "stars": 5,
		"rank_stars": 88, "island_level": 4, "buildings": [1, 0, 2, 0, 0]}
	var pf := FileAccess.open(path, FileAccess.WRITE)
	pf.store_string(JSON.stringify(seeded))
	pf.close()
	var head_before := _first4(path)
	_chk("the seeded save is plaintext to begin with (not GDEC)", head_before != "GDEC", head_before)

	# Launch the game against it.
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout

	# It must have read the old plaintext values -- nothing lost in migration.
	_chk("migrated coins read from the old plaintext save", int(m.coins) == 424242, "coins=%d" % m.coins)
	_chk("migrated rank read too", int(m.rank_stars) == 88, "rank=%d" % m.rank_stars)

	# Force a write, then the file on disk must be encrypted (GDEC magic).
	m.coins = 500000
	var wrote: bool = m._write_save(m._save_dict())
	_chk("the save re-wrote successfully", wrote)
	var head_after := _first4(path)
	_chk("the migrated save is now encrypted at rest (GDEC magic)", head_after == "GDEC", head_after)

	# And a plain text-editor read now yields no economy -- the point of it all.
	var raw := FileAccess.open(path, FileAccess.READ)
	var as_text := raw.get_as_text()
	raw.close()
	_chk("the encrypted save does not expose coins to a text editor",
		not as_text.contains("500000") and not as_text.contains("coins"), as_text.substr(0, 40))

	# The game reads its own encrypted save back correctly.
	var reloaded: Dictionary = m._read_save()
	_chk("the game reads its own encrypted save back", int(reloaded.get("coins", 0)) == 500000,
		"coins=%s" % str(reloaded.get("coins")))

	# A tampered encrypted file (one byte flipped in the body) is rejected.
	var eb := FileAccess.open(path, FileAccess.READ)
	var bytes := eb.get_buffer(eb.get_length())
	eb.close()
	# Flip a byte in the middle -- squarely inside the encrypted content, not the
	# trailing AES-block padding past the real length (which the MD5 ignores).
	var at := bytes.size() / 2
	bytes[at] = bytes[at] ^ 0xFF
	var tb := FileAccess.open(path, FileAccess.WRITE)
	tb.store_buffer(bytes)
	tb.close()
	var after_tamper: String = m._read_save_text(path)
	_chk("a tampered encrypted save is refused (not silently accepted)", after_tamper == "",
		"len=%d" % after_tamper.length())

	print("QA: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _first4(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var b := f.get_buffer(4)
	f.close()
	return b.get_string_from_ascii()
