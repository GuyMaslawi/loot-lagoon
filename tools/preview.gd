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
			# GUEST=1 answers the first-run sign-in screen the way a player
			# would, because a harness run on a fresh user:// otherwise sits
			# behind it forever. SPINS=<n> then sets the meter -- SPINS=0 is
			# the only way to look at the out-of-spins state on demand.
			if OS.has_environment("GUEST") or OS.has_environment("SPINS"):
				_seed.call_deferred(game)
			# PAGE=shop|collections|quests|options|island jumps straight there
			if OS.has_environment("PAGE"):
				_open_page.call_deferred(game, OS.get_environment("PAGE"))
			if OS.has_environment("SPIN"):
				_spin.call_deferred(game)
			# GRANT=shields:5 hands the game a reward on demand. The shield
			# overflow is three beats over about 1.7s and the only way to it in
			# play is a lucky roll on a full bucket, so SHOTS/SHOT_GAP over
			# this is how the sequence gets judged at all.
			if OS.has_environment("GRANT"):
				_grant.call_deferred(game, OS.get_environment("GRANT"))
			# RAID=steal|attack drops straight into the raid flow -- the search
			# screen and the island behind it -- without waiting on a triple.
			if OS.has_environment("RAID"):
				_raid.call_deferred(game, OS.get_environment("RAID"))
			# SCORE=<n>[:<tier>] parks the tournament n points under a rung and
			# then scores a build, which is the only way to watch the whole
			# sequence Guy asked for -- points flying to the trophy, the trophy
			# pressing itself, the bar rising and the prize landing. In play it
			# takes a real seventy-two hour cycle and a couple of thousand
			# points to arrive at, and it is about six seconds long.
			if OS.has_environment("SCORE"):
				_score.call_deferred(game, OS.get_environment("SCORE"))
			# CLAIM=daily opens the daily bonus and presses its button, which
			# is the only way to watch the prizes leave the card: in play it
			# needs a save whose 24 hours happen to be up, and the flights are
			# about two seconds long. SHOTS/SHOT_GAP over this is how the
			# sequence gets judged as motion rather than as a still.
			if OS.has_environment("CLAIM"):
				_claim.call_deferred(game, OS.get_environment("CLAIM"))
			# CAMEO=<kind> fires one of the resident raccoon's reactions on
			# the spin page (the env var keeps its old name; the raccoon does
			# not leave any more). In play each is gated behind the event it
			# is named for, and a reaction is one to three seconds of motion,
			# which a still of either end proves nothing about.
			if OS.has_environment("CAMEO"):
				_cameo.call_deferred(game, OS.get_environment("CAMEO"))
			# DEAL=<taken>[:take] opens the deal ladder with that many rungs
			# already down. `:take` then presses the live rung, which is the
			# only way to watch the two beats the ladder is built around --
			# the rung being spent and the next one coming unlocked. In play
			# a ladder rolls in on its own clock and the pair is about two
			# seconds long, so SHOTS/SHOT_GAP over this is how it gets judged.
			if OS.has_environment("DEAL"):
				_deal.call_deferred(game, OS.get_environment("DEAL"))
			# POWERUP=<id> opens the 1+2 takeover. It shows itself once per
			# offer at the start of a session and never again, so this is the
			# only way to look at it twice in a row.
			if OS.has_environment("POWERUP"):
				_powerup.call_deferred(game, OS.get_environment("POWERUP"))
			# GOTO=<page> plays the page change itself, which is the only way
			# to see what main.gd's shell is for: the bar and the side discs
			# have to hold still while the page under them slides. A still of
			# either end of the transition proves nothing about the middle.
			if OS.has_environment("GOTO"):
				_goto_reel.call_deferred(game, OS.get_environment("GOTO"))
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
	# GRANT owns the capture when it is set: the reward fires a fixed moment
	# after a boot whose length is not fixed, so a SHOT_DELAY measured from
	# start-up lands wherever it likes. _grant shoots from the grant instead.
	# SCORE and CLAIM own it for the same reason.
	if OS.has_environment("SHOT") and not OS.has_environment("GRANT") \
			and not OS.has_environment("SCORE") and not OS.has_environment("CLAIM") \
			and not OS.has_environment("GOTO") and not OS.has_environment("TIP") \
			and not OS.has_environment("DEAL") and not OS.has_environment("POWERUP") \
			and not OS.has_environment("CAMEO"):
		_shoot.call_deferred()

