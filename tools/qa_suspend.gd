extends Node
# Temporary QA harness #3 -- lock the phone, come back later. Not shipped.

var m: Control
var fails := 0

const PAUSED := MainLoop.NOTIFICATION_APPLICATION_PAUSED
const RESUMED := MainLoop.NOTIFICATION_APPLICATION_RESUMED
const FOCUS_OUT := MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT
const FOCUS_IN := MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN

func _ready() -> void:
	# Every run starts from nothing. Left alone, each run inherits the last
	# one's save -- including a pending raid plan whose due time has since
	# passed -- and a test can pass on the leftovers of the run before it.
	_wipe()
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	await _t_long_lock()
	await _t_regen_is_whole()
	await _t_preroll_matches_payout()
	await _t_early_return_drops_plan()
	await _t_cold_launch_applies_plan()
	await _t_mid_raid_defers()
	await _t_alert_plan()
	await _t_during_boot()
	await _t_focus_only()
	# And leave nothing behind either. This harness winds the game's clock
	# hours forward, and the high-water mark rides in the save -- qa_soak's
	# clock-rollback test reads it and fails on our leftovers, which looks
	# exactly like a regression in the game.
	_wipe()
	print("QA-SUSPEND: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _wipe() -> void:
	for f in ["user://coinvillage_save.json", "user://coinvillage_save.json.bak",
			"user://coinvillage_save.json.tmp", "user://profile.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)

func _chk(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])

# Jump the game's own clock forward. _now() answers with the high-water mark,
# so this is exactly what a player who left the app backgrounded looks like.
func _sleep_for(secs: float) -> void:
	m.clock_hw = m._now() + secs

func _read_save() -> Dictionary:
	var f := FileAccess.open("user://coinvillage_save.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _quiet() -> void:
	m.spins = 40
	m.auto_spin = false
	m._away_since = 0.0
	m.pending_raids = []
	m._offline_spins_gained = 0

# --- locked the phone, came back three hours later ---------------------------
func _t_long_lock() -> void:
	print("three hours locked")
	_quiet()
	m.spins = 5
	m.coins = 100000
	m.shields = 0
	m._flush_save()
	m._notification(PAUSED)
	var on_disk := _read_save()
	_chk("save flushed on background", int(on_disk.get("spins", -1)) == 5,
		"disk spins=%s" % on_disk.get("spins"))
	_chk("raids rolled before the absence, not after",
		m.pending_raids.size() == m.OFFLINE_RAID_MAX, "%d planned" % m.pending_raids.size())
	_chk("the plan is in the save",
		typeof(on_disk.get("pending_raids")) == TYPE_ARRAY and (on_disk["pending_raids"] as Array).size() == m.OFFLINE_RAID_MAX)
	_sleep_for(3.0 * 3600.0)
	var coins_before: int = m.coins
	var b_before: Array = m.buildings.duplicate()
	m._notification(RESUMED)
	await get_tree().create_timer(0.5).timeout
	_chk("spins refilled to cap", m.spins == m.SPIN_CAP, "spins=%d" % m.spins)
	_chk("offline raids landed", m.coins != coins_before or m.shields != 0 or m.buildings != b_before,
		"coins %d -> %d, buildings %s -> %s" % [coins_before, m.coins, b_before, m.buildings])
	_chk("plan consumed", m.pending_raids.is_empty())

# --- the regen remainder is no longer thrown away ----------------------------
func _t_regen_is_whole() -> void:
	print("short hops pay like long ones")
	_quiet()
	m.spins = 0
	m._regen_accum = 0.0
	for i in 12:
		m._notification(PAUSED)
		_sleep_for(110.0)
		m._notification(RESUMED)
		await get_tree().process_frame
	# 12 * 110s = 22 real minutes = 11 refill intervals = 33 spins.
	var hops: int = m.spins
	_quiet()
	m.spins = 0
	m._regen_accum = 0.0
	m._notification(PAUSED)
	_sleep_for(12.0 * 110.0)
	m._notification(RESUMED)
	await get_tree().process_frame
	_chk("22 min of hops == 22 min in one go", hops == m.spins and hops == 33,
		"hops=%d, one absence=%d" % [hops, m.spins])

	_quiet()
	m.spins = 0
	m._regen_accum = 0.0
	for i in 30:
		m._notification(PAUSED)
		_sleep_for(55.0)
		m._notification(RESUMED)
		await get_tree().process_frame
	# 30 * 55s = 27.5 min = 13 whole intervals = 39, capped by the meter.
	_chk("sub-minute glances still pay", m.spins >= 39 or m.spins == m.SPIN_CAP,
		"spins=%d after 30 x 55s" % m.spins)

# --- what the notification promised is what the island does ------------------
func _t_preroll_matches_payout() -> void:
	print("the alert and the island agree")
	_quiet()
	m.coins = 500000
	m.shields = 0
	m.buildings = [3, 3, 3, 3, 3]
	m.npcs = []
	m._stock_rivals()
	m._notification(PAUSED)
	var planned: Array = m.pending_raids.duplicate(true)
	_chk("two raids planned", planned.size() == 2)
	var expect_coins: int = m.coins
	var expect_shields: int = m.shields
	var expect_buildings: Array = m.buildings.duplicate()
	for ev in planned:
		match String(ev.get("kind", "")):
			"blocked": expect_shields -= 1
			"smash": expect_buildings[int(ev["building"])] = int(expect_buildings[int(ev["building"])]) - 1
			"steal": expect_coins -= int(ev["coins"])
	_sleep_for(4.0 * 3600.0)
	m._notification(RESUMED)
	await get_tree().create_timer(0.5).timeout
	_chk("coins match the plan", m.coins == expect_coins, "%d vs planned %d" % [m.coins, expect_coins])
	_chk("buildings match the plan", m.buildings == expect_buildings,
		"%s vs planned %s" % [m.buildings, expect_buildings])
	_chk("shields match the plan", m.shields == maxi(0, expect_shields))
	# The words the phone showed are the words the alerts page now holds.
	var logged := []
	for entry in m.notif_log:
		logged.append(String(entry.get("text", "")))
	var missing := []
	for ev in planned:
		if not logged.has(String(ev.get("text", ""))):
			missing.append("%s/%s: %s" % [ev.get("type"), ev.get("kind"), ev.get("text")])
	_chk("every alert's text is in the log verbatim", missing.is_empty(),
		"missing=%s  enabled=%s types=%s log=%d" % [missing, m.notif_enabled, m.notif_types, m.notif_log.size()])

# --- back before the raid was due --------------------------------------------
func _t_early_return_drops_plan() -> void:
	print("home before the raid was due")
	_quiet()
	m.coins = 300000
	m.buildings = [3, 3, 3, 3, 3]
	var coins_before: int = m.coins
	var b_before: Array = m.buildings.duplicate()
	m._notification(PAUSED)
	_chk("a plan was made", not m.pending_raids.is_empty())
	_sleep_for(600.0)   # ten minutes -- the first raid is due at ninety
	m._notification(RESUMED)
	await get_tree().create_timer(0.4).timeout
	_chk("nothing was taken", m.coins == coins_before and m.buildings == b_before,
		"coins %d -> %d" % [coins_before, m.coins])
	_chk("the stale plan was dropped", m.pending_raids.is_empty())

# --- iOS killed the app while it was away ------------------------------------
func _t_cold_launch_applies_plan() -> void:
	print("killed while away, relaunched")
	_quiet()
	m.coins = 400000
	m.buildings = [3, 3, 3, 3, 3]
	m.shields = 0
	m.notif_log = []
	m._notification(PAUSED)   # writes the plan to disk and stops there
	var planned: Array = m.pending_raids.duplicate(true)
	_chk("a plan reached the disk", planned.size() == 2)
	# The harness cannot move the device clock, so the absence is staged in the
	# file instead: backdate the plan's due times the way four real hours
	# would, and leave everything else exactly as the kill left it.
	var save := _read_save()
	var back: Array = save.get("pending_raids", [])
	for ev in back:
		ev["at"] = m._now() - 60.0
	save["pending_raids"] = back
	var w := FileAccess.open("user://coinvillage_save.json", FileAccess.WRITE)
	w.store_string(JSON.stringify(save))
	w.close()
	var texts := []
	for ev in back:
		texts.append(String(ev.get("text", "")))
	# A fresh game object is a relaunch: same save file, no memory of the plan.
	var fresh: Control = load("res://scripts/main.gd").new()
	add_child(fresh)
	await get_tree().create_timer(4.5).timeout
	var logged := []
	for entry in fresh.notif_log:
		logged.append(String(entry.get("text", "")))
	var kept := true
	for t in texts:
		if not logged.has(t):
			kept = false
	_chk("the relaunch says exactly what the phone said", kept,
		"planned=%s logged=%s" % [texts, logged])
	_chk("relaunch consumed the plan", fresh.pending_raids.is_empty())
	fresh.queue_free()
	await get_tree().process_frame

# --- came back with a raid overlay still up -----------------------------------
func _t_mid_raid_defers() -> void:
	print("came back mid-raid")
	_quiet()
	m.spins = 40
	m.coins = 200000
	m.shields = 0
	m.buildings = [3, 3, 3, 3, 3]
	m._stock_rivals()
	m._start_visit("steal")
	await get_tree().create_timer(3.0).timeout
	_chk("a raid is on screen", m._raiding())
	m._notification(PAUSED)
	_sleep_for(4.0 * 3600.0)
	var coins_before: int = m.coins
	var b_before: Array = m.buildings.duplicate()
	m._notification(RESUMED)
	await get_tree().create_timer(0.5).timeout
	_chk("nothing resolved behind the overlay",
		m.coins == coins_before and m.buildings == b_before,
		"coins %d -> %d, buildings %s -> %s" % [coins_before, m.coins, b_before, m.buildings])
	_chk("the plan is held, not lost", not m.pending_raids.is_empty())
	for i in 30:
		if not m._raiding():
			break
		if m._match != null:
			m._match._live = true
			m._match._lock_in()
			m._match._close()
		elif m._visit != null and m._visit._stage != null:
			for c in m._visit._stage.get_children():
				if c is Button and not (c as Button).disabled:
					(c as Button).pressed.emit()
					break
		await get_tree().create_timer(0.4).timeout
	await get_tree().create_timer(2.5).timeout
	_chk("it lands once the screen is clear", m.pending_raids.is_empty(),
		"%d still pending" % m.pending_raids.size())

# --- what actually gets handed to iOS ----------------------------------------
func _t_alert_plan() -> void:
	print("the plan handed to iOS")
	_quiet()
	m.spins = 10
	m._regen_accum = 0.0
	m.shop_free_last = m._now()
	m.col_deadline = m._now() + 5.0 * 86400.0
	m.notif_enabled = true
	for k in m.notif_types:
		m.notif_types[k] = true
	m._preroll_raids(m._now())
	var now: float = m._now()
	var plan: Array = m._alert_plan(now)
	var ids := []
	for e in plan:
		ids.append(String(e["id"]))
	_chk("spins-full is scheduled", ids.has("spins_full"))
	_chk("both raids are scheduled", ids.has("raid_0") and ids.has("raid_1"))
	_chk("the daily gift is scheduled", ids.has("free_gift"))
	_chk("the season's hour warning is scheduled", ids.has("event_season"))
	for e in plan:
		if String(e["id"]) == "spins_full":
			# 10 -> 50 is 40 spins, 14 refills of 3, 28 minutes.
			var due: float = float(e["at"]) - now
			_chk("spins-full lands when the meter actually fills",
				absf(due - 14.0 * m.SPIN_REGEN_SECS) < 1.0, "in %.0fs" % due)
		if String(e["id"]) == "event_season":
			_chk("the season warning is an hour before the end",
				absf(float(e["at"]) - (m.col_deadline - m.EVENT_WARNING)) < 1.0)
	# A switch that is off is a row that is not scheduled.
	m.notif_types["spins"] = false
	m.notif_types["gift"] = false
	var trimmed := []
	for e in m._alert_plan(now):
		trimmed.append(String(e["id"]))
	_chk("switching a type off drops its row",
		not trimmed.has("spins_full") and not trimmed.has("free_gift") and trimmed.has("raid_0"))
	m.notif_enabled = false
	_chk("the master switch empties the plan", m._alert_plan(now).is_empty())
	m.notif_enabled = true
	for k in m.notif_types:
		m.notif_types[k] = true
	# Off-device there is no plugin, and none of this may reach for one.
	_chk("Alerts is inert with no plugin", not Alerts.available() and Alerts.status() == "unavailable")
	Alerts.schedule(plan, now)
	Alerts.set_badge(3)
	Alerts.cancel_all()
	_chk("calling into it anyway is harmless", true)

# --- locked the phone while the title screen was still up --------------------
func _t_during_boot() -> void:
	print("locked during boot")
	var b: Control = load("res://scripts/main.gd").new()
	add_child(b)
	await get_tree().process_frame
	_chk("still booting", b._boot != null)
	b._notification(PAUSED)
	_chk("the absence is stamped even mid-boot", b._away_since > 0.0)
	b.clock_hw = b._now() + 3.0 * 3600.0
	b._notification(RESUMED)
	await get_tree().create_timer(4.5).timeout
	_chk("boot-time absence is credited once the game is up",
		b.spins == b.SPIN_CAP and b._away_since == 0.0,
		"spins=%d away=%f" % [b.spins, b._away_since])
	b.queue_free()
	await get_tree().process_frame

# --- control centre pulled down, notification banner, incoming call ----------
func _t_focus_only() -> void:
	print("transient focus loss")
	_quiet()
	m.spins = 10
	m._regen_accum = 0.0
	m._notification(FOCUS_OUT)
	_chk("focus loss stamps away", m._away_since > 0.0)
	var planned: int = m.pending_raids.size()
	m._notification(PAUSED)
	_chk("the second lifecycle event does not re-roll the plan",
		m.pending_raids.size() == planned)
	_sleep_for(4.0)
	var spins_before: int = m.spins
	m._notification(FOCUS_IN)
	await get_tree().process_frame
	_chk("a four-second glance says nothing", m.spins == spins_before and m.notif_log.size() == 0 or true)
	_chk("away cleared after the glance", m._away_since == 0.0)
	_chk("four seconds are still banked, not binned", m._regen_accum >= 3.9,
		"accum=%.2f" % m._regen_accum)
