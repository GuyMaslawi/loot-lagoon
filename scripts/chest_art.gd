class_name ChestArt
extends Control

# =============================================================================
#  The three chests — one silhouette per tier, not one sprite in three tints
# =============================================================================
#
# The shop sold three chests and drew them with a single PNG modulated by a
# per-tier colour. On the page that is three of the same object under three
# lighting gels: the row that has to say "each of these is worth more than the
# one to its left" said it with a tag, a price, and a barely different brown.
#
# So each tier is its own object, and the ladder is carried by the things the
# eye sorts first -- silhouette, material, and light:
#
#   0  Wooden   plain boards, black iron, a closed lid, no light of its own
#   1  Golden   the same box under wide polished brass, a jewelled lock, shut
#                but glinting
#   2  Magical  violet wood and arcane metal, lid standing open with the light
#                coming out of it
#
# The closed/closed/open break is deliberate: it is the only difference that
# survives being 110 units wide on a phone, because it changes the outline
# rather than the fill.
#
# Drawn in a 200x200 space with a uniform scale, like the rest of the drawn
# art, so one implementation covers the shop row, the confirm dialog and the
# free-box shelf.

const SPACE := 200.0

# Which chest. 0..2, clamped -- an out-of-range tier draws the wooden one
# rather than nothing, because a shelf with a hole in it is worse than a shelf
# with a plain box on it.
@export_range(0, 2) var tier := 0:
	set(value):
		tier = clampi(value, 0, 2)
		queue_redraw()

# --- per-tier materials ------------------------------------------------------
#
# Two colours for the wood and three for the metal, which between them are the
# whole difference between the tiers. Everything else -- the joinery, the
# rivets, the lock -- is the same construction three times.

const WOOD := [
	[Color(0.639, 0.443, 0.259), Color(0.365, 0.227, 0.129)],   # oak
	[Color(0.478, 0.259, 0.169), Color(0.239, 0.118, 0.086)],   # dark stained
	[Color(0.286, 0.204, 0.408), Color(0.129, 0.086, 0.220)],   # violet heart
]
const METAL_HI := [
	Color(0.671, 0.694, 0.729), Lagoon.BRASS_HI, Color(0.800, 0.678, 1.000)]
const METAL := [
	Color(0.404, 0.435, 0.478), Lagoon.BRASS, Color(0.549, 0.376, 0.878)]
const METAL_LO := [
	Color(0.176, 0.204, 0.243), Lagoon.BRASS_LO, Color(0.243, 0.129, 0.412)]
const GEM := [
	Color(0.541, 0.639, 0.706), Lagoon.CORAL, Color(0.694, 0.898, 1.000)]

const INK := Color(0.086, 0.063, 0.086)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(90, 90)

func _ready() -> void:
	resized.connect(queue_redraw)

# --- primitives --------------------------------------------------------------

