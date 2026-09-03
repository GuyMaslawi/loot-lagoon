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
			# RAID=steal|attack drops straight into the raid flow -- the search
			# screen and the island behind it -- without waiting on a triple.
			if OS.has_environment("RAID"):
				_raid.call_deferred(game, OS.get_environment("RAID"))
		"match":
			# The search screen on its own, no boot and no reels: MATCH=found
			# jumps past the sweep so the rival card can be judged at rest.
			var m := Matchmaking.new()
			m.npc = CV.new_npc(CV.BOT_DEFS[3], 6)
			m.mode = OS.get_environment("MODE") if OS.has_environment("MODE") else "steal"
			m.npc["shield"] = true
			m.stake = 242_000
			m.stars = 11
			add_child(m)
			if OS.get_environment("MATCH") == "found":
				_land.call_deferred(m)
		"mascot":
			_mascot_reel.call_deferred()
			return
		"art":
			# The two drawn objects the shop is built on, side by side and at
			# the size they ship at: three fills of the piggy and three tiers
			# of chest. Judged here rather than on the live page, where each
			# one is four screens apart from the next.
			_art_sheet()
		_:
			_glyph_sheet()
	if OS.has_environment("SHOT"):
		_shoot.call_deferred()

func _land(m: Control) -> void:
	await get_tree().create_timer(0.45).timeout
	m.call("_lock_in")

func _raid(game: Control, mode: String) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	game.call("_start_visit", "attack" if mode == "attack" else "steal")

func _spin(game: Control) -> void:
	await get_tree().create_timer(0.3).timeout
	game.call("_on_spin_requested")

func _open_page(game: Control, key: String) -> void:
	# Wait out the load sequence rather than a fixed delay -- the pages this
	# jumps to do not exist until _run_boot() has built them.
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().process_frame
	if key.begins_with("popup:"):
		# PIGGY=full|empty|<n> pins the bank before the screen opens. The three
		# faces are the point of that drawing and two of them are otherwise
		# only reachable by playing to them.
		if OS.has_environment("PIGGY"):
			var want := OS.get_environment("PIGGY")
			var cap := int(CV.PIGGY_CAP)
			game.set("piggy_coins", cap if want == "full" else (0 if want == "empty" else int(want)))
		game.call("_open_" + key.substr(6))
		return
	if key.begins_with("collections:"):
		# jump straight into one set's own page
		game.set("col_open", key.substr(12))
		game.call("_goto", game.get("pages")["collections"])
		return
	# PAGE=shop:chests parks the shop on one of its shelves, so a row that
	# lives four screens down can be judged without a scroll gesture.
	if key.begins_with("shop:"):
		game.call("_goto_shop", key.substr(5))
		return
	if key == "island":
		game.call("_goto", game.get("village_page"))
	else:
		var pages: Dictionary = game.get("pages")
		if pages.has(key):
			game.call("_goto", pages[key])

func _glyph_sheet() -> void:
	var kinds := ["coin", "wheel", "shield", "island", "shop", "cards", "quests",
		"gift", "bell", "trophy", "gear", "star", "plus", "close", "rivet", "anchor",
		"piggy", "box", "medal", "tick", "spark", "crown", "sun", "moon",
		"calendar", "warn"]
	if OS.has_environment("GLYPHS"):
		kinds = Array(OS.get_environment("GLYPHS").split(","))

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

