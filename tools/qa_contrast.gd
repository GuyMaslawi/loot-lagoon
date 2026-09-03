extends Node
# QA harness -- every piece of text in the game has to be readable on the pixels
# it actually lands on.
#
# The complaint that produced this was "the design is very pale and in many
# places unclear". That is a measurable claim, and it is not measurable from the
# source: a Label's font_color tells you nothing, because what it sits on is a
# translucent panel over a shader backdrop over an island's tint. Only the
# rendered frame knows.
#
# So this renders each page, and for every text node samples the pixels inside
# its own rect. Glyph strokes and background both live in that rect, so the
# darkest and lightest tenth of it bracket the two colours the eye is actually
# asked to separate. Their WCAG ratio is the score. It is self-calibrating --
# it never has to know which stylebox won.
#
#   godot --path . tools/qa_contrast.tscn
#   CONTRAST_PAGES=shop,quests   restricts the run
#
# Thresholds are WCAG AA, relaxed one step for display type because a 44px
# outlined headline is legible below where 4.5 would put it:
#   body  (< 28px)  >= 4.5
#   large (>= 28px) >= 3.0
# Anything under 2.0 is reported as SEVERE -- that is the pale-on-pale band and
# it is what the player is complaining about.

const DESIGN_W := 720.0
const DESIGN_H := 1280.0
const AA_BODY := 4.5
const AA_LARGE := 3.0
const SEVERE := 2.0

var m: Control
var rows := []      # {page, text, size, ratio, rect}

func _ready() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(int(DESIGN_W), int(DESIGN_H))
	w.size = Vector2i(int(DESIGN_W), int(DESIGN_H))
	await get_tree().process_frame
	m = load("res://scripts/main.gd").new()
	add_child(m)
	# Long enough for the welcome-back banners to have come and gone; they sit
	# where a page header does and would be measured instead of it.
	await get_tree().create_timer(5.0).timeout
	m.offer_id = "to_kraken"
	m.offer_until = m._now() + 7000.0
	m.purchased_ids = []
	m.piggy_coins = 105000
	m.tourney_points = 1500

	var want := OS.get_environment("CONTRAST_PAGES")
	var keys := ["slot", "island", "shop", "quests", "collections", "boxes", "options", "alerts"]
	if want != "":
		keys = Array(want.split(","))

	for key in keys:
		await _goto(key)
		await _measure(key, m)

	for opener in ["_open_tourney", "_open_world_ranks", "_open_daily"]:
		await _goto("slot")
		m.call(opener)
		await get_tree().create_timer(2.0).timeout
		if m._popup != null:
			await _measure("popup " + opener.trim_prefix("_open_"), m._popup)
		m._close_popup(true)
		await get_tree().process_frame

	_report()
	get_tree().quit(0)

func _goto(key: String) -> void:
	if m.pages.has(key):
		m._goto(m.pages[key])
		m._fill_page(key)
	elif key == "slot":
		m._goto(m.slot_page)
	elif key == "island" or key == "village":
		m._goto(m.village_page)
	# Page transitions tween; a frame caught mid-fade measures the tween.
	await get_tree().create_timer(1.6).timeout

