# What happened on a phone that is not in this room.
#
# There is no crash reporting in this game, and until now that was survivable
# because the only tester was Guy. It stops being survivable the moment
# twenty-five strangers play it for fourteen days: a crash on a device nobody
# here owns looks exactly like a tester who got bored, and Google's production
# access questionnaire asks -- in writing -- whether testers used all available
# features. "No idea" is a bad answer to give about your own game.
#
# THE ONE HONEST TRICK. Nothing written in GDScript can catch a native crash;
# the process is already gone. What it can do is notice that the PREVIOUS
# session never said goodbye. A marker file is written when the game comes to
# the foreground and deleted on the way to the background, so:
#
#     marker present at launch  ==  the app died while someone was looking at it
#
# The deletion is what makes that claim narrow enough to be worth anything. iOS
# and Android kill backgrounded apps constantly and that is NOT a crash -- it is
# the operating system doing its job -- so if the marker survived backgrounding
# every one of those would arrive here as a false crash and the signal would be
# pure noise. main.gd's _go_away() is the hook, the same one that already
# flushes the save for the same reason.
#
# THREE RULES, borrowed wholesale from cloud.gd, because they were right there:
#
#   1. The game never waits for this. Every send is fire-and-forget and every
#      one of them is allowed to fail forever with nothing shown to the player.
#      Diagnostics that can degrade the thing they observe are worse than none.
#
#   2. Nothing here knows the rules of the game. It counts names it is handed.
#
#   3. It collects no one. install_id is a random number made on the device and
#      reset by a reinstall; there is no name, no email and no device id in any
#      row. The server attaches the island, because the RPC needs a session
#      anyway -- see the note on guests below.
#
# GUESTS FILE NOTHING. report_diagnostics is granted to `authenticated` only,
# like every other function in the schema, so a player who never signs in is
# invisible here. That is a real gap and it is deliberate: the alternative is
# the first unauthenticated write endpoint in a schema that has been through two
# adversarial passes, rate-limited by a value the caller itself supplies. The
# closed-test instructions tell testers to sign in with Google instead.
extends Node

const STATE_PATH  := "user://diag.json"
const STATE_TMP   := "user://diag.json.tmp"

# Present on disk == a foreground session is in progress. Deliberately a
# separate file from the state: this one is created and destroyed constantly and
# must never be able to take the queue down with it.
const MARKER_PATH := "user://diag_session.flag"

# How often the queue goes out. Long, because none of it is urgent and each
# send is a radio wake-up on somebody's battery -- the same reasoning as
# cloud.gd's PUSH_GAP, taken further because this matters even less than a save.
const FLUSH_GAP := 180.0

# The server takes 25 per call. Holding more than that on the client only means
# throwing some away later, so the queue is bounded here at one batch plus a
# little slack for events that arrive mid-flush.
const QUEUE_MAX := 40

# Below this, a "session" is somebody opening the game by accident, and the
# usage counters from it say nothing.
const MIN_SESSION := 10.0

# How often the counters are rolled into a row WHILE the game is being played.
#
# They used to be rolled only in asleep(), which meant the row was written on
# the way out and could not go anywhere until the next launch -- so a tester who
# installed, played once and never came back reported NOTHING, and that is
# precisely the person a fourteen-day engagement test most needs to see. Rolling
# mid-session means the row exists in time for the flush below to carry it while
# the player is still holding the phone.
const ROLL_GAP := 180.0

# How soon after launch a BACKLOG goes out. A queue that survived the last run
# survived because the last run ended without sending it, so making it serve
# another full FLUSH_GAP is punishing exactly the short, rare session that
# produced it. Not zero: Cloud has to restore its session first, and a flush
# before that is refused by linked() and simply wasted.
const BACKLOG_LEAD := 20.0

var _install := ""

# When this install first ran. The clock behind every number in the funnel:
# a milestone is worth reading as "eleven minutes in", not as a wall time.
#
# Zero for an install that predates this field, and the funnel view treats a
# zero as unknown rather than as instant -- see the note on milestone().
var _install_at := 0.0

# The milestones this install has already filed, as a set. On disk, because
# "once, ever" has to survive a relaunch or the funnel counts launches instead
# of players.
var _milestones := {}

var _queue: Array = []

# Feature counters for the session in progress, flushed as one row rather than
# one row per spin. Names are whatever main.gd passes; this file has no list of
# them and does not want one.
var _counts: Dictionary = {}
var _session_start := 0.0

var _where := ""
var _armed := false

var _last_flush := 0.0
var _in_flight := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_state()
	_recover_crash()
	_last_flush = _now()
	if not _queue.is_empty():
		_last_flush = _now() - FLUSH_GAP + BACKLOG_LEAD
	_session_start = _now()


# ---------------------------------------------------------------------------
#  The marker
# ---------------------------------------------------------------------------

