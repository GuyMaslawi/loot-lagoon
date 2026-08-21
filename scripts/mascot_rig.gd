class_name MascotRig
extends Control

# The raccoon, as a puppet rather than as a picture.
#
# He used to be animated by rotating and squashing the one flat drawing he is,
# which is the thing you cannot un-see once you have seen it: a sticker being
# waggled. So the drawing was cut into fifteen pieces -- two ears, hat, head,
# jaw, two eyes, two pupils, torso, two arms, two legs, tail -- each hung on
# its own joint, and what is animated now are the joints. tools/cut_mascot.py
# does the cutting, and the table below is its output; the half of him the
# coin covers was rebuilt there by mirroring the half it does not.
#
# The division of labour is: Boot owns the *performance* -- which act he is
# doing and how far through it he is -- and writes the channels below once a
# frame. This node owns everything involuntary: breathing, blinking, ear
# flicks, the eyes drifting, and the tail, ears and hat trailing behind
# whatever the body just did. That second half is the one nobody notices while
# it is running and everybody notices when it is missing; it is most of the
# difference between a jointed drawing and something that looks alive.
#
# Two rules hold the whole thing together, and both are about weight:
#   * nothing on him turns. Not the figure, not the chest -- he is one frontal
#     drawing, and a drawing that tips reads as a picture being rotated no
#     matter how carefully it is hinged, which is the amateur tell this rig
#     exists to get rid of. What he has instead is displacement, squash and
#     limbs, which is where the weight reads from anyway;
#   * nothing loose is ever set directly. Ears, tail and hat are springs whose
#     targets are what the body is doing, so they arrive late and overshoot,
#     and he reads as having mass.

const DIR := "res://assets/art/mascot/"
const SRC := 512.0            # the drawing these coordinates were measured in

# How far the two pieces that touch the hat are allowed to travel. Everything
# else on him can swing as far as it likes, because everything else has a real
# silhouette to hide its cut behind; these two are joined along a seam that was
# invented, and past these numbers you can see where.
const EAR_SWING := 0.13       # radians
const HAT_TILT := 0.055
const HAT_SLIDE := 8.0        # SRC units

# name, parent ("" hangs it off the hips), whether the piece is drawn behind
# the one it hangs on, the joint it turns about, and where its top-left corner
# sits. Coordinates are in SRC units.
#
# Draw order is the order of this table, and nothing here sets a z_index. It
# would be the obvious way to put an ear behind a head, and it is the wrong
# one twice over: a negative z on a Control's descendant is measured against
# everything else on the canvas, so it puts the leg behind the island rather
# than behind the belly -- and a run of differing z values breaks up the
# CanvasGroup he is composited in, which is what stops him fading in as a
# stack of translucent cut-outs. Three pieces hang behind their parent; the
# rest fall out of the order they are listed in.
const HIP := Vector2(304, 424)   # the joint the whole rig hangs from

const RIG := [
	["leg_l",   "",      false, Vector2(238, 450), Vector2(146, 413)],
	["leg_r",   "",      false, Vector2(400, 450), Vector2(362, 413)],
	["torso",   "",      false, Vector2(304, 424), Vector2(186, 251)],
	["tail",    "torso", true,  Vector2(234, 410), Vector2( 74, 372)],
	["arm_r",   "torso", false, Vector2(390, 312), Vector2(356, 275)],
	["head",    "torso", false, Vector2(302, 298), Vector2(106,   9)],
	["ear_l",   "head",  true,  Vector2(154, 140), Vector2( 80,  21)],
	["ear_r",   "head",  true,  Vector2(390, 148), Vector2(310,   0)],
	["jaw",     "head",  false, Vector2(302, 242), Vector2(225, 223)],
	["eye_l",   "head",  false, Vector2(220, 186), Vector2(172, 138)],
	["eye_r",   "head",  false, Vector2(340, 179), Vector2(292, 131)],
	["pupil_l", "eye_l", false, Vector2(222, 188), Vector2(196, 162)],
	["pupil_r", "eye_r", false, Vector2(340, 180), Vector2(314, 154)],
	["hat",     "head",  false, Vector2(284, 120), Vector2(115,   9)],
	["arm_l",   "torso", false, Vector2(226, 300), Vector2( 20, 175)],
]