# PREVIEW=mascot writes a strip of frames of the title screen's raccoon, so a
# change to his rig can be judged as motion rather than as one lucky pose.
#
#   PREVIEW=mascot ACT=dance ENERGY=0.6 DIR=/tmp/m godot --path . tools/preview.tscn
#
# ACT is one of the act names below, or "auto" to let him choose as he would.
func _mascot_reel() -> void:
	var boot: Control = load("res://scripts/boot.gd").new()
	add_child(boot)

	var dir := OS.get_environment("DIR") if OS.has_environment("DIR") else "/tmp/mascot"
	var frames := int(OS.get_environment("FRAMES")) if OS.has_environment("FRAMES") else 40
	var step := float(OS.get_environment("STEP")) if OS.has_environment("STEP") else 0.075
	var energy := float(OS.get_environment("ENERGY")) if OS.has_environment("ENERGY") else 0.55
	var want := OS.get_environment("ACT") if OS.has_environment("ACT") else "auto"
	var acts := {"dance": 1, "hop": 2, "peek": 3, "coin": 4, "wave": 5, "look": 6,
		"party": 7, "exit": 8}
	DirAccess.make_dir_recursive_absolute(dir)

	boot.call("_set_ratio", minf(energy, 0.99))
	# Let his entrance land before anything is asked of him -- but never wait on
	# it forever, because a rig that failed to build never gets there.
	var patience := 0.0
	while not boot.get("_live") and patience < 6.0:
		patience += get_process_delta_time()
		await get_tree().process_frame
	if not boot.get("_live"):
		push_error("mascot never came alive -- his art probably did not load")
		get_tree().quit(1)
		return

	# FADE=0.5 holds him half-faded-in: his pieces overlap, so that is the frame
	# that shows whether they are being blended one at a time or as one figure.
	if OS.has_environment("FADE"):
		var art: Control = boot.get("_mascot_art")
		var f := float(OS.get_environment("FADE"))
		if art is MascotRig:
			(art as MascotRig).fade = f
		else:
			art.modulate.a = f

	# MOOD=-1|0|1 pins his face while the reel runs, which is the only way to
	# look at a scowl or a laugh outside a live raid -- the expressions belong
	# to island_visit's acts, and getting a shield to eat a hammer on demand is
	# not a thing you can do while judging the face it produces.
	var mood_art: Control = boot.get("_mascot_art")
	var mood_set := OS.has_environment("MOOD")
	var mood_val := float(OS.get_environment("MOOD")) if mood_set else 0.0

	for i in frames:
		if mood_set and mood_art is MascotRig:
			# Written every frame: the rig springs toward it, so one write at
			# the top would be sprung away from before the first shot lands.
			(mood_art as MascotRig).mood = mood_val
		if want != "auto" and acts.has(want) and int(boot.get("_act")) == 0:
			boot.call("_begin_act", acts[want])
			boot.set("_rest", 0.0)
		await get_tree().create_timer(step).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		# The window is whatever macOS would give us, so normalise back to the
		# design canvas before cropping -- otherwise every crop is a guess.
		img.resize(720, 1280, Image.INTERPOLATE_LANCZOS)
		img = img.get_region(Rect2i(20, 330, 680, 760))
		img.save_png("%s/%03d.png" % [dir, i])
	get_tree().quit()

func _shoot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(float(OS.get_environment("SHOT_DELAY")) if OS.has_environment("SHOT_DELAY") else 0.6).timeout
	var shots := int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 1
	var gap := float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.4
	var path := OS.get_environment("SHOT")
	for i in shots:
		if i > 0:
			await get_tree().create_timer(gap).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(path if shots == 1 else path.replace(".png", "_%02d.png" % i))
	get_tree().quit()


func _art_sheet() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	col.position = Vector2(10, 30)
	col.size = Vector2(700, 0)

	var pigs := HBoxContainer.new()
	pigs.add_theme_constant_override("separation", 4)
	col.add_child(pigs)
	for f in [0.0, 0.55, 1.0]:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", Lagoon.sheet())
		cell.custom_minimum_size = Vector2(230, 260)
		pigs.add_child(cell)
		var p := PiggyArt.new()
		p.fill = f
		p.custom_minimum_size = Vector2(220, 240)
		cell.add_child(p)

	var chests := HBoxContainer.new()
	chests.add_theme_constant_override("separation", 4)
	col.add_child(chests)
	for t in 3:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", Lagoon.sheet())
		cell.custom_minimum_size = Vector2(230, 220)
		chests.add_child(cell)
		var c := ChestArt.new()
		c.tier = t
		c.custom_minimum_size = Vector2(200, 200)
		cell.add_child(c)

	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 8)
	col.add_child(small)
	# The sizes they are actually asked to work at on the page.
	for t in 3:
		var c := ChestArt.new()
		c.tier = t
		c.custom_minimum_size = Vector2(120, 110)
		small.add_child(c)
	for f in [0.0, 1.0]:
		var p := PiggyArt.new()
		p.fill = f
		p.custom_minimum_size = Vector2(120, 110)
		small.add_child(p)
