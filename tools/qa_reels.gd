extends Node
# =============================================================================
#  Loot Lagoon -- the third-reel hold
# =============================================================================
#
# The hold is the one piece of the machine that changes how long a spin takes,
# so it is also the one piece most able to change something it must not: what
# the spin PAYS. _roll() decides all three symbols before start_spin is called,
# and the only job of the hold is to take longer getting there.
#
# The load-bearing assertion in here is #3. Everything else is feel; #3 is the
# promise. If the held reel ever lands on a different cell than the unheld one
# would have, the hold has become a thumb on the scale, and that is a different
# game to the one shipped.
#
# Run: godot --headless --path . res://tools/qa_reels.tscn

var fails := 0
var checks := 0
var reels: Reels

func _ready() -> void:
	reels = Reels.new()
	reels.size = Vector2(320, 240)
	add_child(reels)
	await get_tree().process_frame

	_section("1. the hold fires on the four symbols and no others")
	_t_which()
	_section("2. how often a player meets it")
	_t_rate()
	_section("3. the outcome is untouched")
	_t_outcome()
	_section("4. the motion: leaves at speed, arrives at a crawl")
	_t_motion()
	_section("5. no dead air")
	_t_alive()

	print("")
	if fails == 0:
		print("PASS -- %d checks" % checks)
	else:
		print("FAIL -- %d of %d checks" % [fails, checks])
	get_tree().quit(1 if fails > 0 else 0)

# =============================================================================
#  1. which pairs hold
# =============================================================================

func _t_which() -> void:
	for sym in CV.SYMBOLS:
		reels.start_spin([sym, sym, "coin"])
		var want: bool = Reels.HOLD_SYMBOLS.has(sym)
		_eq(reels.is_holding(), want, "pair of %-7s -> hold %s" % [sym, want])
	# A pair that is not a pair never holds, whatever the symbols are.
	reels.start_spin(["bag", "gem", "bag"])
	_eq(reels.is_holding(), false, "bag/gem/bag -> no hold")
	reels.start_spin(["coin", "bag", "bag"])
	_eq(reels.is_holding(), false, "reels 2+3 matching -> no hold (nothing left to watch)")

# =============================================================================
#  2. the rate
# =============================================================================

# The number that decides whether this reads as an event or as the way spins
# are. Held on every matching pair it would be 40%; held on the four worth
# waiting for it should land near a quarter.
func _t_rate() -> void:
	var n := 40000
	var hold := 0
	var pair := 0
	for i in n:
		var r: Array = _roll()
		if r[0] == r[1]:
			pair += 1
			if Reels.HOLD_SYMBOLS.has(String(r[0])):
				hold += 1
	var pct := 100.0 * float(hold) / float(n)
	var pair_pct := 100.0 * float(pair) / float(n)
	print("    any matching pair:  %.1f%%   (unfiltered, for comparison)" % pair_pct)
	print("    holds:              %.1f%%   (~1 spin in %.1f)" % [pct, 100.0 / maxf(pct, 0.01)])
	_ok(pct > 22.0 and pct < 30.0, "hold rate in 22-30%% (got %.1f%%)" % pct)
	_ok(pair_pct > 37.0 and pair_pct < 43.0, "pair rate near 40%% (got %.1f%%)" % pair_pct)

# =============================================================================
#  3. the outcome is untouched   <-- the one that matters
# =============================================================================

# Drive the same result through the reels twice: once as it ships, and once
# with the hold forced off. Both must come to rest on the same symbol.
#
# The absolute stop position is expected to differ -- the held reel covers more
# strip on purpose -- so what is compared is the symbol under the payline,
# which is the only thing _on_spin_finished ever reads.
func _t_outcome() -> void:
	var bad := 0
	for i in 400:
		var r: Array = _roll()
		var held := _land(r)
		_eq_quiet(held, r, "held landing")
		if held != r:
			bad += 1
	_eq(bad, 0, "400 spins land on exactly the symbols _roll() chose")

	# And specifically on the four that hold, where the extra travel is in play.
	bad = 0
	for sym in Reels.HOLD_SYMBOLS:
		for third in CV.SYMBOLS:
			var r := [sym, sym, third]
			if _land(r) != r:
				bad += 1
	_eq(bad, 0, "every held pair x every third symbol lands correctly")

# Runs a spin to completion and reports the three symbols sitting on the
# payline, read off the strips the same way _draw does.
func _land(result: Array) -> Array:
	reels.start_spin(result)
	var guard := 0
	while reels.is_spinning() and guard < 100000:
		reels._process(1.0 / 60.0)
		guard += 1
	var out := []
	for c in Reels.COLS:
		var strip: Array = Reels.STRIPS[c]
		out.append(strip[posmod(int(round(reels._pos[c])), Reels.STRIP)])
	return out

# =============================================================================
#  4. the motion
# =============================================================================