# The game is on screen. Called on launch once there is something to look at,
# and again on every resume.
func awake(where: String = "") -> void:
	_session_start = _now()
	_armed = true
	_where = where
	_write_marker()


# The game is going to sleep, and may not come back. Everything that has to
# reach the disk reaches it here, because after this point there may be no
# more frames. The queue is NOT sent -- a request started now would not finish
# -- it is written down so the next launch sends it.
func asleep() -> void:
	if not _armed:
		return
	_close_session()
	_armed = false
	_save_state()
	_clear_marker()


# A breadcrumb: the screen the player is looking at, so a crash row can say
# where it died instead of only that it did. Written through to disk because
# the whole point is to survive a process that stops without warning -- but
# only when it actually changed, since this is called from screen transitions
# and a file write per transition is a real cost for a string that is usually
# the same one.
func at(where: String) -> void:
	if where == _where:
		return
	_where = where
	if _armed:
		_write_marker()


# ---------------------------------------------------------------------------
#  What the game reports
# ---------------------------------------------------------------------------

# A feature was used. Counted, not sent -- the batch goes out with the session.
func note(feature: String, times: int = 1) -> void:
	if feature == "":
		return
	_counts[feature] = int(_counts.get(feature, 0)) + times


# A player reached something, for the first and only time on this install.
#
# THIS IS THE ONE KIND THAT IS NOT ABOUT THE APP MISBEHAVING, and it is what a
# funnel is made of. `note()` counts how often something happened and is
# summed per session; this records that it happened AT ALL, once, with how long
# it took -- which is the only way to answer "how many people who install this
# ever meet a raid", the question the whole pipeline existed not to answer.
#
# Called freely from the call site. The gate is here, not there, so main.gd
# never has to hold a flag for it -- a milestone fired on every spin costs one
# dictionary lookup after the first.
#
# `since_install_s` is -1 rather than 0 when the install predates _install_at.
# Zero is a real, meaningful value here (a milestone in the first second is
# exactly what first_open is), so the unknown has to look different from it or
# the median in diag_funnel is quietly dragged towards zero by old installs.
func milestone(name: String) -> void:
	if name == "" or _milestones.has(name):
		return
	_milestones[name] = true
	_push({
		"kind": "milestone",
		"detail": {
			"name": name,
			"since_install_s": int(_now() - _install_at) if _install_at > 0.0 else -1,
		},
	})
	# Written through rather than left for the next save. A milestone that is
	# filed but not remembered is filed again on the next launch, and the one
	# guarantee this whole kind rests on is that it is once.
	_save_state()


# The game noticed something wrong and carried on. Not a crash: the cases worth
# calling this for are the ones that are invisible by design -- a purchase that
# could not be verified, a save that would not write, an RPC that failed in a
# way the player was never shown.
func fault(where: String, message: String) -> void:
	_push({
		"kind": "error",
		"detail": {"where": where, "message": message.left(500)},
	})


# ---------------------------------------------------------------------------
#  Crash recovery
# ---------------------------------------------------------------------------

# Called once, at launch, before the marker for THIS session is written.
func _recover_crash() -> void:
	if not FileAccess.file_exists(MARKER_PATH):
		return
	var f := FileAccess.open(MARKER_PATH, FileAccess.READ)
	var prev: Dictionary = {}
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			prev = parsed
	_clear_marker()
	# Written through immediately, not left in memory to go out with the next
	# flush. A build that crashes on launch crashes again on the launch after
	# it, and an in-memory crash row would be lost every time -- so the one
	# failure worth reporting most would be the one that never reported.
	_push({
		"kind": "crash",
		"detail": {
			"where":   String(prev.get("where", "")),
			"build":   int(prev.get("build", 0)),
			# How long they had been playing before it went. A crash four
			# seconds in is a different bug from one at eleven minutes.
			"alive_s": int(prev.get("alive_s", 0)),
		},
	})
	_save_state()


func _write_marker() -> void:
	var f := FileAccess.open(MARKER_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"where":   _where,
		"build":   _build(),
		"alive_s": int(_now() - _session_start),
	}))
	f.close()


func _clear_marker() -> void:
	if not FileAccess.file_exists(MARKER_PATH):
		return
	var d := DirAccess.open("user://")
	if d != null:
		d.remove(MARKER_PATH)


# ---------------------------------------------------------------------------
#  The queue
# ---------------------------------------------------------------------------

# Bounded, and the eviction is not FIFO. A queue that has filled up is exactly
# the case where the rare rows matter most, so usage batches are dropped first
# and a crash is only ever dropped when there is nothing else left to drop.
func _push(event: Dictionary) -> void:
	_queue.append(event)
	while _queue.size() > QUEUE_MAX:
		var victim := -1
		for i in _queue.size():
			if String((_queue[i] as Dictionary).get("kind", "")) == "usage":
				victim = i
				break
		_queue.remove_at(victim if victim >= 0 else 0)


