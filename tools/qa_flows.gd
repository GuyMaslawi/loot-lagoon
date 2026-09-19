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
	await _t_autospin_gesture()
	await _t_autospin()
	await _t_daily_dialog()
	await _t_every_purchase()
	await _t_boxes_and_melt()
	await _t_steal_raid()
	await _t_season_rollover()
	await _t_offline_raids()
	await _t_fair()
	await _t_voyage()
	await _t_powerup()
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

# --- the daily gift, as a control ---------------------------------------------
#
# Two claims Guy made about it off build 111: the gift itself has to take the
# tap ("the button at the bottom is completely redundant"), and the countdown
# under it has to run ("it changes when you go in and then it stops"). Both are
# invisible to every other test in this file, which drives _claim_daily directly.
func _t_daily_dialog() -> void:
	print("daily gift")
	m._close_popup(true)
	await get_tree().process_frame

	# READY: the gift answers, and nothing else on the dialog does.
	m.streak_days = 2
	m.daily_last = 0.0
	m._open_daily()
	await get_tree().process_frame
	var hits := _claim_hits(m._popup)
	_chk("the gift and today's rung are both pressable", hits.size() == 2,
		"%d hit boxes" % hits.size())
	_chk("no claim button is left under them",
		_labelled_claim(m._popup) == null)
	var coins_before: int = m.coins
	if hits.size() > 0:
		hits[0].pressed.emit()
		await get_tree().process_frame
	_chk("tapping the gift claims the day", m.coins > coins_before and not m._daily_ready(),
		"+%d coins" % (m.coins - coins_before))

	# And the second tap, through the fade, pays nothing.
	var after: int = m.coins
	for h in hits:
		if is_instance_valid(h):
			h.pressed.emit()
	await get_tree().process_frame
	_chk("a second tap through the fade pays nothing", m.coins == after,
		"+%d" % (m.coins - after))
	m._close_popup(true)
	await get_tree().process_frame

	# NOT READY: the clock has to move on its own.
	m._open_daily()
	await get_tree().process_frame
	var clock: Label = m._daily_timer_label
	_chk("a dialog that cannot be claimed shows a clock", clock != null)
	if clock != null:
		var first := clock.text
		await get_tree().create_timer(2.2).timeout
		_chk("and the clock counts down live", clock.text != first,
			"%s -> %s" % [first, clock.text])
	m._close_popup(true)
	await get_tree().create_timer(0.5).timeout

func _claim_hits(n: Node) -> Array:
	var out := []
	if n == null:
		return out
	if n is Button and (n as Button).has_meta("claim"):
		out.append(n)
	for c in n.get_children():
		out.append_array(_claim_hits(c))
	return out

func _labelled_claim(n: Node) -> Button:
	if n == null:
		return null
	if n is Button and (n as Button).text.to_upper().begins_with("CLAIM"):
		return n
	for c in n.get_children():
		var f := _labelled_claim(c)
		if f != null:
			return f
	return null

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
# THE GESTURE, NOT THE FLAG.
#
# Everything below _t_autospin sets `m.auto_spin = true` by hand, which is how a
# run that no player could ever start passed every test in this file. The bug
# was in the half-second between the finger going down and coming up again: the
# hold started a run, the run's first spin re-wrote spin_button.disabled, and
# the setter cleared the flag that swallows the release -- so the release
# arrived as a press, and a press during a run is STOP. Drive the button.
func _t_autospin_gesture() -> void:
	print("auto spin, by holding the button")
	m._goto(m.slot_page)
	await get_tree().create_timer(0.8).timeout
	m.spins = 60
	m.auto_spin = false
	m.slot.set_auto(false)
	m.slot.bet = 1
	var btn: SpinButton = m.slot.spin_button

	# The finger goes down and stays down well past HOLD -- long enough for the
	# run to have started AND for its first spin to be under way, which is the
	# window the bug lived in.
	btn._on_down()
	await get_tree().create_timer(SpinButton.HOLD + 0.05).timeout
	_chk("holding the button starts a run", m.auto_spin)
	await get_tree().create_timer(0.6).timeout
	_chk("the run survives its own first spin", m.auto_spin)
	# and now the finger leaves.
	btn._on_up()
	await get_tree().process_frame
	_chk("letting go does not press STOP", m.auto_spin)
	_chk("the button still says STOP", btn._label.text == "STOP", btn._label.text)

	# It really is spinning, and the ordinary tap really does stop it.
	#
	# WATCHED, NOT SAMPLED. The meter is the wrong witness: a triple lands a
	# raid that holds the run for as long as nobody taps through it, and a spin
	# that pays spins puts back more than the bet took -- so "spins went down
	# over four seconds" is a coin toss on a machine that is working perfectly.
	# A reel actually turning is the claim being made.
	var spun := false
	var t3 := 0.0
	while t3 < 12.0 and not spun:
		await get_tree().create_timer(0.15).timeout
		t3 += 0.15
		_tap_through_raid()
		spun = m.slot.is_spinning()
	_chk("the run it started actually spins the reels", spun, "after %.1fs" % t3)
	btn._on_down()
	await get_tree().process_frame
	btn._on_up()
	await get_tree().process_frame
	_chk("a short tap stops the run", not m.auto_spin)

	# A press that is interrupted by the control going dead must not be banked
	# and fired later -- the other half of the same setter.
	btn._on_down()
	btn.disabled = true
	btn.disabled = false
	await get_tree().process_frame
	btn._on_up()
	await get_tree().process_frame
	_chk("a press eaten by a disable does not start a run", not m.auto_spin)
	m.auto_spin = false
	m.slot.set_auto(false)
	await get_tree().create_timer(2.0).timeout

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

