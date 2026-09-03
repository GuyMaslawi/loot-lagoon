class_name PiggyArt
extends Control

# =============================================================================
#  The piggy bank — the character, not the icon
# =============================================================================
#
# There are two pigs in this game and they are not the same drawing. `Glyph`
# has one: forty pixels in a side rail, where the only job is "pink animal,
# coin slot, findable in a row of brass". This is the other one, and it is the
# one the player actually looks at -- a 300-unit object on its own screen, held
# still while they decide whether to spend money.
#
# A glyph blown up to 300 is what that screen used to be, and it read as
# clip art: flat fills, one line weight, a shape with no volume and no face.
# So this is drawn as an object rather than as a symbol:
#
#   * volume from a real gradient. Every rounded part is a stack of ellipses
#     shrinking toward a light point up and to the left, so the pig is lit from
#     the same direction as everything else in the game and reads as ceramic
#     rather than as a pink circle.
#   * an edge on both sides. A warm dark contour all the way round, a white
#     specular rim on the lit side, and a cool bounce along the shadowed side,
#     which is what keeps a bright object off a bright card.
#   * coins you can see through it. The whole mechanic is "the money in here
#     is already yours", and a bar under a picture says that in words. A
#     translucent bank with a real heap rising inside it says it as a picture
#     -- and gives the fill something to animate into.
#   * a face that answers. Empty, filling and full are three different
#     expressions, because the one question this screen has to answer at a
#     glance is which of the three you are looking at.
#
# Authored in a 200x200 space and drawn with a uniform scale, so the same code
# serves the 300 on the piggy screen and the 120 in the confirm dialog.

const SPACE := 200.0

# Ceramic pink. Five values rather than three: a gradient needs somewhere to
# travel, and the two ends do the work the outline used to do on its own.
const HI    := Color(1.000, 0.882, 0.902)
const PINK  := Color(0.988, 0.702, 0.769)
const MID   := Color(0.933, 0.502, 0.612)
const LO    := Color(0.769, 0.310, 0.443)
const INK   := Color(0.404, 0.129, 0.239)

const BLUSH := Color(0.949, 0.400, 0.478, 0.55)

# The hoard. Its own two values rather than the brass the chrome is drawn in:
# it is seen through a pink wall, and brass behind pink comes out as
# gingerbread unless it starts warmer and brighter than brass does.
const GOLD_HI := Color(1.000, 0.871, 0.400)
const GOLD_LO := Color(0.706, 0.412, 0.075)

# How full the bank is, 0..1. Drives the coin level inside the ceramic and,
# at the two ends, the face. Animated by whoever owns the node -- see
# main.gd's piggy screen, which fills it from empty on every open so the
# player watches the ground they gained arrive.
@export_range(0.0, 1.0) var fill := 0.0:
	set(value):
		fill = clampf(value, 0.0, 1.0)
		queue_redraw()

# Expression override for the odd caller that wants a specific face -- the
# confirm dialog holds the full one whatever the number says, because by then
# the decision has been made and a worried pig is not what to send them off
# with. "" means "read it off `fill`".
@export var face := "":
	set(value):
		face = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, 120)

func _ready() -> void:
	resized.connect(queue_redraw)

# --- the rendered art --------------------------------------------------------
#
# Six Blender renders, one per fill step -- tools/render_props.py builds them.
# The reasoning for going to renders at all is in that file; the reasoning for
# six of them is here.
#
# `fill` is tweened continuously by the piggy screen, and a render is a fixed
# frame, so the two frames either side of the current level are cross-faded.
# That works because consecutive frames are the same object under the same
# light with a slightly larger heap inside -- everything except the gold is
# pixel-identical, so the blend has nothing to smear.
#
# Six is a judgement, not a measurement: the popup fills from empty over 1.05s,
# so six frames is a coin landing roughly every 200ms, which is about the rate
# the coin animation drops them at anyway. If a step ever shows, add frames --
# the count lives in SHOTS here and in TARGETS in tools/render_props.py, and
# nothing else has to change.
#
# The drawing below stays as the fallback, exactly as in ChestArt, and it is
# still the thing that documents what the object is supposed to be.

