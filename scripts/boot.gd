class_name Boot
extends Control

# The title screen, shown while Main builds itself.
#
# It is deliberately *not* a fake loader: Main hands it one step at a time as
# the real work completes (save read, art warmed, pages built), so the bar
# measures something. What the bar is really buying, though, is the first two
# seconds of the game -- the player sees their own island, lit and moving,
# before they see a single button. That is why the art is full-bleed and the
# chrome is only a wordmark and a strip of brass at the bottom.

const ART_HAZE := 0.20        # how far the illustration is pushed back
const TOP_SCRIM := 0.55       # haze under the wordmark
const BOT_SCRIM := 0.66       # deep water under the loading strip
const BAR_W := 520.0
const BAR_H := 44.0
const BAR_PAD := 6.0          # inset of the fill inside its well
const BAR_UP := 124.0         # bar's bottom edge, above the screen's
const LABEL_UP := 216.0       # status/percent row, likewise
const MASCOT_H := 502.0       # the raccoon's height, in viewport units
const MASCOT_FEET := 262.0    # where he stands, above the screen's bottom edge
const HOVER := 16.0           # how far the idle hover lifts him
const JUMP_H := 76.0          # an everyday hop
const PARTY_H := 216.0        # the jump he saves for 100%

var _chrome: Control          # the scene he stands in
var _front: Control           # the type and the loading strip, in front of him
var _backdrop: ShaderMaterial
var _art: TextureRect
var _art_mat: ShaderMaterial
var _fill: ColorRect
var _fill_mat: ShaderMaterial
var _pct: Label
var _status: Label
var _ratio := 0.0
var _mascot: Control          # carries the spin flip, pivoted on his feet
var _mascot_art: Control      # carries the hover and every act's displacement
var _rig: MascotRig           # the jointed raccoon, when his cut-out art loaded
var _mascot_shadow: Control
var _shadow_mat: ShaderMaterial
var _glow: ColorRect
var _fx: Control              # coins, dust and splashes, over everything
var _coin_tex: Texture2D
# Top and bottom system insets, in viewport units. The art runs under both --
# that is the point of an edge-to-edge screen -- but the wordmark and the
# loading strip are things you read, so they stay inside them.
var _safe := Vector2.ZERO

func _ready() -> void:
	# Nothing behind this is built yet, so it has to swallow input outright.
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 300
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The screen is built in three layers: the scene, the raccoon, and the type
	# over both. He is his own layer for two reasons -- he jumps *behind* the
	# wordmark, which is what gives the title screen any depth at all, and at
	# the end the other two layers dissolve while he stays and walks off.
	_chrome = Control.new()
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chrome)
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Under the artwork, so an island whose art fails to load still comes up as
	# the lagoon rather than as a black rectangle.
	_backdrop = Lagoon.backdrop(_chrome)

	_safe = UI.safe_insets(get_viewport_rect().size)
	_add_art()
	_add_coins()
	_add_mascot()

	# Coins, dust and splashes go over everything, including the type.
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.z_index = 50
	add_child(_fx)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_front = Control.new()
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.z_index = 40
	add_child(_front)
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_wordmark()
	_add_loader()

