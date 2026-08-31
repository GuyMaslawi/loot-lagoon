extends Node
# =============================================================================
#  Loot Lagoon -- randomized stress and endurance
# =============================================================================
#
# Many player careers, each a fresh install driven through thousands of random
# actions drawn from everything a real player can reach, with the game's
# invariants checked after every single one.
#
# This is the half a scripted test cannot do. The scripted sweep asks "does the
# daily bonus pay the right amount"; this asks "is there any ORDER of the two
# hundred things a player can do that leaves a counter negative, a rank going
# backwards, or a save that will not load" -- and the answer to that is only
# ever found by trying orders nobody thought of.
#
# It also measures the endurance side: node count and memory across the whole
# run, because a leak that costs 200 nodes a session is invisible in a unit test
# and is a crash on a phone after an hour.
#
# Run: godot --headless --path . res://tools/qa_stress.tscn
#      CAREERS=<n> ACTIONS=<n> godot --headless ...

var m: Control
var fails := 0
var checks := 0
var violations := {}
var action_counts := {}
var rank_high := 0
var peak_nodes := 0
var peak_mem := 0
var stuck_raids := 0

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout

	var careers := int(OS.get_environment("CAREERS")) if OS.has_environment("CAREERS") else 120
	var actions := int(OS.get_environment("ACTIONS")) if OS.has_environment("ACTIONS") else 400
	print("stress: %d careers x %d actions = %d player-actions" % [careers, actions, careers * actions])

	var t0 := Time.get_ticks_msec()
	var nodes_start := 0
	for career in careers:
		seed(career * 7919 + 13)
		_new_install()
		for step in actions:
			var act := _pick_action()
			action_counts[act] = int(action_counts.get(act, 0)) + 1
			await _do(act)
			_check_invariants(career, step, act)
		# The career has to survive being written to disk and read back.
		await _roundtrip(career)
		if career == 2:
			nodes_start = _nodes(m)
		peak_nodes = maxi(peak_nodes, _nodes(m))
		peak_mem = maxi(peak_mem, int(OS.get_static_memory_usage()))
		if career % 5 == 0:
			await get_tree().process_frame
			print("  ... career %d/%d  nodes=%d  mem=%.1fMB" % [
				career, careers, _nodes(m),
				float(OS.get_static_memory_usage()) / 1048576.0])
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0

	print("")
	print("== what was exercised")
	var keys := action_counts.keys()
	keys.sort()
	var line := ""
	for k in keys:
		line += "%s:%d  " % [k, action_counts[k]]
	print("   " + line)

	print("")
	print("== invariants")
	if violations.is_empty():
		_chk("no invariant was ever broken, in any order", true,
			"%d player-actions" % (careers * actions))
	else:
		for v in violations:
			_chk(v, false, str(violations[v]))

	print("")
	print("== raids")
	_chk("every raid handed the game back", stuck_raids == 0,
		"%d raids had to be forced down" % stuck_raids)

	print("")
	print("== endurance")
	var nodes_end := _nodes(m)
	_chk("the scene tree settles instead of growing", nodes_end < nodes_start + 500,
		"%d -> %d (peak %d)" % [nodes_start, nodes_end, peak_nodes])
	_chk("memory stays inside a phone's budget", peak_mem < 1200 * 1048576,
		"peak %.1fMB" % (float(peak_mem) / 1048576.0))
	print("   %d player-actions in %.1fs (%.0f/s)" % [
		careers * actions, secs, float(careers * actions) / maxf(secs, 0.001)])

	print("")
	print("QA-STRESS: %d checks, %s" % [checks, "ALL PASS" if fails == 0 else "%d FAILURES" % fails])
	get_tree().quit(1 if fails > 0 else 0)

func _chk(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		fails += 1
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])

func _nodes(n: Node) -> int:
	var t := 1
	for c in n.get_children():
		t += _nodes(c)
	return t

# --- a fresh install ---------------------------------------------------------

