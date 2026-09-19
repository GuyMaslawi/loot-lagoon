extends Node
# THE 1+2 PAYS THREE COLUMNS, AND ONLY ONE OF THEM IS THE ONE APPLE CHARGED FOR.
#
# Guy, 2026-09-19, off his own phone: *"you press buy on the trio deal, the
# window closes after the purchase, and then you cannot take the two free ones
# because it is gone completely."* Nothing in qa_buy could have caught that:
# that harness buys off the SHELF, where a receipt owes exactly one screen. The
# takeover owes three things at once -- the paid pack's box, the two free
# columns' box, and the held counters that ride out of the second one -- and the
# failure is in the seam between them.
#
# So this presses the real button on the real takeover, lets the desktop sim
# deliver the receipt, and then DISMISSES EVERY SCREEN THE WAY A FINGER WOULD,
# checking after each one that the queue kept moving. The measurement that
# matters is the last: the purse has to end up holding the bonus spins and
# coins, because those are the two free columns and they are what the player
# was sold.
#
#   godot --headless --path . res://tools/qa_trio.tscn

var m: Control
var fails := 0

func _ready() -> void:
	print("BOOT: creating main"); m = load("res://scripts/main.gd").new()
	add_child(m)
	var t0 := Time.get_ticks_msec()
	while not bool(m.get("_booted")):
		if Time.get_ticks_msec() - t0 > 20000:
			print("BOOT TIMEOUT"); get_tree().quit(1); return
		await get_tree().process_frame

	print("BOOT: done, running %d power-ups" % Deals.POWERUPS.size())
	# The plain desktop case first -- no payment sheet, no absence -- so a
	# failure there is read as the takeover's own and not as the phone's.
	for pu in Deals.POWERUPS:
		await _run(String(pu["id"]), 0.0, false)
	# Then the phone. StoreKit's sheet is system UI: the app gets FOCUS_OUT when
	# it comes up and FOCUS_IN when it goes, the receipt lands around the second
	# of those, and the two can arrive in either order -- see qa_buy, which
	# learned this the expensive way. 120 seconds is not a stress figure: a
	# sandbox sign-in takes longer than that, and it is over the 60s line where
	# the resume starts crediting time away and raiding.
	for away in [8.0, 120.0]:
		for resume_first in [true, false]:
			await _run("pu_deckhand", away, resume_first)
	await _impatient()

	m._clear_reward_screens()
	for _i in 30:
		await get_tree().process_frame
	print("")
	print("QA-TRIO: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)


# Everything the two free columns are worth, in the units the purse counts in:
# the bonus coins are scaled to the island like every other coin figure.
func _bonus_owed(pu: Dictionary) -> Dictionary:
	var owed := {"spins": 0, "coins": 0, "cards": 0}
	for b in pu["bonus"]:
		owed["spins"] += int((b as Dictionary).get("spins", 0))
		owed["coins"] += m._scaled(int((b as Dictionary).get("coins", 0)))
		owed["cards"] += int((b as Dictionary).get("cards", 0))
	return owed


func _screen() -> String:
	var chest = m.get("_chest_seq")
	var payout = m.get("_payout_seq")
	if chest != null and is_instance_valid(chest):
		return "chest"
	if payout != null and is_instance_valid(payout):
		return "payout"
	# THE OFFER SHEET IS NOT A SCREEN FOR THIS PURPOSE. It stays standing
	# behind the payment sheet on purpose -- see the button in _open_powerup --
	# so counting it here made every wait below return on the frame it started.
	return ""


# One tap on whatever is up. skip(true) is what the finger does: reveal, then
# finish -- which is the signal the queue drains on.
#
# THE WAIT IS WALL-CLOCK, NOT FRAMES, and that is the whole reason this harness
# was wrong once. Headless runs the process loop as fast as it can, so "40
# frames" is a few milliseconds here and a tenth of a second on the phone --
# and everything this is measuring is on a timer: 0.24s for the box to fade
# out, then _reward_next's 0.22s pause before the next one opens. A
# frame-counted wait broke out of the loop in the gap between the two and
# reported a stalled queue that was simply mid-drain.
func _tap() -> void:
	var chest = m.get("_chest_seq")
	var payout = m.get("_payout_seq")
	var node = chest if (chest != null and is_instance_valid(chest)) else payout
	if node == null or not is_instance_valid(node):
		return
	node.skip(true)
	# The box fades for 0.24s before `finished` fires, so waiting on "is a
	# takeover up" alone would answer with the one that was just dismissed.
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(node) and Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
	await _settle()


# Wait for the screen to be whatever it is going to be: the next box open, or
# nothing left to open. Generous, because a false "nothing" is the one reading
# that would send somebody hunting a bug that is not there.
func _settle() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
		if _screen() != "":
			return
		if (m.get("_reward_queue") as Array).is_empty() \
				and not bool(m.get("_reward_draining")) \
				and Time.get_ticks_msec() - t0 > 900:
			return


# Every held figure delivered, or 4 seconds, whichever comes first.
func _settle_flights() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
		var lag: Dictionary = m.get("_hud_lag")
		var pending := 0
		for k in lag.keys():
			pending += int(lag[k])
		if pending == 0:
			return


# A real tap, routed through the takeover's own input handler rather than
# skip() -- which is the only way to exercise the deaf window, since skip is
# the harness door that deliberately bypasses it.
func _poke(node) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	node.gui_input.emit(ev)


func _find_buy(node: Node) -> Button:
	for c in node.get_children():
		if c is Button and (c as Button).text.begins_with("$"):
			return c
		var found := _find_buy(c)
		if found != null:
			return found
	return null


func _run(pu_id: String, away: float, resume_first: bool) -> void:
	var pu := Deals.powerup_by_id(pu_id)
	var pack := CV.pack_by_id(String(pu["pack"]))
	print("")
	if away <= 0.0:
		print("== %s -- %s + two free columns" % [pu_id, pack["id"]])
	else:
		print("== %s -- %ds on the payment sheet, %s" % [pu_id, int(away),
			"resume before the receipt" if resume_first else "receipt before the resume"])

	m._clear_reward_screens()
	m._close_popup(true)
	# The offer, forced live exactly as SHOT=popup:powerup does it.
	m.set("powerup_id", pu_id)
	m.set("powerup_until", m._now() + Deals.POWERUP_DURATION)
	m.set("powerup_pending", "")
	m._open_powerup()
	for _i in 6:
		await get_tree().process_frame
	if m.get("_popup") == null:
		fails += 1
		print("   [FAIL] the takeover did not open at all")
		return

	var spins0 := int(m.get("spins"))
	var coins0 := int(m.get("coins"))
	var owed := _bonus_owed(pu)
	var owed_total_spins := int(owed["spins"]) + int(pack.get("spins", 0))
	var owed_total_coins: int = int(owed["coins"]) + m._scaled(int(pack.get("coins", 0)))

	var btn := _find_buy(m.get("_popup"))
	if btn == null:
		fails += 1
		print("   [FAIL] no price button on the takeover")
		return
	btn.pressed.emit()
	if away > 0.0:
		# The sheet comes up over the game, and time passes on it.
		m._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
		m.set("_away_since", m._now() - away)
		await get_tree().process_frame
		if resume_first:
			m._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
			await _settle()
		else:
			await _settle()
			m._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
			await _settle()
	else:
		# The desktop sim's pretend payment sheet (IAP.SIM_DELAY), then the receipt.
		await _settle()

	print("   after the receipt: screen=%s queue=%d" % [_screen(),
		(m.get("_reward_queue") as Array).size()])
	if _screen() == "":
		fails += 1
		print("   [FAIL] the receipt put nothing on screen")

	# Dismiss everything, one tap at a time, the way a player would. Four is
	# more than the two boxes this owes, so a queue that stalls shows up as an
	# early empty screen rather than as a timeout.
	for i in 4:
		if _screen() == "":
			break
		var before := _screen()
		await _tap()
		print("   tap %d: %s -> %s (queue %d)" % [i + 1, before, _screen(),
			(m.get("_reward_queue") as Array).size()])

	# The flights land in chunks over a second or so and each one takes its
	# figure off the hold, so the HUD has to be read after they have arrived --
	# not on the frame the last box closed.
	await _settle_flights()
	var got_spins := int(m.get("spins")) - spins0
	var got_coins := int(m.get("coins")) - coins0
	print("   purse: spins +%d (owed %d)   coins +%d (owed %d)" % [
		got_spins, owed_total_spins, got_coins, owed_total_coins])
	# The HUD is the other half of it: a figure still on hold is one the player
	# cannot see, which is the same thing to them as one that never arrived.
	var held: Dictionary = m.get("_hud_lag")
	print("   held after dismissal: %s" % held)
	if got_spins < owed_total_spins or got_coins < owed_total_coins:
		fails += 1
		print("   [FAIL] the two free columns did not all land in the purse")
	for k in held.keys():
		if int(held[k]) != 0:
			fails += 1
			print("   [FAIL] '%s' is still held -- the HUD is short by %d" % [k, held[k]])


# THE FINGER THAT IS STILL COMING DOWN.
#
# The regression test for what Guy reported: one receipt owes two boxes, and
# the taps that dismiss the first must not carry through the second. Both boxes
# have to be seen, so the box opened by the queue has to survive a tap that
# arrives on the frame it opens.
func _impatient() -> void:
	print("")
	print("== pu_deckhand -- two taps a frame apart, the way a phone gets them")
	m._clear_reward_screens()
	m._close_popup(true)
	m.set("powerup_id", "pu_deckhand")
	m.set("powerup_until", m._now() + Deals.POWERUP_DURATION)
	m.set("powerup_pending", "")
	m._open_powerup()
	for _i in 6:
		await get_tree().process_frame
	var btn := _find_buy(m.get("_popup"))
	if btn == null:
		fails += 1
		print("   [FAIL] no price button on the takeover")
		return
	btn.pressed.emit()
	await _settle()
	var first = m.get("_chest_seq")
	if first == null or not is_instance_valid(first):
		fails += 1
		print("   [FAIL] the paid pack put no box up")
		return
	# Pop the lid, then dismiss -- two taps, as fast as the hardware sends them.
	_poke(first)
	await get_tree().process_frame
	_poke(first)
	# And a third, aimed at a box that is already on its way out. This is the
	# one that used to land on the free columns' box the instant it opened.
	var second = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await get_tree().process_frame
		var live = m.get("_chest_seq")
		if live != null and is_instance_valid(live) and live != first:
			second = live
			# Both of them on the frame it opened: pop and dismiss, which is
			# what a burst aimed at the box before it actually does.
			_poke(second)
			_poke(second)
			break
	if second == null:
		fails += 1
		print("   [FAIL] the two free columns' box never opened at all")
		return
	# Past the deaf window AND past the 0.24s dismissal fade, so "still valid"
	# means still standing rather than still fading out.
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 1200:
		await get_tree().process_frame
	if not is_instance_valid(second):
		fails += 1
		print("   [FAIL] the stray taps dismissed it -- the free columns were never seen")
	else:
		print("   the free columns' box is standing after the stray taps: PASS")
		second.skip(true)
	await _settle_flights()
