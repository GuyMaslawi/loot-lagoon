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

	_dress_the_set(game)

# A STORE SCREENSHOT OF A SAVE THAT HAS NEVER BEEN PLAYED SELLS NOTHING.
#
# The five images this harness feeds are the first thing a buyer sees, and on a
# fresh save every one of them is a picture of zero: 0/9 on all fifteen
# collection shelves, 0/8 missions, five identical Build buttons on island 1,
# and a 1,500-coin wallet. The shots this replaced showed 248K coins, a full
# spin meter and island 3 -- they were taken off a save that had been played,
# which is why they looked like a game. Nothing recorded how, so the next
# re-render lost it. This is that state, written down.
#
# It is applied AFTER boot, because `_boot_load` reads the save as its first
# step and would overwrite anything set before it, and BEFORE `_capture_page`
# stops waiting -- it opens the page immediately and then sits on a five second
# timer, so the repaint below lands well inside that window.
#
# Deliberately not a save file: nothing here touches user://, so the harness
# leaves no trace and cannot poison the save the other harnesses load.
func _dress_the_set(game: Control) -> void:
	while game.get("_boot") != null:
		await game.get_tree().process_frame

	# Mid-game, not late-game. Island 3 of ninety with the village part-raised
	# is what the second evening looks like, and it reads as a game with room
	# left rather than one already finished.
	game.coins = 248000
	game.spins = game.SPIN_CAP
	game.island_level = 3
	game.buildings = [5, 3, 2, 1, 0]
	game.stars = 11
	game.rank_stars = 11
	game.shields = 2

	# Card shelves at honest, uneven progress. A flat 5/9 everywhere reads as
	# placeholder data; the easy sets running ahead of the hard ones is what
	# actually happens, because the drop weights say so.
	var filled := [7, 6, 5, 5, 4, 4, 3, 3, 2, 2, 2, 1, 1, 1, 0]
	for i in CV.COLLECTIONS.size():
		var c: Dictionary = CV.COLLECTIONS[i]
		var owned: Array = game.col_owned[c["id"]]
		var want: int = filled[i] if i < filled.size() else 0
		# Commonest first, which is the order a player really fills a shelf --
		# the 5-star at the end of each set stays missing, so the grand prize
		# still has somewhere to go.
		var order := []
		for star in [1, 2, 3, 4]:
			for j in (c["items"] as Array).size():
				if int((c["items"] as Array)[j][2]) == star:
					order.append(j)
		for k in mini(want, order.size()):
			owned[order[k]] = true

	# THE ISLAND HAS TO BE REPAINTED, not just set.
	#
	# `island_level` is read during boot to build the slot marquee, the village
	# artwork and every page's backdrop tint, and none of them look at it again.
	# Seeding the number alone gave a set where the wallet said 248K on island 3
	# while the reels were still captioned GREEN MEADOWS and lit in island 1's
	# palette -- and the shots disagreed with EACH OTHER, because whichever page
	# was rebuilt after the seed picked the new value up and the others did not.
	# Inconsistency across five images is worse in a store listing than any one
	# of them being plain.
	game._apply_island_theme()
	game._refresh()
	# `pages` does not hold the two world pages -- the reels and the island are
	# `slot_page` and `village_page` -- so a page key that is not in it is not a
	# mistake and must not be treated as one.
	var key := OS.get_environment("SHOT")
	if game.pages.has(key):
		game._fill_page(key)
