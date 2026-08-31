extends Node
# =============================================================================
#  Loot Lagoon -- full QA sweep
# =============================================================================
#
# Every calculation the game does, every automatic action, and every manual one
# a player can reach, driven headlessly against the real main.gd.
#
# Written as exact assertions wherever the maths is exact (payout tables,
# upgrade ladders, melt values, top-up bounds) and as measured distributions
# where it is random (chest star odds, card drop rate, reel triples) -- the
# random ones matter most, because the chest odds are published in the store
# and App Store Guideline 3.1.1 makes them a promise rather than a tuning knob.
#
# Not shipped. Run: godot --headless --path . res://tools/qa_full.tscn

var m: Control
var fails := 0
var checks := 0

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	_quiet()

	_section("1. the economy curve")
	_t_curve()
	_section("2. published chest odds (App Store 3.1.1)")
	await _t_odds_published()
	await _t_odds_measured()
	_section("3. the price ladders")
	_t_ladders()
	_section("4. the pack table and the store front")
	_t_pack_table()
	_section("5. the upgrade ladder")
	await _t_upgrades()
	_section("6. the top-up dialog")
	_t_topup()
	_section("7. mission periods")
	_t_periods()
	await _t_mission_claims()
	_section("8. the spin meter")
	_t_regen()
	_section("9. the reels -- every payout, exactly")
	await _t_payouts()
	_t_roll_distribution()
	_section("10. card drops")
	await _t_drop_rate()
	_section("11. collections, melting and the grand prize")
	await _t_collections()
	_section("12. the daily bonus and the free gift")
	await _t_daily_and_gift()
	_section("13. the piggy bank")
	await _t_piggy()
	_section("14. the timed offer")
	await _t_offers()
	_section("15. purchases")
	await _t_purchases()
	_section("16. shields")
	await _t_shields()
	_section("17. the tournament")
	await _t_tourney()
	_section("18. a hostile save file")
	await _t_hostile_save()
	_section("19. the clock")
	_t_clock()
	_section("20. raids")
	await _t_raids()
	_section("21. alerts and the notification log")
	_t_alerts()

	print("")
	print("QA-FULL: %d checks, %s" % [checks, "ALL PASS" if fails == 0 else "%d FAILURES" % fails])
	get_tree().quit(1 if fails > 0 else 0)

# --- harness plumbing --------------------------------------------------------

func _section(title: String) -> void:
	print("")
	print("== %s" % title)

func _chk(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		fails += 1
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])

# Everything that would otherwise talk to the player, off. The toasts and
# banners are nodes, and a hundred thousand of them is the harness measuring
# its own allocator rather than the game.
func _quiet() -> void:
	m.muted = true
	m.notif_enabled = false
	m.auto_spin = false
	m.revenge_pending = false
	m.notif_log.clear()

# A hammer or raccoon triple starts a full-screen raid and waits for a tap.
# Nobody is here to tap, so anything that spins has to release it -- otherwise
# every later test runs behind a modal that never lifts, and _offline_raids
# (which correctly refuses to rob a player who cannot see it happen) silently
# does nothing for the rest of the run.
func _release_raid() -> void:
	var waited := 0.0
	while m._raiding() and waited < 15.0:
		if m._match != null and m._match.has_method("_lock_in"):
			m._match._live = true
			m._match._lock_in()
			m._match._close()
		elif m._visit != null and m._visit._stage != null:
			for c in m._visit._stage.get_children():
				if c is Button and not (c as Button).disabled:
					(c as Button).pressed.emit()
					break
		await get_tree().create_timer(0.1).timeout
		waited += 0.1

func _fresh_cards() -> void:
	m.col_owned = {}
	m.col_dupes = {}
	m.col_claimed = {}
	m.col_mega_claimed = false
	m.col_deadline = 0.0
	m._ensure_collections()

# =============================================================================
#  1. the economy curve
# =============================================================================

func _t_curve() -> void:
	_chk("island 1 is the unit of the curve", is_equal_approx(CV.curve(1), 1.0))
	var rising := true
	for lvl in range(1, CV.ECONOMY_MAX_LEVEL):
		if CV.curve(lvl + 1) <= CV.curve(lvl):
			rising = false
	_chk("the curve rises every island up to %d" % CV.ECONOMY_MAX_LEVEL, rising)
	var flat := true
	for lvl in [CV.ECONOMY_MAX_LEVEL, 31, 60, 200, m.MAX_ISLAND]:
		if not is_equal_approx(CV.curve(lvl), CV.curve(CV.ECONOMY_MAX_LEVEL)):
			flat = false
	_chk("and flattens past it, so nothing walks off int64", flat)

	# The whole reason the curve flattens: a price computed out there has to
	# still be a price.
	var bounded := true
	var worst := 0
	for lvl in [1, 30, 31, 99, 500, m.MAX_ISLAND]:
		for base in [400, 9000, 250000, 5000000]:
			var v := CV.scaled(base, lvl)
			worst = maxi(worst, v)
			if v <= 0 or v > 1 << 62:
				bounded = false
	_chk("every scaled figure stays positive and inside int64", bounded, "largest=%d" % worst)

	_chk("a zero base scales to zero", CV.scaled(0, 30) == 0 and CV.scaled(-5, 30) == 0)

	var monotone := true
	for lvl in range(1, CV.ECONOMY_MAX_LEVEL):
		if CV.scaled(9000, lvl + 1) < CV.scaled(9000, lvl):
			monotone = false
	_chk("a given price never gets cheaper on a later island", monotone)

	# Three significant digits, which is what makes a payout read as "+1.25M".
	var snapped := true
	var example := ""
	for lvl in range(1, 31):
		for base in [400, 900, 2000, 4500, 9000, 3000, 150, 60]:
			var v := CV.scaled(base, lvl)
			if v < 1000:
				continue
			var digits := str(v).length()
			var tail := str(v).substr(3)
			if tail != "0".repeat(digits - 3):
				snapped = false
				if example == "":
					example = "%d @ island %d -> %d" % [base, lvl, v]
	_chk("payouts snap to three significant digits", snapped, example)

# =============================================================================
#  2. the chest odds, as published and as rolled
# =============================================================================

func _t_odds_published() -> void:
	var sums_ok := true
	var detail := ""
	for tier in CV.CHEST_STAR_WEIGHTS.size():
		var total := 0.0
		for p in CV.star_odds(tier):
			total += float(p)
		if absf(total - 100.0) > 0.001:
			sums_ok = false
			detail += "tier %d sums to %.3f " % [tier, total]
	_chk("every published odds table sums to 100%", sums_ok, detail)

	# "0%" for a rate that is not zero is exactly the lie the guideline exists
	# to stop.
	var honest := true
	for p in [0.001, 0.01, 0.5, 0.99]:
		if CV.odds_pct(p) == "0%":
			honest = false
	_chk("a non-zero chance never prints as 0%", honest,
		"0.5%% prints as %s" % CV.odds_pct(0.5))
	_chk("a real zero is allowed to print as 0%", CV.odds_pct(0.0) == "0%")
	await get_tree().process_frame

# The one that matters. What the tile promises has to be what the roll does.
func _t_odds_measured() -> void:
	var n := 120000
	for tier in CV.CHEST_STAR_WEIGHTS.size():
		_fresh_cards()
		var seen := [0, 0, 0, 0, 0]
		for i in n:
			var card: Dictionary = m._grant_chest_card(tier)
			var s := int(card.get("stars", 0))
			if s >= 1 and s <= 5:
				seen[s - 1] += 1
			if i % 20000 == 0:
				await get_tree().process_frame
		var published: Array = CV.star_odds(tier)
		var line := ""
		var off := ""
		# Each row is its own binomial, so each gets its own tolerance: five
		# sigma on THAT row's published probability. A single tolerance taken
		# from the rarest row is far too tight for the 30% row and would fail
		# on ordinary sampling noise.
		for i in 5:
			var got := 100.0 * float(seen[i]) / float(n)
			var want := float(published[i])
			var pr := want / 100.0
			var sigma := 100.0 * sqrt(maxf(pr * (1.0 - pr), 1e-9) / float(n))
			var tol := 5.0 * sigma + 0.05
			line += "%d*: %.2f/%.2f  " % [i + 1, got, want]
			if absf(got - want) > tol:
				off += "%d* drifted %.3fpp (tol %.3f) " % [i + 1, absf(got - want), tol]
		_chk("chest tier %d rolls the odds it publishes" % tier, off == "",
			("%s %s" % [off, line]) if off != "" else line)

	# The guarantee, which is a separate promise from the table.
	_fresh_cards()
	var all_five := true
	for i in 2000:
		if int(m._grant_chest_card(2, CV.MAX_STAR).get("stars", 0)) != 5:
			all_five = false
	_chk("a guaranteed 5-star card is always a 5-star card", all_five)
	await get_tree().process_frame