func _add_art() -> void:
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The illustration was drawn to be looked at, not to be read over. Hazing it
	# back a little and laying a scrim at each end is what lets sand-coloured
	# display type sit on the sky and white body type sit on the water.
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec3 haze = vec3(0.827, 0.945, 0.988);
uniform vec3 deep = vec3(0.027, 0.227, 0.286);
uniform float art_haze = 0.20;
uniform float top_scrim = 0.55;
uniform float bot_scrim = 0.66;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb, haze, art_haze);
	c.rgb = mix(c.rgb, haze, smoothstep(0.44, 0.0, UV.y) * top_scrim);
	c.rgb = mix(c.rgb, deep, smoothstep(0.58, 1.0, UV.y) * bot_scrim);
	// corner vignette -- the same one the backdrop uses, so the two agree
	c.rgb *= mix(0.88, 1.0, 1.0 - smoothstep(0.50, 1.05, length(UV - vec2(0.5))));
	COLOR = c;
}
"""
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = sh
	_art_mat.set_shader_parameter("art_haze", ART_HAZE)
	_art_mat.set_shader_parameter("top_scrim", TOP_SCRIM)
	_art_mat.set_shader_parameter("bot_scrim", BOT_SCRIM)
	_art.material = _art_mat
	_chrome.add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# A slow push in. Two seconds of a perfectly still image reads as a hung
	# app; the same image drifting reads as a game that is already running.
	_art.resized.connect(func() -> void: _art.pivot_offset = _art.size * 0.5)
	var tw := create_tween()
	tw.tween_property(_art, "scale", Vector2(1.06, 1.06), 6.0).from(Vector2.ONE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _add_coins() -> void:
	var t := CV.symbol_tex("coin")
	if t == null:
		return
	for i in 5:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var s := randf_range(54, 104)
		tr.size = Vector2(s, s)
		# Clear of the wordmark band and well clear of the loading strip. The
		# high band starts below the notch; the low one is nowhere near an edge.
		# High coins sit in the band under the notch; low ones hug the two
		# margins, because the middle of the screen belongs to the raccoon.
		var high := i % 2 == 0
		var y := _safe.x + randf_range(96, 236) if high else randf_range(560, 940)
		var x := randf_range(16, 640) if high else (randf_range(4, 96) if i % 4 == 1 else randf_range(600, 692))
		tr.position = Vector2(x, y)
		tr.modulate = Color(1, 1, 1, randf_range(0.30, 0.55))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chrome.add_child(tr)
		FX.float_bob(tr, randf_range(12, 26), randf_range(2.0, 3.6))

# =============================================================================
#  The raccoon
# =============================================================================
#
# He is the same thief who lands on the reels, promoted: the one asset in the
# game with a face, carrying the one verb the game is about. A title screen
# without him is a landscape with type on it, which is what every other
# spin-and-build game looks like from the store shelf.
#
# He is a puppet, not a picture: MascotRig hangs the fifteen pieces he was cut
# into on joints, and everything below drives those. What lives here is the
# *performance* -- one short act at a time, picked at random, with a beat of
# idling between -- while the rig owns everything involuntary underneath it.
#
# So an act only ever has to say the deliberate part. It writes where his feet
# and shoulders are, where he is looking and how far his mouth is open, and the
# rig supplies the breathing, the blinking, the ear that flicks, and the tail
# and hat catching up a beat later. He shuffles, hops, flips a coin, casts a
# shifty look around, spins on the spot. The bar feeds him: the fuller it gets
# the faster his clock runs, the shorter his pauses get and the showier the
# acts he picks, so by the time it reads 100% he is already worked up -- and
# 100% is where he jumps.
#
# All of it is integrated in _process rather than tweened, which is what lets
# the layers add together instead of fighting over the same properties, and
# lets a hitch in the loading slow him down rather than teleport him.

enum {ACT_NONE, ACT_DANCE, ACT_HOP, ACT_PEEK, ACT_COIN, ACT_SPIN, ACT_LOOK, ACT_PARTY, ACT_EXIT}

var _live := false            # entrance over, _process owns the transform
var _clock := 0.0             # his own clock, which runs faster as the bar fills
var _energy := 0.0            # 0..1, follows the loading bar
var _act := ACT_NONE
var _act_t := 0.0
var _act_len := 0.0
var _last_act := ACT_NONE     # never the same act twice running
var _rest := 0.6              # seconds of plain idling before the next act
var _marks: Array[float] = [] # points inside the act where an effect fires
var _mark_i := 0
var _partied := false
var _want_party := false      # 100% arrived before he had finished landing
# What the current act is doing to him this frame, on top of the idle.
var _off := Vector2.ZERO
var _lean := 0.0              # tips his chest at the hips, not the picture
var _squash := Vector2.ZERO
var _flip := 1.0              # scale.x, so cos() turns him around
var _arm := Vector2.ZERO      # radians at each shoulder, left then right
var _leg := Vector2.ZERO      # radians at each hip, left then right
var _look := Vector2.ZERO     # -1..1, where the act wants him looking
var _mouth := 0.0             # 0..1, how far the act wants his jaw open
var _head := 0.0              # radians of head turn the act is asking for
var _shadow_gain := 1.0
var _shadow_home := Vector2.ZERO
var _homed := false

func _add_mascot() -> void:
	var tex := CV.symbol_tex("steal")
	if tex == null:
		return
	_coin_tex = CV.symbol_tex("coin")

	var feet := -MASCOT_FEET - _safe.y
	var side := (720.0 - MASCOT_H) * 0.5

	# Warm light behind him. The art is hazed back by 20% and the water below
	# is dragged toward ABYSS, so without this he reads as a sticker laid on a
	# photograph instead of something standing in the scene. It belongs to the
	# scene rather than to him, so it fades out with the scene.
	_glow = _disc(Color(Lagoon.BRASS_HI.r, Lagoon.BRASS_HI.g, Lagoon.BRASS_HI.b, 0.30), 0.10)
	_chrome.add_child(_glow)
	_glow.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_glow.offset_left = side - 70.0
	_glow.offset_right = -side + 70.0
	_glow.offset_top = feet - MASCOT_H - 40.0
	_glow.offset_bottom = feet + 40.0

	# The contact shadow is deliberately *not* his child: it has to tighten and
	# darken as he rises, which is the opposite of what it would do if it were
	# carried along by the hover.
	_mascot_shadow = _disc(Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.72), 0.02)
	_shadow_mat = _mascot_shadow.material as ShaderMaterial
	_mascot_shadow.z_index = 5
	add_child(_mascot_shadow)
	_mascot_shadow.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_mascot_shadow.offset_left = 212.0
	_mascot_shadow.offset_right = -212.0
	_mascot_shadow.offset_top = feet - 36.0
	_mascot_shadow.offset_bottom = feet + 22.0
	# Set here as well as on resize: the signal can fire before the connection
	# above, and a disc scaled around the wrong corner slides out from under him.
	_mascot_shadow.pivot_offset = Vector2((720.0 - 424.0) * 0.5, 29.0)
	_mascot_shadow.resized.connect(func() -> void:
		_mascot_shadow.pivot_offset = _mascot_shadow.size * 0.5)

	_mascot = Control.new()
	_mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# His own band, above the scene and below the type. The rig sorts fifteen
	# pieces against each other inside it, and Godot sorts those against
	# everything else on the canvas -- so without the band a leg at the bottom
	# of his stack goes behind the island rather than behind his belly.
	_mascot.z_index = 10
	add_child(_mascot)
	_mascot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_mascot.offset_left = side
	_mascot.offset_right = -side
	_mascot.offset_top = feet - MASCOT_H
	_mascot.offset_bottom = feet
	_mascot.pivot_offset = Vector2(MASCOT_H * 0.5, MASCOT_H)
	# Everything pivots on his feet, so the breath compresses him downward the
	# way weight does, rather than shrinking him toward his middle.
	_mascot.resized.connect(func() -> void:
		_mascot.pivot_offset = Vector2(_mascot.size.x * 0.5, _mascot.size.y)
		if _mascot_art != null:
			_mascot_art.size = _mascot.size
			_mascot_art.pivot_offset = _mascot.size * 0.5)

	# Fifteen pieces on joints if the cut-out art is there, and the one
	# undivided drawing if it is not. A part that failed to load should cost
	# the title screen its articulation, never its raccoon.
	var rig := MascotRig.new()
	if rig.build():
		_rig = rig
		_mascot_art = rig
	else:
		var flat := TextureRect.new()
		flat.texture = tex
		flat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_mascot_art = flat
	_mascot_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascot_art.size = Vector2(MASCOT_H, MASCOT_H)
	_mascot_art.pivot_offset = _mascot_art.size * 0.5
	if _rig != null:
		_rig.fade = 0.0
	else:
		_mascot_art.modulate.a = 0.0
	_mascot.add_child(_mascot_art)

	# He drops in rather than being there from frame one -- the screen is
	# already fading up around him, and something arriving is the cheapest
	# possible signal that the game is running and not stuck. This is the one
	# piece of him that is tweened, because nothing has to layer on top of it.
	var enter := create_tween()
	enter.tween_interval(0.10)
	enter.tween_property(_mascot_art, "fade" if _rig != null else "modulate:a", 1.0, 0.30)
	enter.parallel().tween_property(_mascot_art, "position:y", 0.0, 0.58) \
		.from(196.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	enter.tween_callback(_go_live)

func _go_live() -> void:
	_live = true
	if _want_party:
		_begin_act(ACT_PARTY)
	else:
		_rest = 0.25   # he barely waits -- he is glad to be here

func _process(delta: float) -> void:
	if not _live or _mascot == null:
		return
	# A frame that took 200ms is a frame the loader spent building a page.
	# Clamping it makes a hitch read as him moving slowly for an instant,
	# instead of him teleporting through the middle of a jump.
	delta = minf(delta, 0.05)
	_clock += delta * (1.0 + 0.30 * _energy)

	if not _homed:
		_homed = true
		_shadow_home = _mascot_shadow.position

	_off = Vector2.ZERO
	_lean = 0.0
	_squash = Vector2.ZERO
	_flip = 1.0
	_shadow_gain = 1.0
	_arm = Vector2.ZERO
	_leg = Vector2.ZERO
	_look = Vector2.ZERO
	_mouth = 0.0
	_head = 0.0
	_advance_act(delta)

	# Edge-on, his limbs have to come in. Fifteen pieces at scale.x near zero
	# are fifteen separate slivers unless they are stacked on top of one
	# another -- which is also what a body does when it wants to spin faster.
	var tuck := absf(_flip)
	_arm *= tuck
	_leg *= tuck

	# The idle underneath, always running: a breath that trades width for
	# height so he keeps his volume, a sway, and a hover -- three periods with
	# no common multiple, which is what stops the eye finding the loop point.
	var breath := sin(_clock * TAU / 2.60)
	var sway := sin(_clock * TAU / 3.70 + 0.7)
	var hover := 0.5 - 0.5 * cos(_clock * TAU / 3.10)

	var drift := Vector2(_off.x, -HOVER * hover + _off.y)
	_mascot_art.position = drift
	if _rig != null:
		# The sway and the squash are handed to his hips rather than applied to
		# the whole picture. He tips his chest over feet that stay where they
		# were put, his head stays level over the tip, and the tail and the hat
		# arrive late -- which is the whole of the difference between a
		# character leaning and a drawing being rotated. The breath belongs to
		# the rig now too, so it moves his chest and not his boots.
		_rig.energy = _energy
		_rig.lean = deg_to_rad(2.6) * sway + _lean
		_rig.squash = _squash
		_rig.body = drift
		_rig.arm = _arm
		_rig.leg = _leg
		_rig.look = _look
		_rig.mouth = clampf(_mouth + 0.16 * _energy, 0.0, 1.0)
		_rig.head_turn = _head
		_rig.tick(delta)
		_mascot.rotation = 0.0
		_mascot.scale = Vector2(_flip, 1.0)
	else:
		_mascot.rotation = deg_to_rad(2.1) * sway + _lean
		_mascot.scale = Vector2(
			(1.0 - 0.016 * breath + _squash.x) * _flip,
			1.0 + 0.024 * breath + _squash.y)

	# The shadow answers his height rather than copying it: as he goes up it
	# pulls in and lightens, and it slides only part of the way when he steps.
	# That single relationship is most of what makes a cut-out feel like it is
	# standing on ground.
	var lift := clampf((HOVER * hover - _off.y) / (HOVER + JUMP_H), 0.0, 1.0)
	_mascot_shadow.position.x = _shadow_home.x + _off.x * 0.55
	var k := (1.0 - 0.34 * lift) * _shadow_gain
	_mascot_shadow.scale = Vector2(k, k)
	_shadow_mat.set_shader_parameter("fade", (1.0 - 0.42 * lift) * _shadow_gain)

# --- the performance -------------------------------------------------------

func _advance_act(delta: float) -> void:
	if _act == ACT_NONE:
		_rest -= delta
		if _rest <= 0.0:
			_begin_act(_pick_act())
		return
	_act_t += delta
	while _mark_i < _marks.size() and _act_t >= _marks[_mark_i] * _act_len:
		_fire_mark(_mark_i)
		_mark_i += 1
	_pose(clampf(_act_t / _act_len, 0.0, 1.0))
	if _act_t >= _act_len:
		_end_act()

# Calm and watchful early on, showing off by the time the bar is nearly full.
func _pick_act() -> int:
	var pool: Array[int] = [ACT_LOOK, ACT_COIN, ACT_PEEK]
	if _energy > 0.25:
		pool.append_array([ACT_DANCE, ACT_HOP])
	if _energy > 0.55:
		pool.append_array([ACT_DANCE, ACT_SPIN, ACT_HOP])
	var choices := pool.filter(func(a: int) -> bool: return a != _last_act)
	if choices.is_empty():
		choices = pool
	_last_act = choices.pick_random()
	return _last_act

func _begin_act(a: int) -> void:
	if _mascot == null:
		return
	_act = a
	_act_t = 0.0
	_mark_i = 0
	_marks = []
	# Everything he does gets a little quicker as the loading gets further on.
	var tempo := 1.0 - 0.22 * _energy
	match a:
		ACT_DANCE:
			_act_len = 2.30 * tempo
		ACT_HOP:
			_act_len = 1.05 * tempo
			_marks = [0.56, 0.99]
		ACT_PEEK:
			_act_len = 1.40 * tempo
		ACT_COIN:
			_act_len = 1.35 * tempo
			_marks = [0.10]
		ACT_SPIN:
			_act_len = 0.95 * tempo
		ACT_LOOK:
			_act_len = 1.65 * tempo
		ACT_PARTY:
			_act_len = 1.45
			_marks = [0.13, 0.36, 0.62]
		ACT_EXIT:
			_act_len = 0.70
			_marks = [0.60]

func _end_act() -> void:
	var was := _act
	_act = ACT_NONE
	_marks = []
	_mark_i = 0
	if was == ACT_EXIT:
		_live = false          # he is off the bottom of the screen; stop driving him
		_mascot.visible = false
		_mascot_shadow.visible = false
		return
	_rest = randf_range(0.45, 1.15) * (1.0 - 0.55 * _energy)

# Where each act puts him, as a function of how far through it he is. The
# pieces are deliberately small: the idle is still running underneath, so an
# act only has to supply the part that is *not* breathing.
func _pose(u: float) -> void:
	match _act:
		ACT_DANCE:
			# A shuffle: weight shifts side to side on the beat, with a bounce
			# at twice the rate and a squash at the bottom of each one. The
			# sine envelope is what walks him into and out of it, so he never
			# snaps from idling to dancing. The legs step against the weight
			# shift and the arms against the legs, which is the whole of what
			# separates a dance from a wobble.
			var e := sin(u * PI)
			var beat := u * TAU * 2.0
			var bounce := absf(sin(beat * 2.0))
			var step := sin(beat)
			_off.x = step * 30.0 * e
			_off.y = -14.0 * bounce * e
			_lean = deg_to_rad(-7.0) * step * e
			_squash = Vector2(0.030, -0.034) * (1.0 - bounce) * e
			_leg = Vector2(deg_to_rad(-19.0), deg_to_rad(19.0)) * step * e
			_arm = Vector2(deg_to_rad(24.0), deg_to_rad(24.0)) * step * e
			_head = deg_to_rad(4.5) * sin(beat * 2.0) * e
			_look = Vector2(step * 0.55, -0.12) * e
			_mouth = 0.62 * e
		ACT_HOP:
			# Crouch, then two hops, the second a little lower than the first.
			if u < 0.12:
				var c := smoothstep(0.0, 1.0, u / 0.12)
				_squash = Vector2(0.075, -0.085) * c
				_arm = Vector2(deg_to_rad(-16.0), deg_to_rad(16.0)) * c
				_look = Vector2(0.0, 0.5) * c
			else:
				var v := (u - 0.12) / 0.88
				var h := _arc(fmod(v * 2.0, 1.0)) * (1.0 - 0.28 * floorf(v * 2.0))
				_off.y = -JUMP_H * h
				_off.x = (v - 0.5) * 24.0
				_squash = Vector2(-0.055 * h, 0.065 * h)
				_lean = deg_to_rad(5.0) * sin(v * TAU)
				# Arms up and legs tucked at the top: the two things a body
				# does in the air that a sliding drawing cannot.
				_arm = Vector2(deg_to_rad(40.0), deg_to_rad(-40.0)) * h
				_leg = Vector2(deg_to_rad(-13.0), deg_to_rad(13.0)) * h
				_mouth = 0.85 * h
				_look = Vector2(0.0, -0.55 * h)
		ACT_PEEK:
			# He leans out at the player, the way something with eyes that size
			# is supposed to, and nods once while he is there.
			var e := sin(u * PI)
			_lean = deg_to_rad(-9.0) * e
			_off.x = -16.0 * e
			_off.y = (-6.0 - 5.0 * sin(u * TAU * 3.0)) * e
			_squash = Vector2(0.05, 0.05) * e
			_head = deg_to_rad(-7.0) * e
			_arm = Vector2(deg_to_rad(13.0), deg_to_rad(9.0)) * e
			_mouth = 0.55 * e
			_look = Vector2(-0.10, 0.30) * e
		ACT_COIN:
			# The free paw flicks up and the coin leaves it -- and then he
			# watches the coin, which is the part that sells it. His eyes get
			# there before his head does, because the rig springs them harder.
			var e := sin(u * PI)
			_off.y = -10.0 * e
			_lean = deg_to_rad(4.0) * e
			_squash = Vector2(-0.02 * e, 0.03 * e)
			var flick := -smoothstep(0.0, 1.0, u / 0.10) if u < 0.10 \
				else sin((u - 0.10) / 0.90 * PI)
			_arm.y = deg_to_rad(-38.0) * flick
			_arm.x = deg_to_rad(7.0) * e
			var watch := clampf(sin(u * PI) * 1.7, 0.0, 1.0)
			_look = Vector2(0.62, -0.85) * watch
			_head = deg_to_rad(-5.0) * watch
			_mouth = 0.70 * e
		ACT_SPIN:
			# A turn on the spot, done as a cosine on scale.x: the same trick
			# the flipped coin uses, and it reads the same way. Arms out and
			# feet in, because that is what a body does to spin faster.
			_flip = cos(u * TAU)
			var lift := _arc(u)
			_off.y = -JUMP_H * 0.45 * lift
			_squash = Vector2(0.0, 0.05 * lift)
			_arm = Vector2(deg_to_rad(32.0), deg_to_rad(-32.0)) * lift
			_leg = Vector2(deg_to_rad(-15.0), deg_to_rad(15.0)) * lift
			_mouth = 0.80 * lift
		ACT_LOOK:
			# The thief's glance: left, hold, right, hold, settle. He is a
			# character who is about to steal something, and this is the
			# cheapest possible way to say so. It is a head turn now rather
			# than a tilt -- the eyes lead it and the ears swing against it.
			var a := 0.0
			if u < 0.18:
				a = -smoothstep(0.0, 1.0, u / 0.18)
			elif u < 0.42:
				a = -1.0
			elif u < 0.60:
				a = -1.0 + 2.0 * smoothstep(0.0, 1.0, (u - 0.42) / 0.18)
			elif u < 0.82:
				a = 1.0
			else:
				a = 1.0 - smoothstep(0.0, 1.0, (u - 0.82) / 0.18)
			_lean = deg_to_rad(4.0) * a
			_off.x = 9.0 * a
			_squash = Vector2(0.02, -0.02) * absf(a)
			_head = deg_to_rad(7.0) * a
			_look = Vector2(a, -0.10)
			_arm = Vector2(deg_to_rad(6.0) * a, deg_to_rad(6.0) * a)
			_mouth = 0.15
		ACT_PARTY:
			_pose_party(u)
		ACT_EXIT:
			_pose_exit(u)

# 100%. Wind up, one full turn in the air with the coins going up with him,
# a heavy landing, then two bounces he cannot quite contain. This is the whole
# point of keeping him on screen: the bar filling is information, but him
# jumping about it is the part anybody remembers.
func _pose_party(u: float) -> void:
	if u < 0.13:
		var c := smoothstep(0.0, 1.0, u / 0.13)
		_squash = Vector2(0.13, -0.15) * c
		_arm = Vector2(deg_to_rad(-22.0), deg_to_rad(22.0)) * c
		_look = Vector2(0.0, 0.6) * c
		_mouth = 0.3 * c
	elif u < 0.62:
		var v := (u - 0.13) / 0.49
		var h := _arc(v)
		_off.y = -PARTY_H * h
		_squash = Vector2(-0.10 * h, 0.12 * h)
		_flip = cos(v * TAU)
		_lean = deg_to_rad(11.0) * sin(v * TAU)
		# Everything thrown open at once. This is the one second of the title
		# screen anybody will describe afterwards, so nothing on him is held back.
		_arm = Vector2(deg_to_rad(62.0), deg_to_rad(-62.0)) * h
		_leg = Vector2(deg_to_rad(-26.0), deg_to_rad(26.0)) * h
		_head = deg_to_rad(-8.0) * h
		_look = Vector2(0.0, -0.75 * h)
		_mouth = 1.0
	elif u < 0.72:
		var k := sin((u - 0.62) / 0.10 * PI)
		_squash = Vector2(0.16, -0.18) * k
		_arm = Vector2(deg_to_rad(-26.0), deg_to_rad(26.0)) * k
		_mouth = 0.9 * k
		_look = Vector2(0.0, 0.5) * k
	else:
		var v := (u - 0.72) / 0.28
		var b := absf(sin(v * TAU)) * (1.0 - v)
		_off.y = -36.0 * b
		_lean = deg_to_rad(6.0) * sin(v * TAU * 2.0)
		_squash = Vector2(-0.04 * b, 0.05 * b)
		_arm = Vector2(deg_to_rad(34.0), deg_to_rad(-34.0)) * b
		_leg = Vector2(deg_to_rad(-11.0), deg_to_rad(11.0)) * b
		_mouth = 0.85 * b

# How he leaves: a crouch and a dive off the bottom of the screen, into the
# lagoon and into the game. He is never faded out -- the screen goes and he
# walks off it, which is the difference between a mascot leaving and a mascot
# being deleted.
func _pose_exit(u: float) -> void:
	if u < 0.20:
		var c := smoothstep(0.0, 1.0, u / 0.20)
		_squash = Vector2(0.15, -0.17) * c
		_off.y = 8.0 * c
		_arm = Vector2(deg_to_rad(-24.0), deg_to_rad(24.0)) * c
		_look = Vector2(0.0, 0.7) * c
		_head = deg_to_rad(4.0) * c
	else:
		var v := (u - 0.20) / 0.80
		_off.y = -80.0 * sin(v * PI * 0.55) + 1150.0 * v * v
		_squash = Vector2(-0.10, 0.13)
		_lean = deg_to_rad(-14.0) * v
		_shadow_gain = 1.0 - smoothstep(0.0, 0.45, v)
		# A dive, so: arms thrown forward, legs trailing, and his eyes already
		# on the water he is about to be in.
		_arm = Vector2(deg_to_rad(74.0), deg_to_rad(-74.0)) * smoothstep(0.0, 0.5, v)
		_leg = Vector2(deg_to_rad(22.0), deg_to_rad(-22.0)) * smoothstep(0.0, 0.6, v)
		_head = deg_to_rad(-9.0) * v
		_look = Vector2(0.0, 0.9)
		_mouth = 0.9

func _fire_mark(i: int) -> void:
	match _act:
		ACT_HOP:
			_dust()
		ACT_COIN:
			_toss_coin()
		ACT_PARTY:
			match i:
				0:
					_dust()
				1:
					_party_apex()
				2:
					_dust()
					FX.shake(_chrome, 7.0, 4)
					FX.shake(_front, 7.0, 4)
		ACT_EXIT:
			_splash()

func _arc(v: float) -> float:
	return 4.0 * v * (1.0 - v)

# Dust comes off the soles he is actually standing on, not off the middle of
# his bounding box -- once the feet move independently, the two stop agreeing.
func _foot_point() -> Vector2:
	if _rig != null and _rig.built:
		var inv := get_global_transform().affine_inverse()
		return (inv * _rig.bone_global("leg_l", Vector2(-46.0, 58.0))).lerp(
			inv * _rig.bone_global("leg_r", Vector2(20.0, 58.0)), 0.5)
	return _mascot.position + Vector2(_mascot.size.x * 0.5 + _off.x, _mascot.size.y - 8.0)

func _dust() -> void:
	FX.burst(_fx, _foot_point(), Lagoon.SAND_DEEP, 6)

func _splash() -> void:
	var p := _foot_point()
	FX.burst(_fx, Vector2(p.x, size.y - 40.0), Lagoon.LAGOON, 14)

# The top of the 100% jump: coins out of both paws, a flare of the light he is
# standing in, and confetti dropped into Main rather than into this screen, so
# it is still falling over the game after the title has gone.
func _party_apex() -> void:
	var mid: Vector2 = (get_global_transform().affine_inverse() * _rig.bone_global("torso", Vector2(0.0, -92.0))) \
		if _rig != null and _rig.built else _mascot.position + _mascot.size * Vector2(0.5, 0.44) + _off
	FX.burst(_fx, mid, Lagoon.BRASS_HI, 16)
	FX.confetti(_confetti_host(), 34)
	for i in 7:
		_pop_coin(mid, Vector2(randf_range(-260, 260), randf_range(-330, -170)))
	if _glow != null:
		var tw := create_tween()
		tw.tween_property(_glow, "modulate", Color(1.7, 1.55, 1.25), 0.14) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(_glow, "modulate", Color.WHITE, 0.55) \
			.set_trans(Tween.TRANS_SINE)

# Confetti belongs to whatever outlives this screen, so it keeps falling
# through the handover instead of being freed with the splash.
func _confetti_host() -> Control:
	var p := get_parent()
	return p as Control if p is Control else self

func _pop_coin(from: Vector2, vel: Vector2) -> void:
	if _coin_tex == null:
		return
	var coin := TextureRect.new()
	coin.texture = _coin_tex
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size = Vector2(52, 52)
	coin.pivot_offset = coin.size * 0.5
	coin.position = from - coin.size * 0.5
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(coin)
	var apex := coin.position + vel
	var tw := create_tween()
	tw.tween_property(coin, "position", apex, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(coin, "position", apex + Vector2(vel.x * 0.35, 620.0), 0.85) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(coin, "modulate:a", 0.0, 0.85).set_delay(0.35)
	tw.tween_callback(coin.queue_free)
	var flip := create_tween()
	flip.tween_method(func(a: float) -> void: coin.scale.x = cos(a), 0.0, TAU * 3.0, 1.27)

# The idle gesture. One coin, up out of his free paw and back down into it,
# turning over the whole way -- the flip is a cosine on scale.x, which costs
# nothing and reads as a coin because a coin is the one object people accept
# as flat.
func _toss_coin() -> void:
	if _coin_tex == null or _mascot == null:
		return
	# Out of the paw itself, wherever the shoulder has swung it to.
	var hand: Vector2 = (get_global_transform().affine_inverse() * _rig.bone_global("arm_r", Vector2(28.0, 96.0))) \
		if _rig != null and _rig.built else _mascot.position + _mascot.size * Vector2(0.755, 0.585) + _off
	var coin := TextureRect.new()
	coin.texture = _coin_tex
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size = Vector2(66, 66)
	coin.pivot_offset = coin.size * 0.5
	coin.position = hand - coin.size * 0.5
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.modulate.a = 0.0
	_fx.add_child(coin)

	var apex := hand + Vector2(30.0, -198.0)
	var tw := create_tween()
	tw.tween_property(coin, "position", apex - coin.size * 0.5, 0.54) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(coin, "modulate:a", 1.0, 0.16)
	tw.tween_callback(func() -> void: FX.burst(_fx, apex, Lagoon.BRASS_HI, 5))
	tw.tween_property(coin, "position", (hand + Vector2(4.0, 0.0)) - coin.size * 0.5, 0.48) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(coin, "modulate:a", 0.0, 0.48).set_delay(0.24)
	tw.tween_callback(coin.queue_free)

	var flip := create_tween()
	flip.tween_method(func(a: float) -> void: coin.scale.x = cos(a), 0.0, TAU * 2.0, 1.02)

# A soft radial disc: the light behind him and the shadow under him are the
# same primitive at two colours, so they always agree about where he is.
func _disc(tint: Color, edge := 0.3) -> ColorRect:
	var r := ColorRect.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec4 tint = vec4(1.0);
uniform float edge = 0.3;
uniform float fade = 1.0;   // driven by the hover, so the shadow can answer it

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = 1.0 - smoothstep(edge, 1.0, d);
	COLOR = vec4(tint.rgb, tint.a * a * a * fade);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("edge", edge)
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _add_wordmark() -> void:
	var logo := Lagoon.wordmark("LOOT  LAGOON", 76)
	_front.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 268.0 + _safe.x
	logo.offset_bottom = 372.0 + _safe.x
	FX.pulse_forever(logo, 1.035, 2.4)

	var tagline := Lagoon.title("Spin · Raid · Build your island", UI.F_BODY, Color.WHITE, Lagoon.ABYSS)
	_front.add_child(tagline)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tagline.offset_top = 380.0 + _safe.x
	tagline.offset_bottom = 430.0 + _safe.x

func _add_loader() -> void:
	# Anchored to the bottom edge, like the nav bar it will be replaced by. The
	# viewport is stretched to the phone's real aspect, so the extra height
	# lands in the middle of the screen: measured from the top, the strip would
	# drift up into the artwork and out of the scrim that makes it readable.
	_status = Lagoon.title("Waking the lagoon", UI.F_CAPTION, Color(1, 1, 1, 0.92), Lagoon.ABYSS)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_front.add_child(_status)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = (720.0 - BAR_W) * 0.5
	_status.offset_right = -(720.0 - BAR_W) * 0.5
	_status.offset_top = -LABEL_UP - _safe.y
	_status.offset_bottom = -LABEL_UP - _safe.y + 42.0

	_pct = Lagoon.title("0%", UI.F_CAPTION, Lagoon.BRASS_HI, Lagoon.ABYSS)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_front.add_child(_pct)
	_pct.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_pct.offset_left = (720.0 - BAR_W) * 0.5
	_pct.offset_right = -(720.0 - BAR_W) * 0.5
	_pct.offset_top = -LABEL_UP - _safe.y
	_pct.offset_bottom = -LABEL_UP - _safe.y + 42.0

	# The well: the same sunken sea glass the spin meter sits in, rimmed in
	# brass so the loading strip belongs to the same machine as everything else.
	var well := Panel.new()
	var sb := Lagoon.glass_well(int(BAR_H * 0.5))
	sb.bg_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.46)
	sb.set_border_width_all(4)
	sb.border_color = Lagoon.BRASS
	sb.shadow_size = 8
	sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.35)
	sb.shadow_offset = Vector2(0, 3)
	well.add_theme_stylebox_override("panel", sb)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.add_child(well)
	well.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	well.offset_left = (720.0 - BAR_W) * 0.5
	well.offset_right = -(720.0 - BAR_W) * 0.5
	well.offset_top = -BAR_UP - BAR_H - _safe.y
	well.offset_bottom = -BAR_UP - _safe.y

	# The fill is polished brass rather than a flat colour: it is the same metal
	# as the plaques and the rim it grows inside.
	var inner_h := BAR_H - BAR_PAD * 2.0
	_fill = ColorRect.new()
	_fill_mat = Lagoon.brass_material(int(inner_h * 0.5))
	_fill.material = _fill_mat
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.position = Vector2(BAR_PAD, BAR_PAD)
	_fill.size = Vector2(0, inner_h)
	_fill.resized.connect(func() -> void: _fill_mat.set_shader_parameter("rect_px", _fill.size))
	well.add_child(_fill)

	_fill.add_child(_sheen(inner_h))

# A highlight sweeping along the filled metal. It keeps the strip alive across
# a step that takes longer than the tween, which is the difference between
# "loading" and "stuck".
func _sheen(inner_h: float) -> ColorRect:
	var r := ColorRect.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec2 rect_px = vec2(100.0, 32.0);
uniform float radius = 16.0;
uniform float speed = 0.55;

float rr(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_px;
	float inside = 1.0 - smoothstep(-1.0, 0.5, rr(p, rect_px * 0.5, radius));
	// a band that runs the length of the fill and wraps
	float head = fract(TIME * speed);
	float d = abs(UV.x - head);
	d = min(d, 1.0 - d);
	float band = smoothstep(0.14, 0.0, d);
	COLOR = vec4(1.0, 0.98, 0.90, band * inside * 0.34);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("radius", inner_h * 0.5)
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.resized.connect(func() -> void: mat.set_shader_parameter("rect_px", r.size))
	return r

# --- driven by Main ---

# Dresses the screen in the island the save actually left off on, so the very
# first frame of the session is already the player's own place.
func set_island(p: Dictionary, art: Texture2D) -> void:
	Lagoon.tint_backdrop(_backdrop, p)
	if art != null:
		_art.texture = art
	if _art_mat != null:
		var accent: Color = p["accent"]
		var mid: Color = p["mid"]
		_art_mat.set_shader_parameter("haze", _v3(Lagoon.SKY_HI.lerp(accent, 0.16)))
		_art_mat.set_shader_parameter("deep", _v3(Lagoon.ABYSS.lerp(mid, 0.30)))

func set_status(text: String) -> void:
	if _status != null:
		_status.text = text

# Runs the bar up to `ratio` and returns when it gets there, so the caller's
# next step cannot start until the player has seen this one land.
func advance(ratio: float) -> void:
	var target := clampf(ratio, 0.0, 1.0)
	var tw := create_tween()
	tw.tween_method(_set_ratio, _ratio, target, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished

# The bar hitting the end is his cue, not Main's: he goes off the moment the
# number says 100, while the last of the build is still finishing.
func celebrate() -> void:
	if _partied or _mascot == null:
		return
	_partied = true
	if _live:
		_begin_act(ACT_PARTY)
	else:
		_want_party = true   # loading beat his entrance; he'll jump on landing

func dismiss() -> void:
	# If he never got as far as standing up -- a load that finished before his
	# entrance did -- there is no performance to protect, so the whole screen
	# goes at once and he goes with it.
	if _mascot == null or not _live:
		var out := create_tween()
		out.set_parallel(true)
		out.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
		out.tween_property(_art, "scale", _art.scale * 1.04, 0.45).set_trans(Tween.TRANS_SINE)
		await out.finished
		queue_free()
		return

	# If the 100% jump is still in the air, let it come down -- cutting away
	# from a celebration halfway through is worse than not having one. His
	# victory bounces, on the other hand, get cut the moment he lands: the
	# crouch he leaves on is a better use of the same second.
	while _act == ACT_PARTY and _act_t < _act_len * 0.72:
		await get_tree().process_frame

	_begin_act(ACT_EXIT)
	await get_tree().create_timer(0.10).timeout   # let him gather himself

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_chrome, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_front, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	# Lifting as it fades hands the screen over rather than cutting away from it.
	tw.tween_property(_art, "scale", _art.scale * 1.04, 0.45).set_trans(Tween.TRANS_SINE)

	# He is not in that fade. The scene dissolves out from under him and he
	# dives off the bottom edge under his own power, which is the difference
	# between a mascot leaving and a mascot being switched off.
	while _act == ACT_EXIT:
		await get_tree().process_frame
	queue_free()

func _set_ratio(v: float) -> void:
	_ratio = v
	_energy = v
	if _fill != null:
		_fill.size.x = (BAR_W - BAR_PAD * 2.0) * v
	if _pct != null:
		_pct.text = "%d%%" % roundi(v * 100.0)
	if v >= 0.999:
		celebrate()

func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