func _new_install() -> void:
	m._close_popup(true)
	m.coins = 1500
	m.spins = 30
	m.shields = 0
	m.stars = 0
	m.rank_stars = 0
	m.island_level = 1
	m.buildings = [0, 0, 0, 0, 0]
	m.piggy_coins = 0
	m.piggy_promised = 0
	m.purchased_ids = []
	m.topup_pending = {}
	m.daily_last = 0.0
	m.shop_free_last = 0.0
	m.offer_id = ""
	m.offer_until = 0.0
	m.offer_next = 0.0
	m.revenge_pending = false
	m.auto_spin = false
	m.muted = true
	m.notif_enabled = false
	m.notif_log = []
	m.pending_raids = []
	m.mission_state = {}
	m.col_owned = {}
	m.col_dupes = {}
	m.col_claimed = {}
	m.col_mega_claimed = false
	m.col_deadline = 0.0
	m.tourney_id = m._tourney_now_id()
	m.tourney_points = 0
	m.tourney_claimed = []
	m._ensure_missions()
	m._ensure_collections()
	m._stock_rivals()
	rank_high = 0

# --- the action table --------------------------------------------------------
#
# Weighted the way a session actually goes: mostly spinning, with everything
# else threaded through it.
const ACTIONS := [
	["spin", 40], ["upgrade", 10], ["daily", 3], ["shop_gift", 3],
	["buy_pack", 5], ["open_box", 5], ["melt", 4], ["claim_set", 3],
	["claim_mega", 1], ["tourney_claim", 3], ["offer_tick", 3],
	["piggy_add", 4], ["piggy_break", 1], ["background", 4], ["resume", 4],
	["offline_raids", 3], ["mission_claim", 3], ["save_load", 2],
	["sanitize_clock", 1], ["topup", 2], ["sail", 1], ["notify", 2],
]

func _pick_action() -> String:
	var total := 0
	for a in ACTIONS:
		total += int(a[1])
	var roll := randi_range(1, total)
	for a in ACTIONS:
		roll -= int(a[1])
		if roll <= 0:
			return String(a[0])
	return "spin"

func _do(act: String) -> void:
	# A raid owns the screen while it is up; a real player cannot do anything
	# else, and neither may the fuzzer.
	if m._raiding():
		await _release_raid()
		return
	match act:
		"spin":
			if m.spins <= 0:
				m.spins = randi_range(1, m.SPIN_CAP)
			m._last_bet = [1, 2, 3, 5].pick_random()
			m.spins -= 1
			m._on_spin_finished(m._roll())
		"upgrade":
			m._on_upgrade_requested(randi_range(0, CV.BUILDINGS.size() - 1))
			m._close_popup(true)
		"daily":
			m._open_daily()
			m._close_popup(true)
		"shop_gift":
			m._claim_shop_gift()
			m._close_popup(true)
		"buy_pack":
			var all := [CV.STARTER_PACK]
			for g in [CV.CHEST_PACKS, CV.SPIN_PACKS, CV.COIN_PACKS, CV.BUNDLE_PACKS, CV.TIMED_OFFERS]:
				for p in g:
					all.append(p)
			m._on_purchase_ok(IAP.PREFIX + String((all.pick_random() as Dictionary)["id"]))
			m._close_popup(true)
		"open_box":
			m._open_card_box(CV.CARD_BOXES.pick_random())
			m._close_popup(true)
		"melt":
			var rows: Array = m._all_dupes()
			if not rows.is_empty():
				var r: Dictionary = rows.pick_random()
				m._melt_stack(String((r["set"] as Dictionary)["id"]), int(r["idx"]),
					randi_range(1, int(r["count"]) + 2))
		"claim_set":
			m._claim_collection(CV.COLLECTIONS.pick_random())
			m._close_popup(true)
		"claim_mega":
			m._claim_mega()
			m._close_popup(true)
		"tourney_claim":
			m._tourney_claim(randi_range(-1, m.TOURNEY_TIERS.size()))
			m._close_popup(true)
		"offer_tick":
			m._offer_tick()
		"piggy_add":
			m._piggy_add(randi_range(1, CV.PIGGY_PER_RAID))
		"piggy_break":
			m._break_piggy()
			m._close_popup(true)
		"background":
			m._go_away()
		"resume":
			# A plausible absence: a lunch break, a night, a fortnight.
			if m._away_since > 0.0:
				m._away_since -= [60.0, 3600.0, 86400.0, 86400.0 * 14.0].pick_random()
			m._resume_from_away()
		"offline_raids":
			m._offline_raids()
		"mission_claim":
			var period: String = ["daily", "weekly", "monthly"].pick_random()
			for mission in m.MISSION_DEFS[period]:
				m._claim_mission(period, mission)
			m._claim_mission_bonus(period)
			m._close_popup(true)
		"save_load":
			m._flush_save()
			m._load_game()
		"sanitize_clock":
			m.daily_last += float(randi_range(-100000, 100000))
			m.shop_free_last += float(randi_range(-100000, 100000))
			m._sanitize_clock()
		"topup":
			var offer: Dictionary = m._topup_for(randi_range(1, 10000000))
			if not offer.is_empty():
				m.topup_pending = {"id": String((offer["pack"] as Dictionary)["id"]),
					"coins": int(offer["coins"])}
				m._on_purchase_ok(IAP.PREFIX + String((offer["pack"] as Dictionary)["id"]))
			m._close_popup(true)
		"sail":
			# The one action that moves the whole economy under everything else.
			if m.island_level < m.MAX_ISLAND:
				m.island_level += 1
				m.buildings = [0, 0, 0, 0, 0]
				m._rescale_coin_progress()
		"notify":
			m.notif_enabled = true
			m._notify(["attack", "steal", "spins", "gift", "events"].pick_random(),
				"stress", "!", false)
			m.notif_enabled = false
	await get_tree().process_frame