# =============================================================================
#  3. the price ladders
# =============================================================================

func _t_ladders() -> void:
	for pair in [["spins", CV.SPIN_PACKS], ["coins", CV.COIN_PACKS]]:
		var key: String = pair[0]
		var packs: Array = pair[1]
		var climbing := true
		var prices_rise := true
		var line := ""
		var last_rate := 0.0
		var last_usd := 0.0
		for p in packs:
			var usd := CV.price_usd(p)
			var rate := float(p[key]) / usd
			line += "%.0f " % rate
			if rate <= last_rate:
				climbing = false
			if usd <= last_usd:
				prices_rise = false
			last_rate = rate
			last_usd = usd
		_chk("the %s ladder gets better per dollar every rung" % key, climbing, line)
		_chk("the %s ladder's prices only go up" % key, prices_rise)
		_chk("the %s entry rung is the quoted base rate" % key,
			is_equal_approx(float(packs[0][key]) / CV.price_usd(packs[0]),
				CV.SPIN_BASE_RATE if key == "spins" else CV.COIN_BASE_RATE))
		_chk("the %s entry rung advertises no bonus" % key, CV.bonus_pct(packs[0]) == 0,
			"%d%%" % CV.bonus_pct(packs[0]))
		var bonus_ok := true
		for p in packs:
			if CV.bonus_pct(p) < 0:
				bonus_ok = false
		_chk("no %s rung advertises a negative bonus" % key, bonus_ok)

	# Bundles carry a hand-set value instead of a measurable rate. It still has
	# to be a claim in the player's favour.
	var bundles_ok := true
	for group in [CV.BUNDLE_PACKS, CV.TIMED_OFFERS]:
		for p in group:
			if CV.bonus_pct(p) <= 0:
				bundles_ok = false
	_chk("every bundle and timed offer claims positive value", bundles_ok)

	# The piggy's pitch is that a full one beats the best rung on the shelf.
	var best_shelf := 0.0
	for p in CV.COIN_PACKS:
		best_shelf = maxf(best_shelf, float(p["coins"]) / CV.price_usd(p))
	var piggy_rate := float(CV.PIGGY_CAP) / CV.price_usd(CV.PIGGY_PACK)
	_chk("a full piggy really is the best coin deal in the game", piggy_rate > best_shelf,
		"%.0f vs %.0f coins/$" % [piggy_rate, best_shelf])

# =============================================================================
#  4. the pack table -- and whether the store can actually sell it
# =============================================================================

func _t_pack_table() -> void:
	var all := [CV.STARTER_PACK, CV.PIGGY_PACK]
	for group in [CV.CHEST_PACKS, CV.SPIN_PACKS, CV.COIN_PACKS, CV.BUNDLE_PACKS, CV.TIMED_OFFERS]:
		for p in group:
			all.append(p)

	var seen := {}
	var dupes := ""
	for p in all:
		var id := String(p["id"])
		if seen.has(id):
			dupes += id + " "
		seen[id] = true
	_chk("every pack id is unique", dupes == "", dupes)

	var priced := true
	var round_trips := true
	var bad := ""
	for p in all:
		if CV.price_usd(p) <= 0.0:
			priced = false
			bad += String(p["id"]) + " "
		if CV.pack_by_id(String(p["id"])).is_empty():
			round_trips = false
	_chk("every pack carries a real price", priced, bad)
	_chk("every pack is findable by its id", round_trips)
	_chk("an id the build does not know resolves to nothing",
		CV.pack_by_id("no_such_pack").is_empty())

	# The store can only sell what it registered. A pack with no product id is
	# a tile that opens Apple's sheet and gets an error back.
	var registered: Array = IAP.all_product_ids()
	var missing := ""
	for p in all:
		if not registered.has(IAP.PREFIX + String(p["id"])):
			missing += String(p["id"]) + " "
	_chk("every sellable pack has a product id the store registers", missing == "", missing)
	var orphan := ""
	for pid in registered:
		var short := String(pid).trim_prefix(IAP.PREFIX)
		if CV.pack_by_id(short).is_empty():
			orphan += short + " "
	_chk("every registered product id maps back to a pack", orphan == "", orphan)
	var uniq := {}
	for pid in registered:
		uniq[pid] = true
	_chk("no product id is registered twice", uniq.size() == registered.size(),
		"%d ids, %d unique" % [registered.size(), uniq.size()])
	# Card boxes are bought with stars and must never appear on the money list.
	var boxes_leaked := ""
	for box in CV.CARD_BOXES:
		if registered.has(IAP.PREFIX + String(box["id"])):
			boxes_leaked += String(box["id"]) + " "
	_chk("nothing bought with stars is registered for money", boxes_leaked == "", boxes_leaked)

# =============================================================================
#  5. the upgrade ladder
# =============================================================================

func _t_upgrades() -> void:
	var costs: Array = m._star_costs()
	_chk("there is one cost per star level", costs.size() == CV.MAX_STAR)
	var rising := true
	for i in costs.size() - 1:
		if int(costs[i + 1]) <= int(costs[i]):
			rising = false
	_chk("each star costs more than the one below it", rising, str(costs))

	var positive := true
	for lvl in [1, 30, 31, 200, m.MAX_ISLAND]:
		m.island_level = lvl
		for c in m._star_costs():
			if int(c) <= 0:
				positive = false
	_chk("star costs stay positive on every island", positive)

	# A whole island built out, counted to the coin.
	m.island_level = 1
	m.buildings = [0, 0, 0, 0, 0]
	m.coins = 100000000
	m.stars = 0
	m.rank_stars = 0
	m.tourney_id = m._tourney_now_id()
	m.tourney_points = 0
	m.tourney_claimed = []
	m._ensure_missions()
	# Measured as a delta. Missions persist in the save, so a previous run of
	# this harness leaves build progress on today's daily and an absolute
	# count would be measuring that instead of these twenty-five upgrades.
	var builds_before := int(m.mission_state["daily"]["progress"].get("builds", 0))
	var start_coins: int = m.coins
	var expect_cost := 0
	for c in m._star_costs():
		expect_cost += int(c)
	expect_cost *= CV.BUILDINGS.size()
	# 1+2+3+4+5 per building: an upgrade is worth the level it reaches.
	var expect_stars := 15 * CV.BUILDINGS.size()

	for i in CV.BUILDINGS.size():
		for lvl in CV.MAX_STAR:
			var waited := 0.0
			while m.village.is_constructing(i) and waited < 8.0:
				await get_tree().create_timer(0.1).timeout
				waited += 0.1
			m._on_upgrade_requested(i)
			await get_tree().process_frame
	_chk("every hut reached five stars",
		m.buildings == [5, 5, 5, 5, 5], str(m.buildings))
	_chk("the island cost exactly the sum of its star prices",
		start_coins - m.coins == expect_cost,
		"spent %d, expected %d" % [start_coins - m.coins, expect_cost])
	_chk("building paid the stars the ladder promises", m.stars == expect_stars,
		"%d vs %d" % [m.stars, expect_stars])
	_chk("and banked the same into the permanent rank", m.rank_stars == expect_stars,
		"%d vs %d" % [m.rank_stars, expect_stars])
	_chk("the tournament scored every build",
		m.tourney_points == m.TP_BUILD * CV.MAX_STAR * CV.BUILDINGS.size(),
		"%d points" % m.tourney_points)
	var builds_counted := int(m.mission_state["daily"]["progress"].get("builds", 0)) - builds_before
	_chk("the builds mission counted every one",
		builds_counted == CV.MAX_STAR * CV.BUILDINGS.size(),
		"%d of %d" % [builds_counted, CV.MAX_STAR * CV.BUILDINGS.size()])

	# A finished hut cannot be bought again, and a hut you cannot afford does
	# not quietly go up anyway.
	var before_coins: int = m.coins
	m._on_upgrade_requested(0)
	_chk("a five-star hut refuses another upgrade",
		m.buildings[0] == 5 and m.coins == before_coins)
	m.buildings = [0, 0, 0, 0, 0]
	m.coins = 0
	m._on_upgrade_requested(0)
	_chk("a hut you cannot afford does not go up",
		m.buildings[0] == 0 and m.coins == 0)
	m._close_popup(true)
	await get_tree().process_frame

