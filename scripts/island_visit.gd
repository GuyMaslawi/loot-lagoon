class_name IslandVisit
extends Control

signal finished(result: Dictionary)

var npc: Dictionary
var mode := "steal"
var mult := 1

var _picks_left := 3
var _stolen := 0
var _acted := false
var _attempts_label: Label
var _target_buttons: Array = []
var _building_visuals: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var npc_island: int = int(npc.get("island", 1))
	var bg_t := CV.island_bg_tex(npc_island)
	if bg_t != null:
		var bg := TextureRect.new()
		bg.texture = bg_t
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.5, 0.75, 0.55)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if mode == "attack":
		var tint := ColorRect.new()
		tint.color = Color(0.55, 0.05, 0.05, 0.16)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tint)
		tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg_img := CV.bg_image(bg_t)
	for i in CV.BUILDINGS.size():
		var b: Dictionary = CV.BUILDINGS[i]
		var rect: Rect2 = CV.SLOT_RECTS[i]
		var level: int = int(npc["buildings"][i])
		var holder := Control.new()
		holder.position = rect.position
		holder.size = rect.size
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)

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

		_building_visuals.append({"tex": tr, "fallback": fb, "stars": stars, "rect": rect})

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
	banner.offset_top = 12.0
	banner.offset_bottom = 110.0

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
		_setup_targets()

func _flat_button(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())

# --- steal ---

func _setup_chests() -> void:
	var total: int = int(npc["coins"]) * mult
	var q := int(total * 0.25)
	var amounts := [q, q, total - 2 * q, 0]
	amounts.shuffle()

	_attempts_label = Lagoon.title("Attempts left: 3", UI.F_BODY, Color.WHITE, Lagoon.ABYSS)
	add_child(_attempts_label)
	_attempts_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_attempts_label.offset_top = 120.0
	_attempts_label.offset_bottom = 154.0

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
		add_child(btn)
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
		FX.rise_label(self, pos, "+%d" % amount, Lagoon.BRASS_HI, 32)
		FX.fly_coins(self, btn.position + btn.size * 0.5, Vector2(90, 40), 5)
		FX.burst(self, btn.position + btn.size * 0.5, Color(1.0, 0.8, 0.3), 10)
	else:
		FX.rise_label(self, pos, "Empty!", Color(0.85, 0.85, 0.85), 26)
	if _picks_left == 0:
		var tw := create_tween()
		tw.tween_interval(1.3)
		tw.tween_callback(func() -> void:
			finished.emit({"mode": "steal", "npc": npc, "stolen": _stolen})
		)

# --- attack ---

func _setup_targets() -> void:
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
		add_child(btn)
		FX.pop_in(btn, 0.35)
		FX.pulse_forever(btn, 1.12, 0.7)
		_target_buttons.append(btn)

func _on_target(i: int) -> void:
	if _acted:
		return
	_acted = true
	for b in _target_buttons:
		b.queue_free()
	_target_buttons.clear()
	var rect: Rect2 = CV.SLOT_RECTS[i]
	var center := rect.position + rect.size * Vector2(0.5, 0.4)
	if bool(npc["shield"]):
		npc["shield"] = false
		var sh_t := CV.symbol_tex("shield")
		if sh_t != null:
			var sh := TextureRect.new()
			sh.texture = sh_t
			sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sh.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sh.size = Vector2(170, 170)
			sh.position = center - Vector2(85, 85)
			sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(sh)
			FX.pop_in(sh, 0.3)
			create_tween().tween_property(sh, "modulate:a", 0.0, 0.6).set_delay(1.0)
		Sfx.play("shield", -2.0)
		FX.shake(self, 8.0, 5)
		FX.rise_label(self, center + Vector2(-60, -60), "BLOCKED!", Lagoon.LAGOON, 36)
		_finish({"mode": "attack", "npc": npc, "blocked": true})
	else:
		npc["buildings"][i] = maxi(0, int(npc["buildings"][i]) - 1)
		Sfx.play("attack", -2.0)
		FX.burst(self, center, Color(1.0, 0.55, 0.2), 22)
		FX.shake(self, 18.0, 8)
		var vis: Dictionary = _building_visuals[i]
		var new_level: int = int(npc["buildings"][i])
		vis["stars"].text = "⭐".repeat(new_level)
		var mod := Color(1, 1, 1) if new_level > 0 else Color(0.5, 0.5, 0.5, 0.4)
		vis["tex"].modulate = mod
		vis["fallback"].modulate = mod
		FX.rise_label(self, center + Vector2(-40, -50), "-1 LEVEL", Lagoon.CORAL, 34)
		_finish({"mode": "attack", "npc": npc, "blocked": false, "target": i})

func _finish(result: Dictionary) -> void:
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(func() -> void:
		finished.emit(result)
	)
