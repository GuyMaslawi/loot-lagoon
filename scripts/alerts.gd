extends Node

# Notifications that arrive while the game is closed.
#
# The whole feature rests on one constraint: a backgrounded app does not run --
# true on both platforms and for different reasons, iOS suspending it outright
# and Android putting it where Doze can. There is no timer ticking in the
# background, no code that can notice the spins came back and post a message
# about it. Everything the player will
# see over the next hours has to be handed to iOS *before* the app goes to
# sleep, complete with its text and its due time.
#
# So this is not a "send a notification" API. It is a plan: main.gd works out
# every future moment worth pinging about, hands the whole list over on the way
# to the background, and iOS delivers them without us. Coming back cancels
# whatever has not fired yet, because the plan was written against a state the
# player has now changed.
#
# Which means a scheduled notification is a PROMISE about what the game will
# say when it is opened. "Your spins are full" has to be true at the moment it
# lands, or the player taps it and finds 41 spins. That is why the offline
# regen maths and the offline raid roll both had to move -- see main.gd.

signal permission_result(granted: bool)

# iOS will hold 64 pending local notifications per app and silently drops the
# rest; Android's AlarmManager cap is higher, so the tighter number governs.
# Nothing here comes close, but the trim is real code rather than a comment
# because "nothing comes close" is exactly the sort of thing an event system
# added later stops being true.
const MAX_PENDING := 64

# Below this there is no point waking anybody: they are still holding the phone.
const MIN_LEAD := 60.0

var _plugin: Object = null
# The Android plugin takes the plan as JSON rather than as an Array -- see the
# note on schedule() below. Read once here rather than per call.
var _android := false
# Whether iOS has been asked. Not the answer -- see status(); the player can
# revoke us in Settings between one launch and the next.
var _asked := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_android = OS.get_name() == "Android"
	if Engine.has_singleton("LocalNotifications"):
		_plugin = Engine.get_singleton("LocalNotifications")
		_plugin.permission_result.connect(_on_permission_result)

# Whether there is a platform underneath at all. The editor, the desktop build
# and the simulator have no plugin, and every call below is a no-op there -- the
# game must not gate any of its own logic on notifications having happened.
#
# This was ALSO false on Android until 2026-09-01, silently: the singleton was
# an iOS plugin, so the entire retention plan below was computed every time the
# game was backgrounded and thrown away. See addons/LocalNotificationsAndroid.
func available() -> bool:
	return _plugin != null

# "notDetermined" | "denied" | "authorized" | "provisional" | "ephemeral",
# or "unavailable" off-device. Asked fresh every time rather than cached: a
# player who turns us off in Settings has not launched the app to tell us.
func status() -> String:
	if _plugin == null:
		return "unavailable"
	return String(_plugin.permission_status())

func granted() -> bool:
	var s := status()
	return s == "authorized" or s == "provisional"

# Whether it is still worth putting the system prompt in front of the player.
# iOS shows it exactly once per install; after that this is permanently false
# and the only route back is the Settings app.
func can_ask() -> bool:
	return _plugin != null and status() == "notDetermined"

func request_permission() -> void:
	if _plugin == null:
		permission_result.emit(false)
		return
	_asked = true
	_plugin.request_permission()

func _on_permission_result(ok: bool) -> void:
	permission_result.emit(ok)

# The plan, replacing whatever was pending.
#
# `entries` is an Array of {id, at, title, body} where `at` is a *game* time
# from main.gd's _now(). Converted to a delay here, and deliberately: _now() is
# a high-water mark that can sit hours ahead of the device clock after a player
# has wound their phone forward. An absolute date computed from it would put a
# notification years out; the gap between two _now() readings is the same
# number of seconds in either clock, so only the gap is worth trusting.
func schedule(entries: Array, now: float) -> void:
	if _plugin == null:
		return
	if not granted():
		# Nothing to schedule into. Clear rather than leave the last plan
		# standing -- a player who has just switched us off in Settings should
		# not keep getting yesterday's queue.
		_plugin.cancel_all()
		return
	var due := []
	for e in entries:
		var delay: float = float(e.get("at", 0.0)) - now
		if delay < MIN_LEAD:
			continue
		due.append({"id": String(e.get("id", "")), "in": delay,
			"title": String(e.get("title", "")), "body": String(e.get("body", ""))})
	# Soonest first, so if the list ever outgrows the cap it is the far future
	# that gets dropped and not tonight.
	due.sort_custom(func(a, b) -> bool: return float(a["in"]) < float(b["in"]))
	if due.size() > MAX_PENDING:
		push_warning("Alerts: %d planned, the cap is %d -- dropping the furthest out." % [due.size(), MAX_PENDING])
		due.resize(MAX_PENDING)
	# The one place the two platforms differ. The Android plugin takes JSON
	# because an Array of Dictionaries has to cross JNI, where every number
	# arrives as a boxed type nobody chose, and the failure mode for getting
	# that wrong is not an error -- it is a tester who never gets a
	# notification. A String crosses exactly one way. See the comment on
	# schedule() in LootLagoonNotifications.java.
	if _android:
		_plugin.schedule(JSON.stringify(due))
	else:
		_plugin.schedule(due)

func cancel_all() -> void:
	if _plugin != null:
		_plugin.cancel_all()

# The red dot on the icon, and the pile in Notification Centre.
func set_badge(count: int) -> void:
	if _plugin != null:
		_plugin.set_badge(count)

func clear_delivered() -> void:
	if _plugin != null:
		_plugin.clear_delivered()