# =============================================================================
#  6. the top-up dialog
# =============================================================================
#
# Two promises, swept across the whole range a real player can be short by:
# never a worse deal than the shelf, and never a giveaway.
func _t_topup() -> void:
	var never_worse := true
	var never_giveaway := true
	var exact_flag := true
	var bad := ""
	for lvl in [1, 5, 12, 20, 30, 60, 300]:
		m.island_level = lvl
		var rate: float = m._coin_rate()
		for shortfall in [1, 100, 5000, 43000, 250000, 3000000, 90000000, 1 << 40]:
			var offer: Dictionary = m._topup_for(shortfall)
			if offer.is_empty():
				continue
			var pack: Dictionary = offer["pack"]
			var grant: int = offer["coins"]
			var shelf: int = m._scaled(int(pack["coins"]))
			var ceiling := int(CV.price_usd(pack) * rate)
			if grant < shelf:
				never_worse = false
				bad += "island %d short %d -> %d < shelf %d; " % [lvl, shortfall, grant, shelf]
			if grant > maxi(ceiling, shelf):
				never_giveaway = false
				bad += "island %d short %d -> %d > ceiling %d; " % [lvl, shortfall, grant, ceiling]
			if bool(offer["exact"]) != (grant >= shortfall):
				exact_flag = false
	_chk("a top-up is never a worse deal than the shelf", never_worse, bad)
	_chk("and never a giveaway either", never_giveaway, bad)
	_chk("the 'covers it' flag tells the truth", exact_flag)

	m.island_level = 1
	var best_rate := 0.0
	for p in CV.COIN_PACKS:
		best_rate = maxf(best_rate, float(m._scaled(int(p["coins"]))) / CV.price_usd(p))
	_chk("the quoted rate is the best rate published anywhere on the shelf",
		is_equal_approx(m._coin_rate(), best_rate),
		"%.1f vs %.1f" % [m._coin_rate(), best_rate])
	_chk("nothing is offered for a shortfall of nothing", m._topup_for(0).is_empty())
	m.island_level = 1

# =============================================================================
#  7. missions
# =============================================================================

func _t_periods() -> void:
	for period in ["daily", "weekly", "monthly"]:
		var secs: int = m._period_reset_secs(period)
		_chk("the %s cycle has time left on it" % period, secs > 0, "%ds" % secs)
		var span := 86400
		if period == "weekly":
			span = 7 * 86400
		elif period == "monthly":
			span = 31 * 86400
		_chk("the %s reset is inside one %s" % [period, period], secs <= span,
			"%ds vs %ds" % [secs, span])
	# Formatting, which is what the player actually reads off the timer.
	_chk("a countdown over a day reads in days", m._countdown_text(90000).begins_with("1d"),
		m._countdown_text(90000))
	_chk("a countdown under a day reads as a clock", m._countdown_text(3661) == "01:01:01",
		m._countdown_text(3661))
	_chk("a countdown at zero is still a clock", m._countdown_text(0) == "00:00:00")

	# Coin targets ride the same curve as the payouts they measure, or a single
	# reel win clears the monthly.
	m.island_level = 20
	var scaled_target: int = m._mission_target({"id": "coins_won", "target": 250000})
	var flat_target: int = m._mission_target({"id": "spins", "target": 400})
	_chk("a coin target scales with the island", scaled_target > 250000, str(scaled_target))
	_chk("a count target does not", flat_target == 400, str(flat_target))
	m.island_level = 1

func _t_mission_claims() -> void:
	m.island_level = 1
	m.coins = 0
	m.spins = 0
	m.mission_state = {}
	m._ensure_missions()
	var total_coins := 0
	var total_spins := 0
	for period in ["daily", "weekly", "monthly"]:
		var st: Dictionary = m.mission_state[period]
		for mission in m.MISSION_DEFS[period]:
			st["progress"][mission["id"]] = m._mission_target(mission) * 10
			total_coins += m._mission_coins(mission)
			total_spins += int(mission.get("spins", 0))
		total_coins += m._bonus_coins(period)
		total_spins += int(m.MISSION_BONUS[period]["spins"])

	for period in ["daily", "weekly", "monthly"]:
		for mission in m.MISSION_DEFS[period]:
			_chk("  a finished %s mission reads as ready: %s" % [period, mission["id"]],
				m._mission_ready(period, mission), "")
			m._claim_mission(period, mission)
		_chk("  the %s all-clear bonus unlocks" % period, m._bonus_ready(period))
		m._claim_mission_bonus(period)
	_chk("claiming every mission paid exactly the advertised coins",
		m.coins == total_coins, "%d vs %d" % [m.coins, total_coins])
	_chk("and exactly the advertised spins", m.spins == total_spins,
		"%d vs %d" % [m.spins, total_spins])

	# The double-claim, which is the whole reason claims are recorded.
	var coins_after: int = m.coins
	var spins_after: int = m.spins
	for period in ["daily", "weekly", "monthly"]:
		for mission in m.MISSION_DEFS[period]:
			m._claim_mission(period, mission)
		m._claim_mission_bonus(period)
	_chk("nothing can be claimed twice",
		m.coins == coins_after and m.spins == spins_after,
		"+%d coins +%d spins" % [m.coins - coins_after, m.spins - spins_after])
	await get_tree().process_frame

# =============================================================================
#  8. the spin meter
# =============================================================================

func _t_regen() -> void:
	# Twelve short visits are worth exactly one long one. They used to be worth
	# nothing at all, twelve times over.
	m.spins = 0
	m._regen_accum = 0.0
	m._offline_spins_gained = 0
	for i in 720:
		m._credit_time_away(10.0)
	var many: int = m.spins
	m.spins = 0
	m._regen_accum = 0.0
	m._offline_spins_gained = 0
	m._credit_time_away(7200.0)
	var one: int = m.spins
	_chk("many short absences pay what one long one does", many == one,
		"%d vs %d" % [many, one])

	m.spins = 0
	m._regen_accum = 0.0
	m._credit_time_away(m.SPIN_REGEN_SECS * 4.0)
	_chk("four regen periods pay four times the regen amount",
		m.spins == 4 * m.SPIN_REGEN_AMOUNT, "%d spins" % m.spins)

	m.spins = 0
	m._regen_accum = 0.0
	m._credit_time_away(m.SPIN_REGEN_SECS * 10000.0)
	_chk("an absence longer than the meter cannot overfill it",
		m.spins == m.SPIN_CAP, "%d/%d" % [m.spins, m.SPIN_CAP])

	m.spins = m.SPIN_CAP
	m._regen_accum = 0.0
	m._credit_time_away(m.SPIN_REGEN_SECS * 50.0)
	_chk("a full meter banks nothing to pay out later",
		m.spins == m.SPIN_CAP and is_zero_approx(m._regen_accum),
		"spins=%d accum=%.1f" % [m.spins, m._regen_accum])

	m.spins = m.SPIN_CAP
	_chk("a full meter is already full", is_zero_approx(m._spins_full_at(1000.0)))
	m.spins = m.SPIN_CAP - 1
	m._regen_accum = 0.0
	_chk("one spin short is one period away",
		is_equal_approx(m._spins_full_at(0.0), m.SPIN_REGEN_SECS),
		"%.1f" % m._spins_full_at(0.0))
	m.spins = 0
	m._regen_accum = 0.0
	var need := int(ceil(float(m.SPIN_CAP) / float(m.SPIN_REGEN_AMOUNT)))
	_chk("an empty meter fills in the right number of periods",
		is_equal_approx(m._spins_full_at(0.0), float(need) * m.SPIN_REGEN_SECS),
		"%.1f" % m._spins_full_at(0.0))

	m.spins = 10
	m._credit_time_away(-500.0)
	_chk("negative time pays nothing", m.spins == 10, str(m.spins))

