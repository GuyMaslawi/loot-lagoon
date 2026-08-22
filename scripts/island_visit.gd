class_name IslandVisit
extends Control

signal finished(result: Dictionary)

var npc: Dictionary
var mode := "steal"
# The bet the spin was played at. It is deliberately NOT folded into the chests
# or into the attack reward any more -- the raid pays what the island held, and
# the bet is applied on top of that, on screen, where the player can watch it
# happen. See `_payout`.
var mult := 1
# What a successful smash is worth before the bet is applied, island-scaled by
# whoever opened the raid. An attack pays coins like a steal does; it just took
# until now for the player to be shown them on the island rather than after it.
var attack_reward := 0
# The rival's purse is written at its island-1 value, like every other coin
# source; main passes the island multiplier in so the chests show what pays out.
var coin_mult := 1.0
# How far down the screen the island has to come. Set by whoever opens the
# raid, because only they know where the nav bar's slab starts.
var reach := 0.0

var _picks_left := 3
var _stolen := 0
var _acted := false
var _attempts_label: Label
var _loot_label: Label
var _target_buttons: Array = []
var _building_visuals: Array = []
# Everything that belongs to the rival's island -- the art, their huts, the
# chests you open on top of them -- lives in here, in the 720x1280 coordinates
# it was all drawn in, hung on the screen as one piece. The banner and the
# attempt counter stay outside it: those are ours, not theirs, and they are the
# only two things on this screen that have to dodge the notch.
var _stage: Control
var _sky: ColorRect

# The raccoon, when this is an attack. He is the one who throws the hammer, and
# everything below that reads as a performance -- the wind-up, the release, the
# fist-pump, the sulk when a shield eats it -- is him. A raid that was a tap
# and a number now has somebody doing it.
var _rac: MascotRig
var _rac_holder: Control
var _act := "idle"
var _act_t := 0.0
# The run-on owns his position until it lands; after that the performance does.
var _entered := false

