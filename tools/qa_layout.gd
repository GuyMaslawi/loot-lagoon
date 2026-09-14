extends Node
# QA harness #4 -- nothing may hang off the right edge of the phone.
#
# This is the third time the same bug class has shipped: a Control that loses to
# a minimum size keeps its position and grows, a VBoxContainer hands its widest
# child's minimum width to every sibling, and one over-wide card therefore
# carries a whole page off the screen. Both previous instances were invisible in
# the source and obvious in a render. So this measures instead of reading.

var m: Control
var fails := 0

func _ready() -> void:
	# Forced to the phone the game is designed for, and this is the whole
	# premise of the harness. Headless has no window, so the root viewport comes
	# up at whatever the platform hands it -- 1280 wide in this build -- and
	# every page then lays itself out with 560px of room it will never have on a
	# phone. The first version of this measured against that and cheerfully
	# passed a page carrying a deliberate 900px canary.
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(int(DESIGN_W), int(DESIGN_H))
	w.size = Vector2i(540, 960)
	await get_tree().process_frame
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	# Every card that only appears under a condition, forced on: a live timed
	# offer and an unbought starter pack are the two widest things the shop can
	# draw, and neither is present on the fresh save this harness starts from.
	m.offer_id = "to_kraken"
	m.offer_until = m._now() + 7000.0
	m.purchased_ids = []
	m.piggy_coins = 105000
	# The daily dialog is widest with a long streak behind it: seven pips in a
	# row, a "your N-day streak ended" line above them, and the day-seven
	# promise below. A fresh save draws none of that.
	m.streak_days = 12
	m.daily_last = m._trusted_now() - m.DAILY_COOLDOWN * 3.0
	# ...and the mark chooser needs rivals to choose between.
	m._stock_rivals()
	# THE CLAN PAGE'S WIDE STATE IS THE ROSTER, NOT THE SIGNED-OUT CARD.
	#
	# _fill_clan asks Cloud.linked() first, which is false in a harness, so
	# without this the page measured here is a single centred paragraph -- the
	# narrowest thing it can draw, and a clean pass that means nothing. Faking
	# the session makes it draw the real one: eight members, the longest names
	# the game will accept, and a budget line under a clan name at full length.
	m._clan_fake = true
	Cloud._access = "harness"
	Cloud._player = {"id": "me-0000"}
	var roster := []
	for i in 8:
		roster.append({"id": "p%d" % i, "name": "Islander%dXXXXXX" % i,
			"emoji": "🧑", "island_level": 30 - i})
	roster[0]["id"] = "me-0000"
	m.my_clan = {"id": "c1", "name": "The Kraken's Own", "emoji": "🐙",
		"owner": "me-0000", "members": roster, "stars": 148320, "rank": 12}
	# THE LEAGUE TABLE, AT ITS WIDEST. A row is a rank plate, a crest, a name,
	# a score and a chip on one line, which makes it the narrowest column on
	# the page and therefore the first thing to push the card over -- so it is
	# measured with the longest clan name create_clan will accept (20), a
	# six-figure total, and the YOURS chip that only the player's own row
	# carries. Without this the board is never drawn here at all: the real
	# Cloud.clan_list answers nothing in a harness.
	m._clan_fake_list = [
		{"id": "c9", "name": "Twenty Characters Ok", "emoji": "🦈",
			"members": 30, "open": true, "full": true, "stars": 998877, "rank": 1},
		{"id": "c1", "name": "The Kraken's Own", "emoji": "🐙",
			"members": 8, "open": false, "full": false, "stars": 148320, "rank": 12}]
	m.gift_budget = {"sent": 4, "give_cap": 5, "got": 2, "receive_cap": 3}
	# The give-card list is as long as the player has spares, so every set gets
	# one -- and a gold one too, which must NOT appear in the dialog.
	for c in CV.COLLECTIONS:
		var arr: Array = m.col_dupes.get(String(c["id"]), [])
		for i in arr.size():
			arr[i] = 2
	m.grudges = [{"name": String(m.npcs[0]["name"]) if not m.npcs.is_empty() else "Boris",
		"emoji": "🏴", "coins": 99999, "hits": 3, "at": m._now()}]
	# Shown, not merely filled. Every page but the current one is visible=false,
	# and a hidden Control is never laid out -- measuring one reports zeroes and
	# passes, which is worse than not measuring it at all. The first version of
	# this harness did exactly that and gave a clean bill of health to a page
	# that was known to be broken.
	for key in ["shop", "quests", "collections", "boxes", "clan", "options", "alerts"]:
		var page: Control = m.pages.get(key, null)
		if page == null:
			print("  [skip] %s (no such page)" % key)
			continue
		var was := page.visible
		page.visible = true
		m._fill_page(key)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_page(key)
		page.visible = was
	# THE REWARD TRACK, ON ALL THREE BOARDS AND WITH ITS RUNGS AWAKE.
	#
	# The track hangs four boxes off fractional anchors along one bar, and the
	# width of each is measured off the figures printed in it -- so the page
	# above measures exactly one of the twelve arrangements it has, the cheapest
	# one: the daily board, nothing claimed, the smallest numbers the game
	# mints. The monthly board at a high island is where the figures are widest,
	# and a claimed rung is where a box is tallest.
	#
	# The rung at fraction 1.0 is the one that matters. It is hung off the right
	# edge of its card by design, which makes it the one control on this page
	# that is guaranteed to spill the moment its contents outgrow it.
	m.island_level = 30
	for board in ["daily", "weekly", "monthly"]:
		m.quests_tab = board
		m._ensure_missions()
		var defs: Array = m.MISSION_DEFS[board]
		var st: Dictionary = m.mission_state[board]
		for i in defs.size():
			var mission: Dictionary = defs[i]
			st["progress"][mission["id"]] = m._mission_target(mission)
			st["claimed"][mission["id"]] = true
		st["miles"] = {"0": true}
		var qp: Control = m.pages.get("quests", null)
		if qp == null:
			continue
		var was_q := qp.visible
		qp.visible = true
		m._fill_page("quests")
		await get_tree().process_frame
		await get_tree().process_frame
		_check_page("quests " + board, qp)
		await _check_rung_taps(qp, board)
		qp.visible = was_q
	m.island_level = 1

	# The modals, laid out by the same containers and just as able to grow past
	# the glass they sit in.
	# A score that lights two of the four rungs and puts a prize chip beside the
	# top five names -- which is the state the table is widest in, because the
	# chip is the longest string any row ever carries.
	m.tourney_points = 1500
	# _open_intro is in here because it is the widest arrangement in the game
	# that a container gets to decide: three rows of picture-plus-wrapped-text,
	# where the text column is the thing asked to shrink. That is the shop deal
	# row's bug exactly, and this is the harness that caught that one.
	for opener in ["_open_tourney", "_open_world_ranks", "_open_daily", "_open_intro",
			"_open_pick_target", "_intro_build_card", "_shot_give_card"]:
		m.call(opener)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_page("popup " + opener, m._popup)
		_check_fixed_height("popup " + opener, m._popup)
		m._close_popup(true)
		await get_tree().process_frame
	# THE THREE DEAL SCREENS, which were not in this sweep and are the three
	# that most needed to be: they are the widest dialogs in the game, they are
	# the only ones built out of drawn goods rather than type, and all three
	# have overflowed. The ladder runs past the bottom of a 720x1280 sheet by
	# construction; the 1+2 put its countdown under the fold; the solo deal
	# stood floor-to-ceiling around 735 units of content because a deferred
	# measurement was taken before its shader rects had settled.
	#
	# The state comes from the SCREENSHOT harness's own seeding rather than
	# being set up again here, so the two can never disagree about what "a live
	# offer" looks like -- the same argument _shot_quests settles for the
	# mission board.
	m.deal_id = ""
	m.deal_until = 0.0
	m.deal_next = 0.0
	m.deal_taken = 0
	m._deal_tick()
	for deal_opener in ["_open_deal", "_shot_powerup", "_shot_solo"]:
		m.call(deal_opener)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_page("popup " + deal_opener, m._popup)
		_check_fixed_height("popup " + deal_opener, m._popup)
		m._close_popup(true)
		await get_tree().process_frame
	# ...and the ladder again, parked mid-climb, which is the only state that
	# draws all three kinds of rung at once -- spent, live and locked -- and the
	# only one where a TAKEN medallion is on the page to be measured.
	m.deal_taken = 2
	m.call("_open_deal")
	await get_tree().process_frame
	await get_tree().process_frame
	_check_page("popup _open_deal mid-climb", m._popup)
	_check_fixed_height("popup _open_deal mid-climb", m._popup)
	m._close_popup(true)
	await get_tree().process_frame
	m.deal_id = ""
	m.deal_until = 0.0
	m.deal_taken = 0
	m.solo_id = ""
	m.solo_until = 0.0
	m.solo_next = 0.0
	m.powerup_id = ""
	m.powerup_until = 0.0

	# EVERY RUNG'S CHIP, ON THE CARD.
	#
	# The bubble a tapped rung puts up is anchored to the rung, and the rungs
	# sit at both ends of the rail -- so it is the one control on this screen
	# that is centred on the very edge of the card by design. It hung off the
	# side, and `_check_page` could not see it: `_spills` measures right edges
	# against the screen, and this one went left, off a card that is itself
	# inset from the screen. So this measures both edges against the rail.
	#
	# Every rung is taken or out of reach first. A rung you can claim answers a
	# press by paying out and rebuilding the board, which puts up no chip at
	# all -- that is the one state with nothing here to measure.
	m.tourney_id = m._tourney_now_id()
	m.tourney_lap = 0
	m.tourney_lap_base = 0
	m.tourney_claimed = [0, 1, 2]
	m.tourney_points = 1500
	m.call("_open_tourney")
	await get_tree().process_frame
	await get_tree().process_frame
	var rungs := []
	for b in m._popup.find_children("*", "Button", true, false):
		if b.has_meta("tourney_pip"):
			rungs.append(b)
	if rungs.is_empty():
		fails += 1
		print("  [FAIL] tournament board drew no rungs to press")
	for pip in rungs:
		pip.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_tip(int(pip.get_meta("tourney_pip")))
	m._close_popup(true)
	await get_tree().process_frame

	# The end-of-tournament dialog, in both its shapes: a podium finish carrying
	# three reward cells, and a placing with none. The first is the widest thing
	# this modal ever draws.
	for spec in [[1, 12000, 250, 3], [11, 0, 0, 0]]:
		m.call("_tourney_result_dialog", int(spec[0]), 24, 1840,
			int(spec[1]), int(spec[2]), int(spec[3]))
		await get_tree().process_frame
		await get_tree().process_frame
		_check_page("popup tourney result #%d" % int(spec[0]), m._popup)
		m._close_popup(true)
		await get_tree().process_frame
	# --- the second lap ---
	#
	# Island names carry their lap past thirty ("Green Meadows II"), and that
	# string goes on the slot machine's ribbon and the island page's plaque,
	# both of which are cut to fit the longest name in ISLANDS. Five characters
	# is not much, but "one card grew and took the page with it" is this
	# harness's entire reason for existing, so it gets measured rather than
	# argued about. Run against the longest island name there is, not island 31.
	var longest_i := 0
	for i in CV.ISLANDS.size():
		if String(CV.ISLANDS[i]["name"]).length() > String(CV.ISLANDS[longest_i]["name"]).length():
			longest_i = i
	for lap in [1, 2, 10]:
		m.island_level = (lap - 1) * CV.ISLANDS.size() + longest_i + 1
		m._apply_island_theme()
		# THE TWO THINGS THE NAME IS PRINTED ON, not the pages around them.
		#
		# Both pages spill by design and do so identically on lap one, so
		# measuring them here would report art rather than the suffix:
		# slot_page carries a full-bleed 800px backdrop starting at x=-55, and
		# the island's own buildings are placed at authored SLOT_RECTS, one of
		# which runs 19px past the right edge on Samurai Village. Neither is
		# anything to do with laps, and a check that goes red for a reason it
		# was not asked about is a check people learn to skip.
		for pair in [["island plaque", m._island_title], ["slot ribbon", m.slot]]:
			var node: Control = pair[1]
			if node == null:
				continue
			var page: Control = m.village_page if pair[0].begins_with("island") else m.slot_page
			var was := page.visible
			page.visible = true
			await get_tree().process_frame
			await get_tree().process_frame
			_check_page("%s on lap %d (%s)" % [pair[0], lap, CV.island_name(m.island_level)], node)
			page.visible = was
	print("QA-LAYOUT: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

# THE WORD "CLAIM" HAS TO BE THE BUTTON, and this is here because it was not.
#
# Guy, 2026-09-13, off his phone: "the button there is broken -- I press it with
# my finger and it does not collect." It was not the tap target and it was not
# the handler. A rung's Button sits UNDERNEATH the face that is printed on it,
# so every node in that face has to be deaf to the finger -- and Lagoon.chip is
# a PanelContainer, which defaults to MOUSE_FILTER_STOP. The chip that says
# CLAIM was therefore the one dead spot on a card whose every other pixel
# worked: the game drew a target and then covered it with the label naming it.
#
# Reading the source cannot catch that -- the filter lives in Lagoon, three
# files away from the rung -- so this asks the viewport the same question a
# finger does: point at the word, and see which control answers.
#
# The card is scrolled up the page first. The lower band of the track sits at
# y ~1150 on an unscrolled quests page, which is behind the nav shell's tab
# bar, and a probe there answers "the Island button" quite correctly. That is
# the harness standing in the wrong place, not a bug in the page.
func _check_rung_taps(qp: Control, board: String) -> void:
	var rungs := []
	for b in qp.find_children("*", "Button", true, false):
		if b.has_meta("mile_pip"):
			rungs.append(b)
	if rungs.is_empty():
		print("  [skip] %s reward track has no claimable rung to press" % board)
		return
	var sc: ScrollContainer = null
	for c in qp.find_children("*", "ScrollContainer", true, false):
		sc = c
		break
	if sc != null:
		# The TOPMOST rung, not the first one found. The track's two bands are
		# 340 units apart and find_children returns them in build order, which
		# starts on the lower one -- scrolling to that put the upper band above
		# the scroller's own rect, where it is clipped, and a probe there reads
		# straight through the page to the shell behind it.
		var top: float = (rungs[0] as Control).global_position.y
		for b in rungs:
			top = minf(top, (b as Control).global_position.y)
		sc.scroll_vertical = maxi(0, sc.scroll_vertical + int(top) - 320)
		await get_tree().process_frame
		await get_tree().process_frame
	for b in rungs:
		var hit: Button = b
		# The word a finger aims at, rather than the middle of the card -- the
		# middle was never the broken part.
		var word: Control = null
		for l in hit.get_parent().find_children("*", "Label", true, false):
			if (l as Label).text == "CLAIM":
				word = l
		if word == null:
			continue
		var at: Vector2 = word.global_position + word.size * 0.5
		# A rung the harness could not bring into view is a rung this cannot
		# say anything about. Reported as a skip rather than passed quietly --
		# a check that silently measures nothing is worse than no check.
		if sc != null and not sc.get_global_rect().has_point(at):
			print("  [skip] %s rung %d is not on screen to be pressed" % [
				board, int(hit.get_meta("mile_pip"))])
			continue
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		# in_local_coords, because the window is 540 wide and the canvas is 720:
		# an event pushed in screen units lands 0.75 of the way to where it was
		# aimed, which on this page is the tab bar.
		get_viewport().push_input(mm, true)
		await get_tree().process_frame
		var hov := get_viewport().gui_get_hovered_control()
		var ok := hov == hit
		if not ok:
			fails += 1
		print("  [%s] %s rung %d: the word CLAIM answers to its own button%s" % [
			"ok" if ok else "FAIL", board, int(hit.get_meta("mile_pip")),
			"" if ok else " -- %s (%s) swallows the press" % [
				hov.name if hov else "<nothing>",
				hov.get_class() if hov else "-"]])

# The width of the phone the game draws for. project.godot's viewport is
# 720x1280 and every page is laid out in those units, so this is the edge that
# matters -- not the size of whatever surface the harness happens to run on.
const DESIGN_W := 720.0
const DESIGN_H := 1280.0

func _view_w() -> float:
	return DESIGN_W

# Walks the tree and reports the worst overhang, not merely the first. The first
# one found is usually a child of the real culprit -- a VBoxContainer inherits
# its widest child's minimum and then every sibling reports the same overflow --
# so the widest offender is the one worth naming.
func _check_page(key: String, root: Node = null) -> void:
	var page: Node = root if root != null else m.pages.get(key, null)
	if page == null:
		print("  [skip] %s (no such page)" % key)
		return
	var worst := 0.0
	var who := ""
	var over := 0
	_seen = 0
	_widest = 0.0
	for c in _spills(page, _view_w()):
		over += 1
		var ctl: Control = c
		var spill: float = ctl.global_position.x + ctl.size.x - _view_w()
		if spill > worst:
			worst = spill
			who = "%s (%s) x=%.0f w=%.0f" % [ctl.name, ctl.get_class(),
				ctl.global_position.x, ctl.size.x]
	if over > 0:
		fails += 1
		_blame(page)
	if over > 0:
		print("    (walked %d visible controls, widest right edge %.0f of %.0f)" % [
			_seen, _widest, _view_w()])
	print("  [%s] %s fits the screen %s" % ["ok" if over == 0 else "FAIL", key,
		"" if over == 0 else "-- %d controls spill, worst %.0fpx: %s" % [over, worst, who]])

# The rail is inset 30px inside the card, which is the whole of the room a chip
# centred on an end rung has to lean into.
const RAIL_INSET := 30.0

func _check_tip(tier: int) -> void:
	var tip: Control = null
	for c in m._popup.find_children("*", "Control", true, false):
		if c.has_meta("tourney_tip"):
			tip = c
	if tip == null:
		fails += 1
		print("  [FAIL] tournament rung %d put up no chip" % tier)
		return
	# `position`, not `global_position`: the chip pops in from a third of its
	# size, and for the fifth of a second that takes, the transform puts the
	# origin a good 50px right of where the layout put it. Measuring through
	# the animation reports a spill that is not there and, worse, would hide
	# one that is. `position` is the resting rect and that is the thing under
	# test.
	var host: Control = tip.get_parent()
	var left: float = tip.position.x
	var right: float = left + tip.size.x
	var on_screen: float = host.global_position.x + left
	var bad := ""
	if left < -RAIL_INSET - SLACK or right > host.size.x + RAIL_INSET + SLACK:
		bad = "x=%.0f..%.0f, the card column is %.0f wide" % [left, right, host.size.x]
	elif on_screen < -SLACK or on_screen + tip.size.x > _view_w() + SLACK:
		bad = "x=%.0f..%.0f on a %.0f screen" % [
			on_screen, on_screen + tip.size.x, _view_w()]
	elif tip.position.y + tip.size.y > SLACK:
		bad = "it reaches %.0fpx into the rail" % (tip.position.y + tip.size.y)
	if bad != "":
		fails += 1
	print("  [%s] tournament rung %d chip sits on the card %s" % [
		"ok" if bad == "" else "FAIL", tier, "" if bad == "" else "-- " + bad])

# One pixel of tolerance, because a rounded layout can land a border half a unit
# past the edge and that is not what this is looking for.
const SLACK := 1.0
var _seen := 0
var _widest := 0.0

func _spills(n: Node, limit: float, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			var ctl := c as Control
			_seen += 1
			_widest = maxf(_widest, ctl.global_position.x + ctl.size.x)
			if ctl.size.x > 0.0 and ctl.global_position.x + ctl.size.x > limit + SLACK:
				out.append(ctl)
		_spills(c, limit, out)
	return out


# THE OTHER AXIS, for the one kind of control _check_page is blind to.
#
# _spills measures right edges against the screen, which finds every horizontal
# overflow in the game. It cannot see a VERTICAL one, and there is a control
# here that can have one: the daily hero is a plain Control pinned to a fixed
# DAILY_HERO_H with a PanelContainer full of rows inside it. A Control does not
# clip, so contents taller than the box do not disappear -- they draw straight
# over the streak ladder below, which reads as a spacing bug rather than as the
# overflow it is.
#
# Anything that pins a height and fills it can opt into this by setting the
# meta; the value is the height being claimed.
func _check_fixed_height(what: String, root: Node) -> void:
	if root == null:
		return
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.has_meta("daily_hero"):
			continue
		var claimed: float = float(c.get_meta("daily_hero"))
		var need := 0.0
		for kid in c.get_children():
			if kid is Control:
				need = maxf(need, (kid as Control).get_combined_minimum_size().y)
		if need > claimed + 0.5:
			fails += 1
			print("  [FAIL] %s: fixed-height box claims %.0f, contents need %.0f"
				% [what, claimed, need])
		else:
			print("  [ok] %s: fixed-height box fits (%.0f of %.0f)" % [what, need, claimed])

# WHICH card did it. A page that overflows almost never overflows because of the
# control that reports the overflow: a VBoxContainer hands its widest child's
# minimum width to every sibling, and the ScrollContainer above them loses to
# that same minimum and grows past its own anchors. So the useful answer is the
# single deepest node whose own minimum is the widest, which is the thing that
# actually has to be made narrower.
func _blame(page: Node) -> void:
	# Collected into an array rather than assigned inside a lambda: GDScript
	# captures by value, so a `worst = c` in a callback updates the copy and the
	# caller sees nothing at all.
	var all: Array = []
	_min_walk(page, all)
	if all.is_empty():
		return
	# Widest first, and among equals the DEEPEST first. A ScrollContainer and
	# every container between it and the offending card all report the same
	# inherited minimum, and naming the outermost one says only "the page is too
	# wide" -- which is what we already knew. The leaf is the thing to fix.
	all.sort_custom(func(a, b) -> bool:
		if absf(a[1] - b[1]) > 0.5:
			return a[1] > b[1]
		return a[2] > b[2]
	)
	var worst: Control = all[0][0]
	var worst_w: float = all[0][1]
	var trail := PackedStringArray()
	var n: Node = worst
	while n != null and n != page:
		if n is Control:
			trail.insert(0, "%s(%s min=%.0f)" % [n.name, n.get_class(),
				(n as Control).get_combined_minimum_size().x])
		n = n.get_parent()
	print("      widest minimum: %.0f -- %s" % [worst_w, " > ".join(trail)])
	print("      next widest:")
	for i in mini(8, all.size()):
		var c: Control = all[i][0]
		print("        %6.0f  depth %d  %s (%s)  %s" % [all[i][1], all[i][2], c.name,
			c.get_class(), _words(c)])

func _min_walk(n: Node, out: Array, depth := 0) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			out.append([c, (c as Control).get_combined_minimum_size().x, depth])
		_min_walk(c, out, depth + 1)


# The first few words under a node, so a blamed @PanelContainer@647 can be
# recognised as a card a human has seen.
func _words(n: Node) -> String:
	var got := PackedStringArray()
	_words_into(n, got)
	return "\"" + " | ".join(got) + "\""

func _words_into(n: Node, out: PackedStringArray) -> void:
	if out.size() >= 5:
		return
	for c in n.get_children():
		if c is Label and String((c as Label).text).strip_edges() != "":
			out.append(String((c as Label).text).strip_edges())
		elif c is Button and String((c as Button).text).strip_edges() != "":
			out.append("[" + String((c as Button).text).strip_edges() + "]")
		_words_into(c, out)