# =============================================================================
#  9. the reels
# =============================================================================
#
# Every payout the machine can make, asserted to the coin. The collections are
# emptied first so a card drop lands as a NEW card -- which pays stars and no
# coins -- and the wallet delta is therefore the reel prize and nothing else.
func _t_payouts() -> void:
	var cases := [
		# [reels, bet, expected island-1 coin gain]
		[["coin", "coin", "coin"], 1, 1000],
		[["coin", "coin", "coin"], 5, 5000],
		[["bag", "bag", "bag"], 1, 3000],
		[["bag", "bag", "bag"], 3, 9000],
		[["gem", "gem", "gem"], 1, 2000],
		[["gem", "gem", "gem"], 5, 10000],
		[["coin", "bag", "gem"], 1, 750],
		[["coin", "bag", "gem"], 5, 3750],
		[["coin", "coin", "bag"], 1, 600],
		[["bag", "bag", "gem"], 2, 2100],
		[["hammer", "steal", "shield"], 1, 0],
		[["bolt", "hammer", "steal"], 5, 0],
	]
	var bad := ""
	for lvl in [1, 7, 30]:
		m.island_level = lvl
		for case in cases:
			_fresh_cards()
			m.coins = 1000000
			m.spins = 50
			m._last_bet = int(case[1])
			var before: int = m.coins
			m._on_spin_finished(case[0])
			await get_tree().process_frame
			var want: int = m._scaled(int(case[2]))
			var got: int = m.coins - before
			if got != want:
				bad += "island %d %s x%d -> %d want %d; " % [lvl, str(case[0]), case[1], got, want]
	_chk("every reel payout pays exactly its published prize", bad == "", bad)
	m.island_level = 1

	# The triples that are not coins.
	_fresh_cards()
	m.spins = 0
	m.shields = 0
	m._last_bet = 3
	m._on_spin_finished(["bolt", "bolt", "bolt"])
	await get_tree().process_frame
	_chk("a bolt triple pays twelve spins a bet", m.spins == 12 * 3, "%d spins" % m.spins)

	m.shields = 0
	m.spins = 0
	m._last_bet = 2
	m._on_spin_finished(["shield", "shield", "shield"])
	await get_tree().create_timer(0.3).timeout
	_chk("a shield triple banks one shield a bet", m.shields == 2, "%d shields" % m.shields)

	# A losing spin is a losing spin.
	_fresh_cards()
	m.coins = 5000
	m._last_bet = 5
	m._on_spin_finished(["hammer", "bolt", "shield"])
	await get_tree().process_frame
	_chk("a spin that wins nothing takes nothing either", m.coins == 5000, "%d" % m.coins)

	# A malformed result must not be able to pay.
	m.coins = 5000
	m._on_spin_finished([])
	m._on_spin_finished(["coin"])
	_chk("a short reel result is survivable and pays nothing", m.coins == 5000)
	await get_tree().process_frame

func _t_roll_distribution() -> void:
	var n := 200000
	var triples := 0
	var by_symbol := {}
	for s in CV.SYMBOLS:
		by_symbol[s] = 0
	var off_strip := ""
	for i in n:
		var r: Array = m._roll()
		if r.size() != 3:
			off_strip = "roll returned %d reels" % r.size()
			break
		for s in r:
			if not by_symbol.has(s):
				off_strip = "unknown symbol %s" % str(s)
			else:
				by_symbol[s] = int(by_symbol[s]) + 1
		if r[0] == r[1] and r[1] == r[2]:
			triples += 1
	_chk("the reels only ever land on real symbols", off_strip == "", off_strip)
	# 30% forced triples, plus the ones a free draw lands on by chance:
	# 0.7 * (1/7)^2 = 1.43%.
	var want := 0.30 + 0.70 / 49.0
	var got := float(triples) / float(n)
	_chk("the triple rate matches the design", absf(got - want) < 0.006,
		"%.3f%% vs %.3f%%" % [got * 100.0, want * 100.0])
	var line := ""
	var spread_ok := true
	for s in CV.SYMBOLS:
		var share := float(by_symbol[s]) / float(n * 3)
		line += "%s %.1f%%  " % [s, share * 100.0]
		# Forced triples are weighted, free draws are flat, so no symbol should
		# be anywhere near absent or dominant.
		if share < 0.07 or share > 0.24:
			spread_ok = false
	_chk("no symbol is starved or dominant", spread_ok, line)

# =============================================================================
#  10. card drops
# =============================================================================

func _t_drop_rate() -> void:
	_fresh_cards()
	var n := 60000
	var before_cards := 0
	var drops := 0
	for i in n:
		var owned_before: int = _owned_total() + m._dupe_card_count()
		m._maybe_drop_card()
		if _owned_total() + m._dupe_card_count() > owned_before:
			drops += 1
		if i % 10000 == 0:
			await get_tree().process_frame
	var got := float(drops) / float(n)
	_chk("a spin drops a card at the published rate",
		absf(got - CV.CARD_DROP_CHANCE) < 0.008,
		"%.2f%% vs %.2f%%" % [got * 100.0, CV.CARD_DROP_CHANCE * 100.0])

func _owned_total() -> int:
	var n := 0
	for c in CV.COLLECTIONS:
		for v in m.col_owned.get(c["id"], []):
			if v:
				n += 1
	return n

# =============================================================================
#  11. collections
# =============================================================================

func _t_collections() -> void:
	_fresh_cards()
	m.stars = 0
	m.rank_stars = 0
	m.spins = 0

	# Fill every set by hand, counting what the rules say it is worth.
	# The cards are placed straight into col_owned rather than drawn, so they
	# never went through _earn_stars -- only the CLAIM bonuses below should
	# show up in the rank.
	var expect_rank := 0
	var expect_spins := 0
	for c in CV.COLLECTIONS:
		var items: Array = c["items"]
		for i in items.size():
			m.col_owned[c["id"]][i] = true
	var all_complete := true
	for c in CV.COLLECTIONS:
		if not m._collection_complete(c):
			all_complete = false
	_chk("every set reads as complete once filled", all_complete)

	# Claims. Each set pays its spins plus five stars a card.
	for c in CV.COLLECTIONS:
		expect_spins += int(c["reward_spins"])
		expect_rank += 5 * (c["items"] as Array).size()
		m._claim_collection(c)
		await get_tree().process_frame
	_chk("claiming every set paid the advertised spins", m.spins == expect_spins,
		"%d vs %d" % [m.spins, expect_spins])
	var spins_after: int = m.spins
	for c in CV.COLLECTIONS:
		m._claim_collection(c)
	_chk("a set cannot be claimed twice", m.spins == spins_after,
		"+%d" % (m.spins - spins_after))

	# The grand prize, which needs all of them.
	m._claim_mega()
	await get_tree().process_frame
	expect_spins += CV.COLLECTION_MEGA_SPINS
	expect_rank += 250
	_chk("the grand prize pays once every set is claimed",
		m.spins == expect_spins, "%d vs %d" % [m.spins, expect_spins])
	m._claim_mega()
	_chk("and cannot be claimed twice", m.spins == expect_spins)
	_chk("the rank banked every set bonus and the grand prize",
		m.rank_stars == expect_rank, "%d vs %d" % [m.rank_stars, expect_rank])

	# Melting. Pays the wallet, never the rank.
	_fresh_cards()
	m.stars = 0
	m.rank_stars = 500
	var expect_melt := 0
	for c in CV.COLLECTIONS:
		var items: Array = c["items"]
		for i in items.size():
			m.col_owned[c["id"]][i] = true
			for k in 3:
				m._add_dupe(c["id"], i)
			expect_melt += 3 * int(items[i][2])
	_chk("the pile is worth the sum of its cards",
		m._dupe_star_value() == expect_melt, "%d vs %d" % [m._dupe_star_value(), expect_melt])
	var rank_before: int = m.rank_stars
	var gained := 0
	for row in m._all_dupes():
		gained += m._melt_stack(row["set"]["id"], row["idx"], int(row["count"]))
	_chk("melting pays exactly what the pile was worth", gained == expect_melt and m.stars == expect_melt,
		"paid %d, stars %d, expected %d" % [gained, m.stars, expect_melt])
	_chk("melting leaves the pile empty", m._dupe_card_count() == 0)
	_chk("melting never touches the rank", m.rank_stars == rank_before,
		"%d -> %d" % [rank_before, m.rank_stars])
	_chk("melting a stack that is not there pays nothing",
		m._melt_stack(String(CV.COLLECTIONS[0]["id"]), 0, 99) == 0)
	_chk("melting a card index off the end is survivable",
		m._melt_stack(String(CV.COLLECTIONS[0]["id"]), 9999, 1) == 0)

	# The season ending.
	m.rank_stars = 1234
	m.col_deadline = m._now() - 10.0
	m._ensure_collections()
	_chk("an expired season clears the shelf", _owned_total() == 0)
	_chk("and dates the next one forward", m.col_deadline > m._now())
	_chk("and leaves the permanent rank alone", m.rank_stars == 1234, str(m.rank_stars))

	# Boxes. Stars in, cards out, never into overdraft.
	_fresh_cards()
	m.stars = 0
	for box in CV.CARD_BOXES:
		m._open_card_box(box)
	_chk("a box you cannot afford does not open", m.stars == 0, str(m.stars))
	# Every card already owned, so nothing drawn is a first copy and nothing
	# pays stars back -- the delta is then the price and only the price.
	for c in CV.COLLECTIONS:
		for i in (c["items"] as Array).size():
			m.col_owned[c["id"]][i] = true
	m.stars = 100
	var opened_at := int(CV.CARD_BOXES[0]["stars"])
	m._open_card_box(CV.CARD_BOXES[0])
	await get_tree().process_frame
	_chk("opening a box charges exactly its price", m.stars == 100 - opened_at,
		"100 -> %d (price %d)" % [m.stars, opened_at])
	m._close_popup(true)
	await get_tree().process_frame