# --- written by the performance, once a frame, before tick() ---------------
var energy := 0.0             # 0..1, how far the loading bar has got
var squash := Vector2.ZERO    # added to the torso's scale; -y is compressed
var body := Vector2.ZERO      # where the whole rig has been displaced to
var look := Vector2.ZERO      # -1..1; where he is deliberately looking
var mouth := 0.0              # 0..1; how far the jaw is open
var arm := Vector2.ZERO       # radians at each shoulder, left then right
var leg := Vector2.ZERO       # radians at each hip, left then right
var head_turn := 0.0          # radians, on top of the counter-rotation

# Set this instead of modulate:a. Modulate is inherited, so it reaches each of
# the fifteen pieces separately, and half-faded he then arrives as a stack of
# translucent cut-outs with every overlap showing through. self_modulate on
# the group is applied to the composite of all fifteen instead, which is the
# whole reason he is drawn into a CanvasGroup.
var fade := 1.0:
	set(v):
		fade = v
		if _hips != null:
			_hips.self_modulate.a = v

var built := false

var _hips: CanvasGroup
var _bone := {}               # name -> Node2D
var _home := {}               # name -> the position it was built at
var _sx := {}                 # spring positions
var _sv := {}                 # spring velocities
var _fitted := -1.0
var _t := 0.0
var _prev_body := Vector2.ZERO
var _prev_vel := Vector2.ZERO
var _blink_wait := 1.4
var _blink_p := -1.0
var _blink_double := false
var _ear_wait := 2.2
var _ear_kick := Vector2.ZERO
var _gaze_wait := 1.0
var _gaze := Vector2.ZERO

# Fails rather than half-builds: if a single piece is missing, Boot keeps the
# undivided drawing instead, which is worse but is never broken.
func build() -> bool:
	var tex := {}
	for row in RIG:
		var t := CV.tex(DIR + str(row[0]) + ".png")
		if t == null:
			return false
		tex[row[0]] = t

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A CanvasGroup rather than a plain Node2D: he is faded up on entrance and
	# his pieces overlap, so blended one at a time he comes in as a stack of
	# translucent cut-outs with every seam showing. The group flattens the
	# fifteen of them first and takes the opacity on the result.
	_hips = CanvasGroup.new()
	_hips.self_modulate.a = fade
	add_child(_hips)

	for row in RIG:
		var part := str(row[0])
		var parent := str(row[1])
		var pivot: Vector2 = row[3]
		var origin: Vector2 = row[4]

		var joint := Node2D.new()
		joint.name = part
		joint.show_behind_parent = bool(row[2])
		joint.position = pivot - (_pivot_of(parent) if parent != "" else HIP)
		(_bone[parent] if parent != "" else _hips).add_child(joint)

		var spr := Sprite2D.new()
		spr.texture = tex[part]
		spr.centered = false
		spr.offset = origin - pivot
		joint.add_child(spr)

		_bone[part] = joint
		_home[part] = joint.position

	resized.connect(_fit)
	_fit()
	built = true
	return true

func _pivot_of(part: String) -> Vector2:
	for row in RIG:
		if str(row[0]) == part:
			return row[3]
	return Vector2.ZERO

func _ready() -> void:
	_fit()

# The drawing is square, and Boot gives this node a square box, so the whole
# rig is one uniform scale away from fitting it. Checked from tick() as well as
# on the signal: a Control resized before it is in the tree does not emit one,
# and a rig left at the scale it was built at is a rig scaled to nothing.
func _fit() -> void:
	if _hips == null or size.x <= 0.0:
		return
	_fitted = size.x
	var k := size.x / SRC
	_hips.scale = Vector2(k, k)
	_hips.position = HIP * k

# =============================================================================
#  A frame
# =============================================================================