# A tournament rung being crossed, from the outside.
#
# SCORE=<n>[:<tier>[:<bet>]] parks the score n points under rung `tier` and
# then scores. Two shapes worth shooting:
#
#   SCORE=20:3      one rung, and it is the LAST one -- taking it rolls the
#                   whole track over underneath a prize that is still landing.
#   SCORE=20:0:100  a steal at bet x100, which is 2,000 points in one action
#                   and clears three rungs of a fresh track from a standing
#                   start. This is the case Guy described off build 101 and
#                   the only way to see the prizes arrive AGGREGATED -- one
#                   spin tile carrying the sum, one tile per card, and a
#                   heading that counts the rungs.
#
# With no bet it scores a build, which is 60 flat and therefore always exactly
# one rung.
func _score(game: Control, spec: String) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(1.6).timeout
	var parts := spec.split(":")
	var under := int(parts[0])
	var caps: Dictionary = game.get_script().get_script_constant_map()
	var tiers: Array = caps.get("TOURNEY_TIERS", [])
	var tier := clampi(int(parts[1]) if parts.size() > 1 else 0, 0, tiers.size() - 1)
	var at: int = int((tiers[tier] as Dictionary)["at"]) if not tiers.is_empty() else 2500
	game.set("tourney_id", game.call("_tourney_now_id"))
	game.set("tourney_lap", 0)
	game.set("tourney_lap_base", 0)
	# Every rung below the one being crossed is already taken, or the board opens
	# on three unclaimed rungs and the auto-claim is not the only thing moving.
	var taken := []
	for i in tier:
		taken.append(i)
	game.set("tourney_claimed", taken)
	game.set("tourney_points", maxi(0, at - under))
	game.call("_refresh")
	await get_tree().process_frame
	# A steal at the given bet, or a build when there is none. The bet is what
	# makes one action worth enough to vault more than one rung.
	var bet := int(parts[2]) if parts.size() > 2 else 0
	if bet > 0:
		game.call("_tourney_add", "steal", bet, Vector2(360, 700))
	else:
		game.call("_tourney_add", "build", 1, Vector2(360, 700))
	if OS.has_environment("SHOT"):
		await _reel(OS.get_environment("SHOT"),
			int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 9,
			float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.22)

func _goto_reel(game: Control, key: String) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(1.4).timeout
	if key == "island":
		game.call("_goto", game.get("village_page"))
	elif key == "spin":
		game.call("_goto", game.get("slot_page"))
	else:
		game.call("_goto", (game.get("pages") as Dictionary)[key])
	if OS.has_environment("SHOT"):
		await _reel(OS.get_environment("SHOT"),
			int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 6,
			float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.08)

func _claim(game: Control, what: String) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(1.6).timeout
	if what == "daily":
		# DAY=<n> picks the rung. Day seven is the interesting one -- it is the
		# only claim that carries a card, so it is the only one with three
		# things flying to three different places.
		var day := int(OS.get_environment("DAY")) if OS.has_environment("DAY") else 1
		game.set("streak_days", maxi(0, day - 1))
		game.set("daily_last", 0.0 if day <= 1 else game.call("_trusted_now") - game.DAILY_COOLDOWN)
		game.call("_open_daily")
	await get_tree().create_timer(0.5).timeout
	# HOLD=1 stops before the press, which is the only way to look at the dialog
	# itself now that the claim is the gift rather than a button under it.
	if OS.has_environment("HOLD"):
		if OS.has_environment("SHOT"):
			await _reel(OS.get_environment("SHOT"),
				int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 1,
				float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.4)
		return
	# The daily's claim is a flat hit box over the gift now, not a labelled
	# button, so it is found by its meta.
	var btn := _find_meta_button(game.get("_popup"), "claim")
	if btn == null:
		btn = _find_button(game.get("_popup"), "CLAIM")
	if btn == null:
		print("  claim: no button found")
		get_tree().quit()
		return
	btn.emit_signal("pressed")
	if OS.has_environment("SHOT"):
		await _reel(OS.get_environment("SHOT"),
			int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 10,
			float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.22)