# =============================================================================
#  12. the daily bonus and the free gift
# =============================================================================

func _t_daily_and_gift() -> void:
	_fresh_cards()
	m.island_level = 1
	m.coins = 0
	m.spins = 0
	m.daily_last = 0.0
	_chk("the daily bonus is ready after a day", m._daily_ready())
	m._open_daily()
	await get_tree().process_frame
	_press_claim()
	await get_tree().process_frame
	_chk("the daily bonus pays the advertised coins",
		m.coins == m._scaled(m.DAILY_BONUS_COINS),
		"%d vs %d" % [m.coins, m._scaled(m.DAILY_BONUS_COINS)])
	_chk("and the advertised spins", m.spins == m.DAILY_BONUS_SPINS, str(m.spins))
	var coins_after: int = m.coins
	var spins_after: int = m.spins
	# The double-tap through the fade, which is how this was taken twice.
	_press_claim()
	m._close_popup(true)
	m._open_daily()
	await get_tree().process_frame
	_press_claim()
	await get_tree().process_frame
	_chk("the daily bonus cannot be taken twice in a day",
		m.coins == coins_after and m.spins == spins_after,
		"+%d coins +%d spins" % [m.coins - coins_after, m.spins - spins_after])
	_chk("and reads as not ready afterwards", not m._daily_ready())
	m._close_popup(true)

	# The shop's free gift, same rules.
	_fresh_cards()
	m.coins = 0
	m.spins = 0
	m.shop_free_last = 0.0
	_chk("the free gift is ready after a day", m._shop_free_ready())
	m._claim_shop_gift()
	await get_tree().process_frame
	_chk("the free gift pays the advertised coins",
		m.coins == m._scaled(CV.SHOP_FREE_COINS),
		"%d vs %d" % [m.coins, m._scaled(CV.SHOP_FREE_COINS)])
	_chk("and the advertised spins", m.spins == CV.SHOP_FREE_SPINS, str(m.spins))
	var c2: int = m.coins
	m._claim_shop_gift()
	_chk("the free gift cannot be taken twice", m.coins == c2, "+%d" % (m.coins - c2))
	_chk("the countdown is a clock, not a negative number",
		m._shop_free_countdown_text().length() == 8, m._shop_free_countdown_text())
	m._close_popup(true)
	await get_tree().process_frame

# Presses the action button of whatever popup is open.
func _press_claim() -> void:
	if m._popup == null or not is_instance_valid(m._popup):
		return
	for b in _buttons_in(m._popup):
		if not b.disabled and b.text.to_upper().contains("CLAIM"):
			b.pressed.emit()
			return

func _buttons_in(n: Node) -> Array:
	var out := []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_buttons_in(c))
	return out

# =============================================================================
#  13. the piggy bank
# =============================================================================

func _t_piggy() -> void:
	m.island_level = 1
	m.piggy_coins = 0
	m.piggy_promised = 0
	var cap: int = m._scaled(CV.PIGGY_CAP)
	_chk("an empty piggy reads as empty", is_zero_approx(m._piggy_frac()))
	for i in 10000:
		m._piggy_add(CV.PIGGY_PER_SPIN)
	_chk("the piggy stops at its cap", m.piggy_coins == cap, "%d vs %d" % [m.piggy_coins, cap])
	_chk("a full piggy reads as full", m._piggy_full() and is_equal_approx(m._piggy_frac(), 1.0))
	m._piggy_add(999999)
	_chk("a full piggy takes nothing more", m.piggy_coins == cap)

	m.coins = 0
	m.piggy_promised = 0
	m._break_piggy()
	await get_tree().process_frame
	_chk("breaking it pays out everything inside", m.coins == cap, "%d vs %d" % [m.coins, cap])
	_chk("and leaves it empty", m.piggy_coins == 0)
	m.coins = 0
	m._break_piggy()
	_chk("breaking an empty piggy pays nothing", m.coins == 0, str(m.coins))

	# The one that matters: a piggy emptied between Pay and grant still pays
	# what was promised, and never both.
	m.piggy_coins = 0
	m.piggy_promised = 12345
	m.coins = 0
	m._break_piggy()
	_chk("a piggy emptied mid-purchase pays the promise", m.coins == 12345, str(m.coins))
	m.coins = 0
	m._break_piggy()
	_chk("and the promise is spent, not standing", m.coins == 0, str(m.coins))

	m.piggy_coins = 5000
	m.piggy_promised = 20000
	m.coins = 0
	m._break_piggy()
	_chk("a piggy pays the larger of what it holds and what it promised",
		m.coins == 20000, str(m.coins))

	m.piggy_coins = 30000
	m.piggy_promised = 1000
	m.coins = 0
	m._break_piggy()
	_chk("and never pays less than it is holding", m.coins == 30000, str(m.coins))
	await get_tree().process_frame

# =============================================================================
#  14. the timed offer
# =============================================================================

func _t_offers() -> void:
	m.offer_id = ""
	m.offer_until = 0.0
	m.offer_next = 0.0
	m._offer_tick()
	_chk("an offer comes up when the dark stretch is over", m.offer_id != "", m.offer_id)
	_chk("and it is one the build knows", not CV.pack_by_id(m.offer_id).is_empty())
	_chk("and it is live now", not m._active_offer().is_empty())
	var ends: float = m.offer_until
	_chk("it runs for the advertised two hours",
		absf(ends - m._now() - CV.OFFER_DURATION) < 2.0,
		"%.0fs" % (ends - m._now()))
	_chk("the countdown reads as a clock", m._offer_countdown_text() != "", m._offer_countdown_text())

	# Run it out.
	m.offer_until = m._now() - 1.0
	m._offer_tick()
	_chk("an expired offer goes off the shelf", m.offer_id == "")
	_chk("and nothing is live in the dark stretch", m._active_offer().is_empty())
	_chk("and the next one is a cooldown away",
		absf(m.offer_next - m._now() - CV.OFFER_COOLDOWN) < 2.0,
		"%.0fs" % (m.offer_next - m._now()))
	m._offer_tick()
	_chk("the dark stretch does not immediately re-roll", m.offer_id == "")

	# Buying the live offer ends it, rather than advertising at somebody who
	# just paid.
	m.offer_next = 0.0
	m._offer_tick()
	var live: String = m.offer_id
	if live != "":
		m._grant_pack(CV.pack_by_id(live))
		await get_tree().process_frame
		_chk("buying the live offer takes it down", m.offer_id == "", m.offer_id)
	m._close_popup(true)
	await get_tree().process_frame

