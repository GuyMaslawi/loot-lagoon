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
# deliver the receipt, and then dismisses what the paid pack put up the way a
# finger would -- and then checks the three things the offer owes, which Guy
# named on 2026-09-19:
#
#   1. THE SHEET STAYS. The takeover is not torn down by its own receipt; the
#      player closes it when they are done looking at it.
#   2. THE TWO SEALS OPEN. Both padlocks spring, and the price button retires
#      so a spent offer cannot be sold twice.
#   3. THE TWO PACKS CAN BE OPENED. Guy, off the build on 2026-09-24: after the
#      purchase the animation opens both of them *"but they are not clickable,
#      and that is very severe"*. So an unsealed column is not scenery -- it
#      carries a live target, one press opens one pack, and a second press on
#      the same one may not pay it twice.
#   4. THE GOODS LAND. The purse ends up holding the bonus spins and coins and
#      the HUD is not left with a figure on hold -- whether the player opened
#      the two packs or walked away from them (_abandoned).
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
	# AND THE STATE A REAL PLAYER IS MOST LIKELY TO BE IN. A chain runs 24 hours
	# in every 54 and a trio 12 in every 32, so the two overlap most days -- and
	# `pu_squall` sells `to_squall`, which is rung three of the High Tide Hunt.
	# Both credit handlers claim the same receipt, and the ladder's beats go
	# into the same queue as the two free columns.
	await _run("pu_squall", 0.0, false, "tide_hunt")
	await _impatient()
	await _abandoned()

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


# THE TWO FREE PACKS, OPENED THE WAY THE PLAYER OPENS THEM.
#
# The target is a real Button laid over the whole column and kept on the seal
# as `tap` -- see _powerup_seal_arm -- so pressing it here is the same event a
# finger raises, and its absence is the failure this harness exists to catch.
#
# It is waited for, not read once: the seal arms about half a second after the
# box in front of it was dismissed (the queue's pause, the stagger between the
# two locks, and the shackle's own swing), and a harness that looked on the
# frame the chest closed would report a dead pack every time.
#
# Returns how many of the two could actually be pressed.
func _open_free_packs() -> int:
	var seals: Array = m.get("_powerup_seals")
	var armed := 0
	for i in seals.size():
		var plate = seals[i]
		if not is_instance_valid(plate):
			continue
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3000:
			if is_instance_valid(plate.get_meta("tap", null)):
				break
			await get_tree().process_frame
		var tap = plate.get_meta("tap", null)
		if not (is_instance_valid(tap) and tap is Button):
			continue
		armed += 1
		(tap as Button).pressed.emit()
		# TWICE, A FRAME APART. One pack, one payout: a double tap on the same
		# column must not pay it a second time, and the purse check at the end
		# of _run is what would catch it if it did.
		await get_tree().process_frame
		if is_instance_valid(tap):
			(tap as Button).pressed.emit()
		await _settle()
		# Whatever that pack put up -- a column carrying cards opens a box.
		for _i in 3:
			if _screen() == "":
				break
			await _tap()
		if not bool((plate as Control).get_meta("takenmark", false)):
			fails += 1
			print("   [FAIL] pressing a free pack left its seal unspent")
	return armed


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