func _deal(game: Control, spec: String) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(1.6).timeout
	# The splash is still paying itself out when `_boot` goes null, so a capture
	# started on that alone opens over a loading bar rather than over the ladder.
	await get_tree().create_timer(3.0).timeout
	var parts := spec.split(":")
	# DEAL=done seeds the cooldown after a CLEARED chain — the teaser with the
	# six spent miniatures over the countdown, not the ladder.
	if parts[0] == "done":
		game.set("deal_id", "")
		game.set("deal_until", 0.0)
		game.set("deal_taken", 0)
		game.set("deal_done", true)
		game.set("deal_next", game.call("_now") + 7.0 * 3600.0 + 1234.0)
		game.call("_open_deal")
	else:
		# CHAIN=<id> picks which of the four runs; they differ in hue and in where
		# their paid rungs sit, which is most of what the screen looks like.
		var chain: String = OS.get_environment("CHAIN") if OS.has_environment("CHAIN") else "tide_hunt"
		game.set("deal_id", chain)
		game.set("deal_until", game.call("_now") + Deals.CHAIN_DURATION)
		game.set("deal_taken", clampi(int(parts[0]), 0, Deals.STEPS))
		game.set("deal_finale", false)
		game.set("spins", 400)
		game.call("_open_deal")
	await get_tree().create_timer(0.6).timeout
	if parts.size() > 1 and parts[1] == "take":
		var btn := _find_button(game.get("_popup"), "FREE")
		if btn == null:
			print("  deal: the live rung is not a free one")
		else:
			btn.emit_signal("pressed")
	if OS.has_environment("SHOT"):
		await _reel(OS.get_environment("SHOT"),
			int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 10,
			float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.22)

func _seed(game: Control) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	if OS.has_environment("GUEST") and (game.get("profile") as Dictionary).is_empty():
		game.set("profile", {"name": "Guest", "email": "", "provider": "guest"})
		game.call("_save_profile")
		game.call("_close_login")
	if OS.has_environment("SPINS"):
		game.set("spins", int(OS.get_environment("SPINS")))
		game.call("_refresh")

func _cameo(game: Control, kind: String) -> void:
	# The same wait every other helper in this file uses, and for the reason
	# spelled out in _deal: `_boot` going null is not the splash being gone. It
	# is cleared before `splash.dismiss()` runs so the game can tick while the
	# title screen dissolves, which leaves a window where a cue would land on
	# a mascot still frozen underneath a full-screen splash. The 4.6s on top
	# clears the dissolve and lets him settle into his idle first, so the reel
	# shows a reaction interrupting a resident rather than a rig fading in.
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(4.6).timeout
	print("  react: %s" % kind)
	game.call("_mascot_cue", kind)
	if OS.has_environment("SHOT"):
		await _reel(OS.get_environment("SHOT"),
			int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 12,
			float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.16)

func _powerup(game: Control, id: String) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	game.set("powerup_id", id if id != "1" else "pu_quartermaster")
	game.set("powerup_until", game.call("_now") + Deals.POWERUP_DURATION)
	game.set("powerup_pending", "")
	game.call("_open_powerup")
	if OS.has_environment("SHOT"):
		await _reel(OS.get_environment("SHOT"),
			int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 1,
			float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.5)

func _find_meta_button(node: Node, key: String) -> Button:
	if node == null:
		return null
	for c in node.get_children():
		if c is Button and (c as Button).has_meta(key) and not (c as Button).disabled:
			return c as Button
		var found := _find_meta_button(c, key)
		if found != null:
			return found
	return null

func _find_button(node: Node, starts: String) -> Button:
	if node == null:
		return null
	for c in node.get_children():
		if c is Button and (c as Button).text.begins_with(starts):
			return c as Button
		var found := _find_button(c, starts)
		if found != null:
			return found
	return null

func _land(m: Control) -> void:
	await get_tree().create_timer(0.45).timeout
	m.call("_lock_in")

func _raid(game: Control, mode: String) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	game.call("_start_visit", "attack" if mode == "attack" else "steal")