# =============================================================================
#  15. purchases
# =============================================================================

func _t_purchases() -> void:
	_fresh_cards()
	m.island_level = 3
	var all := [CV.STARTER_PACK]
	for group in [CV.CHEST_PACKS, CV.SPIN_PACKS, CV.COIN_PACKS, CV.BUNDLE_PACKS, CV.TIMED_OFFERS]:
		for p in group:
			all.append(p)

	# A pack containing cards can also pay a small coin refund for any duplicate
	# it draws, so the coin figure is exact only for the packs carrying no
	# cards. For the rest the rule is that it is never LESS than the tile says.
	var bad := ""
	for pack in all:
		_fresh_cards()
		m.coins = 0
		m.spins = 0
		m.shields = 0
		m.purchased_ids = []
		var want_coins: int = m._scaled(int(pack.get("coins", 0)))
		var want_spins := int(pack.get("spins", 0))
		var has_cards := int(pack.get("cards", 0)) > 0
		m._grant_pack(pack)
		await get_tree().process_frame
		if has_cards:
			if m.coins < want_coins:
				bad += "%s coins %d UNDER %d; " % [pack["id"], m.coins, want_coins]
		elif m.coins != want_coins:
			bad += "%s coins %d want %d; " % [pack["id"], m.coins, want_coins]
		if m.spins != want_spins:
			bad += "%s spins %d want %d; " % [pack["id"], m.spins, want_spins]
		m._close_popup(true)
	_chk("every pack grants at least what its tile says", bad == "", bad)

	# The starter is a once-only, and the store has to remember that.
	m.purchased_ids = []
	m._grant_pack(CV.STARTER_PACK)
	await get_tree().process_frame
	_chk("a once-only pack records itself as bought",
		m.purchased_ids.has(CV.STARTER_PACK["id"]), str(m.purchased_ids))
	m._close_popup(true)

	# A top-up settles through an ordinary coin-pack id and must not be scaled
	# a second time on the way in.
	m.island_level = 12
	m.coins = 0
	var exact := 4321000
	m.topup_pending = {"id": "coins_m", "coins": exact}
	m._on_purchase_ok(IAP.PREFIX + "coins_m")
	await get_tree().process_frame
	_chk("a top-up grants the exact figure it quoted, unscaled",
		m.coins == exact, "%d vs %d" % [m.coins, exact])
	_chk("and the pending record is spent", m.topup_pending.is_empty())
	m.coins = 0
	m._on_purchase_ok(IAP.PREFIX + "coins_m")
	await get_tree().process_frame
	_chk("a replayed top-up transaction pays the shelf, not the quote again",
		m.coins == m._scaled(90000), "%d" % m.coins)
	m._close_popup(true)

	# The ids the build cannot honour.
	m.coins = 777
	m._on_purchase_ok(IAP.PREFIX + "no_such_pack")
	m._on_purchase_ok("")
	m._on_purchase_ok("com.someone.else.thing")
	_chk("an unknown product id is survivable and grants nothing", m.coins == 777, str(m.coins))

	# A cancel and a failure must not leave a top-up armed behind them.
	m.topup_pending = {"id": "coins_m", "coins": 999}
	m._on_purchase_cancel("x")
	_chk("cancelling disarms a pending top-up", m.topup_pending.is_empty())
	m.topup_pending = {"id": "coins_m", "coins": 999}
	m._on_purchase_fail("x", "nope")
	_chk("a failure disarms it too", m.topup_pending.is_empty())
	m._close_popup(true)
	m.island_level = 1
	await get_tree().process_frame

# =============================================================================
#  16. shields
# =============================================================================

func _t_shields() -> void:
	m.shields = 0
	m.spins = 0
	m._grant_shields(2, Vector2.ZERO)
	_chk("shields bank up to the cap", m.shields == 2, str(m.shields))
	m._grant_shields(5, Vector2.ZERO)
	await get_tree().create_timer(0.2).timeout
	_chk("the cap holds", m.shields == m.SHIELD_CAP, "%d/%d" % [m.shields, m.SHIELD_CAP])
	_chk("and the overflow comes back as spins, not nothing", m.spins == 4,
		"%d spins" % m.spins)
	m.shields = m.SHIELD_CAP
	m.spins = 0
	m._grant_shields(3, Vector2.ZERO)
	await get_tree().create_timer(0.2).timeout
	_chk("a full bucket turns the whole grant into spins", m.spins == 3, str(m.spins))
	m.spins = 0
	m._grant_shields(0, Vector2.ZERO)
	m._grant_shields(-5, Vector2.ZERO)
	_chk("a grant of nothing does nothing", m.spins == 0 and m.shields == m.SHIELD_CAP)
	await get_tree().create_timer(1.0).timeout

# =============================================================================
#  17. the tournament
# =============================================================================

func _t_tourney() -> void:
	m.tourney_id = m._tourney_now_id()
	m.tourney_points = 0
	m.tourney_claimed = []
	m._tourney_add("steal", 1)
	_chk("a steal scores its published points", m.tourney_points == m.TP_STEAL, str(m.tourney_points))
	m.tourney_points = 0
	m._tourney_add("steal", 5)
	_chk("and five times that at bet x5", m.tourney_points == m.TP_STEAL * 5, str(m.tourney_points))
	m.tourney_points = 0
	m._tourney_add("attack", 3)
	_chk("an attack scores per bet too", m.tourney_points == m.TP_ATTACK * 3, str(m.tourney_points))
	m.tourney_points = 0
	m._tourney_add("build", 5)
	_chk("a build is flat, whatever the bet", m.tourney_points == m.TP_BUILD, str(m.tourney_points))
	m.tourney_points = 0
	m._tourney_add("nonsense", 5)
	_chk("an action that is not scored scores nothing", m.tourney_points == 0)

	# Claims.
	m.tourney_points = 999999
	m.tourney_claimed = []
	m.spins = 0
	var want_spins := 0
	for t in m.TOURNEY_TIERS:
		want_spins += int(t["spins"])
	for i in m.TOURNEY_TIERS.size():
		m._tourney_claim(i)
		await get_tree().process_frame
	_chk("every rung pays the spins it advertises", m.spins == want_spins,
		"%d vs %d" % [m.spins, want_spins])
	var after: int = m.spins
	for i in m.TOURNEY_TIERS.size():
		m._tourney_claim(i)
	_chk("a claimed rung stays claimed", m.spins == after, "+%d" % (m.spins - after))

	# A rung you have not reached is not a rung.
	m.tourney_points = 0
	m.tourney_claimed = []
	m.spins = 0
	for i in m.TOURNEY_TIERS.size():
		m._tourney_claim(i)
	_chk("an unearned rung pays nothing", m.spins == 0, str(m.spins))
	_chk("nothing is claimable at zero points", not m._tourney_claimable())
	m.tourney_points = int(m.TOURNEY_TIERS[0]["at"])
	_chk("the first rung arms exactly at its threshold", m._tourney_claimable())

	# An index off the end of the table.
	m.tourney_points = 999999
	m.tourney_claimed = []
	m.spins = 0
	m._tourney_claim(-1)
	m._tourney_claim(99)
	_chk("a rung index off the table is survivable", m.spins == 0 and m.tourney_claimed.is_empty())

	# The rollover, and the invariant that must never break.
	m.rank_stars = 4242
	m.tourney_points = 5000
	m.tourney_claimed = [0, 1]
	m.tourney_id = m._tourney_now_id() - 1
	m._tourney_sync()
	_chk("a new tournament zeroes the score", m.tourney_points == 0, str(m.tourney_points))
	_chk("and un-earns the rungs", m.tourney_claimed.is_empty())
	_chk("and never touches the permanent rank", m.rank_stars == 4242, str(m.rank_stars))
	_chk("the cycle id is the same integer on every device",
		m._tourney_now_id() == int(floor(Time.get_unix_time_from_system() / m.TOURNEY_SECONDS)))
	var left: float = m._tourney_seconds_left()
	_chk("the clock left is inside one cycle", left > 0.0 and left <= m.TOURNEY_SECONDS,
		"%.0fs" % left)
	m._close_popup(true)
	await get_tree().process_frame

