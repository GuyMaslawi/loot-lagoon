extends Node
# QA harness #4 -- nothing may hang off the right edge of the phone.
#
# This is the third time the same bug class has shipped: a Control that loses to
# a minimum size keeps its position and grows, a VBoxContainer hands its widest
# child's minimum width to every sibling, and one over-wide card therefore
# carries a whole page off the screen. Both previous instances were invisible in
# the source and obvious in a render. So this measures instead of reading.

var m: Control
var fails := 0

func _ready() -> void:
	# Forced to the phone the game is designed for, and this is the whole
	# premise of the harness. Headless has no window, so the root viewport comes
	# up at whatever the platform hands it -- 1280 wide in this build -- and
	# every page then lays itself out with 560px of room it will never have on a
	# phone. The first version of this measured against that and cheerfully
	# passed a page carrying a deliberate 900px canary.
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(int(DESIGN_W), int(DESIGN_H))
	w.size = Vector2i(540, 960)
	await get_tree().process_frame
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	# Every card that only appears under a condition, forced on: a live timed
	# offer and an unbought starter pack are the two widest things the shop can
	# draw, and neither is present on the fresh save this harness starts from.
	m.offer_id = "to_kraken"
	m.offer_until = m._now() + 7000.0
	m.purchased_ids = []
	m.piggy_coins = 105000
	# Shown, not merely filled. Every page but the current one is visible=false,
	# and a hidden Control is never laid out -- measuring one reports zeroes and
	# passes, which is worse than not measuring it at all. The first version of
	# this harness did exactly that and gave a clean bill of health to a page
	# that was known to be broken.
	for key in ["shop", "quests", "collections", "boxes", "options", "alerts"]:
		var page: Control = m.pages.get(key, null)
		if page == null:
			print("  [skip] %s (no such page)" % key)
			continue
		var was := page.visible
		page.visible = true
		m._fill_page(key)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_page(key)
		page.visible = was
	# The modals, laid out by the same containers and just as able to grow past
	# the glass they sit in.
	m.tourney_points = 1500
	for opener in ["_open_ranks", "_open_daily"]:
		m.call(opener)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_page("popup " + opener, m._popup)
		m._close_popup(true)
		await get_tree().process_frame
	print("QA-LAYOUT: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

# The width of the phone the game draws for. project.godot's viewport is
# 720x1280 and every page is laid out in those units, so this is the edge that
# matters -- not the size of whatever surface the harness happens to run on.
const DESIGN_W := 720.0
const DESIGN_H := 1280.0

func _view_w() -> float:
	return DESIGN_W

# Walks the tree and reports the worst overhang, not merely the first. The first
# one found is usually a child of the real culprit -- a VBoxContainer inherits
# its widest child's minimum and then every sibling reports the same overflow --
# so the widest offender is the one worth naming.
func _check_page(key: String, root: Node = null) -> void:
	var page: Node = root if root != null else m.pages.get(key, null)
	if page == null:
		print("  [skip] %s (no such page)" % key)
		return
	var worst := 0.0
	var who := ""
	var over := 0
	_seen = 0
	_widest = 0.0
	for c in _spills(page, _view_w()):
		over += 1
		var ctl: Control = c
		var spill: float = ctl.global_position.x + ctl.size.x - _view_w()
		if spill > worst:
			worst = spill
			who = "%s (%s) x=%.0f w=%.0f" % [ctl.name, ctl.get_class(),
				ctl.global_position.x, ctl.size.x]
	if over > 0:
		fails += 1
		_blame(page)
	if over > 0:
		print("    (walked %d visible controls, widest right edge %.0f of %.0f)" % [
			_seen, _widest, _view_w()])
	print("  [%s] %s fits the screen %s" % ["ok" if over == 0 else "FAIL", key,
		"" if over == 0 else "-- %d controls spill, worst %.0fpx: %s" % [over, worst, who]])

# One pixel of tolerance, because a rounded layout can land a border half a unit
# past the edge and that is not what this is looking for.
const SLACK := 1.0
var _seen := 0
var _widest := 0.0

func _spills(n: Node, limit: float, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			var ctl := c as Control
			_seen += 1
			_widest = maxf(_widest, ctl.global_position.x + ctl.size.x)
			if ctl.size.x > 0.0 and ctl.global_position.x + ctl.size.x > limit + SLACK:
				out.append(ctl)
		_spills(c, limit, out)
	return out


# WHICH card did it. A page that overflows almost never overflows because of the
# control that reports the overflow: a VBoxContainer hands its widest child's
# minimum width to every sibling, and the ScrollContainer above them loses to
# that same minimum and grows past its own anchors. So the useful answer is the
# single deepest node whose own minimum is the widest, which is the thing that
# actually has to be made narrower.
func _blame(page: Node) -> void:
	# Collected into an array rather than assigned inside a lambda: GDScript
	# captures by value, so a `worst = c` in a callback updates the copy and the
	# caller sees nothing at all.
	var all: Array = []
	_min_walk(page, all)
	if all.is_empty():
		return
	# Widest first, and among equals the DEEPEST first. A ScrollContainer and
	# every container between it and the offending card all report the same
	# inherited minimum, and naming the outermost one says only "the page is too
	# wide" -- which is what we already knew. The leaf is the thing to fix.
	all.sort_custom(func(a, b) -> bool:
		if absf(a[1] - b[1]) > 0.5:
			return a[1] > b[1]
		return a[2] > b[2]
	)
	var worst: Control = all[0][0]
	var worst_w: float = all[0][1]
	var trail := PackedStringArray()
	var n: Node = worst
	while n != null and n != page:
		if n is Control:
			trail.insert(0, "%s(%s min=%.0f)" % [n.name, n.get_class(),
				(n as Control).get_combined_minimum_size().x])
		n = n.get_parent()
	print("      widest minimum: %.0f -- %s" % [worst_w, " > ".join(trail)])
	print("      next widest:")
	for i in mini(8, all.size()):
		var c: Control = all[i][0]
		print("        %6.0f  depth %d  %s (%s)  %s" % [all[i][1], all[i][2], c.name,
			c.get_class(), _words(c)])

func _min_walk(n: Node, out: Array, depth := 0) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			out.append([c, (c as Control).get_combined_minimum_size().x, depth])
		_min_walk(c, out, depth + 1)


# The first few words under a node, so a blamed @PanelContainer@647 can be
# recognised as a card a human has seen.
func _words(n: Node) -> String:
	var got := PackedStringArray()
	_words_into(n, got)
	return "\"" + " | ".join(got) + "\""

func _words_into(n: Node, out: PackedStringArray) -> void:
	if out.size() >= 5:
		return
	for c in n.get_children():
		if c is Label and String((c as Label).text).strip_edges() != "":
			out.append(String((c as Label).text).strip_edges())
		elif c is Button and String((c as Button).text).strip_edges() != "":
			out.append("[" + String((c as Button).text).strip_edges() + "]")
		_words_into(c, out)