func tick(delta: float) -> void:
	if not built:
		return
	if not is_equal_approx(size.x, _fitted):
		_fit()
	# A frame that took 200ms is a frame the loader spent building a page.
	# Clamping it makes a hitch read as him moving slowly for an instant rather
	# than as every spring in him being fired at once.
	delta = minf(delta, 0.05)
	_t += delta * (1.0 + 0.35 * energy)

	# What the body just did. Everything loose on him is answering this.
	var vel := (body - _prev_body) / maxf(delta, 1e-4)
	var acc := (vel - _prev_vel) / maxf(delta, 1e-4)
	_prev_body = body
	_prev_vel = vel
	acc = acc.limit_length(9000.0)

	var breath := sin(_t * TAU / 2.60)
	var crouch := maxf(-squash.y, 0.0)

	# --- the body -----------------------------------------------------------
	var torso: Node2D = _bone["torso"]
	torso.scale = Vector2(1.0 - 0.014 * breath + squash.x,
						  1.0 + 0.020 * breath + squash.y)

	# The legs hang off the hips, not off the chest, so the breath and the
	# squash above them do not reach them: they splay as he compresses, and
	# they shorten instead of being scaled by it.
	var leg_l: Node2D = _bone["leg_l"]
	var leg_r: Node2D = _bone["leg_r"]
	leg_l.rotation = leg.x - crouch * 0.85
	leg_r.rotation = leg.y + crouch * 0.85
	var shin := 1.0 - crouch * 0.55
	leg_l.scale = Vector2(1.0 + crouch * 0.30, shin)
	leg_r.scale = Vector2(1.0 + crouch * 0.30, shin)

	# --- the arms -----------------------------------------------------------
	# They swing against whatever the body is doing sideways, and they arrive
	# where the performance put them a beat late.
	var swing := clampf(-vel.x * 0.00060, -0.30, 0.30)
	_bone["arm_l"].rotation = _spring("arm_l", arm.x + swing, 210.0, 17.0, delta)
	_bone["arm_r"].rotation = _spring("arm_r", arm.y - swing, 210.0, 17.0, delta)

	# --- the head -----------------------------------------------------------
	# It does not simply ride the body: it arrives at a turn late and leaves it
	# late, which is the single cheapest thing that reads as a neck.
	var head: Node2D = _bone["head"]
	var yaw := clampf(look.x, -1.0, 1.0)
	head.rotation = _spring("head", head_turn + yaw * 0.09, 200.0, 15.0, delta)
	head.position = _home["head"] + Vector2(yaw * 4.0, -1.6 * breath + crouch * 9.0)
	# A flat drawing cannot turn, so the turn is faked the way it is in every
	# cut-out rig: the face slides across the skull and the skull narrows.
	head.scale = Vector2(1.0 - 0.035 * absf(yaw), 1.0)

	# --- ears: lag, plus a flick of their own -------------------------------
	# Held to EAR_SWING either way. They are drawn hard up against the crown of
	# the hat and carry a little of it underneath them, so a few degrees is a
	# live ear and fifteen is a fringe of hat grey sliding into view.
	_ear_wait -= delta
	if _ear_wait <= 0.0:
		_ear_wait = randf_range(1.7, 4.8) * (1.0 - 0.35 * energy)
		var k := randf_range(1.6, 2.9)
		_ear_kick = Vector2(k, 0.0) if randf() < 0.5 else Vector2(0.0, -k)
	var ear_base := -head.rotation * 0.30
	_bone["ear_l"].rotation = clampf(_spring("ear_l", ear_base - yaw * 0.04, 165.0,
		12.0, delta, _ear_kick.x - acc.x * 0.00012), -EAR_SWING, EAR_SWING)
	_bone["ear_r"].rotation = clampf(_spring("ear_r", ear_base - yaw * 0.04, 165.0,
		12.0, delta, _ear_kick.y - acc.x * 0.00012), -EAR_SWING, EAR_SWING)
	_ear_kick = Vector2.ZERO

	# --- eyes ---------------------------------------------------------------
	_blink_wait -= delta
	if _blink_p < 0.0 and _blink_wait <= 0.0:
		_blink_p = 0.0
		_blink_double = randf() < 0.20
		_blink_wait = randf_range(1.8, 5.4) * (1.0 - 0.40 * energy)
	var blink := 0.0
	if _blink_p >= 0.0:
		_blink_p += delta
		var span := 0.34 if _blink_double else 0.17
		if _blink_p >= span:
			_blink_p = -1.0
		else:
			blink = _blink_shape(fmod(_blink_p, 0.17) / 0.17)
	# He screws his eyes up when he is pleased with himself, which by the time
	# the bar is full is most of the time.
	var shut := clampf(blink + 0.10 * energy + 0.20 * mouth, 0.0, 1.0)
	for n in ["eye_l", "eye_r"]:
		var e: Node2D = _bone[n]
		e.scale = Vector2(1.0, 1.0 - 0.94 * shut)
		e.position = _home[n] + Vector2(yaw * 7.0, shut * 5.0)

	# Pupils: driven where the performance is looking, and drifting on their
	# own when it is not. Eyes that hold perfectly still are the deadest thing
	# a face can do.
	_gaze_wait -= delta
	if _gaze_wait <= 0.0:
		_gaze_wait = randf_range(0.7, 2.5)
		_gaze = Vector2(randf_range(-1.0, 1.0), randf_range(-0.7, 0.7)) * 0.40
	var gaze := (look + _gaze).limit_length(1.0) * Vector2(13.0, 9.0)
	var pupil := _spring2("pupil", gaze, 420.0, 26.0, delta)
	_bone["pupil_l"].position = _home["pupil_l"] + pupil
	_bone["pupil_r"].position = _home["pupil_r"] + pupil

	# --- jaw ----------------------------------------------------------------
	var jaw := _spring("jaw", mouth, 250.0, 19.0, delta)
	_bone["jaw"].rotation = jaw * 0.15
	_bone["jaw"].position = _home["jaw"] + Vector2(yaw * 5.0, jaw * 6.0)

	# --- tail ---------------------------------------------------------------
	# Heavy and slow: a soft spring, dragged by the body's sideways speed and
	# kicked by its acceleration, over a swish it does anyway.
	var tail_want := -clampf(vel.x * 0.0016, -0.5, 0.5) \
		+ sin(_t * TAU / 2.15) * (0.055 + 0.075 * energy)
	_bone["tail"].rotation = _spring("tail", tail_want, 92.0, 9.5, delta,
		-acc.x * 0.00030)

	# --- hat ----------------------------------------------------------------
	# Not attached to him, only resting on him: it slides when he accelerates
	# and settles after he stops. Kept on a short leash, because a hat that
	# leaves his head is a bug and not a gag.
	var hat: Node2D = _bone["hat"]
	hat.rotation = clampf(_spring("hat_a", -head.rotation * 0.24,
		128.0, 11.0, delta, -acc.x * 0.00018), -HAT_TILT, HAT_TILT)
	var slide := _spring2("hat_o", Vector2.ZERO, 150.0, 12.0, delta,
		Vector2(-acc.x, -acc.y) * 0.00034).limit_length(HAT_SLIDE)
	_sx["hat_o"] = slide
	hat.position = _home["hat"] + slide + Vector2(yaw * 3.0, 0.0)