func _grant(game: Control, spec: String) -> void:
	while game.get("_boot") != null:
		await get_tree().process_frame
	# Long enough for the boot's fade to finish. At 0.5 the reward flew across
	# a title card that was still on screen, which makes the strip unreadable.
	await get_tree().create_timer(1.6).timeout
	var parts := spec.split(":")
	var n := int(parts[1]) if parts.size() > 1 else 5
	match parts[0]:
		"shields":
			# get() reads properties, not constants -- `game.get("SHIELD_CAP")`
			# comes back null and takes the whole harness down with it. The
			# constant map is where a const actually lives.
			var caps: Dictionary = game.get_script().get_script_constant_map()
			game.set("shields", int(caps.get("SHIELD_CAP", 3)))
			game.call("_refresh")
			await get_tree().process_frame
			game.call("_grant_shields", n, Vector2(360, 760))
		"shields_room":
			game.set("shields", 0)
			game.call("_refresh")
			await get_tree().process_frame
			game.call("_grant_shields", n, Vector2(360, 760))
		"spins":
			game.call("_grant_spins", n, Vector2(360, 760))
		# GRANT=cards:3 draws a handful and shows the chest dialog they arrive
		# in -- the NEW badge on each first copy, and the stars leaving those
		# cards for the pill at the top. In play it costs a chest.
		"cards":
			# A shelf with holes in it, or every draw comes back a spare and the
			# dialog has nothing new on it to look at.
			var owned: Dictionary = game.get("col_owned")
			var fresh_map: Dictionary = game.get("col_new")
			for id in owned:
				var arr: Array = owned[id]
				for i in arr.size():
					arr[i] = false
				# The unseen markers go with them. A previous run of this hook
				# leaves them on disk, and a badge on a set whose cards have just
				# been un-owned is a state the game itself cannot produce.
				var farr: Array = fresh_map.get(id, [])
				for i in farr.size():
					farr[i] = false
			game.call("_refresh")
			await get_tree().process_frame
			var cards := []
			for _i in n:
				cards.append(game.call("_grant_chest_card", 2))
			# GRANT=cards:6:shelf and :set skip the dialog and go and look at
			# where the badge lands afterwards -- the shelf tile that says how
			# many arrived, and the card in the grid wearing the tab.
			var where := str(parts[2]) if parts.size() > 2 else ""
			if where == "":
				game.call("_show_chest_result", cards, "Chest Opened!")
				return
			if where == "set":
				for c in cards:
					if not bool((c as Dictionary).get("dup", true)):
						game.set("col_open", str((c as Dictionary).get("set_id", "")))
						break
			# _goto fills the page on its way in. Filling it again here draws a
			# SECOND copy -- and the NEW badges are spent by the first draw, so
			# the shot came back with none of the thing it was taken to look at.
			game.call("_goto", (game.get("pages") as Dictionary)["collections"])
	if OS.has_environment("SHOT"):
		await _reel(OS.get_environment("SHOT"),
			int(OS.get_environment("SHOTS")) if OS.has_environment("SHOTS") else 9,
			float(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 0.22)

# A strip of frames from right now, so a sequence can be judged as motion.
func _reel(path: String, shots: int, gap: float) -> void:
	for i in shots:
		if i > 0:
			await get_tree().create_timer(gap).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path.replace(".png", "_%02d.png" % i))
	print("  reel: %d frames" % shots)
	get_tree().quit()

func _spin(game: Control) -> void:
	# Waits out the boot rather than a fixed 0.3s, which is what _open_page and
	# _raid already do. The slot page does not exist until _run_boot() has built
	# it, so the old delay called _on_spin_requested() against a null `slot` and
	# the harness died on "Nonexistent function 'is_spinning' in base 'Nil'" --
	# a shot of the reels in motion has never actually come out of SPIN=1.
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	# AUTO=1 turns the run on first, which is the only way to shoot the hero
	# button in its other state. During an auto run it is the STOP control and
	# has to stay live for the whole spin -- both of which are invisible in a
	# still of the button at rest, and neither of which can be reached from a
	# harness without holding a finger on it for 0.55s.
	if OS.has_environment("AUTO"):
		var slot: Node = game.get("slot")
		slot.call("set_auto", true)
		game.set("auto_spin", true)
	game.call("_on_spin_requested")

