extends Node
# One-off: a 1+2 purchase must leave TWO reward screens, taken in turn, and the
# free columns' spins and coins must land on the counters when the second one
# is dismissed.
var m: Control
var fails := 0

# FRAMES ARE NOT SECONDS IN A HEADLESS RUN. The loop spins as fast as the
# process will go, so sixty of them is a few dozen milliseconds of tween time
# and every animation this file is waiting on is still in the air. Waited on
# the wall clock instead -- see the qa harness notes.
func _wait(secs: float) -> void:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	var t0 := Time.get_ticks_msec()
	while not bool(m.get("_booted")):
		if Time.get_ticks_msec() - t0 > 20000:
			print("BOOT TIMEOUT"); get_tree().quit(1); return
		await get_tree().process_frame

	var pu: Dictionary = Deals.POWERUPS[1]   # bundle_m: 350 spins, 200k coins, 2 cards, 1 shield free
	m.set("powerup_id", String(pu["id"]))
	m.set("powerup_until", m._now() + 3600.0)
	m.set("powerup_pending", String(pu["id"]))
	var spins0: int = m.get("spins")
	var coins0: int = m.get("coins")

	m._on_purchase_ok(IAP.PREFIX + String(pu["pack"]))
	await _wait(1.0)

	var q: Array = m.get("_reward_queue")
	print("screen 1: chest=%s payout=%s  queued behind it: %d"
		% [is_instance_valid(m.get("_chest_seq")), is_instance_valid(m.get("_payout_seq")), q.size()])
	if q.size() != 1:
		fails += 1
		print("   [FAIL] the two free packs should be waiting behind the pack that was paid for")

	print("   spins shown %d / truth %d   coins shown %d / truth %d"
		% [m._hud_shown("spins", m.get("spins")), m.get("spins"),
		   m._hud_shown("coins", m.get("coins")), m.get("coins")])
	if m._hud_shown("spins", m.get("spins")) >= int(m.get("spins")):
		fails += 1
		print("   [FAIL] the free spins are on the counter before the screen that owes them")

	# A finger on the first screen.
	var first = m.get("_chest_seq")
	if first == null or not is_instance_valid(first):
		first = m.get("_payout_seq")
	first.skip()
	await _wait(1.5)
	print("screen 2: chest=%s payout=%s  still queued: %d"
		% [is_instance_valid(m.get("_chest_seq")), is_instance_valid(m.get("_payout_seq")),
		   (m.get("_reward_queue") as Array).size()])
	if not is_instance_valid(m.get("_chest_seq")) and not is_instance_valid(m.get("_payout_seq")):
		fails += 1
		print("   [FAIL] the free packs never got their screen")

	var second = m.get("_chest_seq")
	if second != null and is_instance_valid(second):
		second.skip()
	await _wait(5.0)
	print("after both: spins %d -> %d (shown %d), coins %d -> %d (shown %d)"
		% [spins0, m.get("spins"), m._hud_shown("spins", m.get("spins")),
		   coins0, m.get("coins"), m._hud_shown("coins", m.get("coins"))])
	if m._hud_shown("spins", m.get("spins")) != int(m.get("spins")):
		fails += 1
		print("   [FAIL] the spin counter is left short of the save")
	if m._hud_shown("coins", m.get("coins")) != int(m.get("coins")):
		fails += 1
		print("   [FAIL] the purse is left short of the save")

	m._clear_reward_screens()
	await _wait(0.5)

	print("")
	print("QA-QUEUE: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)


