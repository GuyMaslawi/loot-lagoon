extends Node
# Temporary QA harness -- crash detection and the usage counters. Not shipped.
#
# Run: godot --headless --path . res://tools/qa_diag.tscn
#
# This one earns a harness more than most. Everything diag.gd claims is a claim
# about a process that ENDED, so none of it can be observed by playing: the only
# way to see whether "the app died on screen" and "the OS reclaimed a
# backgrounded app" are told apart is to stage both and look at what the next
# launch says. A reporter that quietly calls every backgrounding a crash reads
# as a game that crashes constantly, and the fix would be looked for in the
# game.
#
# Every test builds its own diag.gd rather than using the Diag autoload, which
# has already run its _ready() by the time anything here executes and cannot be
# made to launch twice.

var fails := 0

func _ready() -> void:
	await get_tree().process_frame
	_wipe()
	_t_install_id_is_stable()
	_t_marker_lifecycle()
	_t_a_crash_is_reported_once()
	_t_a_clean_exit_is_not_a_crash()
	_t_background_kill_is_not_a_crash()
	_t_counters_close_with_the_session()
	_t_a_glance_files_nothing()
	_t_the_queue_is_bounded_and_keeps_the_rare_rows()
	_t_a_backlog_does_not_wait_a_full_gap()
	_t_a_player_who_never_returns_still_reports()
	_t_first_open_is_the_denominator()
	_t_a_milestone_fires_once_ever()
	_t_an_unknown_install_age_is_not_zero()
	_t_a_guest_is_not_refused_by_the_flush_gate()
	_wipe()
	print("QA-DIAG: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _wipe() -> void:
	for f in ["user://diag.json", "user://diag.json.tmp", "user://diag_session.flag"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func _chk(name: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


# A launch. Building the node runs _ready(), which is where the previous
# session's marker is read -- so this IS the thing under test.
func _launch() -> Node:
	var d: Node = load("res://scripts/diag.gd").new()
	add_child(d)
	return d


func _shut(d: Node) -> void:
	remove_child(d)
	d.queue_free()


# The first row of a given kind, or {}. Tests used to index _queue directly,
# which was fine while a fresh install queued nothing -- first_open changed
# that, and a positional test would have started asserting about the milestone
# sitting in front of the row it meant.
func _row(d: Node, kind: String) -> Dictionary:
	for e in d._queue:
		if String((e as Dictionary).get("kind", "")) == kind:
			return e
	return {}


func _kinds(d: Node) -> Array:
	var out: Array = []
	for e in d._queue:
		out.append(String((e as Dictionary).get("kind", "")))
	return out


# --- the install id ----------------------------------------------------------
func _t_install_id_is_stable() -> void:
	print("the install id")
	_wipe()
	var a := _launch()
	var first: String = a._install
	_chk("a fresh install makes one", first != "")
	_shut(a)

	var b := _launch()
	_chk("and the next launch reads the same one back", b._install == first,
		 "%s vs %s" % [first, b._install])
	_shut(b)

	# It must not be derived from anything about the device or the person: a
	# reinstall is a different install and is supposed to look like one.
	_wipe()
	var c := _launch()
	_chk("while a reinstall is a different install", c._install != first)
	_shut(c)


# --- the marker --------------------------------------------------------------
func _t_marker_lifecycle() -> void:
	print("the marker")
	_wipe()
	var d := _launch()
	_chk("no marker before the game is on screen",
		 not FileAccess.file_exists(d.MARKER_PATH))
	d.awake("boot")
	_chk("awake arms it", FileAccess.file_exists(d.MARKER_PATH))
	d.at("shop")
	var f := FileAccess.open(d.MARKER_PATH, FileAccess.READ)
	var body: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_chk("and the breadcrumb follows the player", String(body.get("where", "")) == "shop",
		 str(body))
	d.asleep()
	_chk("asleep clears it", not FileAccess.file_exists(d.MARKER_PATH))
	_shut(d)


# --- the whole point ---------------------------------------------------------
func _t_a_crash_is_reported_once() -> void:
	print("an app that died while someone was looking at it")
	_wipe()
	var a := _launch()
	a.awake("boot")
	a.at("spin")
	# No asleep(): this is the process simply ceasing to exist.
	_shut(a)

	var b := _launch()
	_chk("the next launch files exactly one crash", _kinds(b).count("crash") == 1,
		 str(_kinds(b)))
	var crash: Dictionary = _row(b, "crash")
	_chk("and it says which screen it died on",
		 String((crash.get("detail", {}) as Dictionary).get("where", "")) == "spin", str(crash))
	_chk("and the marker is not left to fire again",
		 not FileAccess.file_exists(b.MARKER_PATH))
	_shut(b)

	# The row has to survive a build that crashes on every launch, which is the
	# case where it matters most and the one an in-memory queue would lose.
	var c := _launch()
	_chk("the crash row is on disk, not only in memory", _kinds(c).count("crash") == 1,
		 str(_kinds(c)))
	_chk("and a third launch does not invent a second one",
		 _kinds(c).count("crash") == 1, str(_kinds(c)))
	_shut(c)


func _t_a_clean_exit_is_not_a_crash() -> void:
	print("an app that was closed on purpose")
	_wipe()
	var a := _launch()
	a.awake("boot")
	a.asleep()
	_shut(a)

	var b := _launch()
	_chk("files no crash", _kinds(b).count("crash") == 0, str(_kinds(b)))
	_shut(b)


# The one that decides whether any of this is worth reading. iOS and Android
# kill backgrounded apps as a matter of routine; if that arrived as a crash,
# every install would report several a day and the signal would be gone.
func _t_background_kill_is_not_a_crash() -> void:
	print("an app the OS reclaimed while it was in the background")
	_wipe()
	var a := _launch()
	a.awake("boot")
	a.at("island")
	a.asleep()          # main.gd's _go_away, on the way to the background
	_shut(a)            # and then the OS ends the process, minutes later

	var b := _launch()
	_chk("is not a crash", _kinds(b).count("crash") == 0, str(_kinds(b)))
	_shut(b)


# --- the counters ------------------------------------------------------------
func _t_counters_close_with_the_session() -> void:
	print("what the player actually touched")
	_wipe()
	var d := _launch()
	d.awake("boot")
	d.note("spin", 12)
	d.note("chest")
	d.note("page:collections")
	d._session_start = d._now() - 300.0    # a five-minute session
	d.asleep()
	_chk("the session closes as ONE usage row, not one per event",
		 _kinds(d).count("usage") == 1, str(_kinds(d)))
	var counters: Dictionary = (_row(d, "usage").get("detail", {}) as Dictionary).get("counters", {})
	_chk("and it carries the totals", int(counters.get("spin", 0)) == 12, str(counters))
	_chk("including the screens that were reached at all",
		 counters.has("page:collections"), str(counters))
	_chk("the counters are cleared, so the next session starts at zero",
		 d._counts.is_empty())
	_shut(d)


func _t_a_glance_files_nothing() -> void:
	print("someone opening the game by accident")
	_wipe()
	var d := _launch()
	d.awake("boot")
	d.note("spin")
	d._session_start = d._now() - 2.0      # two seconds
	d.asleep()
	_chk("a two-second session is not a data point", _kinds(d).count("usage") == 0,
		 str(_kinds(d)))
	_shut(d)


# --- getting it off the phone ------------------------------------------------
#
# These two are the difference between a pipeline that collects and one that
# only looks like it does. Both failures were silent: nothing errored, rows were
# written correctly, and they simply never left the device.

func _t_a_backlog_does_not_wait_a_full_gap() -> void:
	print("a queue left over from the last run")
	_wipe()
	# A launch with nothing pending waits the full gap before its first send.
	# Seeded rather than launched fresh, because a FRESH install is no longer
	# such a launch -- it files first_open in _load_state, which is a backlog by
	# the only definition _ready has and, more to the point, deserves to be
	# treated as one: the install that opens the game and leaves inside a minute
	# is exactly the install whose row must get out, and it is the only kind of
	# install that never files anything else. See _t_first_open_is_the_denominator.
	var seed := FileAccess.open("user://diag.json", FileAccess.WRITE)
	seed.store_string(JSON.stringify({"install": "settled", "install_at": 1.0, "queue": []}))
	seed.close()
	var fresh := _launch()
	_chk("a launch with nothing to say is in no hurry",
		 fresh._now() - fresh._last_flush < 1.0,
		 "%.0fs of the gap already spent" % (fresh._now() - fresh._last_flush))
	_shut(fresh)

	# ...and the fresh install is deliberately the other way.
	_wipe()
	var born := _launch()
	_chk("but a brand new install sends its first_open soon",
		 born._now() - born._last_flush >= born.FLUSH_GAP - born.BACKLOG_LEAD - 1.0,
		 "%.0fs of %.0f already spent" % [born._now() - born._last_flush, born.FLUSH_GAP])
	_shut(born)

	# A launch that finds a backlog must not: the reason it is a backlog is that
	# the previous run ended without sending it.
	var d := _launch()
	d.fault("iap", "left over from last time")
	d._save_state()
	_shut(d)

	var b := _launch()
	_chk("but one that finds a backlog leaves only a short lead",
		 b._now() - b._last_flush >= b.FLUSH_GAP - b.BACKLOG_LEAD - 1.0,
		 "%.0fs of %.0f already spent" % [b._now() - b._last_flush, b.FLUSH_GAP])
	_chk("and it is a lead, not zero -- Cloud has to sign in first",
		 b.BACKLOG_LEAD > 0.0)
	_shut(b)


func _t_a_player_who_never_returns_still_reports() -> void:
	print("a tester who installs, plays once and never opens it again")
	_wipe()
	var d := _launch()
	d.awake("boot")
	d.note("spin", 5)
	d.note("page:shop")

	# Not long enough yet: rolling every few seconds would be one row per
	# handful of spins.
	d._process(0.0)
	_chk("a minute in, nothing has been rolled yet", _kinds(d).count("usage") == 0,
		 str(_kinds(d)))

	# Past the roll gap, and the row exists WITHOUT the player ever backgrounding
	# the game -- which is the whole point. Before this fix the counters were
	# rolled only in asleep() and the row could not leave until the next launch,
	# so a player who never came back reported nothing at all.
	d._session_start = d._now() - d.ROLL_GAP - 1.0
	d._process(0.0)
	_chk("past the roll gap the row exists mid-session", _kinds(d).count("usage") == 1,
		 str(_kinds(d)))
	var counters: Dictionary = (_row(d, "usage").get("detail", {}) as Dictionary).get("counters", {})
	_chk("and it carries what was played", int(counters.get("spin", 0)) == 5, str(counters))
	_chk("the counters reset, so the next roll is not a running total",
		 d._counts.is_empty())

	# And it does not keep rolling empty rows for a player who has stopped.
	d._session_start = d._now() - d.ROLL_GAP - 1.0
	d._process(0.0)
	_chk("an idle stretch adds no second row", _kinds(d).count("usage") == 1,
		 str(_kinds(d)))
	_shut(d)


# --- the queue ---------------------------------------------------------------
func _t_the_queue_is_bounded_and_keeps_the_rare_rows() -> void:
	print("a queue that has been offline for a fortnight")
	_wipe()
	var d := _launch()
	d._queue.clear()
	d.fault("iap", "the one row that matters")
	for i in 200:
		d._push({"kind": "usage", "detail": {"n": i}})
	_chk("the queue is bounded", d._queue.size() <= d.QUEUE_MAX, str(d._queue.size()))
	_chk("and usage was evicted before the fault", _kinds(d).count("error") == 1,
		 str(_kinds(d).count("error")))

	# Only when there is nothing cheaper left to drop does a rare row go.
	d._queue.clear()
	for i in d.QUEUE_MAX + 5:
		d._push({"kind": "crash", "detail": {"n": i}})
	_chk("a queue of nothing but crashes is still bounded",
		 d._queue.size() <= d.QUEUE_MAX, str(d._queue.size()))
	_shut(d)


# --- the funnel --------------------------------------------------------------
#
# Everything below is about `milestone`, which carries a promise the other two
# kinds do not: ONCE, EVER, PER INSTALL. A milestone that fires twice does not
# make a slightly wrong number -- it makes a funnel where a step can exceed the
# step above it, which is the shape that tells a reader the data is broken and
# stops them trusting any of it.
func _t_first_open_is_the_denominator() -> void:
	print("first_open")
	_wipe()
	var a := _launch()
	var m: Dictionary = _row(a, "milestone")
	_chk("a fresh install files one", not m.is_empty(), str(_kinds(a)))
	_chk("and it is first_open",
		 String((m.get("detail", {}) as Dictionary).get("name", "")) == "first_open", str(m))
	_shut(a)

	# The denominator has to be filed by an install that opens the game and
	# leaves immediately, because that install is the whole D0 question and it
	# never reaches MIN_SESSION, so it files no usage row to be counted from.
	var b := _launch()
	_chk("a second launch does not file it again",
		 _kinds(b).count("milestone") == 1, str(_kinds(b)))
	_shut(b)

	_wipe()
	var c := _launch()
	_chk("but a reinstall is a new install and does",
		 not _row(c, "milestone").is_empty())
	_shut(c)


func _t_a_milestone_fires_once_ever() -> void:
	print("once, ever")
	_wipe()
	var a := _launch()
	a.milestone("first_raid")
	a.milestone("first_raid")
	a.milestone("first_raid")
	var raids := 0
	for e in a._queue:
		if String((e as Dictionary).get("detail", {}).get("name", "")) == "first_raid":
			raids += 1
	_chk("three calls in one session file one row", raids == 1, str(_kinds(a)))
	# Not shut down cleanly on purpose: the write-through in milestone() is
	# what this is testing, so asleep() must not be the thing that saved it.
	_shut(a)

	var b := _launch()
	var again := 0
	for e in b._queue:
		if String((e as Dictionary).get("detail", {}).get("name", "")) == "first_raid":
			again += 1
	_chk("and the queue that survived still holds exactly one", again == 1, str(again))
	b.milestone("first_raid")
	var after := 0
	for e in b._queue:
		if String((e as Dictionary).get("detail", {}).get("name", "")) == "first_raid":
			after += 1
	_chk("a NEW LAUNCH calling it again still files nothing", after == 1, str(after))
	_chk("an empty name is refused", b._milestones.has("") == false)
	_shut(b)


func _t_an_unknown_install_age_is_not_zero() -> void:
	print("an install that predates the clock")
	_wipe()
	# A save written by a build before install_at existed: an install id, a
	# queue, and no age. It must not claim every milestone happened instantly.
	var f := FileAccess.open("user://diag.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"install": "old-install", "queue": []}))
	f.close()

	var d := _launch()
	_chk("the old install id is kept", d._install == "old-install", d._install)
	_chk("and no first_open is invented for it", _row(d, "milestone").is_empty(),
		 str(_kinds(d)))
	d.milestone("first_spin")
	var m: Dictionary = _row(d, "milestone")
	_chk("a milestone from it says the age is unknown",
		 int((m.get("detail", {}) as Dictionary).get("since_install_s", 0)) == -1, str(m))
	_shut(d)

	# ...where a real one carries a real number. Zero is a legitimate answer
	# here, which is exactly why the unknown had to be -1 and not 0.
	_wipe()
	var e := _launch()
	var fo: Dictionary = _row(e, "milestone")
	_chk("while a fresh install reports a real age",
		 int((fo.get("detail", {}) as Dictionary).get("since_install_s", -1)) >= 0, str(fo))
	_shut(e)


func _t_a_guest_is_not_refused_by_the_flush_gate() -> void:
	print("the guest gate")
	_wipe()
	var d := _launch()
	d.milestone("first_spin")
	_chk("a guest has something to send", not d._queue.is_empty())
	# THE REGRESSION THIS EXISTS FOR. flush() used to return early on
	# `not Cloud.linked()`, so a guest queued for ever and the pipeline was
	# blind to the majority of players. It must now get as far as asking Cloud,
	# which is where the two doors are chosen. Reading the source is the honest
	# test here: the alternative is a live request, and a harness that needs
	# the network is a harness that goes red when the wifi does.
	var src := FileAccess.get_file_as_string("res://scripts/diag.gd")
	_chk("flush no longer gates on linked()",
		 not src.contains("Cloud.linked()"), "diag.gd still tests linked()")
	_chk("and still refuses when there is no server at all",
		 src.contains("Cloud.configured()"))
	var cs := FileAccess.get_file_as_string("res://scripts/cloud.gd")
	_chk("cloud has a guest door", cs.contains("report_diagnostics_guest"))
	_chk("and takes the authenticated one first",
		 cs.find("_rpc(\"report_diagnostics\"") < cs.find("report_diagnostics_guest\""),
		 "the guest door must not shadow the signed-in one")
	_shut(d)