func _run(pu_id: String, away: float, resume_first: bool, chain_id := "") -> void:
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
	# A chain parked on the rung that sells this pack, when the case asks for
	# one. deal_taken is the rung the ladder is standing on.
	m.set("deal_id", "")
	if chain_id != "":
		var chain := Deals.by_id(chain_id)
		var rung := -1
		for i in (chain["steps"] as Array).size():
			if String((chain["steps"][i] as Dictionary).get("pack", "")) == String(pu["pack"]):
				rung = i
		if rung < 0:
			print("   [SKIP] %s does not sell %s" % [chain_id, pu["pack"]])
			return
		m.set("deal_id", chain_id)
		m.set("deal_until", m._now() + Deals.CHAIN_DURATION)
		m.set("deal_taken", rung)
		print("   (%s is standing on rung %d, which sells the same pack)" % [chain_id, rung + 1])
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

	# AND NOW THE PART THE RECEIPT DOES NOT DO. The two free packs are sitting
	# on the sheet unsealed and unopened; nothing is owed to the HUD until a
	# finger takes them. This is the press Guy went looking for and did not
	# find, so a harness that measured the counters without it would be
	# measuring the bug and passing it.
	var armed := await _open_free_packs()
	print("   free packs armed: %d of 2" % armed)
	if armed < 2:
		fails += 1
		print("   [FAIL] an unsealed free pack had nothing to press")
	# The flights land in chunks over a second or so and each one takes its
	# figure off the hold, so the HUD has to be read after they have arrived --
	# not on the frame the last box closed.
	await _settle_flights()
	# 1. the sheet is still standing, and its price is retired
	var sheet_up := m.get("_popup") != null
	var btn_after = m.get("_powerup_buy_btn")
	var retired := btn_after != null and is_instance_valid(btn_after) and (btn_after as Button).disabled
	print("   the offer sheet after the receipt: %s   price button retired: %s"
		% ["still up" if sheet_up else "GONE", retired])
	if not sheet_up:
		fails += 1
		print("   [FAIL] the receipt closed the offer -- it has to stay until the player closes it")
	if not retired:
		fails += 1
		print("   [FAIL] the price button is still live on a spent offer")

	# 2. both seals came off
	var seals: Array = m.get("_powerup_seals")
	var opened := 0
	for plate in seals:
		if is_instance_valid(plate) and bool((plate as Control).get_meta("opened", false)):
			opened += 1
	print("   seals opened: %d of %d" % [opened, seals.size()])
	if opened < 2:
		fails += 1
		print("   [FAIL] the two locks did not open on the sheet")

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
# The regression test for what Guy reported: the taps that dismiss the paid
# pack's box must not carry through to whatever the offer opens next. With the
# sheet now surviving its own receipt, the thing that must survive the burst is
# the sheet itself -- a stray tap may not close the screen the player is about
# to watch two locks open on.
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
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(first) and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	# Everything the unseal owes, plus the box the cards open in.
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 2500:
		await get_tree().process_frame
	var seals: Array = m.get("_powerup_seals")
	var opened := 0
	var eaten := 0
	for plate in seals:
		if not (is_instance_valid(plate) and bool((plate as Control).get_meta("opened", false))):
			continue
		opened += 1
		# AND THE BURST MUST NOT HAVE OPENED A PACK EITHER. The seal arms about
		# half a second after the box in front of it goes, which is past the
		# window a double tap lives in -- if that ever drifts, the finger that
		# dismissed the paid pack's chest would spend one of the two free ones
		# on its way back up and the player would never see it open.
		if bool((plate as Control).get_meta("takenmark", false)):
			eaten += 1
	if m.get("_popup") == null:
		fails += 1
		print("   [FAIL] the stray taps took the offer sheet down with the box")
	elif opened < 2:
		fails += 1
		print("   [FAIL] the seals did not open: %d of %d" % [opened, seals.size()])
	elif eaten > 0:
		fails += 1
		print("   [FAIL] %d free pack(s) were opened by the stray taps" % eaten)
	else:
		print("   the sheet is standing, both seals are open and neither pack was spent: PASS")
	m._clear_reward_screens()
	m._close_popup(true)
	await _settle_flights()


# THE PLAYER WHO NEVER PRESSES THEM.
#
# The two packs wait for a finger, and a finger is the one thing a screen
# cannot insist on: the cross is right there, and a dialog opening over the top
# of the sheet takes it down without asking. What must not happen is the goods
# going with it -- they are banked and saved by then, but they are also HELD
# off the HUD, and a hold nobody settles is a purse that reads short for the
# rest of the session. See _powerup_abandon, which _close_popup runs before it
# frees anything.
func _abandoned() -> void:
	print("")
	print("== pu_quartermaster -- both free packs left unopened, sheet closed with the cross")
	m._clear_reward_screens()
	m._close_popup(true)
	await _settle_flights()
	m.set("powerup_id", "pu_quartermaster")
	m.set("powerup_until", m._now() + Deals.POWERUP_DURATION)
	m.set("powerup_pending", "")
	m._open_powerup()
	for _i in 6:
		await get_tree().process_frame
	var spins0 := int(m.get("spins"))
	var coins0 := int(m.get("coins"))
	var pu := Deals.powerup_by_id("pu_quartermaster")
	var owed := _bonus_owed(pu)
	var btn := _find_buy(m.get("_popup"))
	if btn == null:
		fails += 1
		print("   [FAIL] no price button on the takeover")
		return
	btn.pressed.emit()
	await _settle()
	# Dismiss the paid pack's box and let both seals spring, then walk away.
	for _i in 3:
		if _screen() == "":
			break
		await _tap()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1800:
		await get_tree().process_frame
	var held_before: Dictionary = (m.get("_hud_lag") as Dictionary).duplicate()
	m._close_popup()
	# The box the unopened cards open behind it, dismissed like any other.
	for _i in 3:
		await _settle()
		if _screen() == "":
			break
		await _tap()
	await _settle_flights()
	var got_spins := int(m.get("spins")) - spins0
	var got_coins := int(m.get("coins")) - coins0
	var held: Dictionary = m.get("_hud_lag")
	print("   held with both packs still sealed: %s" % held_before)
	print("   purse: spins +%d (owed >=%d)   coins +%d (owed >=%d)   held after: %s"
		% [got_spins, owed["spins"], got_coins, owed["coins"], held])
	if int(held_before.get("coins", 0)) <= 0:
		fails += 1
		print("   [FAIL] an unopened pack was not holding its coins off the HUD")
	if got_spins < int(owed["spins"]) or got_coins < int(owed["coins"]):
		fails += 1
		print("   [FAIL] closing the sheet lost what the two packs were holding")
	for k in held.keys():
		if int(held[k]) != 0:
			fails += 1
			print("   [FAIL] '%s' is still held after the sheet went -- the HUD is short by %d"
				% [k, held[k]])
	m._clear_reward_screens()
	await _settle_flights()