const SHOTS := 6

static var _shot: Array[Texture2D] = []
static var _shot_read := false

static func _rendered() -> Array[Texture2D]:
	if not _shot_read:
		_shot_read = true
		var got: Array[Texture2D] = []
		for i in SHOTS:
			var t := CV.tex("res://assets/art/props/piggy_%d.png" % i)
			if t == null:          # a partial set is worse than none: the blend
				return _shot       # between a render and a drawing is a smear
			got.append(t)
		_shot = got
	return _shot

func _blit(t: Texture2D, alpha := 1.0) -> void:
	var ts := Vector2(t.get_width(), t.get_height())
	var k := minf(size.x / ts.x, size.y / ts.y)
	var d := ts * k
	draw_texture_rect(t, Rect2((size - d) * 0.5, d), false, Color(1, 1, 1, alpha))

# Full at the top, and "empty" is deliberately not 0 -- a bank holding eleven
# coins out of forty thousand is empty in every sense the face is for.
func mood() -> String:
	if face != "":
		return face
	if fill >= 0.995:
		return "full"
	if fill < 0.06:
		return "empty"
	return "saving"

# --- geometry ---------------------------------------------------------------
#
# One layout, named once, so the coin drop outside this file can aim at the
# slot instead of at a magic number that stops being true the day the pig
# moves.

const BODY_C   := Vector2(104, 110)
const BODY_R   := Vector2(65, 56)
# The hoard lives in the belly rather than in the whole body. Filling the body
# ellipse turned a full bank into a gold pig: at 100% there was no pink left,
# and the character the screen is selling disappeared exactly at the moment it
# was meant to be at its best. Kept clear of the head, so gold never sits
# behind the face.
const BELLY_C  := Vector2(114, 116)
const BELLY_R  := Vector2(44, 44)
const SNOUT_C  := Vector2(36, 120)
const SNOUT_R  := Vector2(24, 20)
const SLOT_C   := Vector2(124, 66)
const EYE_C    := Vector2(64, 90)

# Where a coin has to land to go in, in this control's own coordinates. The
# rendered pig is a different pose from the drawing, so its slot is somewhere
# else -- measured off the render by finding the brass in the top of the frame,
# rather than guessed. Both textures are square and fitted the same way, so one
# off/scale calculation covers both.
const SLOT_SHOT := Vector2(94, 43)

func slot_point() -> Vector2:
	var s := minf(size.x, size.y) / SPACE
	var off := (size - Vector2(SPACE, SPACE) * s) * 0.5
	var p := SLOT_SHOT if not _rendered().is_empty() else SLOT_C
	return off + p * s

# --- primitives -------------------------------------------------------------

func _ell(c: Vector2, r: Vector2, a0 := 0.0, a1 := TAU, n := 44) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a: float = a0 + (a1 - a0) * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

func _fill_ell(c: Vector2, r: Vector2, col: Color) -> void:
	draw_colored_polygon(_ell(c, r), col)

# An exact linear ramp across a polygon: colour is a linear function of the
# projection onto `dir`, and barycentric interpolation of a linear function is
# that same function.
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

func _arc_ell(c: Vector2, r: Vector2, a0: float, a1: float, col: Color, w: float) -> void:
	draw_polyline(_ell(c, r, a0, a1, 24), col, w, true)

# The move the whole drawing is built on: a rounded mass shaded by stacking
# ellipses that shrink toward the light instead of toward their own centre.
# Twenty-two steps is where the banding stops being visible at 300 units and
# the cost is still nothing.
func _mass(c: Vector2, r: Vector2, lo: Color, hi: Color, pull := Vector2(-0.30, -0.34), steps := 22) -> void:
	var light := c + Vector2(r.x * pull.x, r.y * pull.y)
	for i in steps:
		var t := float(i) / float(steps - 1)
		var k := 1.0 - t * 0.88
		_fill_ell(c.lerp(light, t * 0.92), r * k, lo.lerp(hi, sqrt(t)))

