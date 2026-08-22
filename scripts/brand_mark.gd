class_name BrandMark
extends Control

# =============================================================================
#  Sign-in marks — the three logos the game is not allowed to redesign
# =============================================================================
#
# Everything else in the chrome goes through Glyph, which bends every icon to
# one light direction, one line weight and one warm outline. These three must
# not be bent. A player recognises the Google G before they read the word next
# to it, and a G in lagoon teal with a brass rim is a G nobody trusts -- which
# is the opposite of what a sign-in button is for. Apple, Google and Meta all
# say the same thing in their brand terms: exact colours, exact proportions,
# no restyling.
#
# So this is a second, deliberately plain drawing surface. No outlines, no
# bevels, no tint override. Authored in the same 100x100 space as Glyph purely
# so the two scale identically inside a button.
#
# Fidelity note: these are drawn from the published geometry rather than
# shipped as bitmaps, because a PNG of a logo goes stale at every rebrand and
# blurs at every size. If Apple ever asks for their own asset -- their terms
# prefer it -- the honest fix is to drop their SVG into assets/art and swap
# _apple() for a TextureRect, not to argue.

const SPACE := 100.0

const G_BLUE := Color("#4285F4")
const G_GREEN := Color("#34A853")
const G_YELLOW := Color("#FBBC05")
const G_RED := Color("#EA4335")

@export var kind := "google":
	set(value):
		kind = value
		queue_redraw()

# Only the marks that are a silhouette rather than fixed colours: the Apple
# logo and the Facebook f take the colour of whatever they sit on.
@export var ink := Color.WHITE:
	set(value):
		ink = value
		queue_redraw()

# What the bite is cut out of. The apple is drawn solid and the bite painted
# back in the button's own face colour, which is exact as long as the mark
# sits under the gloss rather than over it -- see _provider_button.
@export var behind := Color.BLACK:
	set(value):
		behind = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(40, 40)

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var s := minf(size.x, size.y) / SPACE
	var off := (size - Vector2(SPACE, SPACE) * s) * 0.5
	draw_set_transform(off, 0.0, Vector2(s, s))
	match kind:
		"google":   _google()
		"apple":    _apple()
		"facebook": _facebook()

# --- Google ------------------------------------------------------------------
#
# A ring of four arcs with the mouth open at the right, and a blue bar running
# in from the outer edge to the centre. Colours are Google's four hex values,
# unmodified. Angles are clockwise from 3 o'clock, which is Godot's own
# convention, so the numbers below read as clock positions: red owns the top,
# yellow the left, green the bottom, blue the right plus the bar.
func _google() -> void:
	var c := Vector2(50, 50)
	var outer := 46.0
	var w := 21.0
	var mid := outer - w * 0.5
	var arcs := [
		[40.0, 145.0, G_GREEN],    # 4 o'clock round the bottom to 8
		[145.0, 216.0, G_YELLOW],  # 8 up the left side to 10
		[216.0, 306.0, G_RED],     # 10 over the top to 1
		[306.0, 360.0, G_BLUE],    # 1 down the right to 3
	]
	for a in arcs:
		draw_arc(c, mid, deg_to_rad(a[0]), deg_to_rad(a[1]), 48, a[2], w, true)
	# The crossbar. Its top edge sits on the centre line rather than straddling
	# it -- that is what opens the mouth underneath and leaves the G a G rather
	# than an O with a stripe through it.
	draw_rect(Rect2(50.0, 50.0, outer, w), G_BLUE)

# --- Apple -------------------------------------------------------------------
#
# Two lobes meeting in a notch, a bite out of the right, and a leaf. Built as a
# smooth curve rather than a point soup so it stays round at 24px in a button
# and at 120px in a splash.
func _apple() -> void:
	draw_colored_polygon(_smooth([
		[Vector2(50, 40), Vector2(-10, -8), Vector2(10, -8)],    # the notch
		[Vector2(70, 28), Vector2(-8, -5), Vector2(11, 6)],      # right lobe
		[Vector2(87, 52), Vector2(0, -10), Vector2(0, 12)],
		[Vector2(73, 88), Vector2(8, -12), Vector2(-7, 7)],
		[Vector2(50, 97), Vector2(10, 0), Vector2(-10, 0)],
		[Vector2(27, 88), Vector2(7, 7), Vector2(-8, -12)],
		[Vector2(13, 52), Vector2(0, 12), Vector2(0, -10)],
		[Vector2(30, 28), Vector2(-11, 6), Vector2(8, -5)],      # left lobe
	]), ink)
	# The bite, painted back in the face colour. Shoulder height on the right,
	# and deep enough to be a bite -- a shallow one just reads as a dent.
	draw_circle(Vector2(91, 47), 17.0, behind)
	# The leaf: a lens on the axis from the notch up to the right, sharp at both
	# ends and bulging between them. Both tips are hard corners, which is what
	# stops it rendering as a horn growing out of the fruit.
	draw_colored_polygon(_smooth([
		[Vector2(82, 1), Vector2(0, 0), Vector2(0, 0)],          # tip
		[Vector2(73, 21), Vector2(5, -8), Vector2(-5, 6)],       # outer edge
		[Vector2(55, 31), Vector2(0, 0), Vector2(0, 0)],         # base
		[Vector2(64, 11), Vector2(-4, 6), Vector2(4, -6)],       # inner edge
	]), ink)

# --- Facebook ----------------------------------------------------------------
#
# The f alone, no blue disc: the button is already the disc, and Meta's own
# guidance is that the mark sits on the brand colour rather than carrying a
# second one inside it.
func _facebook() -> void:
	draw_colored_polygon(_smooth([
		[Vector2(74, 8), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(74, 26), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(64, 26), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(56, 34), Vector2(0, -4), Vector2(0, 2)],
		[Vector2(56, 44), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(73, 44), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(70, 62), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(56, 62), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(56, 96), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(37, 96), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(37, 62), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(26, 62), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(26, 44), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(37, 44), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(37, 32), Vector2(0, 0), Vector2(0, 0)],
		[Vector2(50, 9), Vector2(-6, 10), Vector2(7, -6)],
	]), ink)

# Curve2D does the rounding, so a shape is described by where it turns rather
# than by fifty points along the way. Entries are [position, in, out]; a pair
# of zero tangents is a hard corner, which is most of the f.
func _smooth(points: Array) -> PackedVector2Array:
	var curve := Curve2D.new()
	for p in points:
		curve.add_point(p[0], p[1], p[2])
	curve.add_point(points[0][0], points[0][1], points[0][2])
	return curve.tessellate(5, 2.0)