func _blink_shape(u: float) -> float:
	# Shuts fast and opens slowly, which is what a blink does and what makes
	# the difference between a blink and a twitch.
	if u < 0.35:
		return smoothstep(0.0, 1.0, u / 0.35)
	return 1.0 - smoothstep(0.0, 1.0, (u - 0.35) / 0.65)

# A spring, integrated once per channel per frame. `kick` is added straight to
# the velocity: that is how an impulse -- a landing, an ear flick -- enters the
# system without teleporting anything.
func _spring(key: String, target: float, k: float, damp: float, delta: float,
		kick := 0.0) -> float:
	var x: float = _sx.get(key, target)
	var v: float = _sv.get(key, 0.0) + kick
	v += (target - x) * k * delta
	v *= exp(-damp * delta)
	x += v * delta
	_sx[key] = x
	_sv[key] = v
	return x

func _spring2(key: String, target: Vector2, k: float, damp: float, delta: float,
		kick := Vector2.ZERO) -> Vector2:
	var x: Vector2 = _sx.get(key, target)
	var v: Vector2 = _sv.get(key, Vector2.ZERO) + kick
	v += (target - x) * k * delta
	v *= exp(-damp * delta)
	x += v * delta
	_sx[key] = x
	_sv[key] = v
	return x

# Where a joint has ended up, in canvas space. The coin has to leave the paw
# that threw it and the dust has to come off the soles he is standing on, and
# once those move independently there is no box-relative fraction that stays
# true.
func bone_global(bone: String, at := Vector2.ZERO) -> Vector2:
	if not built or not _bone.has(bone):
		return global_position + size * 0.5
	return (_bone[bone] as Node2D).get_global_transform() * at
