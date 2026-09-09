extends Node
# =============================================================================
#  Loot Lagoon -- the adversarial sweep. Not shipped.
# =============================================================================
#
# The QA files that already exist ask three different questions:
#
#   qa_full   -- is the arithmetic right?
#   qa_stress -- is there an ORDER of valid actions that breaks an invariant?
#   qa_schema -- does a save from a LATER build survive this one?
#
# This asks the fourth, which none of them ask: what happens when the input is
# not valid at all. A save field holding a string where a number belongs. A
# server row with the keys missing. A popup dismissed that was never opened. A
# button pressed twice inside one frame.
#
# NONE OF THIS NEEDS A MODIFIED CLIENT, which is the reason it is worth having.
# A save arrives from another build through the ordinary cloud path. A server
# row arrives from a migration that is half applied -- and there are two of
# those in this project's history. A double press is a phone that dropped a
# frame. A null in a list is a player who deleted their account between the
# query and the render.
#
# HOW TO READ A FAILURE. Every case prints a `CASE:` line before it runs. A
# `SCRIPT ERROR` printed between one CASE line and the next belongs to that
# case, and it is a failure whether or not the assertion after it passed --
# the assertion only proves the game survived, not that it handled the input.
#
#   godot --headless --path . res://tools/qa_chaos.tscn 2>&1 | grep -B3 "SCRIPT ERROR"
#
# Run: godot --headless --path . res://tools/qa_chaos.tscn

var m: Control
var fails := 0
var checks := 0
var cases := 0

const SAVE_PATH := "user://coinvillage_save.json"

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await _await_boot()

	_section("1. a save file with the wrong types in it")
	await _t_hostile_save_fields()
	_section("2. a save that is not a save at all")
	await _t_hostile_save_files()
	_section("3. server rows with the keys missing")
	await _t_hostile_server_payloads()
	_section("4. screens opened and dismissed in impossible orders")
	await _t_page_and_popup_chaos()
	_section("5. the same button twice in one frame")
	await _t_double_fire()
	_section("6. numbers at the edge of the type")
	await _t_boundaries()

	# qa_full's seventh trap, pointing the other way: that one was a harness
	# DELETING a file another harness needed. This one WRITES a poisoned save
	# that every other harness on the machine will load.
	_restore_clean_state()

	print("QA-CHAOS: %d cases, %d checks, %s"
		% [cases, checks, "ALL PASS" if fails == 0 else "%d FAILURES" % fails])
	get_tree().quit(1 if fails > 0 else 0)

# WAIT FOR THE CONDITION, NOT FOR A DURATION -- qa_security's ninth trap.
func _await_boot() -> void:
	var t0 := Time.get_ticks_msec()
	while not bool(m.get("_booted")):
		if Time.get_ticks_msec() - t0 > 20000:
			_chk("the game finished booting", false, "gave up after 20s")
			return
		await get_tree().process_frame

func _section(name: String) -> void:
	print("")
	print("== %s" % name)

func _case(name: String) -> void:
	cases += 1
	print("CASE: %s" % name)

