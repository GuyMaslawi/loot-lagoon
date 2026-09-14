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

	# --- and the ladder, which is the other half of the same report: the six
	# rungs, where a paid one used to close the screen it was bought from.
	await _chain()

	print("")
	print("QA-QUEUE: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)


# A PAID RUNG KEEPS THE LADDER. It used to be torn down on the tap, which made
# _after_deal_step's "the ladder is on screen" branch unreachable for the one
# rung that costs money -- so the unlock the player had just paid for was owed
# to their next visit. Now the screen survives the payment sheet and the beats
# play when the box in front of them is dismissed.
func _chain() -> void:
	print("")
	var chain: Dictionary = Deals.CHAINS[0]
	var paid := -1
	for i in (chain["steps"] as Array).size():
		if Deals.is_paid(chain["steps"][i]):
			paid = i
			break
	m.set("deal_id", String(chain["id"]))
	m.set("deal_until", m._now() + 3600.0)
	m.set("deal_taken", paid)
	m._open_deal()
	await _wait(0.6)
	if m.get("_popup") == null:
		fails += 1
		print("   [FAIL] the ladder would not open")
		return
	m._take_deal(paid)
	IAP.sim_cancel()
	print("ladder, rung %d pressed: popup still up = %s" % [paid + 1, m.get("_popup") != null])
	if m.get("_popup") == null:
		fails += 1
		print("   [FAIL] the ladder was torn down on the tap -- it has to stay behind the payment sheet")

	m._on_purchase_ok(IAP.PREFIX + String(chain["steps"][paid]["pack"]))
	await _wait(1.0)
	print("   after the receipt: rung taken = %d, popup still up = %s, box on screen = %s"
		% [m.get("deal_taken"), m.get("_popup") != null,
		   is_instance_valid(m.get("_chest_seq")) or is_instance_valid(m.get("_payout_seq"))])
	if int(m.get("deal_taken")) != paid + 1:
		fails += 1
		print("   [FAIL] the rung did not advance")
	if m.get("_popup") == null:
		fails += 1
		print("   [FAIL] the ladder is gone -- the unlock plays where nobody can see it")
	m._clear_reward_screens()
	await _wait(0.8)
