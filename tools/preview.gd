extends Control

# Dev-only harness: renders something into the 720x1280 canvas, saves a PNG and
# quits, so design iterations can be eyeballed without driving the simulator.
#
#   PREVIEW=glyphs SHOT=/tmp/a.png godot --path . tools/preview.tscn
#   PREVIEW=game   SHOT=/tmp/b.png godot --path . tools/preview.tscn
#
# SPIN=1 starts a spin first, so SHOT_DELAY picks the frame of the reel
# animation you want to look at.
#
# Never shipped -- tools/ is excluded from the export preset.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Lagoon.backdrop(self)
	match OS.get_environment("PREVIEW"):
		"game":
			var game: Control = load("res://scripts/main.gd").new()
			add_child(game)
			# PAGE=shop|collections|quests|options|island jumps straight there
			if OS.has_environment("PAGE"):
				_open_page.call_deferred(game, OS.get_environment("PAGE"))
			if OS.has_environment("SPIN"):
				_spin.call_deferred(game)
		_:
			_glyph_sheet()
	if OS.has_environment("SHOT"):
		_shoot.call_deferred()

func _spin(game: Control) -> void:
	await get_tree().create_timer(0.3).timeout
	game.call("_on_spin_requested")

func _open_page(game: Control, key: String) -> void:
	await get_tree().create_timer(0.4).timeout
	if key.begins_with("popup:"):
		game.call("_open_" + key.substr(6))
		return
	if key.begins_with("collections:"):
		# jump straight into one set's own page
		game.set("col_open", key.substr(12))
		game.call("_goto", game.get("pages")["collections"])
		return
	if key == "island":
		game.call("_goto", game.get("village_page"))
	else:
		var pages: Dictionary = game.get("pages")
		if pages.has(key):
			game.call("_goto", pages[key])

func _glyph_sheet() -> void:
	var kinds := ["coin", "wheel", "shield", "island", "shop", "cards", "quests",
		"gift", "bell", "trophy", "gear", "star", "plus", "close", "rivet", "anchor"]

	var t := Lagoon.plaque("ICON  SET", 460, 84, 46)
	add_child(t)
	t.position = Vector2(130, 24)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)
	grid.position = Vector2(24, 140)
	for k in kinds:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", Lagoon.glass(Lagoon.R_CARD))
		cell.custom_minimum_size = Vector2(158, 158)
		grid.add_child(cell)
		var g := Glyph.new()
		g.kind = k
		cell.add_child(g)
		var cap := Lagoon.label(k, UI.F_TINY, Lagoon.INK_SOFT)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(cap)
		cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		cap.offset_top = -26.0

	# button kinds, on the same page, so materials can be compared side by side
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	row.position = Vector2(60, 840)
	row.size = Vector2(600, 0)
	for kind in ["primary", "brass", "kelp", "urchin", "glass", "danger"]:
		var b := Button.new()
		b.text = kind.to_upper()
		b.custom_minimum_size = Vector2(600, UI.TAP)
		Lagoon.button(b, kind)
		row.add_child(b)
		Lagoon.button_gloss(b, 22)

func _shoot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(float(OS.get_environment("SHOT_DELAY")) if OS.has_environment("SHOT_DELAY") else 0.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT"))
	get_tree().quit()