# The counters for the session that is ending, as one row.
func _close_session() -> void:
	var secs := _now() - _session_start
	if _counts.is_empty() or secs < MIN_SESSION:
		_counts.clear()
		return
	_push({
		"kind": "usage",
		"detail": {
			"secs":     int(secs),
			"where":    _where,
			"counters": _counts.duplicate(),
		},
	})
	_counts.clear()
	_session_start = _now()


func _process(_delta: float) -> void:
	# Roll first, so a row that has just become due is carried by this same
	# tick's flush rather than waiting a whole gap for the next one.
	if not _counts.is_empty() and _now() - _session_start >= ROLL_GAP:
		_close_session()
	if _queue.is_empty() or _in_flight:
		return
	if _now() - _last_flush < FLUSH_GAP:
		return
	flush()


# Sends what is queued, if there is anywhere to send it.
#
# THE linked() TEST USED TO BE HERE AND IT WAS THE WHOLE HOLE. A guest has no
# session, so every guest queued events on disk for ever and the note under this
# function -- "a sign-in three days later carries it" -- described a sign-in
# that, for most players, never comes. Guest mode is the default path and is
# advertised as a full game; the closed test worked around it by paying 25
# testers to sign in, which does not scale to the public.
#
# Cloud picks the door now: a device with a session uses the authenticated
# function, one without uses the guest one. That choice must NOT be made here,
# because "signed in" is a fact about a session that this file would have to
# re-derive and could get wrong in exactly one direction -- filing a signed-in
# player'"'"'s rows as anonymous and losing the attribution.
func flush() -> void:
	if _in_flight or _queue.is_empty():
		return
	if not Cloud.configured():
		return
	_last_flush = _now()
	_in_flight = true

	# Taken, not cleared. If the send fails they go back, and if it succeeds
	# only the ones that went are dropped -- events that arrived mid-flight are
	# still in _queue and must survive either outcome.
	var batch: Array = _queue.slice(0, 25)

	Cloud.report_diagnostics(_install, _platform(), _os_version(), _model(), _build(), batch,
		func(ok: bool) -> void:
			_in_flight = false
			if ok:
				_queue = _queue.slice(batch.size())
				_save_state()
	)


# ---------------------------------------------------------------------------
#  Disk
# ---------------------------------------------------------------------------

func _load_state() -> void:
	if FileAccess.file_exists(STATE_PATH):
		var f := FileAccess.open(STATE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				var d: Dictionary = parsed
				_install = String(d.get("install", ""))
				_install_at = float(d.get("install_at", 0.0))
				var m = d.get("milestones", {})
				if typeof(m) == TYPE_DICTIONARY:
					for k in (m as Dictionary):
						_milestones[String(k)] = true
				var q = d.get("queue", [])
				if typeof(q) == TYPE_ARRAY:
					for e in (q as Array):
						if typeof(e) == TYPE_DICTIONARY:
							_queue.append(e)
	if _install == "":
		# Not a device id and not derived from one: a fresh reinstall is a
		# different install and is supposed to look like one.
		_install = "%d-%d" % [int(_now()), randi()]
		_install_at = _now()
		_save_state()
		# THE ONLY MILESTONE FIRED FROM IN HERE, and it has to be: it is the
		# denominator. Every percentage in diag_funnel is "of installs", and an
		# install that is never recorded is one the funnel silently divides by
		# nothing. This is the one moment the game can be certain it is new.
		milestone("first_open")


func _save_state() -> void:
	var f := FileAccess.open(STATE_TMP, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"install": _install,
		"install_at": _install_at,
		"milestones": _milestones,
		"queue": _queue,
	}))
	f.close()
	var d := DirAccess.open("user://")
	if d == null:
		return
	# rename() will not replace, so the old one goes first -- the same trade
	# cloud.gd's _save_session makes, and it costs even less here: the window
	# is a lost diagnostics queue.
	if FileAccess.file_exists(STATE_PATH):
		d.remove(STATE_PATH)
	d.rename(STATE_TMP, STATE_PATH)


# ---------------------------------------------------------------------------
#  Facts about the phone
# ---------------------------------------------------------------------------
#
# Model and OS version are the whole reason a crash row is worth reading: "it
# crashes on a Galaxy A15 running Android 14" is actionable and "it crashed" is
# not. Neither identifies anybody -- OS.get_unique_id() would, and is not used.

func _platform() -> String:
	return OS.get_name()


func _os_version() -> String:
	return OS.get_version()


func _model() -> String:
	return OS.get_model_name()


func _build() -> int:
	return int(BuildID.read().get("build", 0))


func _now() -> float:
	return Time.get_unix_time_from_system()
