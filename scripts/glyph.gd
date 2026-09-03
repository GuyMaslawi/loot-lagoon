class_name Glyph
extends Control

# =============================================================================
#  The Loot Lagoon icon set — drawn, not typed
# =============================================================================
#
# Every icon in the chrome is vector-drawn here instead of being an emoji.
# Emoji come from three different design systems at once (Apple's, Noto's, the
# game's own painted art), so a bar of them never looks like it was made for
# one game. These are built from a single set of rules:
#
#   * one light direction — everything is lit from above, so highlights sit on
#     top edges and the darker shade always pools at the bottom
#   * one line weight — a 6-unit outline in a warm dark of the icon's own hue,
#     never black, so nothing looks sooty against the bright lagoon
#   * one material vocabulary — brass, sea glass, coral, sand, kelp. An icon
#     drawn in brass means the same thing as a brass frame does: valuable.
#   * generous, tumbled shapes with no tight corners, matching the panels
#
# Icons are authored in a 100x100 space and scaled to whatever the control is,
# so the same glyph is legible at 28px in a chip and 120px on the nav bar.

const SPACE := 100.0
const LINE := 6.0

# Which glyph to draw. Unknown names draw nothing rather than erroring, so a
# typo shows up as a hole instead of taking the screen down.
@export var kind := "coin":
	set(value):
		kind = value
		queue_redraw()

# Optional hue override — lets one shape serve two jobs (a teal ship's wheel in
# the HUD, a coral one on the nav bar) without a second glyph.
@export var tint := Color(0, 0, 0, 0):
	set(value):
		tint = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(40, 40)

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Uniform scale, centred, so non-square boxes never stretch an icon.
	var s := minf(size.x, size.y) / SPACE
	var off := (size - Vector2(SPACE, SPACE) * s) * 0.5
	draw_set_transform(off, 0.0, Vector2(s, s))
	match kind:
		"coin":    _coin()
		"wheel":   _wheel()
		"shield":  _shield()
		"island":  _island()
		"shop":    _shop()
		"cards":   _cards()
		"quests":  _quests()
		"gift":    _gift()
		"bell":    _bell()
		"trophy":  _trophy()
		"gear":    _gear()
		"star":    _star_icon()
		"plus":    _plus()
		"close":   _close()
		"rivet":   _rivet()
		"anchor":  _anchor()
		"piggy":   _piggy()
		"box":     _box()
		"medal":   _medal()
		"tick":    _tick()
		"spark":   _spark()
		"crown":   _crown()
		"sun":     _sun()
		"moon":    _moon()
		"calendar": _calendar()
		"warn":    _warn()

# --- drawing primitives ------------------------------------------------------

func _hue(base: Color) -> Color:
	return tint if tint.a > 0.0 else base

# Filled shape with its own warm outline. Passing `ink` overrides the derived
# outline colour for the rare case where a shape sits on its own hue.
func _shape(pts: PackedVector2Array, fill: Color, w := LINE, ink := Color(0, 0, 0, 0)) -> void:
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, ink if ink.a > 0.0 else fill.darkened(0.42), w, true)

func _disc(c: Vector2, r: float, fill: Color, w := LINE, ink := Color(0, 0, 0, 0)) -> void:
	draw_circle(c, r, fill)
	if w > 0.0:
		draw_arc(c, r - w * 0.5, 0.0, TAU, 40, ink if ink.a > 0.0 else fill.darkened(0.42), w, true)

# A capsule — the shape every bar, rod and ribbon in the set is made of.
func _bar(a: Vector2, b: Vector2, thick: float, fill: Color, w := LINE) -> void:
	draw_line(a, b, fill.darkened(0.42), thick + w, true)
	draw_line(a, b, fill, thick, true)

