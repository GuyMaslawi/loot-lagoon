extends Node
# A PURCHASE ON A PHONE IS NOT ONE EVENT, IT IS FOUR, AND THE HARNESS THAT
# ONLY SENDS THE LAST ONE PASSES. Not shipped.
#
# On iOS, StoreKit's payment sheet is system UI. The app gets FOCUS_OUT when it
# comes up and FOCUS_IN when it goes away, and the transaction callback lands
# somewhere around the second of those. So the real order is:
#
#   1. price button pressed on the shelf     -> IAP.purchase()
#   2. NOTIFICATION_APPLICATION_FOCUS_OUT    -> _go_away()
#   3. NOTIFICATION_APPLICATION_FOCUS_IN     -> _resume_from_away()
#   4. purchase_succeeded                    -> _on_purchase_ok()
#
# ...and 3 and 4 can arrive in either order. Nothing on the desktop sends 2 or
# 3 at all, which is why every earlier harness saw a clean purchase.
#
#   godot --headless --path . res://tools/qa_buy.tscn

var m: Control
var fails := 0

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	var t0 := Time.get_ticks_msec()
	while not bool(m.get("_booted")):
		if Time.get_ticks_msec() - t0 > 20000:
			print("BOOT TIMEOUT"); get_tree().quit(1); return
		await get_tree().process_frame

	# Every pack family, because they do not all land in the same result
	# dialog: only the ones carrying cards open a chest reveal.
	for id in ["spins_s", "spins_m", "coins_m", "coins_l", "chest_w", "chest_m",
			"bundle_s", "starter"]:
		await _buy(id, 5.0, true)

	# Both orderings, and a long enough absence to trip the 60s branch that
	# only a real payment sheet is slow enough to reach.
	for away in [5.0, 120.0]:
		for resume_first in [true, false]:
			await _buy("chest_g", away, resume_first)

	print("")
	print("QA-BUY: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _buy(short: String, away: float, resume_first: bool) -> void:
	print("")
	print("== %s, %ds on the payment sheet, %s" % [short, int(away),
		"resume before the receipt" if resume_first else "receipt before the resume"])
	m._close_popup(true)
	m._goto(m.pages["shop"])
	for _i in 6:
		await get_tree().process_frame
	var body: VBoxContainer = m._page_bodies["shop"]
	print("   shop rows before: %d" % body.get_child_count())

	# 2. the sheet comes up
	m._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	# time passes on the sheet
	m._away_since = m._now() - away
	await get_tree().process_frame

	if resume_first:
		m._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
		await get_tree().process_frame
		m._on_purchase_ok(IAP.PREFIX + short)
	else:
		m._on_purchase_ok(IAP.PREFIX + short)
		await get_tree().process_frame
		m._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)

	for _i in 90:
		await get_tree().process_frame

	var rows := body.get_child_count()
	# WHAT COUNTS AS "THE PURCHASE SAID SOMETHING" IS NO LONGER ONE THING.
	#
	# This used to test `_popup` alone, because every purchase ended in a
	# dialog. Two of them now end in a full-screen takeover instead -- a pack
	# of coins or spins in PayoutShow, a handful of cards in ChestOpen with the
	# cards thrown out of the lid -- and a card handful with nothing extra to
	# report puts up no dialog at all any more.
	#
	# The CHECK still matters and is not being relaxed: the thing it exists to
	# catch is a payment that leaves the screen looking exactly as it did
	# before, which Guy read as a failed purchase on his own phone. So it now
	# asks the real question -- is ANY of the three saying what arrived -- and
	# would still fail if all three were missing.
	var popup = m.get("_popup")
	var chest = m.get("_chest_seq")
	var payout = m.get("_payout_seq")
	var shown := ""
	if popup != null:
		shown = "popup"
	elif chest != null and is_instance_valid(chest):
		shown = "chest takeover"
	elif payout != null and is_instance_valid(payout):
		shown = "payout takeover"
	print("   shop rows after:  %d" % rows)
	print("   receipt on screen: %s" % (shown if shown != "" else "NOTHING"))
	if rows < 5:
		fails += 1
		print("   [FAIL] the shop page came back EMPTY -- header and nothing under it")
	if shown == "":
		fails += 1
		print("   [FAIL] nothing on screen says what was bought")