# =============================================================================
#  18. a hostile save file
# =============================================================================

func _t_hostile_save() -> void:
	var path: String = m.SAVE_PATH
	var hostile := {
		"coins": -999999,
		"spins": -50,
		"stars": -10,
		"rank_stars": -10,
		"shields": 9999,
		"island_level": -7,
		"buildings": [99, -3, "x", null, 2, 7, 7, 7],
		# Stamped for the tournament that is actually running: an old id is a
		# legitimate reason for the loader to clear the rungs, and would hide
		# the coercion this is testing.
		"tourney_id": m._tourney_now_id(),
		"tourney_points": 999999999,
		"tourney_claimed": [-3, 99, 1, 1, "x", 2.5],
		"purchased": ["starter", {"id": "hack"}, 42, null],
		"topup_pending": {"id": "coins_3xl", "coins": 999999999999},
		"piggy": -5000,
		"piggy_promised": -5000,
		"col_owned": "not a dictionary",
		"notif_log": "not an array",
		"daily_last": 1e18,
		"shop_free_last": 1e18,
		"offer_until": 1e18,
		"offer_next": 1e18,
		"col_deadline": 1e18,
		"clock_hw": -1.0,
		"ts": 0.0,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(hostile))
	f.close()
	m._load_game()
	m._sanitize_clock()
	await get_tree().process_frame

	_chk("a negative wallet loads as zero or better", m.coins >= 0, str(m.coins))
	_chk("a negative meter loads as zero or better", m.spins >= 0, str(m.spins))
	_chk("shields load inside the cap", m.shields >= 0 and m.shields <= m.SHIELD_CAP, str(m.shields))
	_chk("the island loads inside its range",
		m.island_level >= 1 and m.island_level <= m.MAX_ISLAND, str(m.island_level))

	var b_ok: bool = m.buildings.size() == CV.BUILDINGS.size()
	for b in m.buildings:
		if typeof(b) != TYPE_INT or int(b) < 0 or int(b) > CV.MAX_STAR:
			b_ok = false
	_chk("the island's huts load as five real star levels", b_ok, str(m.buildings))

	# The trap that was an exploit: JSON has one number type, so an int array
	# comes back as floats and Array.has(int) stops matching.
	var t_ok := true
	for v in m.tourney_claimed:
		if typeof(v) != TYPE_INT or int(v) < 0 or int(v) >= m.TOURNEY_TIERS.size():
			t_ok = false
	var seen_rungs := {}
	var no_dupes := true
	for v in m.tourney_claimed:
		if seen_rungs.has(v):
			no_dupes = false
		seen_rungs[v] = true
	_chk("hand-edited tournament rungs load as real, unique indexes",
		t_ok and no_dupes, str(m.tourney_claimed))

	var p_ok := true
	for id in m.purchased_ids:
		if typeof(id) != TYPE_STRING:
			p_ok = false
	_chk("the purchase list loads as strings and nothing else", p_ok, str(m.purchased_ids))

	# A save must not be able to name an arbitrary payout.
	var quoted := int(m.topup_pending.get("coins", 0))
	_chk("an injected top-up cannot quote an arbitrary fortune",
		m.topup_pending.is_empty() or quoted <= 1 << 40,
		"quoted %d" % quoted)

	_chk("a negative piggy loads as zero or better",
		m.piggy_coins >= 0 and m.piggy_promised >= 0,
		"%d / %d" % [m.piggy_coins, m.piggy_promised])
	_chk("a garbage collection shelf is replaced with a real one",
		typeof(m.col_owned) == TYPE_DICTIONARY and m.col_owned.size() > 0)
	_chk("a garbage alert log is replaced with a real one",
		typeof(m.notif_log) == TYPE_ARRAY)

	# Stamps a year in the future must not lock the bonuses out forever.
	var now: float = m._now()
	_chk("a future daily stamp is pulled back", m.daily_last <= now + 1.0, str(m.daily_last))
	_chk("a future gift stamp is pulled back", m.shop_free_last <= now + 1.0)
	_chk("a future offer deadline is pulled back",
		m.offer_until <= now + CV.OFFER_DURATION + 1.0)
	_chk("a future season deadline is pulled back",
		m.col_deadline <= now + CV.COLLECTION_SEASON_DAYS * 86400.0 + 1.0)

	# And the game still runs on it.
	m.spins = 50
	m._last_bet = 1
	for i in 50:
		m._on_spin_finished(m._roll())
		if m._raiding():
			await _release_raid()
	await _release_raid()
	await get_tree().process_frame
	_chk("the game plays on after loading a hostile save",
		m.coins >= 0 and m.spins >= 0 and m.stars >= 0)

	# Total garbage on disk, and the game still opens.
	for junk in ["", "null", "[]", "{}", "not json at all", '{"coins":', '{"coins": "many"}']:
		var g := FileAccess.open(path, FileAccess.WRITE)
		g.store_string(junk)
		g.close()
		m._load_game()
	_chk("no shape of garbage on disk stops the game opening",
		m.coins >= 0 and m.spins >= 0 and m.buildings.size() == CV.BUILDINGS.size())
	await get_tree().process_frame

# =============================================================================
#  19. the clock
# =============================================================================

func _t_clock() -> void:
	var now: float = m._now()
	m.daily_last = now + 86400.0 * 365.0
	m.shop_free_last = now + 86400.0 * 365.0
	m.offer_until = now + 86400.0 * 365.0
	m.offer_next = now + 86400.0 * 365.0
	m.col_deadline = now + 86400.0 * 365.0
	m._sanitize_clock()
	_chk("a clock wound forward and back cannot black out the daily", m.daily_last <= now + 1.0)
	_chk("nor the free gift", m.shop_free_last <= now + 1.0)
	_chk("nor the offer rotation", m.offer_next <= now + CV.OFFER_COOLDOWN + 1.0)
	_chk("nor the card season", m.col_deadline <= now + CV.COLLECTION_SEASON_DAYS * 86400.0 + 1.0)

	# The high-water mark is what stops the same trick working twice.
	var hw: float = m.clock_hw
	_chk("the clock keeps a high-water mark", hw > 0.0, "%.0f" % hw)
	_chk("and _now never reads below it", m._now() >= hw - 1.0)

	# An alert log stamped in the future.
	m.notif_log = [{"type": "spins", "text": "x", "emoji": "!", "ts": now + 1e6, "read": false}]
	m._sanitize_clock()
	_chk("an alert stamped in the future is pulled back",
		float(m.notif_log[0]["ts"]) <= now + 1.0)

# =============================================================================
#  20. raids
# =============================================================================

