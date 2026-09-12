class_name TakeoverSky
extends Control

# =============================================================================
#  The reward backdrop -- the place rewards are opened, not the page behind one
# =============================================================================
#
# Every celebration in this game used to happen on top of whatever page you
# happened to be standing on: a dim wash over the shop's scrolled list, or over
# the spin machine, and the reward opened in front of your own half-read UI.
# That is why the chest opening still read as a popup even after it stopped
# being one -- the backdrop was telling the player "you are in the shop and
# something is covering it", which is the opposite of a takeover.
#
# So a reward gets its OWN place. Deep water, a shaft of light coming down
# through it, and motes drifting up through the shaft. Nothing here says which
# page launched it and nothing here is readable as content, which is the point:
# for the length of the animation the game is somewhere else.
#
# DRAWN, NOT RENDERED. It is a full-screen background that has to sit behind a
# 1024px chest render without competing with it, and it has to work at every
# aspect ratio from a phone to a pad. A painted plate would either tile wrong
# or need six exports; eleven primitives and a phase do not. It also costs no
# Creative Units, which matters while the art budget is going on objects.
#
# Shared by ChestOpen and PayoutShow deliberately -- the box screen and the
# coins screen have to read as two doors into the same room, or they read as
# two features that were built by different people.

# Light sweeps slowly. A fast shaft reads as a searchlight and pulls the eye
# off the object in the middle, which is the one thing the backdrop must not do.
const SWEEP := 0.10

# Kept low on purpose: this draws every frame behind the whole celebration,
# and the difference between eleven shafts and five is invisible while the
# difference in fill cost is not.
const SHAFTS := 5
const MOTES := 22

var tint: Color = Lagoon.LAGOON_DEEP    # the water this reward is opened in
var _t := 0.0
var _seed: Array[float] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Behind the object and its contents, in front of nothing -- the caller
	# parents this first and everything else after it.
	z_index = -1


func _ready() -> void:
	# Fixed offsets rather than randf() per frame: a mote that re-rolls its
	# column every redraw is static noise, not a drifting particle.
	for i in MOTES:
		_seed.append(float(i) * 0.61803399)
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var vs := size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return

	# --- the water -----------------------------------------------------------
	#
	# Vertical bands rather than a shader: dark at the edges, lifting toward the
	# middle where the object stands, so the chest is sitting in the one lit
	# part of the frame and does not need a rim light drawn round it to separate.
	var deep := Color(tint.r * 0.30, tint.g * 0.34, tint.b * 0.40, 0.97)
	var lit := Color(tint.r * 0.92, tint.g * 1.00, tint.b * 1.04, 0.97)
	var bands := 14
	for i in bands:
		var u := float(i) / float(bands - 1)
		# 0 at the top, 1 at the object line (46% down, where ChestOpen lands
		# its chest), back toward 0 at the floor.
		var h := 1.0 - absf(u - 0.46) / 0.54
		var c := deep.lerp(lit, pow(clampf(h, 0.0, 1.0), 2.2) * 0.55)
		draw_rect(Rect2(0.0, vs.y * u - 1.0, vs.x,
			vs.y / float(bands - 1) + 2.0), c)

	# --- the shafts ----------------------------------------------------------
	#
	# Light comes down from above the frame and spreads, so every shaft is a
	# quad that is narrow at the top and wide at the bottom. They sweep across
	# each other at slightly different rates, which is what keeps the backdrop
	# alive without anything in it actually moving.
	for i in SHAFTS:
		var f := float(i)
		var phase := _t * SWEEP + f * 1.37
		var x := vs.x * (0.5 + 0.42 * sin(phase))
		var top := vs.x * 0.035
		var bottom := vs.x * 0.16
		var lean := vs.x * 0.10 * cos(phase * 0.7)
		var a := 0.050 + 0.030 * (0.5 + 0.5 * sin(phase * 1.9))
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - top, -4.0),
			Vector2(x + top, -4.0),
			Vector2(x + bottom + lean, vs.y),
			Vector2(x - bottom + lean, vs.y),
		]), Color(Lagoon.SKY_HI.r, Lagoon.SKY_HI.g, Lagoon.SKY_HI.b, a))

	# --- the motes -----------------------------------------------------------
	#
	# Rising, not falling. Falling specks read as dust in a shut room; rising
	# ones read as water, and they are the only cue that tells the player this
	# backdrop is a place rather than an image.
	for i in MOTES:
		var s := _seed[i]
		var col := fposmod(s * 7.0, 1.0)
		var speed := 0.06 + 0.10 * fposmod(s * 13.0, 1.0)
		var y := fposmod(1.0 - (_t * speed + s), 1.0)
		var r := 1.6 + 3.4 * fposmod(s * 29.0, 1.0)
		# Fade at both ends so a mote is never seen popping into or out of
		# existence at the frame edge.
		var fade := sin(y * PI)
		var px := vs.x * col + sin(_t * 0.5 + s * 6.0) * vs.x * 0.03
		draw_circle(Vector2(px, vs.y * y), r,
			Color(Lagoon.SKY_HI.r, Lagoon.SKY_HI.g, Lagoon.SKY_HI.b,
				0.30 * fade))

	# --- the floor pool ------------------------------------------------------
	#
	# A soft ellipse of light where the object lands. It does the job a cast
	# shadow would do in a 3D scene -- it tells you the chest is standing on
	# something -- and it gives the landing squash a surface to hit.
	var floor_y := vs.y * 0.62
	for i in range(6, 0, -1):
		var k := float(i) / 6.0
		draw_circle(Vector2(vs.x * 0.5, floor_y), vs.x * 0.40 * k,
			Color(Lagoon.SKY_LO.r, Lagoon.SKY_LO.g, Lagoon.SKY_LO.b,
				0.030 * (1.0 - k) + 0.010))