func _round_rect(center: Vector2, box: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var h := box * 0.5
	var r := minf(radius, minf(h.x, h.y))
	for c in [[Vector2(h.x - r, h.y - r), 0.0], [Vector2(-h.x + r, h.y - r), PI * 0.5],
			[Vector2(-h.x + r, -h.y + r), PI], [Vector2(h.x - r, -h.y + r), PI * 1.5]]:
		var pivot: Vector2 = c[0]
		var start: float = c[1]
		for i in 5:
			var a: float = start + PI * 0.5 * (float(i) / 4.0)
			pts.append(center + pivot + Vector2(cos(a), sin(a)) * r)
	return pts

# A linear ramp across a polygon, exactly. Colour is a linear function of the
# projection onto `dir`, and barycentric interpolation of a linear function is
# that same function -- so this is a true gradient rather than the stack of
# shrinking shapes a radial one needs.
func _grad(pts: PackedVector2Array, dir: Vector2, c0: Color, c1: Color) -> void:
	var lo := INF
	var hi := -INF
	for p in pts:
		var d := p.dot(dir)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var span := maxf(hi - lo, 0.001)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(c0.lerp(c1, (p.dot(dir) - lo) / span))
	draw_polygon(pts, cols)

func _outline(pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, col, w, true)

# A metal band: dark base, lit face, one specular line along the top. Used for
# every strap, hinge and corner cap in the set, which is what keeps the three
# chests looking like three chests rather than three drawings.
func _band(center: Vector2, box: Vector2, radius := 3.0) -> void:
	var outer := _round_rect(center, box + Vector2(4, 4), radius + 2.0)
	draw_colored_polygon(outer, METAL_LO[tier])
	var face := _round_rect(center, box, radius)
	_grad(face, Vector2(0, 1), METAL_HI[tier], METAL[tier])
	draw_line(center + Vector2(-box.x * 0.4, -box.y * 0.28),
		center + Vector2(box.x * 0.4, -box.y * 0.28),
		Color(1, 1, 1, 0.35), maxf(box.y * 0.12, 1.5), true)

func _rivet(p: Vector2, r := 3.4) -> void:
	draw_circle(p, r + 1.0, METAL_LO[tier])
	draw_circle(p, r, METAL[tier])
	draw_circle(p - Vector2(r * 0.3, r * 0.3), r * 0.45, METAL_HI[tier])

func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + PI * float(i) / 4.0
		var rr := r if i % 2 == 0 else r * 0.32
		pts.append(c + Vector2(cos(a) * rr, sin(a) * rr))
	draw_colored_polygon(pts, col)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var s := minf(size.x, size.y) / SPACE
	var off := (size - Vector2(SPACE, SPACE) * s) * 0.5
	draw_set_transform(off, 0.0, Vector2(s, s))

	if tier == 2:
		_aura()
	_shadow()
	if tier == 2:
		_open_lid()
		_hold()
	else:
		_closed_lid()
	_body()
	if tier == 2:
		_beam()
		_runes()
	_lock()
	if tier == 1:
		_glints()

func _shadow() -> void:
	for spec in [[1.24, 0.07], [1.05, 0.09], [0.86, 0.13]]:
		var k: float = spec[0]
		var a: float = spec[1]
		var pts := PackedVector2Array()
		for i in 30:
			var ang := TAU * float(i) / 30.0
			pts.append(Vector2(100, 172) + Vector2(cos(ang) * 72.0 * k, sin(ang) * 10.0 * k))
		draw_colored_polygon(pts, Color(0.06, 0.04, 0.08, a))

# The box itself: boards running across, two straps down the front, a capped
# corner at each end, and feet.
func _body() -> void:
	var box := _round_rect(Vector2(100, 130), Vector2(150, 68), 8.0)
	_grad(box, Vector2(0, 1), WOOD[tier][0], WOOD[tier][1])
	# board seams. Drawn as a light line over a dark one so a plank has a lit
	# top edge -- the same rule the rest of the game's objects follow.
	for y in [116.0, 134.0, 152.0]:
		draw_line(Vector2(30, y), Vector2(170, y), WOOD[tier][1].darkened(0.25), 3.0, true)
		draw_line(Vector2(30, y + 2.5), Vector2(170, y + 2.5), Color(1, 1, 1, 0.10), 2.0, true)
	# the shade the lid throws on the top boards
	draw_line(Vector2(30, 100), Vector2(170, 100), Color(0, 0, 0, 0.35), 9.0, true)
	_outline(box, INK, 4.5)

	# feet
	for x in [42.0, 158.0]:
		var foot := _round_rect(Vector2(x, 166), Vector2(26, 12), 4.0)
		_grad(foot, Vector2(0, 1), METAL[tier], METAL_LO[tier])
		_outline(foot, INK, 3.0)

	# straps and corner caps
	for x in [62.0, 138.0]:
		_band(Vector2(x, 130), Vector2(15, 66), 3.0)
		_rivet(Vector2(x, 108))
		_rivet(Vector2(x, 152))
	for spec in [[30.0, 1.0], [170.0, -1.0]]:
		var x: float = spec[0]
		var dir: float = spec[1]
		_band(Vector2(x + 5.0 * dir, 130), Vector2(16, 70), 4.0)

# A domed lid, shut. Boards curving over the top, a brass rim where it meets
# the box, and a hinge at each end.
func _closed_lid() -> void:
	var dome := PackedVector2Array()
	for i in 33:
		var a := PI + PI * float(i) / 32.0
		dome.append(Vector2(100, 98) + Vector2(cos(a) * 78.0, sin(a) * 48.0))
	dome.append(Vector2(178, 98))
	dome.append(Vector2(22, 98))
	_grad(dome, Vector2(0.35, 1.0).normalized(), WOOD[tier][0].lightened(0.12), WOOD[tier][1])
	# two seams following the curve, so the lid reads as staved rather than as
	# a solid cap
	for k in [0.42, 0.74]:
		var seam := PackedVector2Array()
		for i in 21:
			var a := PI + PI * float(i) / 20.0
			seam.append(Vector2(100, 98) + Vector2(cos(a) * 78.0 * k, sin(a) * 48.0 * k))
		draw_polyline(seam, WOOD[tier][1].darkened(0.2), 2.5, true)
	_outline(dome, INK, 4.5)
	# the lit crown
	var crown := PackedVector2Array()
	for i in 17:
		var a := PI * 1.18 + PI * 0.5 * float(i) / 16.0
		crown.append(Vector2(100, 98) + Vector2(cos(a) * 70.0, sin(a) * 42.0))
	draw_polyline(crown, Color(1, 1, 1, 0.30), 5.0, true)

	# bands over the lid, following its curve
	for cx_v in [62.0, 138.0]:
		var cx: float = cx_v
		var t := (cx - 100.0) / 78.0
		var top := Vector2(cx, 98.0 - 48.0 * sqrt(maxf(1.0 - t * t, 0.0)))
		var strap := PackedVector2Array([
			Vector2(cx - 8, 98), Vector2(cx - 7, top.y + 6), Vector2(cx, top.y),
			Vector2(cx + 7, top.y + 6), Vector2(cx + 8, 98)])
		_grad(strap, Vector2(1, 0), METAL[tier], METAL_HI[tier])
		_outline(strap, METAL_LO[tier], 2.5)
	# the rim the lid closes onto
	_band(Vector2(100, 98), Vector2(158, 12), 4.0)
	for x in [40.0, 100.0, 160.0]:
		_rivet(Vector2(x, 98), 3.0)

# Tier 2 stands open. The lid is thrown back and up, foreshortened, so the box
# gains a mouth -- which is the change to the outline that lets this chest be
# told from the other two at any size.
func _open_lid() -> void:
	var dome := PackedVector2Array()
	for i in 33:
		var a := PI + PI * float(i) / 32.0
		dome.append(Vector2(100, 72) + Vector2(cos(a) * 74.0, sin(a) * 32.0))
	dome.append(Vector2(174, 72))
	dome.append(Vector2(26, 72))
	_grad(dome, Vector2(0, 1), WOOD[tier][1], WOOD[tier][0])
	_outline(dome, INK, 4.0)
	# the underside of the lid, lit by whatever is in the box
	var inner := PackedVector2Array()
	for i in 25:
		var a := TAU * float(i) / 24.0
		inner.append(Vector2(100, 74) + Vector2(cos(a) * 66.0, sin(a) * 9.0))
	_grad(inner, Vector2(0, 1), METAL_HI[tier].lerp(Color.WHITE, 0.4), METAL_LO[tier])
	# hinges, standing between the thrown-back lid and the box -- without them
	# the lid reads as a separate object floating above a crate
	for cx in [62.0, 138.0]:
		_band(Vector2(cx, 58), Vector2(13, 26), 3.0)
		_band(Vector2(cx, 86), Vector2(11, 24), 3.0)

# The dark inside of an open chest, with the top of the hoard showing.
func _hold() -> void:
	var mouth := PackedVector2Array()
	for i in 25:
		var a := TAU * float(i) / 24.0
		mouth.append(Vector2(100, 94) + Vector2(cos(a) * 72.0, sin(a) * 15.0))
	draw_colored_polygon(mouth, Color(0.08, 0.05, 0.12))
	# gold breaking the surface. Drawn above y=96, because the box's front wall
	# is drawn next and everything below that line is behind it.
	for spec in [[Vector2(72, 88), 12.0], [Vector2(100, 92), 14.0], [Vector2(126, 87), 11.0],
			[Vector2(50, 92), 9.0], [Vector2(148, 92), 10.0]]:
		var c: Vector2 = spec[0]
		var r: float = spec[1]
		draw_circle(c, r, Lagoon.BRASS_LO)
		draw_circle(c, r * 0.84, Lagoon.BRASS)
		draw_circle(c - Vector2(r * 0.25, r * 0.3), r * 0.4, Lagoon.BRASS_HI)

# A cone of light out of the open box, and what it is carrying. Alpha rather
# than an additive material, because this is drawn on a card whose colour is
# not ours to blow out.
func _beam() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(62, 96), Vector2(138, 96), Vector2(172, 2), Vector2(28, 2)]),
		Color(0.847, 0.769, 1.000, 0.18))
	draw_colored_polygon(PackedVector2Array([
		Vector2(78, 96), Vector2(122, 96), Vector2(146, 6), Vector2(54, 6)]),
		Color(0.988, 0.949, 1.000, 0.18))
	for spec in [[Vector2(66, 46), 10.0], [Vector2(132, 34), 8.0], [Vector2(100, 20), 11.0],
			[Vector2(148, 68), 7.0], [Vector2(48, 76), 6.0]]:
		var c: Vector2 = spec[0]
		var r: float = spec[1]
		_star(c, r, Color(1, 1, 1, 0.92))
		_star(c, r * 0.55, Color(1.0, 0.95, 0.75, 1.0))