# Where he stands, in the 720x1280 the island is drawn in: front-left, clear of
# every hut, close enough to the bottom edge to read as *nearer* than they are.
const RAC_BOX := Vector2(262, 262)
const RAC_POS := Vector2(-14, 812)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var view := get_viewport_rect().size
	var top := UI.safe_top(view)

	# Sky first, so the strip the island does not reach -- the one the notch
	# sits in -- is the same colour the art starts with rather than a hole.
	_sky = ColorRect.new()
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sky)
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	UI.make_design_stage(_stage, view, top, reach if reach > 0.0 else view.y)

	var npc_island: int = int(npc.get("island", 1))
	var bg_t := CV.island_bg_tex(npc_island)
	if bg_t != null:
		var bg := TextureRect.new()
		bg.texture = bg_t
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.5, 0.75, 0.55)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if mode == "attack":
		var tint := ColorRect.new()
		tint.color = Color(0.55, 0.05, 0.05, 0.16)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(tint)
		tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg_img := CV.bg_image(bg_t)
	_sky.color = CV.bg_top_color(bg_img, Color(0.5, 0.75, 0.55))
	for i in CV.BUILDINGS.size():
		var b: Dictionary = CV.BUILDINGS[i]
		var rect: Rect2 = CV.SLOT_RECTS[i]
		var level: int = int(npc["buildings"][i])
		var holder := Control.new()
		holder.position = rect.position
		holder.size = rect.size
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(holder)

		var shadow := ColorRect.new()
		shadow.material = CV.contact_shadow_material()
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sw := rect.size.x * 0.68
		shadow.size = Vector2(sw, 56)
		shadow.position = Vector2((rect.size.x - sw) * 0.5, rect.size.y - 56.0 - 46.0)
		holder.add_child(shadow)

		var tr := TextureRect.new()
		tr.texture = CV.island_building_tex(npc_island, i)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.material = CV.ground_blend_material().duplicate()
		var bcol := CV.terrain_color_at(bg_img, rect, 56.0)
		(tr.material as ShaderMaterial).set_shader_parameter("terrain_col", Vector3(bcol.r, bcol.g, bcol.b))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_bottom = -56.0

		var fb := Label.new()
		fb.text = b["emoji"]
		fb.add_theme_font_override("font", CV.emoji_font())
		fb.add_theme_font_size_override("font_size", 90)
		fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fb.visible = tr.texture == null
		tr.visible = tr.texture != null
		holder.add_child(fb)
		fb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fb.offset_bottom = -56.0

		var mod := Color(1, 1, 1) if level > 0 else Color(0.5, 0.5, 0.5, 0.4)
		tr.modulate = mod
		fb.modulate = mod
		shadow.modulate = Color(1, 1, 1, 1.0 if level > 0 else 0.35)

		# A hut's level is its size, not just the stars under it. Pivoted on the
		# middle of its own base so it grows up out of the grass; without that,
		# knocking a level off makes it sink into the island instead of shrinking.
		var k := CV.level_scale(level)
		for art in [tr, fb]:
			art.resized.connect(func() -> void:
				art.pivot_offset = Vector2(art.size.x * 0.5, art.size.y))
			art.pivot_offset = Vector2(rect.size.x * 0.5, rect.size.y - 56.0)
			art.scale = Vector2(k, k)
		# The contact shadow rides the ladder too, or a small hut sits on a
		# puddle drawn for a big one.
		shadow.pivot_offset = shadow.size * Vector2(0.5, 1.0)
		shadow.scale = Vector2(k, k)

		var stars := Label.new()
		stars.text = "⭐".repeat(level)
		stars.add_theme_font_override("font", CV.emoji_font())
		stars.add_theme_font_size_override("font_size", UI.F_CAPTION)
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(stars)
		stars.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		stars.offset_top = -62.0
		stars.offset_bottom = -22.0

		_building_visuals.append({
			"tex": tr, "fallback": fb, "stars": stars, "rect": rect,
			"holder": holder, "shadow": shadow, "level": level,
		})

	# banner
	# Raiding happens on somebody else's island art, so the brief sits on the
	# same brass-rimmed sea glass the rest of the game uses -- you are a visitor
	# here, and the chrome is the one thing you brought with you.
	var banner := PanelContainer.new()
	var sb := Lagoon.glass(Lagoon.R_CARD, 0.92)
	sb.set_border_width_all(4)
	sb.border_color = Lagoon.BRASS
	banner.add_theme_stylebox_override("panel", sb)
	add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 14.0
	banner.offset_right = -14.0
	banner.offset_top = 12.0 + top
	banner.offset_bottom = 110.0 + top

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	banner.add_child(vb)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 10)
	vb.add_child(title_row)
	var face := Label.new()
	face.text = npc["emoji"]
	face.add_theme_font_override("font", CV.emoji_font())
	face.add_theme_font_size_override("font_size", UI.F_SUBHEAD)
	title_row.add_child(face)
	title_row.add_child(Lagoon.label("%s's Island" % npc["name"], UI.F_SUBHEAD, Lagoon.INK, true))
	var sub := Lagoon.label(
		"Open 3 chests and take the gold!" if mode == "steal" else "Pick a target and SMASH!",
		UI.F_CAPTION, Lagoon.INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	if mode == "steal":
		_setup_chests()
	else:
		_add_raccoon()
		_setup_targets()

func _flat_button(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())

# --- steal ---

func _setup_chests() -> void:
	# The chests hold the island's own money, at the island's own price. The bet
	# is not baked in here: it lands once, at the end, as its own beat.
	var total: int = int(round(int(npc["coins"]) * coin_mult))
	var q := int(total * 0.25)
	var amounts := [q, q, total - 2 * q, 0]
	amounts.shuffle()

	var t := UI.safe_top(get_viewport_rect().size)
	_attempts_label = Lagoon.title("Attempts left: 3", UI.F_BODY, Color.WHITE, Lagoon.ABYSS)
	add_child(_attempts_label)
	_attempts_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_attempts_label.offset_top = 120.0 + t
	_attempts_label.offset_bottom = 154.0 + t

	# A running total, so the third chest is a decision made with a number in
	# hand rather than three taps in the dark.
	_loot_label = Lagoon.title("", UI.F_SUBHEAD, Lagoon.BRASS_HI, Lagoon.ABYSS)
	_loot_label.resized.connect(func() -> void:
		_loot_label.pivot_offset = _loot_label.size * 0.5)
	add_child(_loot_label)
	_loot_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_loot_label.offset_top = 158.0 + t
	_loot_label.offset_bottom = 204.0 + t

	var idxs := [0, 1, 2, 3, 4]
	idxs.shuffle()
	var chest_t := CV.prop_tex("chest")
	for k in 4:
		var rect: Rect2 = CV.SLOT_RECTS[idxs[k]]
		var btn := Button.new()
		btn.size = Vector2(130, 120)
		btn.position = rect.position + rect.size * 0.5 - Vector2(65, 90)
		_flat_button(btn)
		if chest_t != null:
			btn.icon = chest_t
			btn.expand_icon = true
		else:
			btn.text = "📦"
			btn.add_theme_font_override("font", CV.emoji_font())
			btn.add_theme_font_size_override("font_size", 70)
		btn.pressed.connect(_on_chest.bind(btn, amounts[k]))
		_stage.add_child(btn)
		FX.pop_in(btn, 0.35)
		FX.float_bob(btn, 6.0, randf_range(1.4, 2.0))

func _on_chest(btn: Button, amount: int) -> void:
	if _picks_left <= 0 or btn.disabled:
		return
	btn.disabled = true
	_picks_left -= 1
	_attempts_label.text = "Attempts left: %d" % _picks_left
	var open_t := CV.prop_tex("chest_open")
	if open_t != null and btn.icon != null:
		btn.icon = open_t
	Sfx.play("raid", -6.0)
	var pos := btn.position + Vector2(20, -20)
	if amount > 0:
		_stolen += amount
		Sfx.play("coins", -4.0)
		FX.rise_label(_stage, pos, "+%s" % UI.fmt_compact(amount), Lagoon.BRASS_HI, 38)
		FX.fly_coins(_stage, btn.position + btn.size * 0.5, Vector2(90, 40), 5)
		FX.burst(_stage, btn.position + btn.size * 0.5, Color(1.0, 0.8, 0.3), 10)
		_loot_label.text = "Loot  %s" % UI.fmt_compact(_stolen)
		FX.pop_in(_loot_label, 0.26)
	else:
		FX.rise_label(_stage, pos, "Empty!", Color(0.85, 0.85, 0.85), 30)
	if _picks_left == 0:
		var tw := create_tween()
		tw.tween_interval(0.55)
		tw.tween_callback(func() -> void:
			if _stolen <= 0:
				finished.emit({"mode": "steal", "npc": npc, "stolen": 0, "base": 0})
				return
			_payout(_stolen, func() -> void:
				finished.emit({
					"mode": "steal", "npc": npc,
					"stolen": _stolen * maxi(1, mult), "base": _stolen,
				}))
		)

# =============================================================================
#  Attack
# =============================================================================
#
# An attack used to be: tap a target, a number goes down. Everything the player
# was told about it arrived as text on top of a still picture, so a raid -- the
# most aggressive thing in the game -- had less physical presence than opening
# a chest.
#
# It is now a sequence with somebody in it. The raccoon winds up, throws the
# hammer the reels landed on, and the island answers: either a shield comes up
# over the hut and swats it away, or the hut takes it, drops visibly to the
# level below and smokes. Nothing here changes what a raid *does*; it changes
# whether you can see it happen.

func _add_raccoon() -> void:
	_rac_holder = Control.new()
	_rac_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# His own band inside the island. The rig sorts fifteen pieces against each
	# other, and without a band of its own a leg at the bottom of that stack
	# sorts against the island art instead of against his belly.
	_rac_holder.z_index = 10
	_stage.add_child(_rac_holder)
	_rac_holder.position = RAC_POS
	_rac_holder.size = RAC_BOX

	# The contact shadow is not his child: it has to stay put while he leans and
	# lunges over it, which is the whole reason it reads as ground.
	var shade := ColorRect.new()
	shade.material = CV.contact_shadow_material()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.size = Vector2(200, 54)
	shade.position = RAC_POS + Vector2(RAC_BOX.x * 0.5 - 100.0, RAC_BOX.y - 44.0)
	_stage.add_child(shade)

	# Fifteen pieces on joints if the cut-out art is there, one flat drawing if
	# it is not. A missing part should cost the raid its articulation, never its
	# attacker.
	var rig := MascotRig.new()
	if rig.build():
		_rac = rig
		_rac_holder.add_child(rig)
		rig.size = RAC_BOX
	else:
		var flat := TextureRect.new()
		flat.texture = CV.symbol_tex("steal")
		flat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rac_holder.add_child(flat)
		flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# He runs on from off the left edge rather than being there from frame one:
	# the island has just slid in, and somebody arriving on it is the cheapest
	# possible way to say whose turn it is.
	_rac_holder.position = RAC_POS - Vector2(320, 0)
	shade.modulate.a = 0.0
	var tw := _rac_holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rac_holder, "position", RAC_POS, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	tw.tween_property(shade, "modulate:a", 1.0, 0.4).set_delay(0.25)
	tw.chain().tween_callback(func() -> void: _entered = true)

func _set_act(act: String) -> void:
	_act = act
	_act_t = 0.0

# The performance, written once a frame. MascotRig owns everything involuntary
# on top of this -- breathing, blinking, the tail and ears arriving late -- so
# all that is needed here is where the deliberate joints are pointing.
func _process(delta: float) -> void:
	if _rac == null:
		return
	_act_t += delta
	var t := _act_t
	# Arm signs: positive swings a hand toward screen-left, negative toward
	# screen-right. The huts are to his right, so a throw is an arc through
	# negative on the right arm. Legs read the same way, and they are where the
	# weight of the throw lives: this performance used to hand the rig a `lean`
	# it has never had, so every frame of it threw the write away and the throw
	# happened entirely above the waist. Weight is a stance and a step now,
	# which is also the only way to sell it on flat art -- tilting the drawing
	# reads as a sticker being waggled.
	match _act:
		"idle":
			var s := sin(t * 1.7)
			var sway := sin(t * 1.05)
			_rac.arm = Vector2(0.10 * s, -0.10 * s)
			_rac.leg = Vector2(0.05 * sway, 0.05 * sway)
			_rac.look = Vector2(0.6, -0.05)
			_rac.mouth = 0.0
			_rac.body = Vector2(5.0 * sway, 0.0)
			_rac.squash = Vector2.ZERO
			_rac.head_turn = 0.0
		"wind":
			# Weight goes back onto the heels and the throwing arm cocks behind
			# his ear. Squared easing so the load builds instead of snapping.
			var u := clampf(t / 0.40, 0.0, 1.0)
			var e := u * u
			_rac.arm = Vector2(0.55 * e, -2.55 * e)
			# Braced: the back foot plants and the front one takes the load off,
			# so the whole rig is visibly loaded before anything is released.
			_rac.leg = Vector2(0.10 * e, 0.36 * e)
			_rac.body = Vector2(-30.0 * e, 0.0)
			_rac.squash = Vector2(0.06 * e, -0.08 * e)
			_rac.look = Vector2(0.95, -0.3)
			_rac.mouth = 0.3 * e
			_rac.head_turn = -0.10 * e
		"throw":
			var u := clampf(t / 0.18, 0.0, 1.0)
			_rac.arm = Vector2(lerpf(0.55, -0.20, u), lerpf(-2.55, -0.55, u))
			# ...and it comes out of the legs first. He steps through the throw
			# rather than pivoting on the spot.
			_rac.leg = Vector2(lerpf(0.10, -0.32, u), lerpf(0.36, -0.12, u))
			_rac.body = Vector2(lerpf(-30.0, 34.0, u), 0.0)
			_rac.squash = Vector2(lerpf(0.06, -0.05, u), lerpf(-0.08, 0.04, u))
			_rac.look = Vector2(1.0, -0.45)
			_rac.mouth = 1.0
			_rac.head_turn = lerpf(-0.10, 0.08, u)
		"cheer":
			# Both fists up, bouncing on the spot, settling as the shout runs out.
			var decay := exp(-t * 1.1)
			var hop := absf(sin(t * 8.0)) * decay
			_rac.arm = Vector2(2.35 + 0.30 * hop, -2.35 - 0.30 * hop)
			# Legs tuck under him at the top of each hop, which is what makes a
			# vertical displacement read as a jump instead of a lift.
			_rac.leg = Vector2(-0.26 * hop, 0.26 * hop)
			_rac.body = Vector2(0.0, -46.0 * hop)
			_rac.squash = Vector2(-0.05 * hop, 0.07 * hop)
			_rac.look = Vector2(0.35, -0.5)
			_rac.mouth = clampf(0.35 + 0.65 * hop, 0.0, 1.0)
			_rac.head_turn = 0.0
		"boo":
			# Shoulders drop, chin drops, the whole rig sinks a few units. He is
			# not hurt, he is annoyed, and the difference is all in the timing.
			var u := clampf(t / 0.45, 0.0, 1.0)
			var sag := sin(u * PI * 0.5)
			_rac.arm = Vector2(-0.45 * sag, 0.45 * sag)
			_rac.leg = Vector2(0.12 * sag, -0.12 * sag)
			_rac.body = Vector2(0.0, 16.0 * sag)
			_rac.squash = Vector2(0.07 * sag, -0.09 * sag)
			_rac.look = Vector2(0.8, 0.45)
			_rac.mouth = 0.18 * sag
			_rac.head_turn = 0.14 * sag
	# `body` is only an input to the rig's springs -- it tells the tail and the
	# ears what the body just did. Actually displacing him is the caller's job,
	# and without this the lunge and the hop drove his fur and nothing else.
	if _entered:
		_rac_holder.position = RAC_POS + _rac.body
	_rac.tick(delta)

func _setup_targets() -> void:
	# Nothing left standing on this island. There is no button to draw, so
	# without this the raid overlay sits there forever with no target, no close
	# and nothing under it reachable -- the game is simply over until the app is
	# killed. main.gd now steers attacks away from flattened rivals, but the
	# raid is the last place that can still be holding the player, so it refuses
	# the job here rather than trusting the caller.
	var standing := 0
	for i in CV.BUILDINGS.size():
		if int(npc["buildings"][i]) > 0:
			standing += 1
	if standing == 0:
		_acted = true
		var note := Lagoon.title("Nothing left standing here.", UI.F_SUBHEAD, Color.WHITE, Lagoon.ABYSS)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(note)
		note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		note.offset_top = 430.0
		note.offset_bottom = 490.0
		_finish({"mode": "attack", "npc": npc, "blocked": true, "empty": true}, 1.6)
		return

	for i in CV.BUILDINGS.size():
		if int(npc["buildings"][i]) <= 0:
			continue
		var rect: Rect2 = CV.SLOT_RECTS[i]
		var btn := Button.new()
		btn.size = Vector2(110, 110)
		btn.position = rect.position + rect.size * 0.5 - Vector2(55, 85)
		_flat_button(btn)
		btn.text = "🎯"
		btn.add_theme_font_override("font", CV.emoji_font())
		btn.add_theme_font_size_override("font_size", 62)
		btn.pressed.connect(_on_target.bind(i))
		_stage.add_child(btn)
		FX.pop_in(btn, 0.35)
		FX.pulse_forever(btn, 1.12, 0.7)
		_target_buttons.append(btn)

# Where the hammer leaves him. Taken off the actual paw rather than off a fixed
# offset, because the paw is mid-swing when it lets go and a fixed offset puts
# the throw an arm's length away from the arm that threw it.
func _paw() -> Vector2:
	var fallback := RAC_POS + Vector2(RAC_BOX.x * 0.72, RAC_BOX.y * 0.34)
	if _rac == null or not _rac.built:
		return fallback
	var world := _rac.bone_global("arm_r", Vector2(6.0, 118.0))
	return _stage.get_global_transform().affine_inverse() * world

func _on_target(i: int) -> void:
	if _acted:
		return
	_acted = true
	for b in _target_buttons:
		b.queue_free()
	_target_buttons.clear()
	var rect: Rect2 = CV.SLOT_RECTS[i]
	var center := rect.position + rect.size * Vector2(0.5, 0.42)

	_set_act("wind")
	Sfx.play("tick", -14.0)
	var seq := create_tween()
	seq.tween_interval(0.40)
	seq.tween_callback(_throw_at.bind(i, center))

func _throw_at(i: int, center: Vector2) -> void:
	_set_act("throw")
	Sfx.play("raid", -8.0)
	var from := _paw()

	# The hammer, because that is the symbol the reels landed on to get here --
	# three hammers is what an attack *is*, so it is the thing that gets thrown.
	var proj: Control
	var ht := CV.symbol_tex("hammer")
	if ht != null:
		var tr := TextureRect.new()
		tr.texture = ht
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(104, 104)
		proj = tr
	else:
		var l := Label.new()
		l.text = "🔨"
		l.add_theme_font_override("font", CV.emoji_font())
		l.add_theme_font_size_override("font_size", 80)
		l.size = Vector2(104, 104)
		proj = l
	proj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	proj.z_index = 96
	_stage.add_child(proj)

	# Dust off the foot he pushed off with.
	FX.smoke(_stage, RAC_POS + Vector2(RAC_BOX.x * 0.5, RAC_BOX.y - 30.0), 4, 70.0,
		Color(0.88, 0.84, 0.72), 0.12)

	var tw := FX.throw_arc(proj, from, center, 300.0, 0.52, TAU * 2.2)
	tw.tween_callback(_impact.bind(i, center, proj))

func _impact(i: int, center: Vector2, proj: Control) -> void:
	if bool(npc["shield"]):
		npc["shield"] = false
		_blocked(center, proj)
		_finish({"mode": "attack", "npc": npc, "blocked": true}, 2.0)
	else:
		proj.queue_free()
		npc["buildings"][i] = maxi(0, int(npc["buildings"][i]) - 1)
		_smash(i, center)
		# The gold used to be credited silently back on the SPIN page, one page
		# transition after the thing that earned it. It is paid here now, while
		# the hut is still smoking, because that is where the player is looking.
		var pay := create_tween()
		pay.tween_interval(0.95)
		pay.tween_callback(func() -> void:
			_payout(attack_reward, func() -> void:
				finished.emit({
					"mode": "attack", "npc": npc, "blocked": false, "target": i,
					"reward": attack_reward * maxi(1, mult), "base": attack_reward,
				}))
		)

# --- the shield holds --------------------------------------------------------
#
# The old version faded a small shield sprite in over the hut *after* the fact,
# which read as a label rather than as a save. It now arrives ahead of the
# hammer, at a size that clearly covers the whole building, and the hammer
# visibly bounces off it -- so the player watches the block happen instead of
# being told it did.
func _blocked(center: Vector2, proj: Control) -> void:
	var dome := _shield_dome(center)
	Sfx.play("shield", -2.0)
	FX.shake(self, 10.0, 6)
	FX.ring(_stage, center, Color(0.55, 0.92, 1.0, 0.95), 250.0, 0.5, 10.0)
	FX.ring(_stage, center, Color(1.0, 1.0, 1.0, 0.7), 170.0, 0.36, 6.0)
	FX.burst(_stage, center, Color(0.6, 0.9, 1.0), 16)

	# The hammer comes off it, spinning, and drops out of the scene.
	var away := center + Vector2(randf_range(-260, -160), -230)
	var bt := proj.create_tween()
	bt.set_parallel(true)
	bt.tween_property(proj, "position", away - proj.size * 0.5, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bt.tween_property(proj, "rotation", proj.rotation - TAU * 1.4, 0.55)
	bt.tween_property(proj, "modulate:a", 0.0, 0.55).set_delay(0.2)
	bt.chain().tween_callback(proj.queue_free)

	FX.rise_label(_stage, center + Vector2(-92, -140), "BLOCKED!", Lagoon.LAGOON, 40)
	_set_act("boo")

	# It holds for a beat, flares once, and lets go -- a shield that simply
	# faded looked like it had been switched off rather than spent.
	var dt := dome.create_tween()
	dt.tween_interval(0.75)
	dt.tween_property(dome, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.12)
	dt.set_parallel(true)
	dt.tween_property(dome, "modulate:a", 0.0, 0.45)
	dt.tween_property(dome, "scale", Vector2(1.25, 1.25), 0.45).set_trans(Tween.TRANS_BACK)
	dt.chain().tween_callback(dome.queue_free)

func _shield_dome(center: Vector2) -> Control:
	var box := Vector2(300, 300)
	var dome := Control.new()
	dome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dome.size = box
	dome.position = center - box * 0.5
	dome.pivot_offset = box * 0.5
	dome.z_index = 95
	_stage.add_child(dome)

	# A pane of lit glass under the crest, so the thing that stops the hammer is
	# the barrier and not the badge on it.
	var pane := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.92, 1.0, 0.26)
	sb.set_corner_radius_all(150)
	sb.set_border_width_all(7)
	sb.border_color = Color(0.78, 0.98, 1.0, 0.92)
	sb.shadow_size = 26
	sb.shadow_color = Color(0.35, 0.85, 1.0, 0.5)
	pane.add_theme_stylebox_override("panel", sb)
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dome.add_child(pane)
	pane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var crest_t := CV.symbol_tex("shield")
	if crest_t != null:
		var crest := TextureRect.new()
		crest.texture = crest_t
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dome.add_child(crest)
		crest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for m in [["offset_left", 68.0], ["offset_right", -68.0], ["offset_top", 68.0], ["offset_bottom", -68.0]]:
			crest.set(m[0], m[1])
	else:
		var l := Label.new()
		l.text = "🛡️"
		l.add_theme_font_override("font", CV.emoji_font())
		l.add_theme_font_size_override("font_size", 130)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dome.add_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Slams shut rather than growing: it is a save, and a save is abrupt.
	dome.scale = Vector2(1.5, 1.5)
	dome.modulate.a = 0.0
	var tw := dome.create_tween()
	tw.set_parallel(true)
	tw.tween_property(dome, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(dome, "modulate:a", 1.0, 0.12)
	return dome

# --- the hut takes it --------------------------------------------------------

func _smash(i: int, center: Vector2) -> void:
	var vis: Dictionary = _building_visuals[i]
	var new_level: int = int(npc["buildings"][i])

	Sfx.play("attack", -2.0)
	FX.flash(_stage, Color(1.0, 0.88, 0.6, 0.45))
	FX.ring(_stage, center, Color(1.0, 0.72, 0.3, 0.9), 260.0, 0.45, 11.0)
	FX.burst(_stage, center, Color(1.0, 0.55, 0.2), 26)
	FX.burst(_stage, center, Color(0.55, 0.45, 0.38), 14)
	FX.shake(self, 24.0, 9)

	# The hut is hit, recoils, and settles at the size the level below stands
	# at. Two things say "one level less" at once -- the silhouette shrinks and
	# a star leaves -- because either alone is missable in a shaking frame.
	var holder: Control = vis["holder"]
	FX.shake(holder, 12.0, 6)
	var k := CV.level_scale(new_level)
	for art in [vis["tex"], vis["fallback"], vis["shadow"]]:
		var a: Control = art
		var tw := a.create_tween()
		tw.tween_property(a, "scale", Vector2(k * 1.10, k * 0.84), 0.10).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(a, "scale", Vector2(k, k), 0.42).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if new_level <= 0:
		var gone := Color(0.5, 0.5, 0.5, 0.4)
		vis["tex"].modulate = gone
		vis["fallback"].modulate = gone
		(vis["shadow"] as Control).modulate = Color(1, 1, 1, 0.35)

	# The lost star is thrown clear rather than deleted, so the count going down
	# has something visible attached to it.
	var stars: Label = vis["stars"]
	var rect: Rect2 = vis["rect"]
	var lost := Label.new()
	lost.text = "⭐"
	lost.add_theme_font_override("font", CV.emoji_font())
	lost.add_theme_font_size_override("font_size", 52)
	lost.z_index = 97
	lost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lost.position = rect.position + Vector2(rect.size.x * 0.5 - 26.0, rect.size.y - 70.0)
	_stage.add_child(lost)
	var lt := lost.create_tween()
	lt.set_parallel(true)
	lt.tween_property(lost, "position", lost.position + Vector2(randf_range(60, 130), -150), 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lt.tween_property(lost, "rotation", TAU * 0.8, 0.8)
	lt.tween_property(lost, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	lt.chain().tween_callback(lost.queue_free)
	stars.text = "⭐".repeat(new_level)
	FX.pop_in(stars, 0.3)

	# Still burning after the bang. This is the part that makes the damage look
	# permanent rather than like a flash that has already been forgotten.
	var base := rect.position + Vector2(rect.size.x * 0.5, rect.size.y - 90.0)
	FX.smoke(_stage, base, 11, 260.0, Color(0.26, 0.24, 0.24), 1.1)
	FX.smoke(_stage, base + Vector2(-40, -20), 5, 200.0, Color(0.42, 0.30, 0.24), 1.3, 0.35)
	FX.smoke(_stage, base + Vector2(46, -14), 5, 220.0, Color(0.20, 0.19, 0.20), 1.2, 0.6)

	FX.rise_label(_stage, center + Vector2(-70, -120), "-1 LEVEL", Lagoon.CORAL, 38)
	_set_act("cheer")

func _finish(result: Dictionary, hold := 1.4) -> void:
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_callback(func() -> void:
		finished.emit(result)
	)

# =============================================================================
#  The payout
# =============================================================================
#
# Both raids end on the same card now, because both raids pay the same way: the
# loot lands first, at the size the island actually held, and the bet comes
# down on top of it afterwards.
#
# It used to be multiplied out of sight. The chests were quietly pre-scaled by
# the bet, and the smash reward was scaled back on the SPIN page after the
# island had already slid away -- so the one number the player deliberately
# raised was the one number they never saw do anything. Now the multiply *is*
# the beat the sequence is built around: a figure, a stamp landing on it, and
# the same figure counting up to what the stamp made it.
#
# Roughly 1.3s at bet x1 and 2.0s above it. Fast enough not to be in the way,
# slow enough that the thing you just won does not go past unread.

# Dead centre of the island: above the raccoon, below the banner, clear of the
# huts' star rows.
const PAY_AT := Vector2(360.0, 470.0)

func _payout(base: int, done: Callable) -> void:
	var factor := maxi(1, mult)
	var total := base * factor

	# The island steps back for a moment. Without it the number is competing
	# with five huts, a raccoon and a column of smoke.
	var scrim := ColorRect.new()
	scrim.color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.0)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.z_index = 150
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.create_tween().tween_property(scrim, "color:a", 0.55, 0.16)

	# The card lives on the island's stage, so it is laid out in the same
	# 720x1280 as everything else here and lands in the same place on every
	# phone.
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size = Vector2(620.0, 210.0)
	card.position = PAY_AT - card.size * 0.5
	card.pivot_offset = card.size * 0.5
	card.z_index = 200
	_stage.add_child(card)

	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.92)
	sb.set_corner_radius_all(Lagoon.R_PANEL)
	sb.set_border_width_all(6)
	sb.border_color = Lagoon.BRASS
	sb.shadow_size = 24
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The left 130px of the card is kept empty for the stamp to park in, so the
	# figure is not shoved sideways halfway through being read.
	var cap := Lagoon.label("STOLEN" if mode == "steal" else "PLUNDERED",
		UI.F_CAPTION, Lagoon.BRASS_HI, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cap)
	cap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	cap.offset_left = 130.0
	cap.offset_top = 20.0
	cap.offset_bottom = 56.0

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 130.0
	row.offset_top = 60.0
	row.offset_bottom = -16.0

	var coin_t := CV.symbol_tex("coin")
	if coin_t != null:
		var ci := TextureRect.new()
		ci.texture = coin_t
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.custom_minimum_size = Vector2(84, 84)
		ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ci)

	var amount := Lagoon.title(UI.fmt_compact(base), UI.F_DISPLAY, Lagoon.BRASS_HI, Lagoon.ABYSS)
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The text grows as it counts, and a stale pivot would swing it off-centre
	# on the punch. Re-centred every time the label resizes.
	amount.resized.connect(func() -> void:
		amount.pivot_offset = amount.size * 0.5)
	row.add_child(amount)

	var badge := _mult_badge("x%d" % factor)
	badge.visible = factor > 1
	card.add_child(badge)
	var land := Vector2(card.size.x * 0.5 + 52.0, card.size.y * 0.5 + 16.0) - badge.size * 0.5
	# Parked inside the brass rim, not straddling it -- the left 130px of the
	# card was left empty for exactly this.
	var park := Vector2(92.0, card.size.y * 0.5 + 6.0) - badge.size * 0.5
	badge.position = land

	Sfx.play("coins", -3.0)
	card.scale = Vector2(0.34, 0.34)
	card.modulate.a = 0.0
	var seq := card.create_tween()
	seq.tween_property(card, "modulate:a", 1.0, 0.10)
	seq.parallel().tween_property(card, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	seq.parallel().tween_callback(func() -> void:
		FX.ring(_stage, PAY_AT, Lagoon.BRASS_HI, 300.0, 0.45, 9.0)).set_delay(0.08)

	if factor > 1:
		badge.scale = Vector2(2.8, 2.8)
		badge.modulate.a = 0.0
		var write := func(v: float) -> void:
			amount.text = UI.fmt_compact(int(round(v)))
		# The stamp comes down *onto* the figure and accelerates into it, which
		# is the whole difference between a multiplier landing and a badge
		# merely appearing next to one.
		seq.tween_interval(0.22)
		seq.tween_property(badge, "scale", Vector2.ONE, 0.19) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		seq.parallel().tween_property(badge, "modulate:a", 1.0, 0.10)
		seq.tween_callback(_pay_impact.bind(card, amount))
		seq.parallel().tween_method(write, float(base), float(total), 0.52) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# Then it gets out of the figure's way without leaving the card, so the
		# reason the number grew is still on screen while the number is read.
		seq.parallel().tween_property(badge, "position", park, 0.34) \
			.set_delay(0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		seq.tween_interval(0.58)
	else:
		seq.tween_interval(0.72)

	seq.tween_property(card, "scale", Vector2(1.14, 1.14), 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	seq.parallel().tween_property(card, "modulate:a", 0.0, 0.20)
	seq.parallel().tween_property(scrim, "color:a", 0.0, 0.24)
	seq.tween_callback(func() -> void:
		scrim.queue_free()
		card.queue_free()
		done.call())

# The moment the bet lands on the loot: a bang big enough that the figure
# changing under it reads as a consequence rather than a redraw.
func _pay_impact(card: Control, amount: Label) -> void:
	Sfx.play("jackpot", -4.0)
	FX.shake(card, 13.0, 5)
	FX.burst(_stage, PAY_AT, Lagoon.BRASS_HI, 24)
	FX.ring(_stage, PAY_AT, Lagoon.CORAL_HI, 360.0, 0.5, 13.0)
	FX.flash(_stage, Color(1.0, 0.92, 0.62, 0.30))
	amount.pivot_offset = amount.size * 0.5
	var pt := amount.create_tween()
	pt.tween_property(amount, "scale", Vector2(1.34, 1.34), 0.10).set_trans(Tween.TRANS_QUAD)
	pt.tween_property(amount, "scale", Vector2.ONE, 0.40) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# The bet, as a stamp. Coral on brass and tilted off true -- deliberately not
# the game's calm sea glass, because this is the loud half of the payout and it
# should look borrowed from a louder sign.
func _mult_badge(text: String) -> Control:
	var b := Control.new()
	b.size = Vector2(136.0, 104.0)
	b.pivot_offset = b.size * 0.5
	b.rotation = -0.13
	b.z_index = 4
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Lagoon.CORAL
	s.set_corner_radius_all(Lagoon.R_CARD)
	s.set_border_width_all(6)
	s.border_color = Lagoon.BRASS_HI
	s.shadow_size = 16
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var l := Lagoon.title(text, UI.F_HEAD, Color.WHITE, Lagoon.CORAL_LO)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return b
