extends Node
# Temporary QA harness -- card seasons, the break, and the sign that it turned
# over. Not shipped.
#
# All of this happens while the app is CLOSED, which is why it needs a harness:
# the only way a player experiences a rollover is by opening the game and
# finding a different shelf than they left. Every check here winds the clock and
# asks what they would see.

var m: Control
var fails := 0

func _ready() -> void:
	_wipe()
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	_t_cycle_is_global()
	_t_rollover_wipes_once()
	_t_break_pauses_drops()
	_t_first_run_is_quiet()
	_t_five_star_is_rare()
	print("QA-SEASON: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _wipe() -> void:
	for f in ["user://coinvillage_save.json", "user://coinvillage_save.json.bak",
			"user://coinvillage_save.json.tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)

func _chk(name: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1

# _now() is a high-water mark, so the clock only ever goes forward.
func _jump_to(t: float) -> void:
	m.clock_hw = maxf(m.clock_hw, t)

# --- one clock for everybody --------------------------------------------------
func _t_cycle_is_global() -> void:
	print("the season clock is global, not per player")
	var cyc: float = CV.SEASON_CYCLE_SECS
	_chk("a cycle is the season plus the break",
		 is_equal_approx(cyc, CV.COLLECTION_SEASON_DAYS * 86400.0 + CV.COLLECTION_BREAK_HOURS * 3600.0),
		 str(cyc))
	var i := CV.season_index(cyc * 7.0 + 100.0)
	_chk("the index is the cycle count", i == 7, str(i))
	_chk("collecting opens at the top of the cycle",
		 is_equal_approx(CV.season_starts(7), cyc * 7.0))
	_chk("and closes a season later, not a cycle later",
		 is_equal_approx(CV.season_ends(7) - CV.season_starts(7),
						 CV.COLLECTION_SEASON_DAYS * 86400.0))
	# Two players opening the game weeks apart are in the same season -- which
	# the old per-player deadline could never manage.
	_chk("two players a fortnight apart are in the same season",
		 CV.season_index(cyc * 3.0 + 86400.0) == CV.season_index(cyc * 3.0 + 15.0 * 86400.0))

# --- the shelf empties exactly once ------------------------------------------
func _t_rollover_wipes_once() -> void:
	print("a season turns over while the app is shut")
	var idx: int = CV.season_index(m._now())
	m.col_season = idx
	m.col_season_new = false
	m._ensure_collections()
	var owned: Array = m.col_owned["beach"]
	owned[0] = true
	owned[1] = true
	m.col_claimed["beach"] = true
	m.col_mega_claimed = true

	# Still inside the same season: nothing may be touched.
	m._ensure_collections()
	_chk("mid-season the shelf is left alone", bool((m.col_owned["beach"] as Array)[0]))

	# Forward into the next one.
	_jump_to(CV.season_starts(idx + 1) + 60.0)
	m._ensure_collections()
	var after: Array = m.col_owned["beach"]
	_chk("the new season starts empty", not bool(after[0]) and not bool(after[1]))
	_chk("and the claims go with it",
		 not bool(m.col_claimed.get("beach", false)) and not m.col_mega_claimed)
	_chk("the player is told it happened", m.col_season_new)
	_chk("the season on record moved", m.col_season == idx + 1, str(m.col_season))

	# Filling it in and re-running must NOT wipe again -- the old code re-armed
	# a deadline from `now`, so every launch was a fresh month.
	var again: Array = m.col_owned["beach"]
	again[0] = true
	m._ensure_collections()
	_chk("running it again does not wipe a second time", bool((m.col_owned["beach"] as Array)[0]))

	# And seeing the shelf is what clears the sign.
	m._fill_page("collections")
	_chk("opening the shelf clears the badge", not m.col_season_new)

# --- the lull ----------------------------------------------------------------
func _t_break_pauses_drops() -> void:
	print("the hours between seasons")
	var idx: int = CV.season_index(m._now())
	_jump_to(CV.season_ends(idx) + 600.0)
	m._ensure_collections()
	_chk("the game knows it is between seasons", m._col_break())
	_chk("and knows when the next one opens",
		 is_equal_approx(m._col_opens_at(), CV.season_starts(idx + 1)))

	# Two thousand spins' worth of rolls, and not one card may land.
	for c in CV.COLLECTIONS:
		m.col_owned[c["id"]] = []
		for _i in (c["items"] as Array).size():
			(m.col_owned[c["id"]] as Array).append(false)
	for _i in 2000:
		m._maybe_drop_card()
	var any := false
	for c in CV.COLLECTIONS:
		for v in (m.col_owned[c["id"]] as Array):
			if bool(v):
				any = true
	_chk("no card drops during the break", not any)

	# A card that was PAID for still lands. Money never waits on a clock.
	var card: Dictionary = m._grant_chest_card(2)
	_chk("but a bought card still arrives", not card.is_empty(), str(card.get("name", "")))

	# Out the far side.
	_jump_to(CV.season_starts(idx + 1) + 60.0)
	m._ensure_collections()
	_chk("collecting reopens on the hour it said", not m._col_break())

# --- launch one says nothing --------------------------------------------------
func _t_first_run_is_quiet() -> void:
	print("a player who has never seen a season end")
	m.col_season = -1          # what an older save, or a fresh install, looks like
	m.col_season_new = false
	m._ensure_collections()
	_chk("the first run wipes without announcing anything", not m.col_season_new)
	_chk("and records the season it landed in",
		 m.col_season == CV.season_index(m._now()), str(m.col_season))

# --- the whole point ----------------------------------------------------------
#
# Measured against the tables rather than trusted: a gold card is the last card
# of a set, so its rate alone decides whether a season lasts a month or an
# afternoon.
func _t_five_star_is_rare() -> void:
	print("how long a legendary actually takes")
	var w: Array = CV.DROP_STAR_WEIGHTS
	var total := 0.0
	for v in w:
		total += float(v)
	var p5 := float(w[4]) / total
	_chk("a spin-dropped card is 5-star well under 1% of the time",
		 p5 < 0.01, "%.2f%%" % (p5 * 100.0))

	# Every chest tier, against its own published row.
	var pub := [0.5, 3.0, 10.0]
	for tier in 3:
		var pct: Array = CV.star_odds(tier)
		_chk("chest tier %d publishes %.1f%% for 5-star" % [tier, pub[tier]],
			 is_equal_approx(float(pct[4]), pub[tier]), "%.2f%%" % float(pct[4]))
	_chk("and the tiers still climb, so paying buys something",
		 float(CV.star_odds(0)[4]) < float(CV.star_odds(1)[4])
			 and float(CV.star_odds(1)[4]) < float(CV.star_odds(2)[4]))