func _release_raid() -> void:
	# Act ONCE per state and then wait for the state to change. Hammering
	# _lock_in()/_close() every frame re-emits `finished` and spawns a second
	# island visit on top of the first, which is a raid that genuinely never
	# ends -- an artefact of the harness, not of the game.
	var waited := 0.0
	var last_state := ""
	while m._raiding() and waited < 10.0:
		var state := "pending"
		if m._match != null and is_instance_valid(m._match):
			state = "match"
		elif m._visit != null and is_instance_valid(m._visit):
			state = "visit"
		if state != last_state:
			last_state = state
			if state == "match" and m._match.has_method("_lock_in"):
				m._match._live = true
				m._match._lock_in()
				m._match._close()
			elif state == "visit" and m._visit._stage != null:
				for c in m._visit._stage.get_children():
					if c is Button and not (c as Button).disabled:
						(c as Button).pressed.emit()
						break
		else:
			# Same state as last look: the stage may only now have drawn its
			# buttons, so try again on a slower beat than the frame rate.
			if state == "visit" and m._visit._stage != null:
				for c in m._visit._stage.get_children():
					if c is Button and not (c as Button).disabled:
						(c as Button).pressed.emit()
						break
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	if m._raiding():
		stuck_raids += 1
		_note("a raid always hands the game back",
			"stuck in '%s' for %.1fs" % [last_state, waited])
		# Force it down so the rest of the fuzz still runs.
		if m._match != null and is_instance_valid(m._match):
			m._match.queue_free()
		m._match = null
		if m._visit != null and is_instance_valid(m._visit):
			m._visit.queue_free()
		m._visit = null
		m._raid_pending = false
		await get_tree().process_frame

# --- the invariants ----------------------------------------------------------

func _note(rule: String, detail: String) -> void:
	if not violations.has(rule):
		violations[rule] = detail