# Contour, specular and bounce. Every rounded part gets all three, which is
# what makes the parts look cut from one material.
func _edge(c: Vector2, r: Vector2, w := 4.5, spec := 0.75) -> void:
	draw_polyline(_ell(c, r), INK, w, true)
	_arc_ell(c, r * 0.93, PI * 1.06, PI * 1.60, Color(1, 1, 1, spec), w * 0.85)
	_arc_ell(c, r * 0.93, PI * 0.10, PI * 0.52, Color(1.0, 0.75, 0.80, 0.45), w * 0.7)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var shot := _rendered()
	if not shot.is_empty():
		# `face` is an override for the drawing's three expressions; against the
		# renders it means "hold the full one", which is the frame at the top.
		var lv := 1.0 if face == "full" else fill
		var x := clampf(lv, 0.0, 1.0) * float(SHOTS - 1)
		var i := clampi(int(floor(x)), 0, SHOTS - 2)
		var t := x - float(i)
		_blit(shot[i])
		if t > 0.002:
			_blit(shot[i + 1], t)
		return

	var s := minf(size.x, size.y) / SPACE
	var off := (size - Vector2(SPACE, SPACE) * s) * 0.5
	draw_set_transform(off, 0.0, Vector2(s, s))

	var m := mood()
	_shadow()
	_tail()
	_legs(true)
	_ear()
	_body()
	_hoard()
	_legs(false)
	_slot()
	_snout(m)
	_face(m)
	if m == "full":
		_glints()

# A pig standing on nothing floats. Three ellipses at falling alpha are a
# cheaper blur than a shader and land in the same place visually.
func _shadow() -> void:
	for spec in [[1.30, 0.06], [1.12, 0.08], [0.92, 0.12]]:
		var k: float = spec[0]
		var a: float = spec[1]
		_fill_ell(Vector2(102, 178), Vector2(64 * k, 10 * k), Color(0.10, 0.06, 0.12, a))

# Four trotters. The back pair is drawn before the body and darkened, which is
# the cheapest depth cue there is and the only reason the pig has a far side.
func _legs(back: bool) -> void:
	var xs := [66.0, 128.0] if back else [80.0, 142.0]
	for x_v in xs:
		var x: float = x_v
		var c := Vector2(x, 158.0 if back else 160.0)
		var r := Vector2(15, 19)
		if back:
			_mass(c, r, LO.darkened(0.25), MID.darkened(0.18))
			draw_polyline(_ell(c, r), INK.darkened(0.2), 4.0, true)
		else:
			_mass(c, r, LO, PINK)
			_edge(c, r, 4.0, 0.5)
			# the hoof: a dark band across the foot, which is what stops a leg
			# reading as a sausage
			var hoof := _ell(c + Vector2(0, 11), Vector2(13, 7))
			draw_colored_polygon(hoof, INK.lerp(LO, 0.3))
			draw_polyline(hoof, INK, 3.0, true)

# One ear, and it is the near one. A pig drawn from the side with two ears
# showing has to put the far one somewhere, and everywhere it can go is over
# the face or over the back where the slot is.
func _ear() -> void:
	# Wide and leaning forward, with a rounded tip. The first pass made it tall
	# and narrow and the pig came out wearing a party hat -- an ear is read by
	# its base being as wide as its height, not by its point.
	var pts := PackedVector2Array([
		Vector2(52, 74), Vector2(54, 60), Vector2(60, 46), Vector2(70, 39),
		Vector2(81, 44), Vector2(90, 57), Vector2(94, 76)])
	draw_colored_polygon(pts, MID)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, INK, 4.5, true)
	# inner ear, inset from the outline so the ear has a rim rather than being
	# a flat pink triangle
	draw_colored_polygon(PackedVector2Array([
		Vector2(62, 71), Vector2(64, 58), Vector2(71, 48),
		Vector2(80, 54), Vector2(86, 70)]), LO.lerp(INK, 0.3))