func _chk(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		fails += 1
		print("  [FAIL] %s %s" % [name, detail])

# The state every case has to leave the game in, whatever it was fed. Checked
# after each one rather than at the end, so a failure names the input.
func _coherent(where: String) -> void:
	var ok := true
	var why := ""
	if typeof(m.coins) != TYPE_INT or int(m.coins) < 0:
		ok = false
		why = "coins=%s" % str(m.coins)
	elif typeof(m.spins) != TYPE_INT or int(m.spins) < 0:
		ok = false
		why = "spins=%s" % str(m.spins)
	elif typeof(m.stars) != TYPE_INT or int(m.stars) < 0:
		ok = false
		why = "stars=%s" % str(m.stars)
	elif typeof(m.island_level) != TYPE_INT or int(m.island_level) < 1 \
			or int(m.island_level) > int(m.MAX_ISLAND):
		ok = false
		why = "island_level=%s" % str(m.island_level)
	elif typeof(m.buildings) != TYPE_ARRAY or m.buildings.size() != CV.BUILDINGS.size():
		ok = false
		why = "buildings=%s" % str(m.buildings)
	elif typeof(m.shields) != TYPE_INT or int(m.shields) < 0 \
			or int(m.shields) > int(m.SHIELD_CAP):
		ok = false
		why = "shields=%s" % str(m.shields)
	if ok and typeof(m.buildings) == TYPE_ARRAY:
		for b in m.buildings:
			if typeof(b) != TYPE_INT or int(b) < 0 or int(b) > int(CV.MAX_STAR):
				ok = false
				why = "buildings=%s" % str(m.buildings)
				break
	_chk("the island is still coherent after %s" % where, ok, why)

func _write_save(text: String) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()

func _reset() -> void:
	m._close_popup(true)
	m.coins = 5000
	m.spins = 30
	m.stars = 0
	m.shields = 0
	m.island_level = 1
	m.buildings = [0, 0, 0, 0, 0]
	m.pending_raids = []
	m.muted = true
	m.notif_enabled = false

# --- 1. a save with the wrong type in one field ------------------------------
#
# One field at a time, so a failure names the field. A whole-file mangle -- the
# next section -- proves the loader survives; this proves it survives WITHOUT
# losing the other twenty fields to one bad one.
const HOSTILE := [
	null, "", "not a number", -1, -999999999,
	9223372036854775807, 1.5, [], {}, [1, 2, 3], {"a": 1},
	[[[[[[[[[[]]]]]]]]]], true,
]

func _t_hostile_save_fields() -> void:
	_reset()
	m._flush_save()
	var base: Dictionary = _read_save()
	_chk("a real save was written to poison", not base.is_empty())
	if base.is_empty():
		return

	var keys: Array = base.keys()
	keys.sort()
	for key in keys:
		for i in HOSTILE.size():
			var bad: Dictionary = base.duplicate(true)
			bad[key] = HOSTILE[i]
			var label := "%s = %s" % [key, JSON.stringify(HOSTILE[i])]
			_case("save field %s" % label)
			_write_save(JSON.stringify(bad))
			m._load_game()
			m._seed_session()
			await get_tree().process_frame
			_coherent(label)
			# And the game must still be PLAYABLE, not merely non-negative --
			# a loader that survives by zeroing everything has still eaten the
			# island. One spin, and the wallet has to behave like a wallet.
			m.spins = maxi(int(m.spins), 5)
			var before: int = int(m.coins)
			m._last_bet = 1
			m.spins -= 1
			m._on_spin_finished(m._roll())
			await get_tree().process_frame
			_chk("a spin still resolves after %s" % label,
				typeof(m.coins) == TYPE_INT and int(m.coins) >= 0,
				"coins %d -> %s" % [before, str(m.coins)])

# --- 2. a file that is not a save at all -------------------------------------
func _t_hostile_save_files() -> void:
	var files := [
		["empty", ""],
		["whitespace", "  "],
		["not json", "}{ this is not json at all ["],
		["json but a number", "42"],
		["json but a string", "\"hello\""],
		["json but an array", "[1, 2, 3]"],
		["json null", "null"],
		["json true", "true"],
		["an empty object", "{}"],
		["infinity in a number field", "{\"coins\": Infinity, \"spins\": 5}"],
		["nan in a number field", "{\"coins\": NaN, \"spins\": 5}"],
		["a number past int64", "{\"coins\": 99999999999999999999999999, \"spins\": 5}"],
		["a float where an int goes", "{\"coins\": 1.7976931348623157e308}"],
		["negative everything", "{\"coins\": -5, \"spins\": -5, \"stars\": -5, \"shields\": -5, \"island_level\": -5, \"buildings\": [-1,-1,-1,-1,-1]}"],
		["deeply nested", "{\"coins\": " + "[".repeat(200) + "]".repeat(200) + "}"],
		["a very long string", "{\"coins\": 100, \"junk\": \"" + "x".repeat(200000) + "\"}"],
		["buildings too short", "{\"coins\": 100, \"buildings\": [1]}"],
		["buildings too long", "{\"coins\": 100, \"buildings\": [1,1,1,1,1,1,1,1,1,1]}"],
		["buildings of strings", "{\"coins\": 100, \"buildings\": [\"a\",\"b\",\"c\",\"d\",\"e\"]}"],
		["buildings of nulls", "{\"coins\": 100, \"buildings\": [null,null,null,null,null]}"],
		["an island past the last one", "{\"coins\": 100, \"island_level\": 999999}"],
		["a schema from the far future", "{\"coins\": 100, \"schema\": 999999}"],
		["a negative schema", "{\"coins\": 100, \"schema\": -1}"],
	]
	for entry in files:
		var label := String(entry[0])
		_case("save file: %s" % label)
		_write_save(String(entry[1]))
		m._load_game()
		m._seed_session()
		await get_tree().process_frame
		_coherent(label)

	# A save the process cannot read at all. The loader has to treat an
	# unreadable file as a new install rather than as an empty island, and
	# from inside there is no way to tell those apart except by surviving.
	_case("save file: a directory where the file goes")
	var d := DirAccess.open("user://")
	d.remove(SAVE_PATH)
	d.make_dir("coinvillage_save.json")
	m._load_game()
	m._seed_session()
	await get_tree().process_frame
	_coherent("a directory in place of the save")
	d.remove("coinvillage_save.json")

# --- 3. the server, answering with rubbish -----------------------------------
#
# Every one of these is a real shape. `null` in a list is a player deleted
# between the query and the render; a row with no `points` is a board read
# against a half-applied migration; five thousand raids at once is an account
# that has been away for a month.
func _t_hostile_server_payloads() -> void:
	_reset()
	var rows := [
		null, "", 0, [], {},
		{"points": null}, {"points": "lots"}, {"points": -5},
		{"name": null, "points": 10},
		{"name": "x".repeat(5000), "points": 10},
		{"id": null}, {"id": 12345},
		{"emoji": null}, {"emoji": "not an emoji at all"},
		{"island_level": -1, "points": 1}, {"island_level": 99999, "points": 1},
		{"buildings": null}, {"buildings": "five"}, {"buildings": [1, 2]},
		{"coins": -1}, {"coins": 9223372036854775807},
		{"rank_stars": null}, {"me": "yes"},
	]

	_case("_on_cloud_raids with a hostile list")
	m._on_cloud_raids(rows.duplicate(true))
	await get_tree().process_frame
	_coherent("a hostile raid list")

	_case("_on_cloud_raids with a list of nulls")
	m._on_cloud_raids([null, null, null])
	await get_tree().process_frame
	_coherent("a raid list of nulls")

	_case("_on_cloud_raids with an enormous list")
	var huge := []
	for i in 5000:
		huge.append({"kind": "steal", "coins": i})
	m._on_cloud_raids(huge)
	await get_tree().process_frame
	_coherent("five thousand raids at once")

	_case("_on_cloud_gifts with a hostile list")
	m._on_cloud_gifts(rows.duplicate(true))
	await get_tree().process_frame
	_coherent("a hostile gift list")

	_case("_on_cloud_gifts from a giver who deleted their account")
	# THE ONE SHAPE OUR OWN SERVER REALLY SENDS. `unseen_gifts` builds `by`
	# from public_player(from_player), and public_player answers NULL for an
	# island whose owner deleted their account -- a soft delete, so the row and
	# its foreign key both survive and the gift is still delivered. `by` is
	# then JSON null. _on_cloud_raids guards this case by name; its twin did
	# not, and a null there aborted the handler BEFORE Cloud.ack_gifts and
	# before _flush_save -- so the gift was never acked, the applied-list never
	# reached disk, and the same card was granted again on every launch.
	# rank_stars is what those stars feed, and rank_stars is the cloud merge
	# key, so it is a real number going up for free.
	var stars_before: int = int(m.stars)
	m._on_cloud_gifts([{"id": "ghost-gift", "set": "pirate", "idx": 0,
		"stars": 1, "at": 0.0, "by": null}])
	await get_tree().process_frame
	_chk("a gift from a deleted giver is applied and acked, not replayed",
		int(m.applied_gifts.size()) > 0 and m.applied_gifts.has("ghost-gift"),
		"applied=%s stars %d -> %d" % [str(m.applied_gifts), stars_before, int(m.stars)])
	_coherent("a gift from a deleted giver")

	_case("_on_cloud_gifts with cards that do not exist")
	m._on_cloud_gifts([
		{"id": "a", "set": "no such set", "idx": 0, "stars": 3},
		{"id": "b", "set": "pirate", "idx": -1, "stars": 3},
		{"id": "c", "set": "pirate", "idx": 999999, "stars": 3},
		{"id": "d", "set": "pirate", "idx": 0, "stars": 99},
		{"id": "e", "set": null, "idx": null, "stars": null}])
	await get_tree().process_frame
	_coherent("gifts of cards that do not exist")

	_case("_on_cloud_save_rejected with a hostile remote")
	m._on_cloud_save_rejected(0, {})
	m._close_popup(true)
	m._on_cloud_save_rejected(-1, {"save": null})
	m._close_popup(true)
	m._on_cloud_save_rejected(9223372036854775807, {"save": "not a dict"})
	m._close_popup(true)
	await get_tree().process_frame
	_coherent("a hostile save rejection")

	_case("_on_cloud_link_result with every status")
	for status in ["", "ok", "conflict", "gone", "no such status"]:
		m._on_cloud_link_result(status, {}, {})
		m._close_popup(true)
	await get_tree().process_frame
	_coherent("a hostile link result")

	_case("_on_cloud_signed_in with a hostile profile")
	m._on_cloud_signed_in({}, false, {})
	m._close_popup(true)
	m._on_cloud_signed_in({"name": null, "emoji": null}, true, {"save": "no"})
	m._close_popup(true)
	await get_tree().process_frame
	_coherent("a hostile sign-in")

	_case("the tournament placing, at the edges")
	for pair in [[0, 0], [-1, -1], [1, 0], [999999, 1], [1, 999999]]:
		m.tourney_owed_id = -1
		m.tourney_owed_points = 10
		m._tourney_pay(int(pair[0]), int(pair[1]))
		m._close_popup(true)
	await get_tree().process_frame
	_coherent("a hostile placing")

# --- 4. screens in impossible orders -----------------------------------------
func _t_page_and_popup_chaos() -> void:
	_reset()

	_case("dismiss a popup that was never opened")
	for i in 20:
		m._close_popup(true)
	await get_tree().process_frame
	_coherent("twenty dismissals of nothing")

	_case("every page, twice each, in a shuffled order")
	var keys: Array = m.pages.keys()
	keys.shuffle()
	for pass_no in 2:
		for key in keys:
			m._goto(m.pages[key])
			await get_tree().process_frame
	_coherent("every page twice")

	_case("a popup opened on top of a popup, ten deep")
	for i in 10:
		var vb: VBoxContainer = m._open_popup("stack %d" % i)
		_chk("the popup returned a body at depth %d" % i, vb != null)
	for i in 12:
		m._close_popup(true)
	await get_tree().process_frame
	_coherent("ten stacked popups")

	_case("navigate while a popup is up")
	m._open_popup("in the way")
	for key in keys:
		m._goto(m.pages[key])
		await get_tree().process_frame
	m._close_popup(true)
	await get_tree().process_frame
	_coherent("navigation behind a modal")

	_case("every page refilled from scratch")
	for key in keys:
		m._fill_page(key)
		await get_tree().process_frame
	_coherent("every page refilled")

	# NOT TESTED, AND THE REASON IS THE POINT. `_fill_page` is only ever
	# reached with a key out of `pages`, and `_fill_ranks` / `_fill_tourney`
	# are only ever reached with rows their own callers have already built --
	# both call sites filter with `if typeof(e) != TYPE_DICTIONARY: continue`
	# before a row is assembled, so raw server data cannot arrive here. Feeding
	# these three directly produced eight confident SCRIPT ERRORs against code
	# that is correctly guarded one frame upstream, which is a harness
	# measuring a state the game cannot be in.
	#
	# What IS worth driving is the shapes the guard lets through.
	_case("the boards, at the sizes their callers can really produce")
	var list := VBoxContainer.new()
	add_child(list)
	var l1 := Label.new()
	var l2 := Label.new()
	add_child(l1)
	add_child(l2)
	var big := []
	for i in 400:
		big.append({"name": "x".repeat(400), "emoji": "\U01F642", "stars": -i,
			"points": -i, "me": false, "id": "id%d" % i})
	for rows in [[], big]:
		m._fill_ranks(list, rows.duplicate(true))
		m._fill_tourney(list, l1, l2, rows.duplicate(true))
		await get_tree().process_frame
	list.queue_free()
	l1.queue_free()
	l2.queue_free()
	_coherent("an empty board and a four-hundred-row one")

# --- 5. the same button twice in one frame -----------------------------------
#
# Not theoretical. A phone that drops a frame delivers two taps before the
# first handler has redrawn, and every "claim" in the game is a branch that
# reads a flag and then writes it.
func _t_double_fire() -> void:
	_reset()
	m.coins = 100000000
	m.spins = 50

	_case("an upgrade requested twice before the frame ends")
	var before_coins: int = int(m.coins)
	m._on_upgrade_requested(0)
	m._on_upgrade_requested(0)
	m._close_popup(true)
	await get_tree().process_frame
	_chk("a double upgrade tap does not build two rungs for one price",
		int(m.buildings[0]) <= 2,
		"buildings=%s coins %d -> %d" % [str(m.buildings), before_coins, int(m.coins)])
	_coherent("a double upgrade")

	_case("the daily bonus claimed twice")
	m.daily_last = 0.0
	m._open_daily()
	m._close_popup(true)
	var c1: int = int(m.coins)
	m._open_daily()
	m._close_popup(true)
	await get_tree().process_frame
	_chk("the daily bonus pays once", int(m.coins) == c1,
		"%d -> %d" % [c1, int(m.coins)])

	_case("the shop free gift claimed twice")
	m.shop_free_last = 0.0
	m._claim_shop_gift()
	m._close_popup(true)
	var g1: int = int(m.coins)
	m._claim_shop_gift()
	m._close_popup(true)
	await get_tree().process_frame
	_chk("the free gift pays once", int(m.coins) == g1, "%d -> %d" % [g1, int(m.coins)])

	_case("a spin resolved twice on one stake")
	m.spins = 10
	var s0: int = int(m.spins)
	m._last_bet = 1
	m.spins -= 1
	var roll: Array = m._roll()
	m._on_spin_finished(roll)
	m._on_spin_finished(roll)
	await get_tree().process_frame
	_chk("resolving one spin twice never refunds the meter", int(m.spins) <= s0,
		"spins %d -> %d" % [s0, int(m.spins)])
	_coherent("a doubled spin")

	_case("a reel result the reels could not produce")
	for bad in [[], ["coin"], ["coin", "coin"], [null, null, null],
			["", "", ""], ["no such symbol", "no such symbol", "no such symbol"],
			["coin", "coin", "coin", "coin", "coin"], [0, 1, 2]]:
		m._last_bet = 1
		m._on_spin_finished(bad)
		await get_tree().process_frame
	_coherent("impossible reel results")

	_case("the piggy opened at its cap")
	m.piggy_coins = int(m._scaled(CV.PIGGY_CAP))
	m._open_piggy()
	m._close_popup(true)
	await get_tree().process_frame
	_coherent("the piggy opened at its cap")

# --- 6. numbers at the edge of the type --------------------------------------
func _t_boundaries() -> void:
	_reset()

	# THE WALLET IS NOT ASSERTED AT INT64 MAX, deliberately, and this note is
	# here so nobody re-adds it. Setting `coins` to 9223372036854775807 by hand
	# and then paying a win into it wraps negative -- of course it does, that is
	# what the type does -- but no reachable path produces that number. The
	# economy curve was bent at island 30 precisely so the largest figure in the
	# game stays many orders inside int64 (see cv.gd's two-slope note), and the
	# save loader clamps: the hostile-file section above feeds 1e308 and
	# 99999999999999999999999999 and both land coherent.
	#
	# So the honest test is the largest number the game can really hold, and
	# the loader against numbers it cannot.
	_case("a wallet far past any real player, then a spin")
	m.coins = 1000000000000000
	m.spins = 20
	m._last_bet = 5
	m.spins -= 1
	m._on_spin_finished(m._roll())
	await get_tree().process_frame
	_chk("a thousand-trillion wallet does not wrap negative", int(m.coins) >= 0,
		"coins=%s" % str(m.coins))

	_case("that wallet through a save round trip")
	m._flush_save()
	m._load_game()
	m._seed_session()
	await get_tree().process_frame
	_chk("and survives the save intact", int(m.coins) > 0,
		"coins=%s" % str(m.coins))
	_coherent("a very large wallet through the save")

	_case("the last island, fully built, upgraded again")
	m.island_level = int(m.MAX_ISLAND)
	m.buildings = [int(CV.MAX_STAR), int(CV.MAX_STAR), int(CV.MAX_STAR),
		int(CV.MAX_STAR), int(CV.MAX_STAR)]
	m.coins = 9223372036854775807
	for i in CV.BUILDINGS.size():
		m._on_upgrade_requested(i)
		m._close_popup(true)
	await get_tree().process_frame
	_chk("the last island does not roll over", int(m.island_level) <= int(m.MAX_ISLAND),
		"island_level=%s" % str(m.island_level))
	_coherent("the last island fully built")

	_case("the clock, at the edges")
	for t in [0.0, -1.0, -99999999999.0, 99999999999999.0]:
		m.daily_last = t
		m.shop_free_last = t
		m.col_deadline = t
		m._sanitize_clock()
		await get_tree().process_frame
	_coherent("a hostile clock")

func _read_save() -> Dictionary:
	# The game encrypts the save at rest; read it through the game's own decoder
	# (which still reads an older plaintext file too) rather than assuming plaintext.
	var text: String = m._read_save_text(SAVE_PATH)
	if text == "":
		return {}
	var d: Variant = JSON.parse_string(text)
	return d if typeof(d) == TYPE_DICTIONARY else {}

# DELETE THE SAVE. Do not write a tidy one over it.
#
# The first version of this called _reset() and _flush_save(), which looks like
# the careful thing and is not, because ONE FIELD CANNOT BE RESET: `clock_hw`.
# It is a high-water mark on purpose -- `_now()` only ever raises it, and
# `_load_game` adopts it with maxf -- so that a player who winds the phone
# forward for a free daily bonus is stuck in the future rather than handed one.
# It is an anti-cheat, and it is working exactly as designed.
#
# The save-field fuzzer above sets every key in the save to int64 max in turn,
# `clock_hw` included. 9223372036854775807 as a float is 9.22e18, where the
# gap between representable doubles is 2048 SECONDS -- so every duration the
# game computes quantises to a multiple of a kilosecond. _flush_save then wrote
# that clock back to disk, and the next harness on the machine loaded it.
#
# What that looks like is qa_full failing six checks about the timed offer and
# the daily streak, with figures like "it runs for the advertised two hours
# 8192s" and "the window is one fixed length [172032, 173056]" -- arithmetic
# errors, in the economy, in a file that had passed 390 checks an hour earlier.
# Nothing in it points at this harness. It is qa_full's seventh trap pointing
# the other way: that one was a harness DELETING a file another harness needed.
#
# Removing the file leaves a clean first run, which is a state the game handles
# by design and the only one this harness can honestly guarantee.
func _restore_clean_state() -> void:
	var d := DirAccess.open("user://")
	if d != null:
		d.remove(SAVE_PATH)
		d.remove("coinvillage_save.json.bak")
	var f := FileAccess.open("user://profile.json", FileAccess.WRITE)
	if f != null:
		f.store_string("{\"name\":\"Islander\",\"provider\":\"guest\"}")
		f.close()