# Everything with text, anywhere under `root`, that is actually on screen.
func _texts(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Control and not c.is_visible_in_tree():
			continue
		if (c is Label or c is Button) and c.get("text") != null and str(c.text).strip_edges() != "":
			out.append(c)
		_texts(c, out)

func _measure(page: String, root: Node) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if OS.has_environment("CONTRAST_DUMP"):
		img.save_png("user://cx_%s.png" % page.replace(" ", "_"))
		print("[dump] %s img=%dx%d" % [page, img.get_width(), img.get_height()])
	# The frame can be a different size than the design space (hidpi, or a
	# window the platform resized). Everything below is in image pixels.
	var sx := float(img.get_width()) / DESIGN_W
	var sy := float(img.get_height()) / DESIGN_H
	var nodes := []
	_texts(root, nodes)
	for n in nodes:
		var txt := str(n.text).strip_edges()
		# Emoji are pictures. They have their own internal contrast and no font
		# colour to ask about, so scoring them measures nothing and buries the
		# text that does matter under a hundred rows of false failure.
		if _is_pictorial(txt):
			continue
		var r: Rect2 = (n as Control).get_global_rect()
		if r.size.x < 6.0 or r.size.y < 6.0:
			continue
		# Offscreen or clipped out of its scroll container: the layout still
		# reports a rect for a row below the fold, and the pixels there belong
		# to whatever is actually drawn at that coordinate.
		if r.position.y < -4.0 or r.position.y > DESIGN_H - 8.0 or r.position.x > DESIGN_W - 8.0:
			continue
		# A row scrolled past the bottom of its own list is still laid out, and
		# the pixels at those coordinates belong to whatever is drawn there --
		# the page's backdrop, usually. Measuring it produces a confident report
		# that a mission row is dark ink on open water. It is not on screen at
		# all; skip anything its scroll container is not currently showing.
		if _clipped(n, r):
			continue
		var ink: Color = _text_color(n)
		if ink.a < 0.04:
			continue
		# The background the glyphs land on. The median of a text rect is
		# overwhelmingly background -- glyph strokes cover 5-15% of it, which is
		# exactly why a percentile-based "darkest tenth" reads as background too
		# and scores every label in the game a perfect 1.00.
		var bg: Color = _median_color(img, r, sx, sy)
		if bg.a < 0.0:
			continue
		# Semi-transparent ink is composited onto what is behind it before it is
		# judged, because that is what the eye is given.
		var eff := Color(
			ink.r * ink.a + bg.r * (1.0 - ink.a),
			ink.g * ink.a + bg.g * (1.0 - ink.a),
			ink.b * ink.a + bg.b * (1.0 - ink.a))
		var ratio := _ratio(eff, bg)
		# An outlined glyph is read off its outline, not its fill: the outline
		# is what draws the letterform against the page. So a sand-on-brass
		# plaque with a near-black rim is legible even though fill-vs-brass is
		# 1.8, and scoring it 1.8 would send the fix to the wrong place. Credit
		# the better of the two -- which also exposes outlines too thin or too
		# close in value to be doing that job.
		var os_px := 0
		if n.has_theme_constant_override("outline_size"):
			os_px = int(n.get_theme_constant("outline_size"))
		if os_px >= 3:
			var oc: Color = n.get_theme_color("font_outline_color")
			if oc.a > 0.35:
				ratio = maxf(ratio, _ratio(oc, bg))
		var fs := 20
		if n.has_theme_font_size_override("font_size"):
			fs = n.get_theme_font_size("font_size")
		rows.append({"page": page, "text": txt.replace("\n", " ").substr(0, 34),
			"size": fs, "ratio": ratio, "cls": n.get_class(),
			"ink": eff.to_html(false), "bg": bg.to_html(false),
			"at": "%d,%d" % [int(r.position.x), int(r.position.y)]})

func _clipped(n: Control, r: Rect2) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer or (p is Control and (p as Control).clip_contents):
			var pr: Rect2 = (p as Control).get_global_rect()
			if not pr.has_point(r.position + r.size * 0.5):
				return true
		p = p.get_parent()
	return false

# A label whose text is all emoji / symbol codepoints is art, not copy.
func _is_pictorial(t: String) -> bool:
	var letters := 0
	for ch in t:
		var c := ch.unicode_at(0)
		if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c > 0x24F and c < 0x2000:
			letters += 1
	return letters == 0

# What colour this node actually draws its text in, asked of the node rather
# than guessed from the stylesheet -- overrides, themes and inherited defaults
# all resolve through get_theme_color.
func _text_color(n: Control) -> Color:
	if n is Button:
		if n.disabled:
			return n.get_theme_color("font_disabled_color")
		return n.get_theme_color("font_color")
	return n.get_theme_color("font_color")

func _median_color(img: Image, r: Rect2, sx: float, sy: float) -> Color:
	# Inset: a Label's rect includes its padding, and a Button's includes the
	# very edge of its bevel, which is darker than the face and would flatter
	# every button in the game.
	var pad := Vector2(minf(r.size.x * 0.06, 8.0), minf(r.size.y * 0.16, 8.0))
	var rr := Rect2(r.position + pad, r.size - pad * 2.0)
	var x0 := clampi(int(rr.position.x * sx), 0, img.get_width() - 1)
	var y0 := clampi(int(rr.position.y * sy), 0, img.get_height() - 1)
	var x1 := clampi(int((rr.position.x + rr.size.x) * sx), 0, img.get_width())
	var y1 := clampi(int((rr.position.y + rr.size.y) * sy), 0, img.get_height())
	if x1 - x0 < 3 or y1 - y0 < 3:
		return Color(0, 0, 0, -1)
	# A fixed, small grid. The first version walked every pixel in the rect and
	# then sort_custom'd an index array to find the median colour -- 5,000
	# samples times 340 text nodes times a GDScript comparator is tens of
	# millions of script calls and the harness simply never returned. Nothing is
	# gained by it either: a 24x14 grid across a label is already hundreds of
	# samples of a background that is, at most, a gradient.
	var cols := PackedColorArray()
	var lums := PackedFloat32Array()
	for iy in 14:
		var y := y0 + int((y1 - y0 - 1) * float(iy) / 13.0)
		for ix in 24:
			var x := x0 + int((x1 - x0 - 1) * float(ix) / 23.0)
			var c := img.get_pixel(x, y)
			cols.append(c)
			lums.append(_rel_lum(c))
	var sorted := lums.duplicate()
	sorted.sort()
	var mid: float = sorted[sorted.size() / 2]
	# The colour that carries the median luminance, found in one linear pass.
	var best := 0
	var bestd := 1e9
	for i in lums.size():
		var d: float = absf(lums[i] - mid)
		if d < bestd:
			bestd = d
			best = i
	return cols[best]

func _ratio(a: Color, b: Color) -> float:
	var l1 := _rel_lum(a)
	var l2 := _rel_lum(b)
	return (maxf(l1, l2) + 0.05) / (minf(l1, l2) + 0.05)

func _rel_lum(c: Color) -> float:
	var v := [c.r, c.g, c.b]
	for i in 3:
		v[i] = (v[i] / 12.92) if v[i] <= 0.04045 else pow((v[i] + 0.055) / 1.055, 2.4)
	return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]

func _report() -> void:
	rows.sort_custom(func(a, b): return a["ratio"] < b["ratio"])
	var fails := 0
	var severe := 0
	var by_page := {}
	print("\n================ QA-CONTRAST ================")
	for r in rows:
		var need: float = AA_LARGE if int(r["size"]) >= 28 else AA_BODY
		if r["ratio"] >= need:
			continue
		fails += 1
		if r["ratio"] < SEVERE:
			severe += 1
		by_page[r["page"]] = int(by_page.get(r["page"], 0)) + 1
		print("  %5.2f  need %.1f  %-20s %2dpx  #%s on #%s  %s" %
			[r["ratio"], need, r["page"], int(r["size"]), r["ink"], r["bg"], r["text"]])
	print("---------------------------------------------")
	for p in by_page:
		print("  %-24s %d failing" % [p, by_page[p]])
	print("  %d of %d text nodes fail; %d are SEVERE (< %.1f)" % [fails, rows.size(), severe, SEVERE])
	print("=============================================\n")