# A curl that starts at the rump and winds outward-in, drawn as a tapering
# path rather than as concentric arcs. Three arcs about one centre came out as
# a rosette stuck to the pig's side -- a tail has to leave the body somewhere.
func _tail() -> void:
	var c := Vector2(178, 82)
	var pts := PackedVector2Array()
	var steps := 30
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := PI + TAU * 1.15 * t
		var r := lerpf(17.0, 3.5, t)
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.92))
	# ink first, at full width, then the pink over it at a width that falls
	# away -- which is what makes the curl taper
	draw_polyline(pts, INK, 9.5, true)
	for i in steps:
		var w := lerpf(6.0, 2.0, float(i) / float(steps))
		draw_line(pts[i], pts[i + 1], MID, w, true)

func _body() -> void:
	_mass(BODY_C, BODY_R, LO, HI)
	# Occlusion where the belly turns away. Without it the gradient reads as a
	# flat pink disc with a white spot on it.
	_arc_ell(BODY_C, BODY_R * 0.90, PI * 0.16, PI * 0.86, LO.lerp(INK, 0.25), 14.0)

# The coins, seen through the ceramic.
#
# This started as a brass-rimmed porthole in the pig's belly, which showed the
# money perfectly and turned the pig into a washing machine: a round window
# with a chrome ring on the front of an animal is an appliance, and no amount
# of shading talks the eye out of it.
#
# So the bank is translucent instead -- frosted rose, the way a real acrylic
# coin bank is -- and the hoard is drawn inside it and then veiled by a wash of
# the body's own colour. The pig keeps one silhouette, the coins read as being
# *in* rather than *on*, and the level has the whole belly to rise through
# instead of a 60-unit disc.
func _hoard() -> void:
	if fill > 0.0:
		var inner := BELLY_R
		var bottom := BELLY_C.y + inner.y

		# A HEAP, NOT A LEVEL.
		#
		# Two earlier passes drew the coins as the fill of a container -- a
		# level line with gold under it -- and both read as a gold sash painted
		# across the pig. A level is what a liquid does; what is in here is
		# coins, and coins make a mound. So the pile keeps its own shape and
		# grows in both directions at once, which is also the only version
		# where a nearly-empty bank looks like a few coins in the bottom rather
		# than like a thin gold stripe.
		var h := 2.0 * inner.y * fill
		var w := inner.x * lerpf(0.55, 1.0, sqrt(fill))
		var crest := PackedVector2Array()
		var floor_edge := PackedVector2Array()
		var n := 22
		for i in n + 1:
			var u := -1.0 + 2.0 * float(i) / float(n)
			var x := BELLY_C.x + w * u
			var f := clampf((w * u) / inner.x, -1.0, 1.0)
			var y_b := BELLY_C.y + inner.y * sqrt(maxf(1.0 - f * f, 0.0))
			floor_edge.append(Vector2(x, y_b))
			crest.append(Vector2(x, y_b - h * pow(cos(u * PI * 0.5), 0.7)))

		var pts := crest.duplicate()
		for i in range(floor_edge.size() - 1, -1, -1):
			pts.append(floor_edge[i])

		# the pile lights the ceramic around it, which is what makes a
		# translucent bank read as holding something rather than as being
		# painted gold below a line
		_fill_ell(Vector2(BELLY_C.x, bottom - h * 0.42), Vector2(w * 1.15, h * 0.7 + 7.0),
			Color(1.0, 0.784, 0.353, 0.22))
		_grad(pts, Vector2(0, 1), GOLD_HI, GOLD_LO)
		# the lit crest, and the shade just under it
		draw_polyline(crest, Color(1.0, 0.965, 0.808), 3.5, true)

		# coins on the surface, spaced along the crest -- a pile is read by the
		# discs on top of it, and the mass alone came out as a gold blob
		var seats := [-0.72, -0.36, 0.0, 0.36, 0.72, -0.54, 0.54]
		var sizes := [7.0, 8.5, 9.0, 8.5, 7.0, 8.0, 8.0]
		for i in seats.size():
			var u: float = seats[i]
			var cr: float = sizes[i]
			var idx := int(round((u + 1.0) * 0.5 * float(n)))
			var seat: Vector2 = crest[clampi(idx, 0, crest.size() - 1)]
			var sink := 0.0 if i < 5 else 15.0
			if h < cr * 1.6 + sink:
				continue
			_coin(seat + Vector2(0, sink + cr * 0.35), cr, 1.0)

		# the ceramic in front of them: a wash of the body's own colour, so the
		# coins sit behind a surface rather than being stuck to it
		_fill_ell(BELLY_C, BELLY_R * 1.06, Color(PINK.r, PINK.g, PINK.b, 0.15))
		_fill_ell(BODY_C.lerp(BODY_C + Vector2(-BODY_R.x * 0.3, -BODY_R.y * 0.34), 0.85),
			BODY_R * 0.34, Color(1, 1, 1, 0.26))
	_edge(BODY_C, BODY_R, 5.0, 0.8)