# --- the deal chain -----------------------------------------------------------
#
# --- the power up ------------------------------------------------------------
#
# The failure this exists to catch is the expensive one: the player is charged
# for the middle column and the two free ones never arrive. It has three ways of
# happening -- the intent is not recorded, the receipt does not match, or the
# grant runs twice -- and all three look identical from the outside.
# --- the fair ----------------------------------------------------------------
#
# Nine stalls, any order, on a points board. What has to hold: a stall pays
# once, the free half honours its restock clock, a paid stall is marked by the
# RECEIPT and never by the tap, the board pays every rung it has crossed, and
# the whole state survives the round trip through JSON -- which for a dict of
# string keys is the one thing that has bitten this codebase before.
func _t_fair() -> void:
	print("the fair")
	_chk("every fair is well-formed", Deals.fair_verify().is_empty(),
		", ".join(PackedStringArray(Deals.fair_verify())))

	for fair in Deals.FAIRS:
		m._close_popup(true)
		m.fair_id = String(fair["id"])
		m.fair_until = m._now() + Deals.FAIR_DURATION
		m.fair_taken = {}
		m.fair_miles = {}
		m.fair_pts = 0
		m.fair_restock = 0.0
		m._open_fair()
		await get_tree().process_frame

		var deals: Array = fair["deals"]
		var free_spins := 0
		var free_taken := 0
		for i in deals.size():
			var deal: Dictionary = deals[i]
			if String(deal.get("pack", "")) != "":
				# Money never marks a stall on the tap: the sheet can be
				# cancelled, and a stall marked on the
				# tap would be a reward the player paid nothing for.
				m._take_fair(i)
				await get_tree().process_frame
				_chk("%s stall %d is not taken by the tap" % [fair["id"], i],
					not m._fair_took(i))
				m._close_popup(true)
				# The receipt, which is the only thing that may mark it.
				m._fair_credit_purchase(String(deal["pack"]))
				_chk("%s stall %d is taken by the receipt" % [fair["id"], i],
					m._fair_took(i))
				m._open_fair()
				await get_tree().process_frame
				continue
			# A free stall, with the stall open.
			m.fair_restock = 0.0
			var before: int = m.spins
			m._take_fair(i)
			await get_tree().process_frame
			m._close_popup(true)
			free_taken += 1
			free_spins += int(deal.get("spins", 0))
			_chk("%s stall %d pays and is spent" % [fair["id"], i], m._fair_took(i))
			# And the clock it just started actually shuts the free half.
			_chk("%s stall %d shuts the stalls behind it" % [fair["id"], i],
				not m._fair_stall_open())
			var pre_pts: int = m.fair_pts
			m._take_fair(mini(i + 1, deals.size() - 1))
			_chk("%s a shut stall pays nothing" % fair["id"],
				m.fair_pts == pre_pts or String(
					(deals[mini(i + 1, deals.size() - 1)] as Dictionary).get("pack", "")) != "")
			m._open_fair()
			await get_tree().process_frame
			if int(deal.get("spins", 0)) > 0:
				_chk("%s stall %d handed over its spins" % [fair["id"], i],
					m.spins >= before + int(deal["spins"]),
					"+%d" % (m.spins - before))

		_chk("%s: every stall is spent once" % fair["id"],
			m.fair_taken.size() == Deals.FAIR_SLOTS, str(m.fair_taken.size()))
		# A second take of an already-spent stall must pay nothing at all.
		var pts_before: int = m.fair_pts
		for i in deals.size():
			m._take_fair(i)
		_chk("%s: a spent stall cannot be taken again" % fair["id"],
			m.fair_pts == pts_before, "%d -> %d" % [pts_before, m.fair_pts])
		# The board: every rung crossed has been paid, and the grand prize with
		# it, since a full sweep is more points than the top rung asks for.
		var miles: Array = fair["miles"]
		var owed := 0
		for i in miles.size():
			if m.fair_pts >= int((miles[i] as Dictionary)["at"]) \
					and not bool(m.fair_miles.get(str(i), false)):
				owed += 1
		_chk("%s: the board paid every rung it crossed" % fair["id"], owed == 0, str(owed))
		_chk("%s: the grand prize landed" % fair["id"],
			bool(m.fair_miles.get(str(miles.size() - 1), false)))

		# THE JSON ROUND TRIP. Both of these are dicts with string keys for
		# exactly this reason -- an int array comes back as floats and
		# Array.has(3) answers false for the 3.0 in it.
		var packed = JSON.parse_string(JSON.stringify(m._save_dict()))
		var back_taken: Dictionary = packed["fair_taken"]
		var back_miles: Dictionary = packed["fair_miles"]
		var all_back := back_taken.size() == Deals.FAIR_SLOTS
		for i in Deals.FAIR_SLOTS:
			# str(i), not i. This is the assertion: through JSON the key is the
			# STRING "3" and an int lookup finds nothing.
			if not bool(back_taken.get(str(i), false)):
				all_back = false
		_chk("%s: the board survives a save round trip" % fair["id"],
			all_back and bool(back_miles.get(str(miles.size() - 1), false)),
			"%d stalls" % back_taken.size())
		m._close_popup(true)

	# The calendar, which the fair now keeps on its own: it arms when its own
	# clock says so, and it does not roll straight back in the moment one ends.
	m.fair_id = ""
	m.fair_until = 0.0
	m.fair_next = m._now() + 600.0
	m._fair_tick()
	_chk("no fair opens before its clock", m.fair_id == "")
	m.fair_next = 0.0
	m._fair_tick()
	_chk("the fair opens when the clock comes round", m.fair_id != "")
	_chk("and the events disc opens it, not the teaser",
		not m._active_fair().is_empty())
	# Out again, and the cooldown has to be stamped or the next tick re-arms it.
	m.fair_until = m._now() - 1.0
	m._fair_tick()
	_chk("a fair that ends stamps its own cooldown",
		m.fair_id == "" and m.fair_next > m._now())
	m.fair_id = ""
	m.fair_until = 0.0
	m.fair_next = m._now() + Deals.FAIR_DURATION
	m._close_popup(true)
	# THE REGEN CLOCK IS PART OF THE FIXTURE. Spins refill on a timer, and the
	# next test measures a purchase as an exact delta on m.spins -- so a refill
	# landing mid-measurement reads as the pack paying one spin too many. It
	# did: "pays all three columns +1051, wanted 1050", which is a harness bug
	# wearing a game bug's clothes. Wound back to zero here so the tick after
	# this one starts a fresh interval.
	m._regen_accum = 0.0
	await get_tree().create_timer(0.5).timeout

