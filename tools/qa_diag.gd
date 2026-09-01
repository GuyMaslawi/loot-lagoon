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
	var crash: Dictionary = b._queue[0]
	_chk("and it says which screen it died on",
		 String((crash["detail"] as Dictionary).get("where", "")) == "spin", str(crash))
	_chk("and the marker is not left to fire again",
		 not FileAccess.file_exists(b.MARKER_PATH))
	_shut(b)

	# The row has to survive a build that crashes on every launch, which is the
	# case where it matters most and the one an in-memory queue would lose.
	var c := _launch()
	_chk("the crash row is on disk, not only in memory", _kinds(c).count("crash") == 1,
		 str(_kinds(c)))
	_chk("and a third launch does not invent a second one", c._queue.size() == 1,
		 str(_kinds(c)))
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
	var counters: Dictionary = (d._queue[0]["detail"] as Dictionary)["counters"]
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
