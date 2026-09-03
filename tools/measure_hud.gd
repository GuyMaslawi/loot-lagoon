extends Node
# Dev-only harness: does the HUD bar clear the cutout?
#
#   godot --headless --path . tools/measure_hud.tscn
#   DEMO_SAFE_TOP=108 godot --headless --path . tools/measure_hud.tscn
#
# THIS EXISTS BECAUSE THE ANSWER HAS BEEN GUESSED WRONG THREE TIMES. "The icons
# are still not attached to the top" came back on three separate builds, and
# each time the reasoning was done on estimated capsule widths -- which are not
# estimable, because they are set by the player's own numbers in a proportional
# display font.
#
# IT NOW CHECKS TWO THINGS, and the first is the one that matters.
#
# 1. THE BAR SITS BELOW THE INSET. This is the rule as of 2026-09-03: the bar
#    is one object with a gap down its middle, and riding level with a Dynamic
#    Island put the black housing in that gap -- which reads as a broken strip
#    of chrome, whatever the corners are doing. Guy called it off a photo of
#    his own phone. Run with DEMO_SAFE_TOP or the desktop reports no inset and
#    this check has nothing to prove.
#
# 2. COULD THE CAPSULES RIDE BESIDE A DYNAMIC ISLAND? Informational, and kept
#    because it is the measurement that decides the question if anyone ever
#    wants the bar back up there. The answer measured 2026-09-02: they cannot.
#    The left group ends at 288 with a four-figure coin count and 307 with a
#    nine-figure one, against a band that starts at 245.
#
# Re-run this after changing anything about capsule width -- the icon size, the
# content margins, the "+" disc, or which counters live in the bar.

const DESIGN := Vector2i(720, 1280)

# What a Dynamic Island covers, in design units. 126pt of a 393pt-wide screen,
# centred.
const ISLAND_FROM := 245.0
const ISLAND_TO := 475.0

func _ready() -> void:
	# Forced to the phone the game draws for, exactly as qa_layout is and for
	# the same reason: headless comes up at whatever width the platform hands
	# it, and every measurement below would then be against a screen that does
	# not exist.
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = DESIGN
	w.size = Vector2i(540, 960)
	await get_tree().process_frame

	var m: Control = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(5.0).timeout

	var bar := _find_bar(m)
	if bar == null:
		print("  [FAIL] no top bar found")
		get_tree().quit(1)
		return

	# 1. The bar's own rect against the inset the system reports.
	var inset: float = m.safe_top()
	var bar_top: float = m.hud_top()
	var clears: bool = inset <= 0.0 or bar_top >= inset
	print("  safe inset %.0f   bar top %.0f   bar bottom %.0f" % [inset, bar_top, bar_top + 70.0])
	if inset <= 0.0:
		print("  [skip] no inset reported -- re-run with DEMO_SAFE_TOP=108 (island) or 87 (notch)")
	else:
		print("  bar must start at or below %.0f  -> %s" % [
			inset, "ok" if clears else "OVER by %.0f" % (inset - bar_top)])
	print("")
	print("  (informational) Dynamic Island covers %.0f..%.0f of %d" % [ISLAND_FROM, ISLAND_TO, DESIGN.x])
	var worst_left := 0.0
	var worst_right := DESIGN.x as float
	# The widest each side ever gets: a coin count that has not compacted yet,
	# a five-figure star total, and a two-digit island number.
	for coins in ["1,500", "2.48M", "125.6M"]:
		for labels in m._hud_labels:
			labels["coins"].text = coins
			labels["stars"].text = "12.5K"
			labels["island"].text = "30"
		await get_tree().process_frame
		await get_tree().process_frame
		var lg: Control = bar.get_child(0)
		var rg: Control = bar.get_child(2)
		var l_end: float = lg.position.x + lg.size.x + bar.offset_left
		var r_start: float = rg.position.x + bar.offset_left
		worst_left = maxf(worst_left, l_end)
		worst_right = minf(worst_right, r_start)
		print("  coins=%-9s left ends %6.0f   right starts %6.0f" % [coins, l_end, r_start])

	var clear: bool = worst_left <= ISLAND_FROM and worst_right >= ISLAND_TO
	print("")
	print("  left  needs to end   by %.0f, worst is %.0f  -> %s" % [
		ISLAND_FROM, worst_left, "ok" if worst_left <= ISLAND_FROM else
		"OVER by %.0f" % (worst_left - ISLAND_FROM)])
	print("  right needs to start by %.0f, worst is %.0f  -> %s" % [
		ISLAND_TO, worst_right, "ok" if worst_right >= ISLAND_TO else
		"UNDER by %.0f" % (ISLAND_TO - worst_right)])
	print("")
	print("  (informational) capsules %s ride beside a Dynamic Island" % ["CANNOT", "can"][int(clear)])
	print("")
	print("MEASURE-HUD: %s" % ["BAR IS UNDER THE CUTOUT", "bar clears the cutout"][int(clears)])
	get_tree().quit(0 if clears else 1)

# The bar is the HBoxContainer holding [left group][gap][right group].
func _find_bar(m: Control) -> Control:
	for c in m.slot_page.get_children():
		if c is HBoxContainer and c.get_child_count() >= 3:
			return c
	return null