# --- the voyage ---------------------------------------------------------------
#
# Seven days, three goals a day, one bar. What has to hold: only TODAY's goals
# count, a goal pays once, the bar pays every rung it crosses, and the whole
# thing survives JSON -- the keys are "<day>:<goal>" strings for the usual
# reason.
func _t_voyage() -> void:
	print("the voyage")
	_chk("the voyage is well-formed", Deals.voyage_verify().is_empty(),
		", ".join(PackedStringArray(Deals.voyage_verify())))

	m._close_popup(true)
	m.voy_next = 0.0
	m.voy_start = 0.0
	m._voyage_tick()
	_chk("a voyage sets out", m._voyage_live())
	_chk("and it starts on day one", m._voyage_day() == 0, str(m._voyage_day()))

	# Counting. Only today's goals move, and they stop at the target.
	var goal: Dictionary = Deals.voyage_day_goals(0)[0]
	var gid := String(goal["id"])
	m._voyage_add(gid, int(goal["target"]) * 3)
	_chk("a goal counts and clamps at its target",
		int(m.voy_prog[m._voyage_key(0, gid)]) == int(goal["target"]),
		str(m.voy_prog.get(m._voyage_key(0, gid), 0)))
	_chk("and reads as done", m._voyage_done(0, goal))
	_chk("which lights the tab", m._voyage_ready())

	# TOMORROW'S GOALS DO NOT MOVE TODAY. The deadline is the entire difference
	# between this board and the mission board, and a counter that back-filled
	# other days would quietly remove it.
	var later: Dictionary = Deals.voyage_day_goals(3)[0]
	m._voyage_add(String(later["id"]), 999)
	_chk("a later day's goal does not move",
		not m.voy_prog.has(m._voyage_key(3, String(later["id"]))))

	# Claiming: pays once, banks the stamps, and cannot be repeated.
	var spins_before: int = m.spins
	var stamps_before: int = m.voy_stamps
	m._claim_voyage(0, goal)
	await get_tree().process_frame
	m._close_popup(true)
	_chk("claiming banks the stamps",
		m.voy_stamps == stamps_before + int(goal["stamps"]),
		"%d -> %d" % [stamps_before, m.voy_stamps])
	var after_first: int = m.voy_stamps
	m._claim_voyage(0, goal)
	_chk("a goal cannot be claimed twice", m.voy_stamps == after_first)
	if int(goal.get("spins", 0)) > 0:
		_chk("and it handed over its spins", m.spins > spins_before)

	# The bar. Enough stamps for every rung, paid on the way past.
	m.voy_stamps = int((Deals.VOYAGE_MILES[Deals.VOYAGE_MILES.size() - 1] as Dictionary)["at"])
	m._voyage_pay_miles()
	await get_tree().process_frame
	m._close_popup(true)
	var owed := 0
	for i in Deals.VOYAGE_MILES.size():
		if not bool(m.voy_miles.get(str(i), false)):
			owed += 1
	_chk("the bar pays every rung it crosses", owed == 0, str(owed))
	var stamps_held: int = m.voy_stamps
	m._voyage_pay_miles()
	_chk("and does not pay them twice", m.voy_stamps == stamps_held)

	# The day rolls with the clock, not with the calendar.
	m.voy_start = m._now() - 3.5 * Deals.VOYAGE_DAY
	_chk("day four is day four", m._voyage_day() == 3, str(m._voyage_day()))
	m.voy_start = m._now() - float(Deals.VOYAGE_DAYS) * Deals.VOYAGE_DAY - 10.0
	_chk("and a voyage past its last day is over", not m._voyage_live())
	m._voyage_tick()
	_chk("which clears the board and sets the next one",
		m.voy_start == 0.0 and m.voy_prog.is_empty() and m.voy_next > m._now())

	# The JSON round trip. "<day>:<goal>" keys, and an int progress value that
	# has to come back an int.
	m.voy_start = m._now()
	m.voy_prog = {}
	m.voy_claimed = {}
	m._voyage_add(gid, 3)
	m.voy_claimed[m._voyage_key(0, gid)] = true
	var packed = JSON.parse_string(JSON.stringify(m._save_dict()))
	var back_prog: Dictionary = packed["voy_prog"]
	var back_claimed: Dictionary = packed["voy_claimed"]
	_chk("the board survives a save round trip",
		int(back_prog.get(m._voyage_key(0, gid), 0)) == 3
		and bool(back_claimed.get(m._voyage_key(0, gid), false)),
		str(back_prog))

	m.voy_start = 0.0
	m.voy_next = m._now() + Deals.VOYAGE_COOLDOWN
	m.voy_prog = {}
	m.voy_claimed = {}
	m.voy_miles = {}
	m.voy_stamps = 0
	m._close_popup(true)
	m._regen_accum = 0.0
	await get_tree().create_timer(0.5).timeout

