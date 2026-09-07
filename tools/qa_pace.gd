extends Node
# Dev-only harness: HOW LONG AN ISLAND ACTUALLY TAKES.
#
#   godot --headless --path . tools/qa_pace.tscn
#
# Every claim about pacing in this codebase has so far been arithmetic written
# into a comment. This measures it instead, by playing real spins through
# main.gd's own `_roll()` and `_on_spin_finished()`.
#
# WHY ONE ISLAND'S WORTH OF SPINS ANSWERS FOR ALL NINETY. Both sides of the
# ledger ride a curve: a payout is `curve(level)` and a price is
# `cost_curve(level)`. So the number of spins an island takes is
#
#     84,000 * cost_curve(L) / (income_per_spin * curve(L))
#
# and the only thing that moves with L is the RATIO of the two curves. Below the
# knee they are the same function and the ratio is exactly 1 -- which is the
# fact the ninety-island change was built on. So income is sampled once, at
# island 1, and the rest is that ratio.
#
# Not shipped -- tools/ is excluded from the export preset.

const SPINS := 40000
const VAULT_SAMPLES := 20000
# A full island: five buildings, five stars each, at island-1 prices.
const ISLAND_COST := 84000
# What the project has been assuming a player gets through in a day. The meter
# holds 50 and refills 3 every 120s, so 2,160 is the ceiling and only reachable
# by a player who never lets it cap. 350 is a few real sessions.
const SPINS_PER_DAY := 350

var m: Control

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout

	var s := await _sample()
	var vault := _vault_mean()

	# THE STEAL IS EXPECTED, NOT PLAYED. IslandVisit is an overlay with three
	# taps in it and there is no way to drive it in a loop -- but its payout is
	# fully determined: four chests holding [25%, 25%, 50%, 0] of the rival's
	# vault, of which the player opens three. Three of four chests is three
	# quarters of the pot, whichever three.
	var steal_rate: float = float(s["steals"]) / float(SPINS)
	var steal_income: float = steal_rate * vault * 0.75
	# An attack pays no coins at all. It flattens a building and scores the
	# tournament; the coins come back later as revenge, from the other side.
	var attack_rate: float = float(s["attacks"]) / float(SPINS)

	var reel_income: float = float(s["coins"]) / float(SPINS)
	var income := reel_income + steal_income
	# Bolt triples hand back 12 spins, so a played spin costs less than a spin.
	var free: float = float(s["free_spins"]) / float(SPINS)

	print("")
	print("================= QA-PACE =================")
	print("  sampled %d spins at bet x1 on island 1" % SPINS)
	print("")
	print("  reel coins per spin        %8.1f" % reel_income)
	print("  steal coins per spin       %8.1f   (%.2f%% of spins, mean vault %.0f)"
		% [steal_income, steal_rate * 100.0, vault])
	print("  attack coins per spin          0.0   (%.2f%% of spins, pays no coins)"
		% [attack_rate * 100.0])
	print("  ------------------------------------")
	print("  income per spin            %8.1f" % income)
	print("  free spins per spin        %8.3f   (bolt triples)" % free)
	print("")
	print("  a full island costs %s coins at island-1 prices" % UI.fmt(ISLAND_COST))
	print("")
	print("  island   cost/payout   spins played   meter spins   days @ %d/day" % SPINS_PER_DAY)
	var total_played := 0.0
	var total_meter := 0.0
	for lvl in range(1, CV.ECONOMY_MAX_LEVEL + 1):
		var ratio: float = CV.cost_curve(lvl) / CV.curve(lvl)
		var played: float = float(ISLAND_COST) * ratio / income
		var meter: float = played * (1.0 - free)
		total_played += played
		total_meter += meter
		if lvl in [1, 10, 20, 30, 31, 45, 60, 75, 90]:
			print("  %6d   %10.2fx   %12.0f   %11.0f   %8.1f"
				% [lvl, ratio, played, meter, meter / float(SPINS_PER_DAY)])
	print("  ------------------------------------")
	print("  all %d islands: %s spins played, %s off the meter, %.0f days at %d/day"
		% [CV.ECONOMY_MAX_LEVEL, UI.fmt(int(total_played)), UI.fmt(int(total_meter)),
			total_meter / float(SPINS_PER_DAY), SPINS_PER_DAY])
	print("  the first 30:   %s off the meter, %.0f days"
		% [UI.fmt(int(_meter_upto(30, income, free))),
			_meter_upto(30, income, free) / float(SPINS_PER_DAY)])
	print("")
	_passive()
	print("===========================================")
	get_tree().quit(0)