func _round_rect(center: Vector2, box: Vector2, radius: float, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var h := box * 0.5
	var corners := [
		[Vector2(h.x - radius, h.y - radius), 0.0],
		[Vector2(-h.x + radius, h.y - radius), PI * 0.5],
		[Vector2(-h.x + radius, -h.y + radius), PI],
		[Vector2(h.x - radius, -h.y + radius), PI * 1.5],
	]
	for c in corners:
		var pivot: Vector2 = c[0]
		var start: float = c[1]
		for i in 5:
			var a: float = start + PI * 0.5 * (float(i) / 4.0)
			pts.append(pivot + Vector2(cos(a), sin(a)) * radius)
	var out := PackedVector2Array()
	for p in pts:
		out.append(center + p.rotated(rot))
	return out

func _star_pts(c: Vector2, outer: float, inner: float, points := 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := -PI * 0.5 + PI * float(i) / float(points)
		var r := outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

# The specular crescent every round object in the set wears on its upper left.
func _spec(c: Vector2, r: float, strength := 0.75) -> void:
	draw_arc(c, r, PI * 1.08, PI * 1.62, 16, Color(1, 1, 1, strength), LINE, true)

# --- currency ----------------------------------------------------------------

func _coin() -> void:
	var c := Vector2(50, 50)
	_disc(c, 44, _hue(Lagoon.BRASS), 7, Lagoon.BRASS_LO)
	_disc(c, 33, Lagoon.BRASS_HI, 4, Lagoon.BRASS_MID)
	_shape(_star_pts(c, 19, 8.5), Lagoon.BRASS, 4, Lagoon.BRASS_MID)
	_spec(c, 36, 0.7)

# A ship's wheel: the game's mark for a spin. Same shape in the HUD (where it
# counts what you hold) and on the nav bar (where it takes you to spend it).
func _wheel() -> void:
	var c := Vector2(50, 50)
	var body := _hue(Lagoon.LAGOON)
	var dark := body.darkened(0.42)
	for i in 6:
		var a := PI * float(i) / 3.0
		var dir := Vector2(cos(a), sin(a))
		_bar(c + dir * 30.0, c + dir * 45.0, 9.0, body)
		_disc(c + dir * 45.0, 8.0, body, 4.0, dark)
	draw_arc(c, 31, 0.0, TAU, 44, dark, 18.0, true)
	draw_arc(c, 31, 0.0, TAU, 44, body, 12.0, true)
	for i in 6:
		var a := PI * float(i) / 3.0
		_bar(c, c + Vector2(cos(a), sin(a)) * 31.0, 7.0, body, 4.0)
	_disc(c, 12, Lagoon.SHELL, 5.0, dark)
	_spec(c, 31, 0.5)

func _shield() -> void:
	var body := _hue(Lagoon.SHELL)
	var pts := PackedVector2Array([
		Vector2(16, 22), Vector2(50, 9), Vector2(84, 22),
		Vector2(84, 44), Vector2(77, 63), Vector2(64, 80),
		Vector2(50, 92), Vector2(36, 80), Vector2(23, 63), Vector2(16, 44),
	])
	_shape(pts, body, 8.0, Lagoon.BRASS)
	# chevron — reads as "guarded" at any size, unlike a crest or a lock
	var chev := PackedVector2Array([
		Vector2(34, 40), Vector2(50, 54), Vector2(66, 40),
		Vector2(66, 54), Vector2(50, 68), Vector2(34, 54),
	])
	_shape(chev, Lagoon.LAGOON, 4.0, Lagoon.LAGOON_DEEP)

# --- navigation --------------------------------------------------------------

func _island() -> void:
	# sand bar, then the green cap sitting on it, then a palm — three flat
	# ellipses read as an island far better than an outlined landmass does
	var sand := PackedVector2Array()
	for i in 26:
		var a := TAU * float(i) / 26.0
		sand.append(Vector2(50, 73) + Vector2(cos(a) * 41.0, sin(a) * 17.0))
	_shape(sand, Lagoon.SAND_DEEP, 5.0)

	var grass := PackedVector2Array()
	for i in 26:
		var a := TAU * float(i) / 26.0
		grass.append(Vector2(50, 61) + Vector2(cos(a) * 32.0, sin(a) * 15.0))
	_shape(grass, Lagoon.KELP, 5.0, Lagoon.KELP_LO)

	_bar(Vector2(53, 62), Vector2(61, 30), 7.0, Lagoon.BRASS_LO, 4.0)
	for d in [Vector2(-24, -6), Vector2(-14, -18), Vector2(16, -16), Vector2(23, -3)]:
		var tip: Vector2 = Vector2(61, 30) + d
		var frond := PackedVector2Array([
			Vector2(61, 30), tip, tip + Vector2(0, 9), Vector2(61, 34),
		])
		_shape(frond, Lagoon.KELP, 4.0, Lagoon.KELP_LO)
	_disc(Vector2(61, 30), 7, Lagoon.KELP_LO, 0.0)

func _shop() -> void:
	# a beach stall: scalloped awning over a sand counter
	var counter := _round_rect(Vector2(50, 68), Vector2(64, 40), 8.0)
	_shape(counter, Lagoon.SAND, 6.0, Lagoon.SAND_DEEP.darkened(0.3))
	var roof := PackedVector2Array([
		Vector2(8, 44), Vector2(22, 18), Vector2(78, 18), Vector2(92, 44),
	])
	_shape(roof, _hue(Lagoon.CORAL), 6.0, Lagoon.CORAL_LO)
	# scallops alternate coral / shell, which is what makes it read as an
	# awning rather than a roof
	for i in 4:
		var x := 18.5 + 21.0 * float(i)
		_disc(Vector2(x, 44), 10.5, Lagoon.SHELL if i % 2 == 0 else Lagoon.CORAL_HI, 4.0, Lagoon.CORAL_LO)
	_bar(Vector2(20, 58), Vector2(80, 58), 5.0, Lagoon.SAND_DEEP, 0.0)

func _cards() -> void:
	var back := _round_rect(Vector2(40, 54), Vector2(42, 60), 8.0, -0.24)
	_shape(back, Lagoon.URCHIN, 6.0, Lagoon.URCHIN_LO)
	var front := _round_rect(Vector2(60, 50), Vector2(42, 60), 8.0, 0.14)
	_shape(front, Lagoon.SHELL, 6.0, Lagoon.INK_SOFT)
	_shape(_star_pts(Vector2(61, 49), 15, 6.5), Lagoon.CORAL, 4.0, Lagoon.CORAL_LO)

func _quests() -> void:
	var body := _round_rect(Vector2(50, 52), Vector2(56, 68), 7.0)
	_shape(body, Lagoon.SAND, 6.0, Lagoon.SAND_DEEP.darkened(0.3))
	for y in [40.0, 52.0, 64.0]:
		_bar(Vector2(33, y), Vector2(67, y), 5.0, Lagoon.INK_SOFT, 0.0)
	# brass rods top and bottom turn a rectangle into a scroll
	for y in [17.0, 87.0]:
		_bar(Vector2(15, y), Vector2(85, y), 11.0, Lagoon.BRASS, 5.0)

# --- side actions ------------------------------------------------------------

func _gift() -> void:
	var box := _round_rect(Vector2(50, 68), Vector2(64, 40), 6.0)
	_shape(box, _hue(Lagoon.CORAL), 6.0, Lagoon.CORAL_LO)
	var lid := _round_rect(Vector2(50, 43), Vector2(76, 18), 7.0)
	_shape(lid, Lagoon.CORAL_HI, 6.0, Lagoon.CORAL_LO)
	_bar(Vector2(50, 36), Vector2(50, 88), 12.0, Lagoon.SAND, 4.0)
	for x in [37.0, 63.0]:
		_disc(Vector2(x, 25), 12, Lagoon.SAND, 5.0, Lagoon.BRASS)

func _bell() -> void:
	var pts := PackedVector2Array([
		Vector2(24, 68), Vector2(27, 47), Vector2(34, 31),
		Vector2(50, 23), Vector2(66, 31), Vector2(73, 47), Vector2(76, 68),
	])
	_shape(pts, _hue(Lagoon.BRASS), 6.0, Lagoon.BRASS_LO)
	_bar(Vector2(20, 71), Vector2(80, 71), 10.0, Lagoon.BRASS, 5.0)
	_disc(Vector2(50, 17), 7, Lagoon.BRASS, 4.0, Lagoon.BRASS_LO)
	_disc(Vector2(50, 84), 8, Lagoon.BRASS_LO, 4.0)
	draw_arc(Vector2(50, 52), 20, PI * 1.12, PI * 1.52, 12, Color(1, 1, 1, 0.6), 5.0, true)

func _trophy() -> void:
	for side in [-1.0, 1.0]:
		draw_arc(Vector2(50 + 21 * side, 36), 12, -PI * 0.5, PI * 0.5 if side > 0.0 else -PI * 1.5,
			14, Lagoon.BRASS_LO, 11.0, true)
		draw_arc(Vector2(50 + 21 * side, 36), 12, -PI * 0.5, PI * 0.5 if side > 0.0 else -PI * 1.5,
			14, Lagoon.BRASS, 6.0, true)
	var cup := PackedVector2Array([
		Vector2(29, 20), Vector2(71, 20), Vector2(68, 46),
		Vector2(59, 60), Vector2(41, 60), Vector2(32, 46),
	])
	_shape(cup, _hue(Lagoon.BRASS), 6.0, Lagoon.BRASS_LO)
	_bar(Vector2(50, 58), Vector2(50, 74), 11.0, Lagoon.BRASS_MID, 5.0)
	var base := _round_rect(Vector2(50, 80), Vector2(44, 14), 5.0)
	_shape(base, Lagoon.BRASS, 6.0, Lagoon.BRASS_LO)
	_shape(_star_pts(Vector2(50, 36), 13, 5.5), Lagoon.SAND, 3.5, Lagoon.BRASS_LO)

func _gear() -> void:
	var body := _hue(Lagoon.SHELL)
	# Teeth that barely clear the body: pushed further out they read as petals,
	# and a flower is not what "settings" is supposed to look like.
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		_shape(_round_rect(Vector2(50, 50) + dir * 39.0, Vector2(26, 15), 4.0, a), body, 5.0, Lagoon.INK_SOFT)
	_disc(Vector2(50, 50), 35, body, 6.0, Lagoon.INK_SOFT)
	_disc(Vector2(50, 50), 12, Lagoon.LAGOON_DEEP, 4.0, Lagoon.ABYSS)

# --- marks -------------------------------------------------------------------

func _star_icon() -> void:
	_shape(_star_pts(Vector2(50, 52), 44, 19), _hue(Lagoon.BRASS_HI), 6.0, Lagoon.BRASS_LO)

func _plus() -> void:
	var c := _hue(Color.WHITE)
	_bar(Vector2(50, 24), Vector2(50, 76), 17.0, c, 0.0)
	_bar(Vector2(24, 50), Vector2(76, 50), 17.0, c, 0.0)

func _close() -> void:
	var c := _hue(Color.WHITE)
	_bar(Vector2(28, 28), Vector2(72, 72), 15.0, c, 0.0)
	_bar(Vector2(72, 28), Vector2(28, 72), 15.0, c, 0.0)

func _rivet() -> void:
	_disc(Vector2(50, 50), 44, Lagoon.BRASS_MID, 8.0, Lagoon.BRASS_LO)
	_disc(Vector2(46, 45), 24, Lagoon.BRASS_HI, 0.0)

func _anchor() -> void:
	var body := _hue(Lagoon.BRASS)
	_disc(Vector2(50, 20), 11, body, 6.0, Lagoon.BRASS_LO)
	_bar(Vector2(50, 28), Vector2(50, 84), 10.0, body, 5.0)
	_bar(Vector2(28, 40), Vector2(72, 40), 9.0, body, 5.0)
	draw_arc(Vector2(50, 56), 30, PI * 0.16, PI * 0.84, 20, Lagoon.BRASS_LO, 17.0, true)
	draw_arc(Vector2(50, 56), 30, PI * 0.16, PI * 0.84, 20, body, 11.0, true)


# =============================================================================
#  Second wave — the shapes that were emoji
# =============================================================================
#
# Every one of these replaces a system glyph the game was borrowing. They are
# built from the same rules as the first set: one light direction, one line
# weight, one material vocabulary. That is the whole reason to draw them at
# all -- an emoji is correct and it belongs to somebody else's design system,
# so a row of them can never look like it was made for this game.

# The piggy bank, and it is deliberately pink rather than brass: it is the one
# object in the game that is neither a currency you hold nor a control you
# press, and giving it its own hue is what makes it findable in a top bar full
# of metal.
const PIG      := Color(1.000, 0.663, 0.741)
const PIG_MID  := Color(0.949, 0.482, 0.596)
const PIG_LO   := Color(0.639, 0.243, 0.361)

func _piggy() -> void:
	# ear, behind the head so its base disappears under the body
	_shape(PackedVector2Array([Vector2(30, 34), Vector2(46, 28), Vector2(36, 46)]),
		PIG_MID, 5.0, PIG_LO)
	# trotters, likewise behind
	for x in [34.0, 66.0]:
		_shape(_round_rect(Vector2(x, 78), Vector2(15, 20), 5.0), PIG_MID, 5.0, PIG_LO)
	# body
	_disc(Vector2(52, 56), 32, _hue(PIG), 6.0, PIG_LO)
	# snout, on the left so the pig faces out of the screen
	_shape(_round_rect(Vector2(22, 58), Vector2(24, 20), 8.0), PIG_MID, 5.0, PIG_LO)
	for y in [54.0, 62.0]:
		_disc(Vector2(21, y), 3.0, PIG_LO, 0.0)
	# eye
	_disc(Vector2(41, 47), 4.5, Lagoon.ABYSS, 0.0)
	# The slot in its back and the coin going into it -- the two marks that make
	# a pink animal a piggy BANK. Kept toward the middle: at 40px in a top bar
	# anything within six units of the edge is the first thing to be lost.
	_shape(_round_rect(Vector2(54, 31), Vector2(28, 8), 4.0, -0.16), Lagoon.ABYSS, 4.0, Lagoon.ABYSS)
	_disc(Vector2(66, 16), 12, Lagoon.BRASS, 5.0, Lagoon.BRASS_LO)
	_shape(_star_pts(Vector2(66, 16), 6.0, 2.6), Lagoon.BRASS_HI, 2.0, Lagoon.BRASS_MID)
	# curl of tail
	draw_arc(Vector2(82, 48), 9, PI * 0.85, PI * 2.35, 14, PIG_LO, 5.0, true)
	_spec(Vector2(52, 56), 24, 0.55)

# A crate of cards. The spares screen, the box shelf and the dock button all
# used a brown package emoji for this.
func _box() -> void:
	var lid := _round_rect(Vector2(50, 33), Vector2(74, 20), 5.0)
	_shape(lid, Lagoon.BRASS_HI, 6.0, Lagoon.BRASS_LO)
	var body := _round_rect(Vector2(50, 62), Vector2(66, 42), 6.0)
	_shape(body, _hue(Lagoon.BRASS), 6.0, Lagoon.BRASS_LO)
	# strap down the front, so the crate reads as closed rather than as a block
	_bar(Vector2(50, 43), Vector2(50, 84), 12.0, Lagoon.BRASS_MID, 4.0)
	# two cards peeking out of the lid
	for spec in [[-1.0, -0.22], [1.0, 0.22]]:
		var dir: float = spec[0]
		var rot: float = spec[1]
		_shape(_round_rect(Vector2(50 + 15 * dir, 20), Vector2(22, 30), 4.0, rot),
			Lagoon.SHELL, 5.0, Lagoon.INK_SOFT)
	_spec(Vector2(50, 62), 26, 0.35)

# The podium places. Three medals in one glyph, told apart by `tint` -- gold,
# silver and bronze are values of the same object, not three objects.
# SMALL RIBBON, BIG DISC, and the proportions are the whole point of the glyph.
#
# One shape serves gold, silver and bronze -- the metal arrives as `tint`. That
# only works if the metal is most of what you see, and it was not: the two
# ribbons were drawn 30 units wide against a 30-unit disc, in coral, which is
# the same coral whichever place the row is. On the tournament board the glyph
# is 52px in a rank cell, and at that size the first three rows all read as "a
# red bow" -- the one thing the icon exists to say was carried by the smallest
# part of it. The ribbon is a fifth of the object now and the disc is most of
# it, so the three places separate at a glance.
func _medal() -> void:
	var metal := _hue(Lagoon.BRASS)
	for side in [-1.0, 1.0]:
		_shape(PackedVector2Array([
			Vector2(50, 14), Vector2(50 + 15 * side, 4), Vector2(50 + 23 * side, 17),
			Vector2(50 + 10 * side, 25)]), Lagoon.CORAL, 4.0, Lagoon.CORAL_LO)
	_disc(Vector2(50, 60), 38, metal, 6.0, metal.darkened(0.45))
	_disc(Vector2(50, 60), 27, metal.lightened(0.28), 4.0, metal.darkened(0.25))
	_shape(_star_pts(Vector2(50, 60), 17, 7.0), metal.lightened(0.55), 3.0, metal.darkened(0.35))
	_spec(Vector2(50, 60), 30, 0.55)

func _tick() -> void:
	var c := _hue(Lagoon.KELP)
	_disc(Vector2(50, 50), 42, c, 6.0, Lagoon.KELP_LO)
	var pts := PackedVector2Array([Vector2(30, 52), Vector2(44, 66), Vector2(72, 34)])
	draw_polyline(pts, Lagoon.KELP_LO, 15.0, true)
	draw_polyline(pts, Color.WHITE, 9.0, true)

func _spark() -> void:
	var c := _hue(Lagoon.BRASS_HI)
	_shape(_star_pts(Vector2(50, 48), 44, 12, 4), c, 5.0, Lagoon.BRASS_MID)
	_shape(_star_pts(Vector2(80, 78), 17, 5, 4), c, 3.0, Lagoon.BRASS_MID)

func _crown() -> void:
	var c := _hue(Lagoon.BRASS)
	_shape(PackedVector2Array([
		Vector2(18, 72), Vector2(22, 30), Vector2(36, 48), Vector2(50, 22),
		Vector2(64, 48), Vector2(78, 30), Vector2(82, 72),
	]), c, 6.0, Lagoon.BRASS_LO)
	_shape(_round_rect(Vector2(50, 78), Vector2(66, 14), 5.0), Lagoon.BRASS_MID, 5.0, Lagoon.BRASS_LO)
	for x in [22.0, 50.0, 78.0]:
		_disc(Vector2(x, 22.0 if is_equal_approx(x, 50.0) else 30.0), 7,
			Lagoon.CORAL, 4.0, Lagoon.CORAL_LO)

func _sun() -> void:
	var c := _hue(Lagoon.BRASS_HI)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		_bar(Vector2(50, 50) + dir * 30.0, Vector2(50, 50) + dir * 44.0, 9.0, Lagoon.BRASS, 4.0)
	_disc(Vector2(50, 50), 27, c, 6.0, Lagoon.BRASS_LO)
	_spec(Vector2(50, 50), 20, 0.6)

func _moon() -> void:
	# A CRESCENT IS A SHAPE, NOT A SUBTRACTION.
	#
	# The first version drew a full disc and then covered part of it with a
	# second disc in the page colour. That only works if you know what the page
	# colour is, and an icon does not -- on a white card the "bite" rendered as
	# a solid dark circle sitting on top of the moon. Built from two arcs into
	# one polygon, it is a crescent on any background.
	var c := _hue(Lagoon.SHELL)
	var pts := PackedVector2Array()
	for i in 25:
		var a := -PI * 0.5 + PI * float(i) / 24.0
		pts.append(Vector2(50, 50) + Vector2(cos(a), sin(a)) * 40.0)
	for i in 25:
		var a := PI * 0.5 - PI * float(i) / 24.0
		pts.append(Vector2(74, 50) + Vector2(cos(a), sin(a)) * 40.0)
	_shape(pts, c, 6.0, Lagoon.INK_SOFT)
	_disc(Vector2(38, 40), 5, Lagoon.INK_FAINT, 0.0)
	_disc(Vector2(33, 60), 3.5, Lagoon.INK_FAINT, 0.0)

func _calendar() -> void:
	var body := _round_rect(Vector2(50, 56), Vector2(72, 66), 8.0)
	_shape(body, _hue(Lagoon.SHELL), 6.0, Lagoon.INK_SOFT)
	var head := _round_rect(Vector2(50, 32), Vector2(72, 18), 6.0)
	_shape(head, Lagoon.CORAL, 5.0, Lagoon.CORAL_LO)
	for x in [34.0, 66.0]:
		_bar(Vector2(x, 16), Vector2(x, 30), 8.0, Lagoon.BRASS, 4.0)
	for row in [56.0, 74.0]:
		for col in [34.0, 50.0, 66.0]:
			_disc(Vector2(col, row), 5.0, Lagoon.INK_FAINT, 0.0)

func _warn() -> void:
	var c := _hue(Lagoon.REEF)
	_shape(PackedVector2Array([Vector2(50, 12), Vector2(92, 84), Vector2(8, 84)]), c, 7.0, Lagoon.REEF_LO)
	_bar(Vector2(50, 38), Vector2(50, 62), 11.0, Color.WHITE, 0.0)
	_disc(Vector2(50, 73), 6.0, Color.WHITE, 0.0)

# =============================================================================
#  Placing a glyph inside a control
# =============================================================================

# Drops a glyph into `parent`, filling it with an equal inset on all four sides.
#
# WHY THIS EXISTS, AND WHY EVERY ANCHORED GLYPH SHOULD GO THROUGH IT.
#
# `_init` gives every glyph a 40x40 minimum so one added to a container cannot
# collapse to nothing. Anchored inside a small button that minimum is poison:
# ask for a 32x32 box and Control clamps the size back up to 40x40 while keeping
# the *position* the offsets gave it -- so the icon grows down and right out of
# the middle of the disc it is supposed to be centred in. That is the crooked
# "+" on the coin capsule and the crooked "X" on every dialog, and both were
# diagnosed and patched one at a time before this existed. Anchored placement
# only governs if the minimum gets out of the way.
#
# The inset is one number on purpose. `_draw` scales the 100x100 artwork
# uniformly and centres it in whatever box it is given, so an inset that is
# deeper on one side than the other does not shift the drawing -- it makes the
# box non-square, which shrinks the drawing and then centres it in a box whose
# middle is no longer the button's middle. Both crooked icons were that bug
# twice over.
static func fill(parent: Control, kind_name: String, inset := 0.0,
		tint_color := Color(0, 0, 0, 0)) -> Glyph:
	var g := Glyph.new()
	g.kind = kind_name
	if tint_color.a > 0.0:
		g.tint = tint_color
	g.custom_minimum_size = Vector2.ZERO
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(g)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.offset_left = inset
	g.offset_right = -inset
	g.offset_top = inset
	g.offset_bottom = -inset
	return g
