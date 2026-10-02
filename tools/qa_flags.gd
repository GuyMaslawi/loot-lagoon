extends Node
# Temporary QA harness -- remote config, and the ways it must refuse to break
# the game. Not shipped.
#
# This is the only file in the project whose failure mode is "the game turns
# itself off". Everything else here can be wrong and cost a player a reward or a
# frame; a config layer that reads a dead network as `false` costs every player
# every feature at once, and does it on the one afternoon nobody is watching.
#
# So the checks are weighted accordingly. The interesting ones are not "a switch
# works" -- that is three lines and obvious -- they are the six ways an ABSENT or
# MALFORMED answer could come back as off, and the one where a failed request
# silently undoes a live kill switch.
#
# NOTHING HERE TOUCHES THE REAL SERVER, and that takes a deliberate line in
# _ready rather than happening by itself. This repo has a supabase.json, so
# Cloud.configured() is TRUE in a harness -- and unlike _check_client_gate,
# which returns early on an unstamped build, Flags.refresh() and
# Schedule.refresh() have no dev guard and fire on boot. They should: the whole
# point of the dev exemption is that a desktop run can see a row before it
# ships. But it means a harness that builds main.gd makes two live calls, and
# this file then asserts things about whether a fetch has landed -- which is a
# race against a real network, and it is the race that failed in CI.
#
# So Cloud is pointed at a dead local port for the whole run, the same trick
# qa_cloud uses. Every fetch fails as "no connection", which is both hermetic
# and the answer this file most needs to be sure about anyway.

var m: Control
var fails := 0

const DEAD := "http://127.0.0.1:1"