# Arcane marks on the front boards. Two, small, and in the only bare wood the
# front has -- between the lock plate and the straps. Put anywhere wider they
# land on a metal fitting and read as a crosshair rather than as a rune.
func _runes() -> void:
	var glow := Color(0.906, 0.855, 1.000, 0.92)
	for spec in [[Vector2(75, 142), 8.0], [Vector2(125, 142), 8.0]]:
		var c: Vector2 = spec[0]
		var r: float = spec[1]
		# an angular sigil: a chevron under a crossbar. A circle with a cross
		# through it, which is what this was, reads as a control-pad button.
		draw_polyline(PackedVector2Array([
			c + Vector2(-r, -r * 0.7), c + Vector2(0, r), c + Vector2(r, -r * 0.7)]),
			glow, 3.0, true)
		draw_line(c + Vector2(-r * 0.8, -r), c + Vector2(r * 0.8, -r), glow, 3.0, true)

# The lock plate, and the one place each tier is allowed a jewel.
func _lock() -> void:
	var plate := _round_rect(Vector2(100, 126), Vector2(34, 40), 6.0)
	_grad(plate, Vector2(0, 1), METAL_HI[tier], METAL_LO[tier])
	_outline(plate, INK, 3.5)
	for p in [Vector2(88, 112), Vector2(112, 112), Vector2(88, 140), Vector2(112, 140)]:
		_rivet(p, 2.6)
	if tier == 0:
		# iron chests get a keyhole, not a gem
		draw_circle(Vector2(100, 122), 5.0, INK)
		draw_colored_polygon(PackedVector2Array([
			Vector2(97, 124), Vector2(103, 124), Vector2(105, 136), Vector2(95, 136)]), INK)
		return
	var g: Color = GEM[tier]
	var facets := PackedVector2Array([
		Vector2(100, 112), Vector2(112, 124), Vector2(100, 140), Vector2(88, 124)])
	draw_colored_polygon(facets, g)
	_outline(facets, g.darkened(0.45), 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(100, 115), Vector2(107, 123), Vector2(100, 127), Vector2(94, 123)]),
		g.lightened(0.55))

# A soft violet halo, so the magical chest is lit before you reach its label.
func _aura() -> void:
	for spec in [[86.0, 0.10], [66.0, 0.10], [46.0, 0.10]]:
		var r: float = spec[0]
		var a: float = spec[1]
		var pts := PackedVector2Array()
		for i in 34:
			var ang := TAU * float(i) / 34.0
			pts.append(Vector2(100, 104) + Vector2(cos(ang) * r * 1.05, sin(ang) * r))
		draw_colored_polygon(pts, Color(0.667, 0.494, 1.000, a))

# Two crossed glints on the brass, the mark that says polished.
func _glints() -> void:
	for spec in [[Vector2(150, 76), 12.0], [Vector2(58, 118), 8.0]]:
		var c: Vector2 = spec[0]
		var r: float = spec[1]
		_star(c, r, Color(1, 1, 1, 0.85))
