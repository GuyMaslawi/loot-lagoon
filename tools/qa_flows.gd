extends Node
# Temporary QA harness #2 -- drives the interactive flows. Not shipped.

var m: Control
var fails := 0
var errors_seen := 0

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	await _t_page_spam()
	await _t_popup_spam()
	await _t_autospin()
	await _t_every_purchase()
	await _t_boxes_and_melt()
	await _t_steal_raid()
	await _t_season_rollover()
	await _t_offline_raids()
	print("QA-FLOWS: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _chk(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])

# A raid puts a full-screen overlay up and waits for a tap. Nobody is here to
# tap, so the harness does it -- otherwise every test after the first raid runs
# behind a modal that never lifts.
func _tap_through_raid() -> void:
	if m._match != null:
		m._match._live = true
		m._match._lock_in()
		m._match._close()
		return
	if m._visit != null and m._visit._stage != null:
		for c in m._visit._stage.get_children():
			if c is Button and not (c as Button).disabled:
				(c as Button).pressed.emit()
				return

# Every page filled once in a fixed order, then long enough for banners,
# confetti and coin flights to have freed themselves.
func _settle() -> void:
	for key in ["shop", "quests", "collections", "boxes", "options", "alerts"]:
		m._fill_page(key)
		await get_tree().process_frame
	await get_tree().create_timer(3.5).timeout

func _nodes(n: Node) -> int:
	var t := 1
	for c in n.get_children():
		t += _nodes(c)
	return t

# --- hammering the navigation -------------------------------------------------
func _t_page_spam() -> void:
	print("page spam")
	var targets := [m.slot_page, m.village_page]
	for k in m.pages:
		targets.append(m.pages[k])
	# Both measurements are taken from the same fixed state: every page filled
	# once, in the same order, with nothing arriving that would change what a
	# page contains. Without that the count moves with content -- the alerts
	# log grows while the test runs, the spares list grows with it -- and the
	# check is measuring the game playing rather than the tree leaking.
	m.notif_enabled = false
	m.notif_log.clear()
	await _settle()
	var before := _nodes(m)
	for i in 400:
		m._goto(targets.pick_random())
		await get_tree().process_frame
	await _settle()
	var after := _nodes(m)
	_chk("400 page changes leave one page current", m._current_page != null and not m._transitioning)
	# Deliberately loose. The whole-tree count moves with page *content* between
	# runs -- the alerts log grows, the spares list grows, banners are still
	# fading -- so this only catches runaway growth. The per-body checks below
	# are the exact ones.
	_chk("page spam leaves the tree the size it found it", after <= before + 40, "%d -> %d" % [before, after])
	# Where the growth landed, so a regression here names its own culprit.
	var by := {}
	for c in m.get_children():
		var key := "%s:%s" % [c.get_class(), c.name]
		by[key] = int(by.get(key, 0)) + _nodes(c)
	var rows := by.keys()
	rows.sort_custom(func(a, b) -> bool: return int(by[a]) > int(by[b]))
	for i in mini(8, rows.size()):
		print("      %6d  %s" % [by[rows[i]], rows[i]])
	# Where, exactly. A page body rebuilt over and over must land on the same
	# node count every time; anything else is a rebuild leaking into the tree.
	for key in ["shop", "quests", "collections", "boxes", "options", "alerts"]:
		var body: Node = m._page_bodies[key]
		m._fill_page(key)
		await get_tree().process_frame
		await get_tree().process_frame
		var a := _nodes(body)
		for r in 6:
			m._fill_page(key)
			await get_tree().process_frame
			await get_tree().process_frame
		var b := _nodes(body)
		_chk("  %s body is stable across rebuilds" % key, b <= a, "%d -> %d" % [a, b])
	var visible := 0
	for t in targets:
		if t.visible:
			visible += 1
	_chk("exactly one page is visible afterwards", visible == 1, "visible=%d" % visible)

# --- hammering the modals -----------------------------------------------------
func _t_popup_spam() -> void:
	print("popup spam")
	var before := _nodes(m)
	for i in 120:
		m._open_daily()
		m._close_popup()
		m._open_popup("Test")
		m._close_popup(true)
		await get_tree().process_frame
	m._close_popup(true)
	await get_tree().create_timer(1.0).timeout
	_chk("no popup is left standing", m._popup == null)
	_chk("popup spam does not grow the tree", _nodes(m) < before + 300, "%d -> %d" % [before, _nodes(m)])

# --- the auto-spin loop -------------------------------------------------------
func _t_autospin() -> void:
	print("auto spin")
	m._goto(m.slot_page)
	await get_tree().create_timer(0.8).timeout
	m.spins = 40
	m.auto_spin = true
	m.slot.bet = 1
	m._schedule_auto_spin(0.1)
	var t := 0.0
	var lowest := 999
	var spins_done := 0
	var last_spins := int(m.spins)
	while t < 25.0 and m.auto_spin:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		if int(m.spins) < last_spins:
			spins_done += 1
		last_spins = int(m.spins)
		lowest = mini(lowest, int(m.spins))
		_tap_through_raid()
	_chk("auto spin actually kept spinning", spins_done >= 3, "%d spins in %.0fs" % [spins_done, t])
	_chk("auto spin keeps running and never overdraws", lowest >= 0, "lowest spins seen=%d" % lowest)
	# now starve it and confirm it gives up rather than spinning on nothing
	m.spins = 0
	m.auto_spin = true
	m._schedule_auto_spin(0.1)
	var t2 := 0.0
	while t2 < 12.0 and m.auto_spin:
		await get_tree().create_timer(0.2).timeout
		t2 += 0.2
		_tap_through_raid()
	_chk("auto spin stops itself on an empty meter", not m.auto_spin, "after %.1fs" % t2)
	m.auto_spin = false
	await get_tree().create_timer(2.0).timeout

# --- buying everything --------------------------------------------------------
func _t_every_purchase() -> void:
	print("simulated purchase of every pack")
	var packs := [CV.STARTER_PACK, CV.PIGGY_PACK]
	for group in [CV.CHEST_PACKS, CV.SPIN_PACKS, CV.COIN_PACKS, CV.BUNDLE_PACKS, CV.TIMED_OFFERS]:
		for p in group:
			packs.append(p)
	var bad := 0
	for pack in packs:
		var before_coins: int = m.coins
		var before_spins: int = m.spins
		m.piggy_coins = 9999          # so the piggy has something to hand over
		m.piggy_promised = 0
		m._on_purchase_ok(IAP.PREFIX + String(pack["id"]))
		await get_tree().process_frame
		var gained: bool = m.coins > before_coins or m.spins > before_spins \
			or int(pack.get("cards", 0)) > 0 or int(pack.get("shields", 0)) > 0
		if not gained:
			bad += 1
			print("    %s granted nothing" % pack["id"])
	_chk("every pack grants something", bad == 0)
	# and the id the build does not know
	var before: int = m.coins
	m._on_purchase_ok(IAP.PREFIX + "no_such_pack")
	_chk("an unknown product id is survivable", m.coins == before)
	# the piggy that emptied between pay and grant
	m.piggy_coins = 0
	m.piggy_promised = 7777
	var pre: int = m.coins
	m._on_purchase_ok(IAP.PREFIX + String(CV.PIGGY_PACK["id"]))
	_chk("a piggy emptied mid-purchase still pays what was promised", m.coins == pre + 7777,
		"+%d" % (m.coins - pre))
	m._close_popup(true)
	await get_tree().create_timer(0.5).timeout

# --- stars in, cards out ------------------------------------------------------
func _t_boxes_and_melt() -> void:
	print("card boxes and melting")
	m.stars = 100000
	var opened := 0
	for i in 300:
		for box in CV.CARD_BOXES:
			if m.stars >= int(box["stars"]):
				m._open_card_box(box)
				opened += 1
		m._close_popup(true)
		if i % 40 == 0:
			await get_tree().process_frame
	_chk("boxes opened without incident", opened > 0 and m.stars >= 0, "%d boxes, %d stars left" % [opened, m.stars])
	var spare: int = m._dupe_card_count()
	var worth: int = m._dupe_star_value()
	var before: int = m.stars
	var rank_before: int = m.rank_stars
	for row in m._all_dupes():
		m._melt_stack(row["set"]["id"], row["idx"], int(row["count"]))
	_chk("melting the pile pays exactly what it was worth", m.stars == before + worth,
		"%d spares worth %d, got %d" % [spare, worth, m.stars - before])
	_chk("the pile is empty afterwards", m._dupe_card_count() == 0)
	_chk("melting never moved the rank", m.rank_stars == rank_before,
		"%d -> %d" % [rank_before, m.rank_stars])
	await get_tree().create_timer(0.5).timeout

# --- a steal, all the way through --------------------------------------------
func _t_steal_raid() -> void:
	print("steal raid")
	m._close_popup(true)
	m._goto(m.slot_page)
	await get_tree().create_timer(0.8).timeout
	m._stock_rivals()
	m._pick_next_target()
	m._last_bet = 3
	var before: int = m.coins
	m._start_visit("steal")
	var waited := 0.0
	while m._raiding() and waited < 20.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
		if m._visit != null:
			for c in m._visit._stage.get_children():
				if c is Button and not (c as Button).disabled:
					(c as Button).pressed.emit()
					break
	_chk("a steal finishes and hands the game back", not m._raiding(), "waited %.1fs" % waited)
	_chk("the steal paid into the wallet", m.coins >= before, "%d -> %d" % [before, m.coins])
	await get_tree().create_timer(1.5).timeout

# --- the season ending --------------------------------------------------------
func _t_season_rollover() -> void:
	print("collection season rollover")
	# Seasons run on a global cycle, so winding a private deadline into the past
	# proves nothing -- _ensure_collections reads the clock. Moving the RECORDED
	# season back is what a player who was away for a rollover looks like.
	m.col_season -= 1
	m._ensure_collections()
	var any := false
	for c in CV.COLLECTIONS:
		for v in m.col_owned[c["id"]]:
			if v:
				any = true
	_chk("an expired season clears the shelf", not any)
	_chk("a new season is dated forward", m.col_deadline > m._now())
	_chk("the rank survives the season", m.rank_stars > 0, "rank=%d" % m.rank_stars)

# --- rivals hitting back while the app was shut -------------------------------
func _t_offline_raids() -> void:
	print("offline raids")
	m.coins = 500000
	m.shields = 0
	m.buildings = [5, 5, 5, 5, 5]
	# Seeded as a plan, not as an elapsed time. _offline_raids used to roll the
	# raids itself from a stopwatch; it now replays the plan that was written
	# when the app went to the background, and this test went on assigning
	# _offline_elapsed to a property that no longer exists -- which raises,
	# takes the test out with it, and still prints ALL PASS because the harness
	# counts failed checks rather than checks that never ran.
	m.pending_raids = [
		{"at": 0.0, "kind": "steal", "coins": 900000, "npc": "nobody", "text": "raid", "emoji": "\U01F6A8"},
		{"at": 0.0, "kind": "smash", "building": 2, "text": "smash", "emoji": "\U01F6A8"},
		{"at": 0.0, "kind": "blocked", "text": "blocked", "emoji": "\U01F6A8"},
	]
	m._offline_raids()
	var flat := true
	for b in m.buildings:
		if int(b) < 0:
			flat = false
	_chk("offline raids never drive a building negative", flat, str(m.buildings))
	_chk("offline raids never drive coins negative", m.coins >= 0, "coins=%d" % m.coins)
	# and with nothing to take
	m.coins = 0
	m.buildings = [0, 0, 0, 0, 0]
	m.pending_raids = [
		{"at": 0.0, "kind": "steal", "coins": 5000, "npc": "nobody", "text": "raid", "emoji": "\U01F6A8"},
		{"at": 0.0, "kind": "smash", "building": 0, "text": "smash", "emoji": "\U01F6A8"},
	]
	m._offline_raids()
	_chk("a stripped island survives another wave", m.coins >= 0 and m.buildings.min() >= 0,
		"coins=%d %s" % [m.coins, str(m.buildings)])