# Two properties, and they are the two the curve was chosen for.
#
# It must LEAVE at the speed the other reels leave at -- a held reel that
# starts slow reads as a stutter, not as suspense, and is the failure mode of
# simply stretching the old curve over a longer time.
#
# It must ARRIVE slow enough to read symbol by symbol.
func _t_motion() -> void:
	var normal := _trace(["coin", "coin", "coin"])   # coin does not hold
	var held := _trace(["bag", "bag", "coin"])

	var v0_n: float = normal["v0"]
	var v0_h: float = held["v0"]
	print("    leaves at:   normal %.0f cells/s   held %.0f cells/s" % [v0_n, v0_h])
	var ratio := v0_h / maxf(v0_n, 0.001)
	_ok(ratio > 0.85 and ratio < 1.20,
		"held reel leaves within 15%% of the others (ratio %.2f)" % ratio)

	print("    lasts:       normal %.2fs           held %.2fs" % [normal["secs"], held["secs"]])
	_ok(held["secs"] > normal["secs"] + 1.0, "the hold adds over a second")
	_ok(held["secs"] < 3.6, "and stays under 3.6s -- this is a beat, not a wait")

	# What the player can actually read at the end.
	print("    last 0.5s:   normal %.1f cells       held %.1f cells" % [normal["tail"], held["tail"]])
	_ok(held["tail"] < 6.0, "held reel crosses under 6 cells in its last half second")
	_ok(held["tail"] > 0.4, "but is still moving -- more than 0.4 of a cell")

# =============================================================================
#  5. no dead air
# =============================================================================

# The failure this replaced: a reel that reaches its cell early and then sits
# there while a timer runs out. Nothing may be motionless for longer than a
# player reads as "it has landed".
func _t_alive() -> void:
	var held := _trace(["hammer", "hammer", "gem"])
	print("    longest still stretch before the stop: %.2fs" % held["still"])
	_ok(held["still"] < 0.30, "no frozen stretch over 0.30s")
	print("    detent ticks in the crawl: %d" % held["ticks"])
	_ok(held["ticks"] >= 3 and held["ticks"] <= 14,
		"between 3 and 14 clicks (got %d)" % held["ticks"])

# Steps a spin frame by frame and measures the third reel.
func _trace(result: Array) -> Dictionary:
	reels.start_spin(result)
	var dt := 1.0 / 60.0
	var t := 0.0
	var v0 := 0.0
	var still := 0.0
	var worst := 0.0
	var ticks := 0
	var last_cell := -1
	var prev: float = reels._pos[2]
	var trail := []          # (t, pos) so the last half second can be measured
	var guard := 0
	while reels.is_spinning() and guard < 100000:
		reels._process(dt)
		t += dt
		var moved: float = reels._pos[2] - prev
		var speed := moved / dt
		if guard == 0:
			v0 = speed
		if speed < 0.5:
			still += dt
			worst = maxf(worst, still)
		else:
			still = 0.0
		# The same boundary crossing _detent counts, at the same speed gate.
		if speed <= Reels.TICK_SPEED:
			var cell := int(floor(reels._pos[2]))
			if last_cell >= 0 and cell != last_cell:
				ticks += 1
			last_cell = cell
		else:
			last_cell = -1
		trail.append([t, reels._pos[2]])
		prev = reels._pos[2]
		guard += 1

	var end_pos: float = trail[trail.size() - 1][1]
	var tail := 0.0
	for row in trail:
		if float(row[0]) >= t - 0.5:
			tail = end_pos - float(row[1])
			break
	return {"v0": v0, "secs": t, "still": worst, "ticks": ticks, "tail": tail}

# =============================================================================
#  the machine's own roll, copied rather than called
# =============================================================================

# main.gd's _roll is a private method on a Control that boots the whole game.
# The odds it uses are the thing under test here, so a copy that drifts would
# be a real problem -- qa_full already asserts the live triple rate against the
# reels, which is what catches that.
func _roll() -> Array:
	if randf() < 0.3:
		var w := {"hammer": 25, "steal": 22, "coin": 14, "bag": 9, "gem": 12, "shield": 12, "bolt": 6}
		var total := 0
		for v in w.values():
			total += v
		var pick := randi_range(1, total)
		for key in w:
			pick -= w[key]
			if pick <= 0:
				return [key, key, key]
	return [CV.SYMBOLS.pick_random(), CV.SYMBOLS.pick_random(), CV.SYMBOLS.pick_random()]

# =============================================================================
#  harness
# =============================================================================

func _section(title: String) -> void:
	print("\n%s" % title)

func _ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("    ok    %s" % what)
	else:
		fails += 1
		print("    FAIL  %s" % what)

func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, "%s   [got %s, want %s]" % [what, got, want] if got != want else what)

func _eq_quiet(got: Variant, want: Variant, what: String) -> void:
	if got != want:
		print("    FAIL  %s: got %s, want %s" % [what, got, want])
