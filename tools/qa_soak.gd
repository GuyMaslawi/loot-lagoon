extends Node
# Temporary QA harness -- drives the real game headlessly. Not shipped.

var m: Control

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	var fails := 0
	fails += _t_economy()
	fails += await _t_deep_island()
	fails += await _t_save_roundtrip()
	fails += await _t_corrupt_save()
	fails += await _t_tourney_claims_persist()
	fails += _t_clock_rollback()
	fails += await _t_empty_island_attack()
	fails += await _t_spin_soak(25000)
	print("QA: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _chk(name: String, ok: bool, detail := "") -> int:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])
	return 0 if ok else 1

# --- the curve cannot walk off int64 ----------------------------------------
func _t_economy() -> int:
	print("economy curve")
	var bad := 0
	for lvl in [1, 15, 30, 45, 120, 4000]:
		var c := CV.scaled(9000, lvl)
		var s := CV.scaled(3000 * 5, lvl)
		if c <= 0 or s <= 0 or c > 1e17 or s > 1e17:
			bad += 1
			print("    level %d -> star %d jackpot %d" % [lvl, c, s])
	return _chk("scaled() stays positive and bounded at every level", bad == 0)

# --- an island number past the designed thirty --------------------------------
func _t_deep_island() -> int:
	print("progress past the last island")
	m.island_level = 64
	m.coins = 1234
	m.buildings = [5, 5, 5, 5, 5]
	m._flush_save()
	m.island_level = 1
	m._load_game()
	var kept: bool = m.island_level == 64
	var costs: Array = m._star_costs()
	var sane := true
	for c in costs:
		if int(c) <= 0:
			sane = false
	var f := 0
	f += _chk("a level past the last island survives a reload", kept, "got %d" % m.island_level)
	f += _chk("star costs stay positive out there", sane, str(costs))
	f += _chk("the theme still resolves", CV.island_theme(64)["name"] != "")
	await get_tree().process_frame
	return f

# --- what goes in comes out --------------------------------------------------
func _t_save_roundtrip() -> int:
	print("save / load round trip")
	m.coins = 123456789
	m.spins = 41
	m.stars = 777
	m.rank_stars = 999
	m.shields = 2
	m.island_level = 7
	m.buildings = [1, 2, 3, 4, 5]
	m.piggy_coins = 4242
	m.piggy_promised = 1111
	m._flush_save()
	var before := {"c": m.coins, "s": m.stars, "r": m.rank_stars, "b": m.buildings.duplicate(),
		"i": m.island_level, "p": m.piggy_coins, "pp": m.piggy_promised}
	m.coins = 0; m.stars = 0; m.rank_stars = 0; m.buildings = [0,0,0,0,0]
	m.island_level = 1; m.piggy_coins = 0; m.piggy_promised = 0
	m._load_game()
	await get_tree().process_frame
	var ok: bool = m.coins == before["c"] and m.stars == before["s"] and m.rank_stars == before["r"] \
		and m.buildings == before["b"] and m.island_level == before["i"] \
		and m.piggy_coins == before["p"] and m.piggy_promised == before["pp"]
	return _chk("every counter survives a write/read cycle", ok,
		"" if ok else "got coins=%d stars=%d rank=%d island=%d piggy=%d/%d %s" % [m.coins, m.stars, m.rank_stars, m.island_level, m.piggy_coins, m.piggy_promised, str(m.buildings)])

# --- a torn file must not wipe the island ------------------------------------
func _t_corrupt_save() -> int:
	print("corrupt save recovery")
	m.coins = 555000
	m._flush_save()
	m.coins = 556000
	m._flush_save()          # the first write is now the .bak
	var f := FileAccess.open(m.SAVE_PATH, FileAccess.WRITE)
	f.store_string('{"coins": 12345, "spins')   # killed mid-write
	f.close()
	m.coins = 0
	m._load_game()
	var ok: bool = m.coins >= 555000
	return _chk("a half-written save falls back to the backup", ok, "coins=%d" % m.coins)

# --- a claimed tournament rung must stay claimed ------------------------------
#
# The reward track is the only place in the save that stores a list of integers,
# and JSON has one number type: [0, 1] goes out as ints and comes back as
# floats, which Array.has(int) does not match. Every rung therefore re-armed on
# every launch, and the top one -- 300 spins and 3 collection cards -- could be
# taken once per app start, for ever. Written as a round trip rather than a unit
# test of the loader because the bug lived entirely in the crossing.
#
# THIS TEST WENT STALE ON 2026-09-02 AND WAS RED FOR TWO DAYS BEFORE ANYBODY
# LOOKED. The repeating reward track landed that day, and claiming the LAST rung
# now deliberately empties `tourney_claimed` and opens the next track. The test
# still asserted the pre-lap invariant -- all four rungs claimed and nothing
# payable afterwards -- so it failed on correct behaviour and reported it as the
# float bug above, which is a genuinely dangerous thing for a harness to say.
#
# Rewritten to test what the float bug was actually about: WITHIN ONE TRACK, a
# rung that has been taken cannot be taken again after a reload. The lap roll is
# tested as the separate thing it is.
func _t_tourney_claims_persist() -> int:
	print("tournament rungs survive a restart")
	var bad := 0
	var last: int = m.TOURNEY_TIERS.size() - 1
	m.tourney_id = m._tourney_now_id()
	m.tourney_points = 99999          # every rung earned
	m.tourney_claimed = []
	m.tourney_lap = 0
	m.tourney_lap_base = 0

	# Every rung BUT the last, which is the case the float bug broke.
	for tier in range(last):
		m._tourney_claim(tier)
	var spins_after_claiming: int = m.spins
	bad += 0 if m.tourney_claimed.size() == last else 1

	m._flush_save()
	m._load_game()
	await get_tree().process_frame
	# They came back as ints, so has() still matches and none of them re-arms.
	var before_spins: int = m.spins
	for tier in range(last):
		m._tourney_claim(tier)
	var paid_twice: int = m.spins - before_spins
	bad += 0 if paid_twice == 0 else 1
	# The last rung is untouched, so the track is still legitimately claimable.
	bad += 0 if m._tourney_claimable() else 1

	# --- the lap roll, which is a feature and not a leak ---
	var lap_before: int = m.tourney_lap
	var base_before: int = m.tourney_lap_base
	m._tourney_claim(last)
	bad += 0 if m.tourney_lap == lap_before + 1 else 1
	bad += 0 if m.tourney_claimed.is_empty() else 1
	# The base moves to the THRESHOLD, not to the score, so points earned past
	# the top while the reward sat unclaimed carry into the new track.
	bad += 0 if m.tourney_lap_base > base_before else 1
	# ...and it survives the same round trip.
	m._flush_save()
	m._load_game()
	await get_tree().process_frame
	bad += 0 if m.tourney_lap == lap_before + 1 and m.tourney_claimed.is_empty() else 1

	# And a hand-edited list must not be able to index the tier table out of range.
	m.tourney_claimed = [-3, 99, 1, 1]
	m._flush_save()
	m._load_game()
	await get_tree().process_frame
	var sane: bool = true
	for v in m.tourney_claimed:
		if typeof(v) != TYPE_INT or v < 0 or v >= m.TOURNEY_TIERS.size():
			sane = false
	bad += 0 if sane and m.tourney_claimed.size() == 1 else 1
	return _chk("a claimed rung stays claimed across a restart, and the last one turns the lap",
		bad == 0,
		"claimed=%d spins=%d paid twice=%d lap=%d loaded=%s" % [
			m.tourney_claimed.size(), spins_after_claiming,
			paid_twice, m.tourney_lap, str(m.tourney_claimed)])

# --- a clock that went backwards must not lock the bonuses -------------------
func _t_clock_rollback() -> int:
	print("clock rolled backwards")
	var now := Time.get_unix_time_from_system()
	m.daily_last = now + 86400.0 * 30.0     # stamped a month in the "future"
	m.shop_free_last = now + 86400.0 * 30.0
	m.offer_next = now + 86400.0 * 30.0
	m._sanitize_clock()
	var after := Time.get_unix_time_from_system() + 1.0
	var ok: bool = m.daily_last <= after and m.shop_free_last <= after and m.offer_next <= after + CV.OFFER_COOLDOWN
	return _chk("future stamps are pulled back so cooldowns still expire", ok)

# --- the soft-lock ------------------------------------------------------------
func _t_empty_island_attack() -> int:
	print("attack on a flattened rival")
	for n in m.npcs:
		n["buildings"] = [0, 0, 0, 0, 0]
		n["coins"] = 5000
	m.next_target = {}
	m._start_visit("attack")
	# The search screen, then the island, then the raid has to hand itself back.
	var waited := 0.0
	while m._raiding() and waited < 14.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		if m._match != null and m._match.has_method("_lock_in"):
			m._match._live = true
			m._match._lock_in()
			m._match._close()
	return _chk("a raid with nothing to smash releases the game", not m._raiding(),
		"still raiding after %.1fs" % waited)

# --- twenty thousand spins ----------------------------------------------------
func _t_spin_soak(n: int) -> int:
	print("spin soak (%d spins)" % n)
	m.island_level = 4
	m.buildings = [3, 3, 3, 3, 3]
	m.coins = 100000
	var bad := 0
	var nodes_start := 0
	for i in n:
		m.spins = 50
		m._last_bet = [1, 2, 3, 5].pick_random()
		m._on_spin_finished(m._roll())
		if m.coins < 0 or m.spins < 0 or m.stars < 0 or m.rank_stars < m.stars - m._dupe_star_value() - 1:
			bad += 1
			if bad < 4:
				print("    spin %d: coins=%d spins=%d stars=%d rank=%d" % [i, m.coins, m.spins, m.stars, m.rank_stars])
		if i == 200:
			nodes_start = _count_nodes(m)
		if i % 2000 == 0:
			await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	var nodes_end := _count_nodes(m)
	var fails := 0
	fails += _chk("no counter ever went negative", bad == 0)
	fails += _chk("node count settles instead of growing", nodes_end < nodes_start + 400,
		"%d -> %d" % [nodes_start, nodes_end])
	# reels: the position must stay on the strip
	var reels = m.slot.reels
	for c in 3:
		if absf(reels._pos[c]) > 100000.0:
			fails += _chk("reel %d position stayed bounded" % c, false, str(reels._pos[c]))
	return fails

func _count_nodes(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count_nodes(c)
	return total