func _check_invariants(career: int, step: int, act: String) -> void:
	var where := " (career %d step %d after %s)" % [career, step, act]
	if m.coins < 0:
		_note("the wallet never goes negative", "%d%s" % [m.coins, where])
	if m.spins < 0:
		_note("the meter never goes negative", "%d%s" % [m.spins, where])
	if m.stars < 0:
		_note("the star bank never goes negative", "%d%s" % [m.stars, where])
	if m.shields < 0 or m.shields > m.SHIELD_CAP:
		_note("shields stay inside the bucket", "%d%s" % [m.shields, where])
	if m.piggy_coins < 0 or m.piggy_coins > m._scaled(CV.PIGGY_CAP):
		_note("the piggy stays between empty and its cap", "%d%s" % [m.piggy_coins, where])
	if m.island_level < 1 or m.island_level > m.MAX_ISLAND:
		_note("the island stays in range", "%d%s" % [m.island_level, where])

	# The one the cloud-save reconciler depends on. If this ever fails, the
	# server starts overwriting live islands with stale ones.
	if m.rank_stars < rank_high:
		_note("rank_stars only ever rises -- the cloud merge key",
			"%d -> %d%s" % [rank_high, m.rank_stars, where])
	rank_high = maxi(rank_high, m.rank_stars)

	if m.buildings.size() != CV.BUILDINGS.size():
		_note("the island always has five huts", "%d%s" % [m.buildings.size(), where])
	else:
		for b in m.buildings:
			if typeof(b) != TYPE_INT or int(b) < 0 or int(b) > CV.MAX_STAR:
				_note("every hut is a real star level", "%s%s" % [str(m.buildings), where])
				break

	if m.tourney_points < 0:
		_note("tournament points never go negative", "%d%s" % [m.tourney_points, where])
	for v in m.tourney_claimed:
		if typeof(v) != TYPE_INT or int(v) < 0 or int(v) >= m.TOURNEY_TIERS.size():
			_note("claimed rungs stay inside the reward table",
				"%s%s" % [str(m.tourney_claimed), where])
			break
	if m.tourney_claimed.size() > m.TOURNEY_TIERS.size():
		_note("no rung is claimed twice", "%s%s" % [str(m.tourney_claimed), where])

	for id in m.purchased_ids:
		if typeof(id) != TYPE_STRING:
			_note("the purchase list holds only strings", "%s%s" % [str(id), where])
			break

	if m.notif_log.size() > m.NOTIF_LOG_MAX:
		_note("the alert log stays capped", "%d%s" % [m.notif_log.size(), where])

	# Nothing may be so large that the next multiply wraps.
	for pair in [["coins", m.coins], ["stars", m.stars], ["rank_stars", m.rank_stars]]:
		if int(pair[1]) > (1 << 62):
			_note("no counter approaches the int64 ceiling",
				"%s=%d%s" % [pair[0], pair[1], where])

	var dupes_ok := true
	for c in CV.COLLECTIONS:
		var arr: Array = m.col_dupes.get(c["id"], [])
		for v in arr:
			if int(v) < 0:
				dupes_ok = false
	if not dupes_ok:
		_note("the spare-card pile never goes negative", where)

# A career has to survive the round trip that ends every real session.
func _roundtrip(career: int) -> void:
	var before := {
		"coins": m.coins, "spins": m.spins, "stars": m.stars,
		"rank": m.rank_stars, "island": m.island_level,
		"buildings": m.buildings.duplicate(), "piggy": m.piggy_coins,
		"tourney": m.tourney_points, "claimed": m.tourney_claimed.duplicate(),
	}
	m._flush_save()
	m.coins = 0
	m.spins = 0
	m.stars = 0
	m.rank_stars = 0
	m.island_level = 1
	m.buildings = [0, 0, 0, 0, 0]
	m._load_game()
	await get_tree().process_frame
	var same: bool = m.coins == before["coins"] and m.spins == before["spins"] \
		and m.stars == before["stars"] and m.rank_stars == before["rank"] \
		and m.island_level == before["island"] and m.buildings == before["buildings"] \
		and m.piggy_coins == before["piggy"] and m.tourney_points == before["tourney"] \
		and m.tourney_claimed == before["claimed"]
	if not same:
		_note("a career survives being saved and read back",
			"career %d: %s -> coins=%d spins=%d stars=%d rank=%d island=%d %s piggy=%d tp=%d %s" % [
				career, str(before), m.coins, m.spins, m.stars, m.rank_stars,
				m.island_level, str(m.buildings), m.piggy_coins, m.tourney_points,
				str(m.tourney_claimed)])
