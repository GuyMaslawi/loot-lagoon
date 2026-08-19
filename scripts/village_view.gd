class_name VillageView
extends Control

signal upgrade_requested(index: int)

var _slots: Array = []
var _constructing := {}

func _ready() -> void:
	for i in CV.BUILDINGS.size():
		var b: Dictionary = CV.BUILDINGS[i]
		var rect: Rect2 = CV.SLOT_RECTS[i]
		var root := Control.new()
		root.position = rect.position
		root.size = rect.size
		add_child(root)

		var shadow := ColorRect.new()
		shadow.material = CV.contact_shadow_material()
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sw := rect.size.x * 0.68
		shadow.size = Vector2(sw, 56)
		shadow.position = Vector2((rect.size.x - sw) * 0.5, rect.size.y - 86.0 - 46.0)
		root.add_child(shadow)

		var tr := TextureRect.new()
		tr.texture = CV.building_tex(b["id"])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.material = CV.ground_blend_material().duplicate()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_bottom = -86.0

		var fallback := Label.new()
		fallback.text = b["emoji"]
		fallback.add_theme_font_override("font", CV.emoji_font())
		fallback.add_theme_font_size_override("font_size", 90)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.visible = tr.texture == null
		tr.visible = tr.texture != null
		root.add_child(fallback)
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.offset_bottom = -86.0

		var scaffold := TextureRect.new()
		scaffold.texture = CV.prop_tex("scaffold")
		scaffold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scaffold.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		scaffold.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scaffold.visible = false
		root.add_child(scaffold)
		scaffold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scaffold.offset_bottom = -86.0

		var scaffold_fb := Label.new()
		scaffold_fb.text = "🏗️"
		scaffold_fb.add_theme_font_override("font", CV.emoji_font())
		scaffold_fb.add_theme_font_size_override("font_size", 90)
		scaffold_fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		scaffold_fb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		scaffold_fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scaffold_fb.visible = false
		root.add_child(scaffold_fb)
		scaffold_fb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scaffold_fb.offset_bottom = -86.0

		var progress := ProgressBar.new()
		progress.show_percentage = false
		progress.visible = false
		var pb_bg := StyleBoxFlat.new()
		pb_bg.bg_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.55)
		pb_bg.set_corner_radius_all(6)
		var pb_fg := StyleBoxFlat.new()
		pb_fg.bg_color = Lagoon.BRASS_HI
		pb_fg.set_corner_radius_all(6)
		progress.add_theme_stylebox_override("background", pb_bg)
		progress.add_theme_stylebox_override("fill", pb_fg)
		root.add_child(progress)
		progress.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		progress.offset_top = -152.0
		progress.offset_bottom = -132.0

		var stars := Label.new()
		stars.add_theme_font_override("font", CV.emoji_font())
		stars.add_theme_font_size_override("font_size", UI.F_CAPTION)
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(stars)
		stars.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		stars.offset_top = -128.0
		stars.offset_bottom = -92.0

		# Building names sit on painted island art, which is the busiest surface
		# in the game -- a thin outline is not enough to separate them from it.
		var bname := Lagoon.title(b["name"], UI.F_CAPTION, Lagoon.SAND, Lagoon.ABYSS)
		root.add_child(bname)
		bname.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		bname.offset_top = -4.0
		bname.offset_bottom = 34.0

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, UI.TAP)
		btn.pressed.connect(func() -> void: upgrade_requested.emit(i))
		root.add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		btn.offset_top = -float(UI.TAP)

		_slots.append({
			"root": root, "tex": tr, "fallback": fallback,
			"scaffold": scaffold, "scaffold_fb": scaffold_fb,
			"progress": progress, "stars": stars, "button": btn, "name": bname,
			"shadow": shadow,
		})

func set_island(level: int) -> void:
	var bg_img := CV.bg_image(CV.island_bg_tex(level))
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		var t := CV.island_building_tex(level, i)
		var tr: TextureRect = slot["tex"]
		tr.texture = t
		tr.visible = t != null
		slot["fallback"].visible = t == null
		slot["name"].text = CV.island_building_name(level, i)
		var mat := tr.material as ShaderMaterial
		if mat != null:
			var col := CV.terrain_color_at(bg_img, CV.SLOT_RECTS[i], 86.0)
			mat.set_shader_parameter("terrain_col", Vector3(col.r, col.g, col.b))

func is_constructing(index: int) -> bool:
	return _constructing.has(index)

func refresh(buildings: Array, coins: int, costs: Array) -> void:
	for i in _slots.size():
		if _constructing.has(i):
			continue
		var slot: Dictionary = _slots[i]
		var level: int = buildings[i]
		var built := level > 0
		var mod := Color(1, 1, 1, 1.0) if built else Color(0.55, 0.55, 0.55, 0.45)
		if level >= CV.MAX_STAR:
			mod = Color(1.12, 1.05, 0.9)
		slot["tex"].modulate = mod
		slot["fallback"].modulate = mod
		slot["shadow"].modulate = Color(1, 1, 1, 1.0 if built else 0.35)
		slot["stars"].text = "⭐".repeat(level)
		var btn: Button = slot["button"]
		if level >= CV.MAX_STAR:
			btn.text = "MAX"
			btn.disabled = true
		else:
			var cost: int = costs[level]
			btn.text = ("Build  %d" if level == 0 else "Upgrade  %d") % cost
			btn.disabled = coins < cost

func start_construction(index: int, on_done: Callable, duration := 2.2) -> void:
	_constructing[index] = true
	var slot: Dictionary = _slots[index]
	(slot["button"] as Button).disabled = true
	slot["tex"].visible = false
	slot["fallback"].visible = false
	var has_scaffold: bool = slot["scaffold"].texture != null
	slot["scaffold"].visible = has_scaffold
	slot["scaffold_fb"].visible = not has_scaffold
	FX.pop_in(slot["scaffold"] if has_scaffold else slot["scaffold_fb"])
	Sfx.play("build", -4.0)
	var pb: ProgressBar = slot["progress"]
	pb.visible = true
	pb.value = 0.0
	var tw := create_tween()
	tw.tween_property(pb, "value", 100.0, duration)
	tw.tween_callback(func() -> void:
		slot["scaffold"].visible = false
		slot["scaffold_fb"].visible = false
		pb.visible = false
		var t: TextureRect = slot["tex"]
		t.visible = t.texture != null
		slot["fallback"].visible = t.texture == null
		FX.pop_in(t if t.texture != null else slot["fallback"], 0.4)
		var root: Control = slot["root"]
		FX.burst(self, root.position + root.size * Vector2(0.5, 0.4), Color(0.9, 0.75, 0.45), 16)
		Sfx.play("pop", -4.0)
		_constructing.erase(index)
		on_done.call()
	)