func _t_raids() -> void:
	await _release_raid()
	m._close_popup(true)
	m.island_level = 4
	m.coins = 1000000
	m.buildings = [3, 3, 3, 3, 3]
	m.shields = 0
	m._stock_rivals()
	_chk("the rival pool is stocked", m.npcs.size() > 0, "%d rivals" % m.npcs.size())

	var sane := true
	for n in m.npcs:
		if int(n.get("coins", 0)) <= 0 or int(n.get("coins", 0)) > m.NPC_COIN_CAP:
			sane = false
		var bs: Array = n.get("buildings", [])
		if bs.size() != CV.BUILDINGS.size():
			sane = false
		for b in bs:
			if int(b) < 0 or int(b) > CV.MAX_STAR:
				sane = false
		var isl := int(n.get("island", 0))
		if isl < 1 or isl > CV.ISLANDS.size():
			sane = false
	_chk("every rival is a playable island", sane)

	var stars_sane := true
	for n in m.npcs:
		var s: int = m._npc_stars(n)
		if s < 0 or s > 100000:
			stars_sane = false
	_chk("a rival's standing is a real number", stars_sane)

	# The stake scales with the island and the bet, and nothing else.
	var npc := {"coins": 5000, "buildings": [3, 3, 3, 3, 3], "island": 4}
	m.island_level = 1
	m._last_bet = 1
	var base: int = m._raid_stake(npc)
	m._last_bet = 5
	_chk("a x5 raid is worth five times a x1 raid", m._raid_stake(npc) == base * 5,
		"%d vs %d" % [m._raid_stake(npc), base * 5])
	m._last_bet = 1
	m.island_level = 10
	_chk("and the same raid is worth more on a later island",
		m._raid_stake(npc) > base, "%d vs %d" % [m._raid_stake(npc), base])
	m.island_level = 4

	# The offline plan: rolled awake, applied on the way back.
	m.shields = 0
	m.buildings = [3, 3, 3, 3, 3]
	m.coins = 1000000
	m._preroll_raids(m._now() - 100000.0)
	_chk("going to the background rolls a plan", m.pending_raids.size() > 0,
		"%d events" % m.pending_raids.size())
	var plan_ok := true
	for ev in m.pending_raids:
		var kind := String(ev.get("kind", ""))
		if not ["steal", "smash", "blocked"].has(kind):
			plan_ok = false
		if not ["steal", "attack"].has(String(ev.get("type", ""))):
			plan_ok = false
		if String(ev.get("text", "")) == "":
			plan_ok = false
	_chk("every planned raid has a kind, a category and words to say", plan_ok)

	var coins_before: int = m.coins
	m._offline_raids()
	await get_tree().process_frame
	_chk("the plan is applied and cleared", m.pending_raids.is_empty())
	_chk("and never drives the island negative",
		m.coins >= 0 and m.buildings.min() >= 0,
		"coins=%d %s" % [m.coins, str(m.buildings)])
	_chk("and never pays the player for being robbed", m.coins <= coins_before,
		"%d -> %d" % [coins_before, m.coins])

	# A shield is what makes the plan miss.
	m.shields = m.SHIELD_CAP
	m.buildings = [5, 5, 5, 5, 5]
	m.coins = 1000000
	m._preroll_raids(m._now() - 100000.0)
	var all_blocked := true
	for ev in m.pending_raids:
		if String(ev.get("kind", "")) != "blocked":
			all_blocked = false
	_chk("a stocked shield bucket blocks the whole plan", all_blocked,
		str(m.pending_raids.size()))
	var shields_before: int = m.shields
	var coins_held: int = m.coins
	var blocked: int = m.pending_raids.size()
	m._offline_raids()
	await get_tree().process_frame
	_chk("a blocked raid spends a shield and takes nothing else",
		m.coins == coins_held and m.buildings == [5, 5, 5, 5, 5]
			and m.shields == maxi(0, shields_before - blocked),
		"%d blocked, shields %d -> %d, coins %d" % [
			blocked, shields_before, m.shields, m.coins])

	# A raid landing behind an overlay waits rather than robbing an invisible
	# player.
	m.pending_raids = [{"at": 0.0, "kind": "steal", "coins": 100, "npc": "x",
		"type": "steal", "text": "t", "emoji": "!"}]
	m.coins = 50000
	var vb: VBoxContainer = m._open_popup("blocker")
	m._offline_raids()
	_chk("a raid does not land behind a modal",
		m.pending_raids.size() == 1 and m.coins == 50000, str(m.coins))
	m._close_popup(true)
	await get_tree().process_frame
	m._offline_raids()
	await get_tree().process_frame
	_chk("and lands as soon as the screen is the player's again",
		m.pending_raids.is_empty() and m.coins == 49900, str(m.coins))

	# A steal quoted against a wallet that has since emptied.
	m.coins = 10
	m.pending_raids = [{"at": 0.0, "kind": "steal", "coins": 999999999, "npc": "x",
		"type": "steal", "text": "t", "emoji": "!"}]
	m._offline_raids()
	await get_tree().process_frame
	_chk("a raid cannot take more than the vault holds", m.coins == 0, str(m.coins))

	# A live steal, all the way through.
	m._close_popup(true)
	m.coins = 100000
	m._stock_rivals()
	m._pick_next_target()
	m._last_bet = 2
	m.tourney_points = 0
	m.tourney_id = m._tourney_now_id()
	var before: int = m.coins
	m._start_visit("steal")
	var waited := 0.0
	while m._raiding() and waited < 20.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
		if m._match != null and m._match.has_method("_lock_in"):
			m._match._live = true
			m._match._lock_in()
			m._match._close()
		elif m._visit != null and m._visit._stage != null:
			for c in m._visit._stage.get_children():
				if c is Button and not (c as Button).disabled:
					(c as Button).pressed.emit()
					break
	_chk("a steal finishes and hands the game back", not m._raiding(),
		"waited %.1fs" % waited)
	_chk("a steal only ever pays the player", m.coins >= before,
		"%d -> %d" % [before, m.coins])
	_chk("and scores the tournament for it", m.tourney_points > 0, str(m.tourney_points))

	# A second raid must not be able to start on top of the first.
	m._start_visit("attack")
	var second_ok: bool = true
	if m._raiding():
		m._start_visit("steal")
		second_ok = true
	var waited2 := 0.0
	while m._raiding() and waited2 < 20.0:
		await get_tree().create_timer(0.2).timeout
		waited2 += 0.2
		if m._match != null and m._match.has_method("_lock_in"):
			m._match._live = true
			m._match._lock_in()
			m._match._close()
		elif m._visit != null and m._visit._stage != null:
			for c in m._visit._stage.get_children():
				if c is Button and not (c as Button).disabled:
					(c as Button).pressed.emit()
					break
	_chk("a second raid on top of the first does not orphan an overlay",
		not m._raiding(), "waited %.1fs" % waited2)
	m._close_popup(true)
	await get_tree().process_frame

# =============================================================================
#  21. alerts
# =============================================================================

func _t_alerts() -> void:
	m.notif_enabled = true
	m.notif_log = []
	for i in 100:
		m._notify("spins", "message %d" % i, "!", false)
	_chk("the alert log is capped", m.notif_log.size() == m.NOTIF_LOG_MAX,
		"%d entries" % m.notif_log.size())
	_chk("and keeps the newest", String(m.notif_log[0]["text"]) == "message 99",
		String(m.notif_log[0]["text"]))
	_chk("the unread count matches the log", m._unread_count() == m.NOTIF_LOG_MAX,
		str(m._unread_count()))

	# Every type can be switched off, and off means off.
	for t in m.notif_types.keys():
		m.notif_types[t] = false
	m.notif_log = []
	var sent := false
	for t in m.notif_types.keys():
		if m._notify(t, "x", "!", false):
			sent = true
	_chk("a muted alert type sends nothing", not sent and m.notif_log.is_empty())
	for t in m.notif_types.keys():
		m.notif_types[t] = true
	m.notif_enabled = false
	_chk("the master switch overrides the lot", not m._notify("spins", "x", "!", false))
	m.notif_enabled = true

	# The plan handed to iOS has to be honourable: every row needs a time, a
	# title and a body, or the player taps a notification about nothing.
	m.spins = 0
	m._regen_accum = 0.0
	m.shop_free_last = m._now()
	m.offer_id = String(CV.TIMED_OFFERS[0]["id"])
	m.offer_until = m._now() + CV.OFFER_DURATION
	m.col_deadline = m._now() + 86400.0
	m.pending_raids = [{"at": m._now() + 60.0, "kind": "steal", "coins": 5, "npc": "x",
		"type": "steal", "text": "they came for your vault", "emoji": "!"}]
	var plan: Array = m._alert_plan(m._now())
	_chk("the plan has rows in it", plan.size() >= 4, "%d rows" % plan.size())
	var rows_ok := true
	var ids := {}
	var dupe_ids := ""
	for row in plan:
		if String(row.get("title", "")) == "" or String(row.get("body", "")) == "":
			rows_ok = false
		if not row.has("at"):
			rows_ok = false
		var id := String(row.get("id", ""))
		if ids.has(id):
			dupe_ids += id + " "
		ids[id] = true
	_chk("every planned alert has a time, a title and a body", rows_ok)
	_chk("and a unique id, so iOS replaces rather than stacks them",
		dupe_ids == "", dupe_ids)

	# Switching a category off has to take it out of the plan too, not just out
	# of the in-game toast.
	m.notif_types["gift"] = false
	var plan2: Array = m._alert_plan(m._now())
	var has_gift := false
	for row in plan2:
		if String(row.get("id", "")) == "free_gift":
			has_gift = true
	_chk("a muted category leaves the scheduled plan too", not has_gift)
	m.notif_types["gift"] = true
	m.notif_enabled = false
	_chk("the master switch empties the plan", m._alert_plan(m._now()).is_empty())
	m.notif_enabled = true