# A coin on the surface of the pile. It needs a dark rim of its own: gold on
# gold has nothing to separate it, and without the rim the surface coins came
# out as pale smudges rather than as coins.
func _coin(c: Vector2, r: float, a: float) -> void:
	draw_circle(c, r, Color(0.376, 0.208, 0.043, a))
	draw_circle(c, r * 0.86, Color(GOLD_HI.r, GOLD_HI.g, GOLD_HI.b, a))
	draw_circle(c, r * 0.52, Color(GOLD_LO.r, GOLD_LO.g, GOLD_LO.b, a * 0.55))
	draw_circle(c - Vector2(r * 0.24, r * 0.26), r * 0.34, Color(1.0, 0.976, 0.855, a * 0.95))

# The slot, and the two things that make it a slot rather than a black line:
# a brass lip standing proud of the ceramic, and a shadow inside it.
#
# It sits *on* the back rather than above it. Drawn a few units higher it
# floated clear of the silhouette and read as a halo, which is a funny thing
# for a pig that takes your money to be wearing.
func _slot() -> void:
	var w := 27.0
	var h := 6.0
	var rot := -0.15
	var spun := func(pts: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(SLOT_C + (p - SLOT_C).rotated(rot))
		return out
	# the shadow the raised lip casts on the ceramic behind it
	draw_colored_polygon(spun.call(_ell(SLOT_C + Vector2(0, 3.5), Vector2(w + 5.0, h + 5.0))),
		Color(LO.r, LO.g, LO.b, 0.5))
	draw_colored_polygon(spun.call(_ell(SLOT_C, Vector2(w + 4.0, h + 4.0))), Lagoon.BRASS_LO)
	draw_colored_polygon(spun.call(_ell(SLOT_C - Vector2(0, 0.8), Vector2(w + 2.5, h + 2.6))), Lagoon.BRASS)
	draw_polyline(spun.call(_ell(SLOT_C - Vector2(0, 1.6), Vector2(w + 1.0, h + 1.2), PI, TAU, 18)),
		Lagoon.BRASS_HI, 2.0, true)

	draw_colored_polygon(spun.call(_ell(SLOT_C, Vector2(w, h))), Color(0.14, 0.07, 0.12))
	# the lit inside edge of the far wall -- the mark that says "there is a
	# depth in there"
	draw_polyline(spun.call(_ell(SLOT_C + Vector2(0, 1.4), Vector2(w * 0.94, h * 0.45), PI, TAU, 18)),
		Color(0.44, 0.25, 0.33), 2.5, true)

func _snout(m: String) -> void:
	_mass(SNOUT_C, SNOUT_R, LO, HI, Vector2(-0.25, -0.4), 16)
	_edge(SNOUT_C, SNOUT_R, 4.5, 0.7)
	for dy in [-6.5, 6.5]:
		draw_colored_polygon(_ell(SNOUT_C + Vector2(-5, dy), Vector2(3.6, 5.2)), INK)
	# mouth, on the underside of the snout where a pig's is
	match m:
		"full":
			draw_arc(Vector2(50, 142), 12, PI * 0.06, PI * 0.94, 18, INK, 4.0, true)
			draw_colored_polygon(_ell(Vector2(50, 146), Vector2(8, 4.5)), Color(0.85, 0.35, 0.42))
		"empty":
			draw_arc(Vector2(54, 154), 11, PI * 1.12, PI * 1.88, 16, INK, 4.0, true)
		_:
			draw_arc(Vector2(52, 144), 10, PI * 0.12, PI * 0.88, 16, INK, 3.5, true)

# Three faces, and they are the screen's headline. A player who opens this
# should know which of the three states they are in before they have read a
# single number.
func _face(m: String) -> void:
	match m:
		"full":
			# eyes shut, arched up: the only face that reads as delighted at a
			# glance, and it separates instantly from the two open-eyed ones
			draw_arc(EYE_C + Vector2(0, 3), 10, PI * 1.08, PI * 1.92, 16, INK, 5.0, true)
			_blush(Vector2(52, 112), 1.2)
			# brow up and out -- surprise, on a bank that has just filled
			draw_line(Vector2(56, 70), Vector2(76, 66), INK, 4.0, true)
		"empty":
			# half-lidded, brow pitched up at the inside corner: the shape of a
			# disappointed face in every cartoon vocabulary there is
			_eye(EYE_C, 0.42)
			draw_line(Vector2(51, 70), Vector2(78, 80), INK, 5.0, true)
			# One drop, because an empty bank is a joke rather than a problem.
			# Hung off the outer corner of the eye: out on the flank it read as
			# a blue gem stuck to the pig rather than as a tear.
			var drop := PackedVector2Array([
				Vector2(77, 100), Vector2(82, 110), Vector2(77, 118), Vector2(72, 110)])
			draw_colored_polygon(drop, Color(0.55, 0.82, 0.94, 0.85))
			draw_polyline(drop, Color(0.25, 0.5, 0.65, 0.9), 2.0, true)
		_:
			_eye(EYE_C, 1.0)
			draw_line(Vector2(54, 72), Vector2(75, 70), INK, 4.0, true)
			_blush(Vector2(52, 112), 0.85)

func _eye(c: Vector2, open: float) -> void:
	var r := Vector2(7.5, 9.0 * open)
	draw_colored_polygon(_ell(c, r + Vector2(1.2, 1.2)), Color(1, 1, 1, 0.5))
	draw_colored_polygon(_ell(c, r), INK.darkened(0.4))
	# catchlight, up and left with the rest of the light in the scene
	draw_circle(c + Vector2(-2.6, -3.4 * open), 3.4 * maxf(open, 0.5), Color(1, 1, 1, 0.92))
	draw_circle(c + Vector2(2.8, 3.4 * open), 1.7, Color(1, 1, 1, 0.5))
	if open < 0.9:
		# the lid, drawn over the top of the eye rather than by shrinking it,
		# so a half-closed eye keeps its width
		draw_line(c + Vector2(-10, -r.y - 1.0), c + Vector2(10, -r.y - 2.0), INK, 4.5, true)

func _blush(c: Vector2, k: float) -> void:
	draw_colored_polygon(_ell(c, Vector2(13, 8) * k), BLUSH)

# Four-point stars off the ceramic, only on the full pig. Small, and none of
# them over the face.
func _glints() -> void:
	for spec in [[Vector2(152, 62), 9.0], [Vector2(26, 96), 6.0], [Vector2(150, 148), 7.0]]:
		var c: Vector2 = spec[0]
		var r: float = spec[1]
		var pts := PackedVector2Array()
		for i in 8:
			var a := -PI * 0.5 + PI * float(i) / 4.0
			var rr := r if i % 2 == 0 else r * 0.3
			pts.append(c + Vector2(cos(a) * rr, sin(a) * rr))
		draw_colored_polygon(pts, Color(1, 1, 1, 0.9))
