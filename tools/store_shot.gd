extends Node

# Store screenshots at Apple's exact pixel size, from a window that does not
# have to be that big.
#
#   SHOT=slot STORE_SIZE=1290x2796 godot --path . tools/store_shot.tscn
#
# WHY THIS EXISTS. main.gd's SHOT harness captures get_viewport(), which is the
# window -- and macOS clamps a window to the screen, so a 2796-tall one comes
# back 1986 tall and the layout is a different aspect entirely, not a crop.
# Apple's 6.7" slot wants exactly 1290x2796 and will take nothing else, so the
# choice was upscaling a short render or rendering at the real size off-screen.
#
# A SubViewport is not clamped by anything. Parenting main.gd inside one makes
# its own get_viewport() return the SubViewport, so its existing _capture_page
# writes user://shot_<key>.png at whatever size is set here and quits by itself.
# Nothing in main.gd knows or needs to.
#
# Never shipped -- tools/ is excluded from the export preset.

func _ready() -> void:
	var size := Vector2i(1290, 2796)
	var want := OS.get_environment("STORE_SIZE")
	if want.contains("x"):
		var parts := want.split("x")
		size = Vector2i(int(parts[0]), int(parts[1]))

	var vp := SubViewport.new()
	vp.size = size
	# Without this the texture is never drawn and the capture comes back black;
	# a SubViewport defaults to updating only when something asks it to.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The game reads sizes off its own viewport for layout, so it has to believe
	# it owns this one -- which it does.
	vp.handle_input_locally = true
	add_child(vp)

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(host)
	# Same order preview.gd uses: the sky goes down before the game does.
	Lagoon.backdrop(host)
	var game: Control = load("res://scripts/main.gd").new()
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(game)

	# An empty profile makes _after_boot raise the sign-in gate over everything,
	# and _capture_page photographs that instead of the page it was asked for --
	# it waits on _boot, which is already gone by then, not on the login layer.
	# A guest profile is what a phone that has been opened once looks like, and
	# it is the state the store screenshots are supposed to show. Set here
	# rather than on disk so the harness leaves no trace in user://.
	if game.profile.is_empty():
		game.profile = {"name": "Guest", "email": "", "provider": "guest"}
