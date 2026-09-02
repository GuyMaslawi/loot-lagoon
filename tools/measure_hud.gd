extends Node
# Dev-only harness: can the HUD capsules clear the cutout?
#
#   godot --headless --path . tools/measure_hud.tscn
#
# THIS EXISTS BECAUSE THE ANSWER HAS BEEN GUESSED WRONG TWICE. "The icons are
# still not attached to the top" came back on three separate builds, and each
# time the reasoning was done on estimated capsule widths -- which are not
# estimable, because they are set by the player's own numbers in a proportional
# display font.
#
# The question the HUD placement turns on is exactly this: on a phone whose
# cutout is a Dynamic Island (245..475 of 720, see the table above hud_top()),
# do the two capsule groups stay out of that band? If they do, they can ride up
# beside it, which is where the reference games put theirs. If they do not, they
# have to stay under it and no amount of tuning the offset will help.
#
# The answer, measured 2026-09-02: they do NOT. The left group ends at 288 with
# a four-figure coin count and 307 with a nine-figure one, against a band that
# starts at 245; the right group starts at 467 against a band that ends at 475.
# Both overlap. Moving them up is a HUD narrowing job, not a placement tweak.
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

	print("  Dynamic Island covers %.0f..%.0f of %d" % [ISLAND_FROM, ISLAND_TO, DESIGN.x])
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
	print("MEASURE-HUD: capsules %s ride beside a Dynamic Island" % ["CANNOT", "can"][int(clear)])
	get_tree().quit()

# The bar is the HBoxContainer holding [left group][gap][right group].
func _find_bar(m: Control) -> Control:
	for c in m.slot_page.get_children():
		if c is HBoxContainer and c.get_child_count() >= 3:
			return c
	return null