func _t_powerup() -> void:
	print("power up")
	_chk("every power-up is well-formed", Deals.powerup_verify().is_empty(),
		", ".join(PackedStringArray(Deals.powerup_verify())))
	# The solo deals: every pack a product the stores sell, a bonus that is
	# genuinely on top, and a printed multiple the shelf does not already beat.
	_chk("every solo deal is well-formed", Deals.solo_verify().is_empty(),
		", ".join(PackedStringArray(Deals.solo_verify())))

	# THE LOYALTY CARD IS HELD OFF FOR THE WHOLE OF THIS TEST, and finding out
	# why cost the first run of it: every purchase below is measured in spins,
	# the card pays 60 spins when it fills, and the packs bought here are what
	# fill it. Two of the three assertions came back 60 over and read exactly
	# like the free columns being paid when they should not have been. Zeroed
	# before each purchase it can never reach its target, so what is measured is
	# the pack and the columns and nothing else. The card gets its own test at
	# the bottom.
	for pu in Deals.POWERUPS:
		m._close_popup(true)
		m.loyalty_buys = 0
		m.powerup_id = String(pu["id"])
		m.powerup_until = m._now() + Deals.POWERUP_DURATION
		m.powerup_pending = ""
		m._open_powerup()
		await get_tree().process_frame
		m._close_popup(true)

		var owed_spins := 0
		var owed_cards := 0
		for b in pu["bonus"]:
			owed_spins += int((b as Dictionary).get("spins", 0))
			owed_cards += int((b as Dictionary).get("cards", 0))

		# SPINS AT THE CAP BEFORE EITHER MEASUREMENT, because the meter refills
		# on a clock and both checks below are exact deltas. A refill landing
		# between `before` and the assertion reads as the pack paying one spin
		# too many -- it did, as "+1051, wanted 1050", the moment a new test was
		# inserted ahead of this one and moved the tick's phase. At the cap the
		# regen grants nothing, and a grant is free to take the meter past it,
		# so the delta is still exact. See [[loot-lagoon-qa-harness-traps]].
		m.spins = m.SPIN_CAP
		m._regen_accum = 0.0
		# AND ROOM FOR THE SHIELDS, which is the other half of the same trap and
		# the half that was actually biting. A bonus column carrying a shield
		# pays it through _grant_shields, and a shield that does not fit is
		# REFUNDED AS A SPIN rather than eaten -- correct behaviour, and it
		# turns an exact spin delta into "+1051, wanted 1050" the moment
		# anything earlier in the run has filled the shield slots. Only
		# pu_quartermaster failed, because only its bonus carries a shield.
		m.shields = 0

		# Bought from the SHELF rather than the takeover: the bonus columns must
		# not be handed over. Nothing recorded the intent, so nothing is owed.
		m.powerup_pending = ""
		var before: int = m.spins
		m.loyalty_buys = 0
		m._on_purchase_ok(IAP.PREFIX + String(pu["pack"]))
		m._close_popup(true)
		await get_tree().process_frame
		var pack: Dictionary = CV.pack_by_id(String(pu["pack"]))
		_chk("%s off the shelf pays the pack only" % pu["id"],
			m.spins == before + int(pack.get("spins", 0)),
			"+%d, pack is %d" % [m.spins - before, int(pack.get("spins", 0))])

		# And from the takeover, where it is owed.
		m.powerup_id = String(pu["id"])
		m.powerup_until = m._now() + Deals.POWERUP_DURATION
		m.powerup_pending = String(pu["id"])
		m.spins = maxi(m.spins, m.SPIN_CAP)
		m._regen_accum = 0.0
		m.shields = 0
		before = m.spins
		m.loyalty_buys = 0
		m._on_purchase_ok(IAP.PREFIX + String(pu["pack"]))
		m._close_popup(true)
		await get_tree().process_frame
		_chk("%s from the takeover pays all three columns" % pu["id"],
			m.spins == before + int(pack.get("spins", 0)) + owed_spins,
			"+%d, wanted %d" % [m.spins - before, int(pack.get("spins", 0)) + owed_spins])
		_chk("%s is spent once it is bought" % pu["id"], m.powerup_id == "")

		# The replay. An interrupted transaction is re-delivered at boot, and a
		# pending record that outlived its own grant would pay twice.
		before = m.spins
		m.loyalty_buys = 0
		m._on_purchase_ok(IAP.PREFIX + String(pu["pack"]))
		m._close_popup(true)
		await get_tree().process_frame
		_chk("%s does not pay its free columns twice" % pu["id"],
			m.spins == before + int(pack.get("spins", 0)),
			"+%d" % (m.spins - before))

	# The loyalty card pays at the target and resets, rather than running on.
	m.loyalty_buys = 0
	var chests := 0
	for i in Deals.LOYALTY_TARGET * 2:
		var pre: int = m.loyalty_buys
		m._loyalty_add()
		if m.loyalty_buys == 0 and pre == Deals.LOYALTY_TARGET - 1:
			chests += 1
	_chk("the loyalty card pays every %d and resets" % Deals.LOYALTY_TARGET,
		chests == 2 and m.loyalty_buys == 0, "%d chests, at %d" % [chests, m.loyalty_buys])

	# --- the solo deal, the other half of the same calendar slot ---
	#
	# The same three claims the trio is held to: the shelf pays the pack alone,
	# the deal's own screen pays the pack AND the bonus, and a replayed receipt
	# -- an interrupted transaction re-delivered at boot -- pays the bonus once.
	for solo in Deals.SOLOS:
		var sid := String(solo["id"])
		var spack: Dictionary = Deals.solo_pack(solo)
		var sbonus: Dictionary = Deals.solo_bonus(solo)
		var bonus_spins := int(sbonus.get("spins", 0))

		# Off the shelf: nothing recorded the intent, so nothing is owed.
		m._close_popup(true)
		m.solo_id = ""
		m.solo_pending = ""
		m.loyalty_buys = 0
		# The meter at the cap and the shield slots empty, for the two reasons
		# the trio's own block above spells out: a refill landing mid-delta
		# reads as one spin too many, and a shield that does not fit is refunded
		# as a spin. See [[loot-lagoon-qa-harness-traps]].
		m.spins = m.SPIN_CAP
		m._regen_accum = 0.0
		m.shields = 0
		var sbefore: int = m.spins
		m._on_purchase_ok(IAP.PREFIX + String(solo["pack"]))
		m._close_popup(true)
		await get_tree().process_frame
		_chk("%s off the shelf pays the pack only" % sid,
			m.spins == sbefore + int(spack.get("spins", 0)),
			"+%d, pack is %d" % [m.spins - sbefore, int(spack.get("spins", 0))])

		# From the deal's own screen, where the bonus is owed.
		m.solo_id = sid
		m.solo_until = m._now() + Deals.SOLO_DURATION
		m.solo_pending = sid
		m.spins = maxi(m.spins, m.SPIN_CAP)
		m._regen_accum = 0.0
		m.shields = 0
		sbefore = m.spins
		m.loyalty_buys = 0
		m._on_purchase_ok(IAP.PREFIX + String(solo["pack"]))
		m._close_popup(true)
		await get_tree().process_frame
		_chk("%s from its own screen pays the pack and the bonus" % sid,
			m.spins == sbefore + int(spack.get("spins", 0)) + bonus_spins,
			"+%d, wanted %d" % [m.spins - sbefore,
				int(spack.get("spins", 0)) + bonus_spins])
		_chk("%s is spent once it is bought" % sid, m.solo_id == "")

		# The replay.
		sbefore = m.spins
		m.loyalty_buys = 0
		m._on_purchase_ok(IAP.PREFIX + String(solo["pack"]))
		m._close_popup(true)
		await get_tree().process_frame
		_chk("%s does not pay its bonus twice" % sid,
			m.spins == sbefore + int(spack.get("spins", 0)),
			"+%d" % (m.spins - sbefore))

	# THE TWO OFFERS NEVER RUN AT ONCE. It is the invariant the OFFER disc rests
	# on -- _open_offer picks by sequence, not by choice -- and the thing that
	# enforces it is a `solo_next` of zero meaning "not scheduled". A solo that
	# could arm on a fresh save would put a paid takeover in front of a player
	# on the day they installed.
	m.solo_id = ""
	m.solo_until = 0.0
	m.solo_next = 0.0
	m.powerup_id = "pu_squall"
	m.powerup_until = m._now() + Deals.POWERUP_DURATION
	m._solo_tick()
	_chk("an unscheduled solo never arms", m.solo_id == "", m.solo_id)
	m.solo_next = m._now() - 1.0
	m._solo_tick()
	_chk("a solo never arms over a live trio", m.solo_id == "", m.solo_id)
	m.powerup_id = ""
	m.powerup_until = 0.0
	m._solo_tick()
	_chk("a scheduled solo arms once the trio is gone", m.solo_id != "")
	_chk("...and disarms itself so only one lands per cycle", m.solo_next == 0.0,
		str(m.solo_next))

	m.solo_id = ""
	m.solo_until = 0.0
	m.solo_next = 0.0
	m.solo_pending = ""
	m.powerup_id = ""
	m.powerup_next = 0.0
	m.powerup_pending = ""
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