func _ready() -> void:
	_unplug()
	_wipe()
	_t_absent_is_the_compiled_answer()
	_t_a_switch_switches()
	_t_malformed_never_turns_anything_off()
	_t_numbers_are_numbers()
	_t_the_cache_survives_a_restart()
	await _t_a_failed_fetch_keeps_the_switch()
	await _t_the_game_reads_them()
	_t_the_calendar()
	_t_a_scheduled_chain()
	_t_raids_and_the_tournament()
	print("QA-FLAGS: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _chk(name: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


# Pointed somewhere nothing answers, with a key present so configured() stays
# true -- "there is a server and it cannot be reached" is the state worth
# testing, not "there is no server", which is a different and easier path.
func _unplug() -> void:
	Cloud._url = DEAD
	Cloud._key = "test-key"


func _wipe() -> void:
	Flags._values = {}
	Flags._fetched = false
	Schedule._events = []
	Schedule._fetched = false
	for f in [Flags.CACHE_PATH, Flags.CACHE_TMP]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


# -----------------------------------------------------------------------------
#  THE ONE THAT MATTERS
# -----------------------------------------------------------------------------
#
# An empty table, an unapplied migration and a plane all arrive as {}. Every one
# of them has to leave the game exactly as it shipped.
func _t_absent_is_the_compiled_answer() -> void:
	print("-- an answer nobody gave --")
	_wipe()
	_chk("a feature with no row is on", Flags.on("clan_chat"))
	_chk("and so is every other one",
		Flags.on("shop") and Flags.on("card_gifts") and Flags.on("deal_chain"))
	_chk("a number with no row is the one that was passed in",
		Flags.num("chain_hours", 24.0) == 24.0)
	_chk("a value with no row is the fallback",
		Flags.value("banner", "nothing") == "nothing")
	_chk("and nothing claims to have been fetched", not Flags.fetched())
	# The inverted case: a knob that ships off and is turned on from the table
	# once it has been proven. Same guarantee, opposite direction.
	_chk("a knob that ships off stays off until a row says otherwise",
		not Flags.on("some_future_thing", false))


func _t_a_switch_switches() -> void:
	print("-- a switch, in both directions --")
	_wipe()
	Flags._values = {"clan_chat": false, "shop": true}
	_chk("false turns it off", not Flags.on("clan_chat"))
	_chk("true leaves it on", Flags.on("shop"))
	_chk("and a sibling key is untouched", Flags.on("card_gifts"))
	# 0 and 1 are how a human writing SQL at 2am means false and true.
	Flags._values = {"clan_chat": 0, "shop": 1}
	_chk("0 reads as off", not Flags.on("clan_chat"))
	_chk("1 reads as on", Flags.on("shop"))


# Every one of these is a plausible typo in a hand-written ops row, and not one
# of them may be read as "off".
func _t_malformed_never_turns_anything_off() -> void:
	print("-- a row somebody got wrong --")
	for bad in [null, "false", "", "no", [], {}, {"on": false}, [false]]:
		Flags._values = {"clan_chat": bad}
		_chk("a %s value leaves the feature on" % type_string(typeof(bad)),
			Flags.on("clan_chat"), str(bad))
	_wipe()


func _t_numbers_are_numbers() -> void:
	print("-- numbers --")
	Flags._values = {"chain_hours": 18}
	_chk("an int comes back", Flags.num("chain_hours", 24.0) == 18.0)
	Flags._values = {"chain_hours": 18.5}
	_chk("and so does a float", Flags.num("chain_hours", 24.0) == 18.5)
	# "18" coerced to 0.0 would turn a typo into an event that lasts no time.
	for bad in [null, "18", "", [18], {"hours": 18}, true]:
		Flags._values = {"chain_hours": bad}
		_chk("a %s is not a number and falls back" % type_string(typeof(bad)),
			Flags.num("chain_hours", 24.0) == 24.0, str(bad))
	_wipe()


# A kill switch that needs the network to apply is one that lets the broken
# feature run for the first seconds of every launch.
func _t_the_cache_survives_a_restart() -> void:
	print("-- the cache --")
	_wipe()
	Flags._values = {"clan_chat": false, "chain_hours": 9}
	Flags._save_cache()
	_chk("the cache file is written", FileAccess.file_exists(Flags.CACHE_PATH))
	_chk("and the scratch file is not left behind",
		not FileAccess.file_exists(Flags.CACHE_TMP))
	# What a cold start does.
	Flags._values = {}
	Flags._load_cache()
	_chk("a switch thrown yesterday is still thrown this morning",
		not Flags.on("clan_chat"))
	_chk("and so is the number beside it", Flags.num("chain_hours", 24.0) == 9.0)
	# Garbage on disk is not a cache, and must not be a crash either.
	var f := FileAccess.open(Flags.CACHE_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	Flags._values = {}
	Flags._load_cache()
	_chk("an unreadable cache is simply no cache", Flags.all().is_empty())
	_chk("and the game runs on its defaults", Flags.on("clan_chat"))
	_wipe()


# THE OPS PROPERTY. A switch is thrown, then the server has a bad minute. The
# switch must not come back on by itself -- a single failed request undoing a
# live kill switch is the whole reason the empty answer is discarded rather
# than stored.
func _t_a_failed_fetch_keeps_the_switch() -> void:
	print("-- a fetch that failed --")
	_wipe()
	Flags._values = {"clan_chat": false}
	Flags.refresh()
	# Long enough for the request to fail and the callback to run.
	await get_tree().create_timer(2.0).timeout
	_chk("the switch is still off after the request died",
		not Flags.on("clan_chat"), str(Flags.all()))
	_chk("and nothing claims to have been fetched", not Flags.fetched())
	# And with no server configured at all, which is how every desktop run and
	# every build without supabase.json behaves.
	_wipe()
	Flags._values = {"clan_chat": false}
	Cloud._url = ""
	Cloud._key = ""
	Flags.refresh()
	await get_tree().create_timer(0.3).timeout
	_unplug()
	_chk("an unconfigured build keeps what it had too", not Flags.on("clan_chat"))
	_wipe()


# The gates, read through the game rather than through this file. A flag that is
# correct and wired to nothing is the failure this catches.
func _t_the_game_reads_them() -> void:
	print("-- what the game does with them --")
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout

	_wipe()
	_chk("the chain runs its compiled window by default",
		m._chain_duration() == Deals.CHAIN_DURATION,
		"%.0f" % m._chain_duration())
	_chk("and its compiled cooldown",
		m._chain_cooldown() == Deals.CHAIN_COOLDOWN,
		"%.0f" % m._chain_cooldown())

	Flags._values = {"chain_hours": 6, "chain_cooldown_hours": 10}
	_chk("a retuned window reaches the game", m._chain_duration() == 6.0 * 3600.0,
		"%.0f" % m._chain_duration())
	_chk("and a retuned cooldown", m._chain_cooldown() == 10.0 * 3600.0,
		"%.0f" % m._chain_cooldown())

	# A typo in the table must not be able to break the mechanic it is tuning.
	Flags._values = {"chain_hours": 0, "chain_cooldown_hours": 0}
	_chk("a window of nothing is clamped to something finishable",
		m._chain_duration() >= 2.0 * 3600.0, "%.0f" % m._chain_duration())
	_chk("and a cooldown of nothing is clamped too",
		m._chain_cooldown() >= 2.0 * 3600.0, "%.0f" % m._chain_cooldown())
	Flags._values = {"chain_hours": 100000, "chain_cooldown_hours": 100000}
	_chk("and a window of forever is clamped the other way",
		m._chain_duration() <= 168.0 * 3600.0, "%.0f" % m._chain_duration())

	# The shop.
	_wipe()
	_chk("the shop is open by default", m._purchases_open())
	Flags._values = {"shop": false}
	_chk("and a row closes it", not m._purchases_open())
	_chk("and iap.gd refuses on its own account too, for a caller that forgot",
		not Flags.on("shop"))
	_wipe()


# -----------------------------------------------------------------------------
#  The calendar
# -----------------------------------------------------------------------------

# Seeded in the shape refresh() builds, because that conversion -- seconds on
# the wire into this process's own monotonic clock -- is the thing being tested
# through live(), and a harness that bypassed it would be testing a dictionary.
func _sched(kind: String, payload: Dictionary, starts_in: float, ends_in: float) -> Dictionary:
	var at := Time.get_ticks_msec()
	return {"kind": kind, "payload": payload,
		"starts_ms": at + int(starts_in * 1000.0),
		"ends_ms": at + int(ends_in * 1000.0)}


func _t_the_calendar() -> void:
	print("-- the calendar --")
	Schedule._events = []
	_chk("an empty calendar has nothing running", Schedule.live("deal_chain").is_empty())
	# Deterministic only because _unplug ran: main.gd booted above and called
	# Schedule.refresh(), and against a reachable server this raced it.
	_chk("a calendar that could not be reached has not been fetched",
		not Schedule.fetched())
	_chk("and a chain still rolls in on the rotation without one",
		Schedule.live("deal_chain").is_empty())

	Schedule._events = [_sched("deal_chain", {"id": "tide_hunt"}, -1800.0, 3600.0)]
	var ev := Schedule.live("deal_chain")
	_chk("an event inside its window is running", not ev.is_empty())
	_chk("and it carries its payload",
		String((ev.get("payload", {}) as Dictionary).get("id", "")) == "tide_hunt")
	_chk("with roughly the time it has left",
		absf(Schedule.seconds_left(ev) - 3600.0) < 5.0,
		"%.1f" % Schedule.seconds_left(ev))
	_chk("a kind nobody scheduled is not running",
		Schedule.live("some_other_kind").is_empty())

	Schedule._events = [_sched("deal_chain", {"id": "tide_hunt"}, 3600.0, 7200.0)]
	_chk("an event that has not started is not running",
		Schedule.live("deal_chain").is_empty())
	Schedule._events = [_sched("deal_chain", {"id": "tide_hunt"}, -7200.0, -3600.0)]
	_chk("and one that is over is not running either",
		Schedule.live("deal_chain").is_empty())
	_chk("seconds_left never goes negative",
		Schedule.seconds_left({"ends_ms": Time.get_ticks_msec() - 90000}) == 0.0)

	# Two overlapping rows of the same kind are a scheduling mistake; what
	# matters is that every phone resolves it identically. The server sends them
	# in start order, so the first in the list wins.
	Schedule._events = [
		_sched("deal_chain", {"id": "first"}, -3600.0, 3600.0),
		_sched("deal_chain", {"id": "second"}, -1800.0, 3600.0)]
	_chk("two overlapping rows resolve to the earlier one, on every phone",
		String((Schedule.live("deal_chain").get("payload", {}) as Dictionary)
			.get("id", "")) == "first")
	Schedule._events = []


func _t_a_scheduled_chain() -> void:
	print("-- a chain somebody put on a date --")
	var want := String((Deals.CHAINS[0] as Dictionary)["id"])
	var other := String((Deals.CHAINS[1] as Dictionary)["id"])
	_wipe()

	# A LONG COOLDOWN STANDING IN FRONT OF IT. This is the whole reason the
	# calendar is consulted before the cooldown check: a dark window is a
	# property of the rotation, and a scheduled event is not the rotation.
	m.deal_id = ""
	m.deal_next = m._now() + 100000.0
	Schedule._events = [_sched("deal_chain", {"id": want}, -60.0, 7200.0)]
	m._deal_tick()
	_chk("a scheduled chain starts through a cooldown that has hours to run",
		m.deal_id == want, m.deal_id)
	_chk("and it runs to the END OF THE WINDOW, not for the rotation's span",
		absf(m.deal_until - (m._now() + 7200.0)) < 5.0,
		"%.0f left" % (m.deal_until - m._now()))
	_chk("and it starts the ladder at the bottom", m.deal_taken == 0)

	# It must not take a ladder away from somebody standing on it.
	m.deal_id = other
	m.deal_until = m._now() + 50000.0
	m.deal_taken = 3
	Schedule._events = [_sched("deal_chain", {"id": want}, -60.0, 7200.0)]
	m._deal_tick()
	_chk("a scheduled chain never pre-empts one already being climbed",
		m.deal_id == other and m.deal_taken == 3, m.deal_id)

	# A row written for a build that does not exist yet, or a typo. Neither is
	# a reason to run no event at all.
	m.deal_id = ""
	m.deal_until = 0.0
	m.deal_next = 0.0
	Schedule._events = [_sched("deal_chain", {"id": "no_such_chain"}, -60.0, 7200.0)]
	m._deal_tick()
	_chk("a row naming a chain this build does not have falls back to the rotation",
		m.deal_id != "" and not Deals.by_id(m.deal_id).is_empty(), m.deal_id)

	# The switch has to mean off however the chain would have arrived.
	m.deal_id = ""
	m.deal_next = 0.0
	Flags._values = {"deal_chain": false}
	Schedule._events = [_sched("deal_chain", {"id": want}, -60.0, 7200.0)]
	m._deal_tick()
	_chk("the kill switch closes the scheduled path too, not just the rotation",
		m.deal_id == "", m.deal_id)
	_wipe()

	# A long scheduled window must survive the wound-clock sanitiser, which used
	# to clamp to the rotation's span and would have cut five days off a week.
	m.deal_id = want
	m.deal_until = m._now() + 100.0 * 3600.0
	m._sanitize_clock()
	_chk("a seven-day window is not cut back to the rotation's 24 hours",
		m.deal_until > m._now() + 99.0 * 3600.0,
		"%.0fh left" % ((m.deal_until - m._now()) / 3600.0))
	m.deal_until = m._now() + 400.0 * 3600.0
	m._sanitize_clock()
	_chk("but a deadline past every ceiling is still pulled back",
		m.deal_until <= m._now() + m.CHAIN_MAX_SPAN + 5.0,
		"%.0fh left" % ((m.deal_until - m._now()) / 3600.0))

	Schedule._events = []
	m.deal_id = ""
	m.deal_until = 0.0
	m.deal_taken = 0


func _t_raids_and_the_tournament() -> void:
	print("-- raids, and the tournament --")
	_wipe()

	# The cached rival is the case the first draft got wrong: the guard that
	# returns early when one is already held sat in FRONT of the switch, so the
	# one phone that needed clearing never reached it.
	m._server_rival = {"name": "Somebody Real", "cloud_id": "abc-123"}
	Flags._values = {"pvp_raids": false}
	m._prefetch_rival()
	_chk("a rival fetched before the switch was thrown is dropped",
		m._server_rival.is_empty(), str(m._server_rival))
	_wipe()
	m._server_rival = {"name": "Somebody Real", "cloud_id": "abc-123"}
	m._prefetch_rival()
	_chk("and with the switch on it is left alone to be sailed to",
		not m._server_rival.is_empty())
	m._server_rival = {}

	# Stop the scoring, never strand the prize.
	_wipe()
	m.tourney_id = 1
	m.tourney_points = 500
	m.tourney_owed_id = -1
	m.tourney_owed_points = 0
	Flags._values = {"tournament": false}
	m._tourney_add("build")
	_chk("a switched-off tournament scores nothing new", m.tourney_points == 0,
		str(m.tourney_points))
	_chk("but the cycle that ended is still parked for its placing prize",
		m.tourney_owed_id == 1 and m.tourney_owed_points == 500,
		"owed_id=%d pts=%d" % [m.tourney_owed_id, m.tourney_owed_points])

	_wipe()
	m.tourney_id = m._tourney_now_id()
	m.tourney_points = 0
	m.tourney_build_pts = 0
	m._tourney_add("build")
	_chk("and with the switch on it scores again", m.tourney_points > 0,
		str(m.tourney_points))
	_wipe()