# WHAT A PLAYER IS PAID FOR TURNING UP, and it is not small.
#
# None of this comes off the meter, so none of it is in the table above -- but
# it is spent on the same buildings, so it is a share of the same island. Every
# figure is at island-1 prices, the same units as ISLAND_COST, because all of
# them go through `_scaled()` on the way out.
func _passive() -> void:
	# The seven rungs of the streak, averaged: a player who turns up every day
	# is on a different rung each day and holds at seven.
	var streak := 0.0
	for c in m.STREAK_COINS:
		streak += float(c)
	streak /= float(m.STREAK_COINS.size())
	var top := float(m.STREAK_COINS[m.STREAK_COINS.size() - 1])

	# get(), not [] -- the "claim the daily bonus" quest pays in SPINS and
	# carries no "coins" key at all.
	var daily_missions := 0.0
	for q in m.MISSION_DEFS["daily"]:
		daily_missions += float(q.get("coins", 0))
	daily_missions += float(m.MISSION_BONUS["daily"]["coins"])

	var gift := float(CV.SHOP_FREE_COINS)   # the shop's free gift, every 24h
	var a_day := streak + daily_missions + gift
	var at_top := top + daily_missions + gift

	print("  coins a day that are NOT spins, at island-1 prices:")
	print("    daily bonus (7-rung average)   %8s   (%s on day 7)"
		% [UI.fmt(int(streak)), UI.fmt(int(top))])
	print("    daily missions + their bonus   %8s" % UI.fmt(int(daily_missions)))
	print("    the shop's free gift           %8s" % UI.fmt(int(gift)))
	print("    ----------------------------------------")
	print("    per day                        %8s   = %.0f%% of an island"
		% [UI.fmt(int(a_day)), a_day / float(ISLAND_COST) * 100.0])
	print("    on a held day-7 streak         %8s   = %.0f%% of an island"
		% [UI.fmt(int(at_top)), at_top / float(ISLAND_COST) * 100.0])
	print("")
	print("  NOT counted anywhere above: chests, the piggy bank, clan gifts,")
	print("  tournament prizes, weekly and monthly missions. The real pace is")
	print("  therefore FASTER than the table, never slower.")

func _meter_upto(last: int, income: float, free: float) -> float:
	var t := 0.0
	for lvl in range(1, last + 1):
		t += float(ISLAND_COST) * (CV.cost_curve(lvl) / CV.curve(lvl)) / income * (1.0 - free)
	return t

# One island's worth of real spins, with the raid path bolted shut.
#
# `_raid_pending` is set once and never cleared, so `_start_visit` refuses every
# raid triple -- see `_raiding()`. That is deliberate: a raid is a full-screen
# overlay waiting on three taps and there is nothing to tap here, so what is
# wanted from those spins is the COUNT, not the payout.
func _sample() -> Dictionary:
	m.island_level = 1
	m.buildings = [0, 0, 0, 0, 0]
	m.coins = 0
	m.shields = 0
	m._raid_pending = true
	var steals := 0
	var attacks := 0
	var spins_before := 0
	var free_spins := 0
	for i in SPINS:
		m.spins = 50
		m._last_bet = 1
		var roll: Array = m._roll()
		if roll[0] == roll[1] and roll[1] == roll[2]:
			match roll[0]:
				"steal": steals += 1
				"hammer": attacks += 1
				"bolt": free_spins += 12
		spins_before = m.spins
		m._on_spin_finished(roll)
		if i % 2000 == 0:
			await get_tree().process_frame
	return {"coins": m.coins, "steals": steals, "attacks": attacks,
		"free_spins": free_spins}

# What a rival is actually carrying, in island-1 coins. Drawn rather than read
# off CV.new_npc's source, so a change to the purse roll turns up here.
func _vault_mean() -> float:
	var total := 0.0
	for i in VAULT_SAMPLES:
		total += float(CV.new_npc(CV.BOT_DEFS[i % CV.BOT_DEFS.size()], 1)["coins"])
	return total / float(VAULT_SAMPLES)