func _open_page(game: Control, key: String) -> void:
	# Wait out the load sequence rather than a fixed delay -- the pages this
	# jumps to do not exist until _run_boot() has built them.
	while game.get("_boot") != null:
		await get_tree().process_frame
	await get_tree().process_frame
	# DAY=<n> parks the streak so the daily bonus can be looked at on a rung
	# other than the first. Day one is the only state a fresh save can show, and
	# it is the one rung with no ticked tiles behind it.
	if OS.has_environment("DAY"):
		var d := int(OS.get_environment("DAY"))
		game.set("streak_days", maxi(0, d - 1))
		game.set("daily_last", 0.0 if d <= 1 else game.call("_trusted_now") - game.DAILY_COOLDOWN)
	# ALERTS=<n> stocks the notification log, because the alerts page is the
	# one page whose controls depend on having content: the bar at the top
	# carries an unread count and only offers "Clear all" when there is
	# something to clear, so an empty log shows neither. A dev save is almost
	# always empty.
	if OS.has_environment("ALERTS"):
		var n := maxi(1, int(OS.get_environment("ALERTS")))
		var stamp: float = game.call("_now")
		var seeded := []
		for k in n:
			seeded.append({"type": "raid" if k % 2 == 0 else "spins",
				"text": ("Barnaby raided your vault \u2014 %s coins" % (1200 + k * 340))
					if k % 2 == 0 else "+3 spins refilled  (%d/50)" % (20 + k),
				"emoji": "\U01F3F4" if k % 2 == 0 else "\U01F300",
				"ts": stamp - float(k) * 5400.0,
				"read": k >= 3})
		game.set("notif_log", seeded)
	if key.begins_with("popup:"):
		# PIGGY=full|empty|<n> pins the bank before the screen opens. The three
		# faces are the point of that drawing and two of them are otherwise
		# only reachable by playing to them.
		if OS.has_environment("PIGGY"):
			var want := OS.get_environment("PIGGY")
			var cap := int(CV.PIGGY_CAP)
			game.set("piggy_coins", cap if want == "full" else (0 if want == "empty" else int(want)))
		# TIP=<tier>[:<lap>] presses one tournament rung once the board is up
		# and shoots the chip it puts up. That chip exists only after a tap and
		# only lives 2.7 seconds, so it cannot be caught by a delay measured
		# from start-up -- this owns the capture, the way GRANT and SCORE do.
		# The track is parked first: a dev save has no live tournament, and a
		# board with nothing on it has no rungs to press.
		if OS.has_environment("TIP"):
			# `_boot` going null is not the splash being gone -- it fades on
			# its own afterwards, and a shot taken on the boot loop alone is a
			# picture of the raccoon.
			await get_tree().create_timer(1.6).timeout
			var spec := OS.get_environment("TIP").split(":")
			game.set("tourney_id", game.call("_tourney_now_id"))
			game.set("tourney_lap", int(spec[1]) if spec.size() > 1 else 0)
			game.set("tourney_lap_base", 0)
			game.set("tourney_claimed", [0])
			game.set("tourney_points", int(game.call("_tourney_tier_at", 1)) + 40)
			game.call("_refresh")
			game.call("_open_" + key.substr(6))
			await get_tree().process_frame
			await get_tree().process_frame
			var want_tier := int(spec[0])
			for b in game.find_children("*", "Button", true, false):
				if b.has_meta("tourney_pip") and int(b.get_meta("tourney_pip")) == want_tier:
					b.pressed.emit()
			if OS.has_environment("SHOT"):
				await _shoot()
			return
		game.call("_open_" + key.substr(6))
		return
	# PAGE=call:<method> presses a dialog open by name, for the ones that are
	# not `_open_<something>` and so cannot be reached by the popup: route --
	# every confirm in the game is `_confirm_<thing>` and none of them were
	# shootable before this.
	if key.begins_with("call:"):
		game.call(key.substr(5))
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
	# MISSIONS=fresh puts the quest board back to nothing claimed.
	#
	# The harness starts from whatever save is on this machine, and on a dev box
	# that is almost always a board with every mission already taken -- eight
	# green ticks and not one CLAIM button, which is precisely the state that
	# cannot answer "does an unearned button still look pressable".
	if OS.get_environment("MISSIONS") == "fresh":
		var st: Dictionary = game.get("mission_state")
		for period in st:
			st[period]["progress"] = {}
			st[period]["claimed"] = {}
			st[period]["bonus"] = false
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
		"calendar", "warn", "clan"]
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

	# FACE=<name> pins one of MascotRig.FACES, and FACE=all walks the whole set
	# a frame apiece -- which is the only way to judge an expression SHEET
	# rather than an expression. Ten faces built out of eight numbers each are
	# only right relative to one another: "shocked" is not a face on its own,
	# it is the one that has to be unmistakable next to "thrilled".
	var face_env := OS.get_environment("FACE") if OS.has_environment("FACE") else ""
	var face_list: Array = MascotRig.FACES.keys() if face_env == "all" else []
	if face_env == "all":
		frames = face_list.size()

	for i in frames:
		if mood_set and mood_art is MascotRig:
			# Written every frame: the rig springs toward it, so one write at
			# the top would be sprung away from before the first shot lands.
			(mood_art as MascotRig).mood = mood_val
		if face_env != "" and mood_art is MascotRig:
			var want_face: String = face_list[i] if face_env == "all" else face_env
			# Settled before the shot, not written and photographed on the same
			# frame: the channels are springs and a face caught 30ms in is a
			# picture of the transition, which is exactly the thing that makes
			# a contact sheet useless for judging an expression.
			(mood_art as MascotRig).face = want_face
			for _s in 40:
				await get_tree().process_frame
			print("  face: %s" % want_face)
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
