# The island, off the device.
#
# Everything in the game still lives in user://coinvillage_save.json and always
# will -- main.gd reads and writes that file exactly as before, and a player who
# never signs in never touches this. What this adds is a second copy on a server
# and a name that owns it, so that deleting the app stops meaning deleting two
# years of play.
#
# That is worth stating plainly because of what the store sells. Every product
# in iap.gd is a consumable, and its own comment says consumables are never
# restored -- so before this existed, a player who had spent fifty dollars over
# two years and reinstalled had no path back to any of it. Not half. None.
#
# THREE RULES, and they are the whole design:
#
#   1. The game never waits for the network. Not on launch, not on a spin, not
#      on a purchase. Every call here is fire-and-forget with a signal on the
#      way back, and every one of them is allowed to fail forever without the
#      player noticing anything except that a cloud icon is grey.
#
#   2. Local is the working copy. The server is asked what it has at sign-in and
#      after that it is only ever written to. A save that lost a race is not
#      resolved by this file -- push_save on the server rejects it and hands
#      back what it holds, and main.gd decides.
#
#   3. Nothing here knows the rules of the game. It moves a dictionary main.gd
#      built and a handful of numbers main.gd computed. It has no opinion about
#      what a star is worth.
extends Node

# Handed the player record from the server: {id, name, emoji, island_level,
# rank_stars, coins, shields, buildings}.
signal signed_in(player: Dictionary, is_new: bool, remote_save: Dictionary)
signal sign_in_failed(reason: String)
signal signed_out()

# The session landed and RPCs will now authenticate. Not the same thing as
# having an island: claim_player is what turns a session into one, and only
# main.gd can build the payload for it, because that payload is the save.
signal session_ready()

# A link attempt finished. status is "linked", "conflict" or "expired". On
# "conflict" both islands are described so the player can be asked which one
# survives; resolve_link() finishes it.
signal link_result(status: String, mine: Dictionary, theirs: Dictionary)

# The server refused a push because it holds a further-along island. Carries
# what it holds, so main.gd can offer to adopt it.
signal save_rejected(stored_rank: int, remote_save: Dictionary)

# Raids that happened while the player was away, for main.gd to apply under its
# own rules and then acknowledge. See the note on record_raid in migration 0002:
# the server records that a raid happened and never touches the victim's save.
signal raids_arrived(raids: Array)
signal gifts_arrived(gifts: Array)

# "off" | "syncing" | "synced" | "error" -- for a single small icon, nothing
# more. A player who is not signed in sees "off" and no error, ever, because
# not signing in is not a fault.
signal sync_state_changed(state: String)

const CONFIG_PATH := "res://supabase.json"
const SESSION_PATH := "user://cloud_session.json"
const SESSION_TMP := "user://cloud_session.json.tmp"

# A link in progress, on disk rather than in memory, because the thing that
# happens between handing the token out and redeeming it is a sign-in -- and a
# sign-in means a browser on Android or a system sheet on iOS, either of which
# can put this process in the background long enough for iOS to kill it. A token
# that only lived in a variable would be gone exactly when it was needed.
const LINK_PATH := "user://cloud_link.json"

# The network equivalent of main.gd's SAVE_FLUSH_GAP, and much longer for the
# same reason taken further: a disk write costs a frame hitch, a request costs
# a radio wake-up and somebody's battery. The save on the server being half a
# minute behind the one on disk costs nothing, because the one on disk is the
# one being played.
const PUSH_GAP := 30.0

# Refresh this long before the token actually expires. A request that sets off
# with sixty seconds of validity and arrives with none is a 401 for no reason.
const REFRESH_MARGIN := 120.0

const HTTP_TIMEOUT := 20.0

var _url := ""
var _key := ""

var _access := ""
var _refresh := ""
var _expires_at := 0.0
var _player: Dictionary = {}

var _dirty := false
var _pending: Dictionary = {}
var _last_push := 0.0
var _in_flight := false

# Consecutive failures. Only used to back off; never shown to the player.
var _fails := 0

var _state := "off"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := _load_config()
	_url = str(cfg.get("url", "")).rstrip("/")
	_key = str(cfg.get("publishable_key", ""))
	_load_session()


static func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


# Whether there is a server to talk to at all. False in a build with no
# supabase.json, which must stay a perfectly ordinary way to run the game --
# see the same treatment google_oauth.json gets in google_auth.gd.
func configured() -> bool:
	return _url != "" and _key != ""


func linked() -> bool:
	return configured() and _access != ""


func player() -> Dictionary:
	return _player.duplicate(true)


func state() -> String:
	return _state


func _set_state(s: String) -> void:
	if s == _state:
		return
	_state = s
	sync_state_changed.emit(s)


# =============================================================================
#  Session
# =============================================================================
#
# Kept in its own file rather than in the save, because it is not progress and
# because the save is handed around: _flush_save's dictionary is what gets
# pushed to the server, and a refresh token riding along inside it would be a
# credential stored in a column that other code is allowed to read back.
# The scratch path is tried second, and only ever second.
#
# _save_session removes the real file and then renames the scratch one over it,
# because DirAccess.rename() will not replace something that exists. Those are
# two operations and this game is killed between operations for a living, so
# there is a window with a complete session on disk under the wrong name and
# nothing under the right one. Reading it back closes that window; ordering it
# second is what keeps the fix from becoming its own bug, because a scratch file
# is ALSO what a death mid-write leaves behind, and that one is half a file.
#
# Which is why it is parsed before it is believed rather than merely opened. A
# truncated file fails JSON.parse_string and is skipped exactly like an absent
# one, so the only scratch file that is ever adopted is a whole one.
func _load_session() -> void:
	for path in [SESSION_PATH, SESSION_TMP]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var access := str((d as Dictionary).get("access_token", ""))
		# A dictionary with no token in it is not a session, and adopting it
		# would only stop the scratch file being tried.
		if access == "":
			continue
		_access = access
		_refresh = str((d as Dictionary).get("refresh_token", ""))
		_expires_at = float((d as Dictionary).get("expires_at", 0.0))
		var pl = (d as Dictionary).get("player", {})
		_player = pl if typeof(pl) == TYPE_DICTIONARY else {}
		return


# Written to one side and renamed into place, the way iap.gd writes the ledger
# and for the same reason: opening the real path with WRITE truncates it, and
# this is a mobile game that is killed without warning. A process that died in
# that window left a half-written cloud_session.json, which _load_session reads
# as "not a dictionary" and skips -- a player silently signed out, and on iOS
# the sign-in button they need is not even drawn until Sign in with Apple
# exists. The rename is atomic, so the file on disk is either the old session
# or the new one and never half of either.
func _save_session() -> void:
	var f := FileAccess.open(SESSION_TMP, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"access_token": _access,
		"refresh_token": _refresh,
		"expires_at": _expires_at,
		"player": _player,
	}))
	f.close()
	var d := DirAccess.open("user://")
	if d == null:
		return
	# rename() will not replace an existing file, so the old one goes first.
	# The window this opens is the crash-with-no-session case, which costs a
	# sign-in; the window it closes is the corrupt-session case, which looks
	# identical and is reached far more often.
	if FileAccess.file_exists(SESSION_PATH):
		d.remove(SESSION_PATH)
	d.rename(SESSION_TMP, SESSION_PATH)


# Signing out used to be entirely local: forget the tokens, delete the file,
# emit. The refresh token stayed valid on GoTrue afterwards, and a refresh token
# is not a password -- it is a bearer credential that answers to whoever holds
# it, for as long as it lives.
#
# That matters because user:// on iOS is the app's Documents container, which is
# in every iCloud and Finder backup. So a copy of cloud_session.json out of a
# backup, a repaired phone, or a handed-down device was a working session even
# though the player had signed out and even after they had changed their Apple
# password -- and create_link_token needs nothing but a session, so one stolen
# copy could be spent on a permanent identity link to that island.
#
# Telling GoTrue first is what makes signing out mean something. It is fired and
# not waited on: the local half must happen whether or not the network answers,
# and a player who signs out on a plane has still signed out on that device.
func sign_out() -> void:
	if _access != "" and configured():
		_post("/auth/v1/logout?scope=global", {}, func(_c: int, _b) -> void: pass, true)
	_access = ""
	_refresh = ""
	_expires_at = 0.0
	_player = {}
	_dirty = false
	_pending = {}
	_time_epoch = 0.0
	_time_ticks = 0
	DirAccess.remove_absolute(SESSION_PATH)
	DirAccess.remove_absolute(SESSION_TMP)
	_clear_pending_link()
	_set_state("off")
	signed_out.emit()


# =============================================================================
#  Signing in
# =============================================================================
#
# `id_token` is the identity token from Apple or Google, and `nonce` is the RAW
# nonce that sign-in was started with. Supabase checks that one matches the
# other, which is what stops a token captured from one session being replayed
# into another.
#
# The two providers disagree about what "the nonce" means and it is the easiest
# mistake in the whole flow: Google copies the value into the token unchanged,
# so raw goes out and raw comes here; Apple is given a SHA-256 of it and puts
# the hash in the token, so the hash goes out and the RAW one comes here. Both
# callers hand this function the raw value -- see the note in google_auth.gd and
# the parameter comment on SignInWithApple::sign_in.
func sign_in(provider: String, id_token: String, nonce: String) -> void:
	if not configured():
		sign_in_failed.emit("Cloud saves are not set up in this build")
		return
	if id_token == "":
		sign_in_failed.emit("No identity token from %s" % provider)
		return
	_set_state("syncing")
	var done := func(code: int, body) -> void:
		if code != 200 or typeof(body) != TYPE_DICTIONARY or not (body as Dictionary).has("access_token"):
			_set_state("error")
			sign_in_failed.emit(_reason(body, "Sign-in was refused"))
			return
		_take_session(body)
		_set_state("synced")
		# Order matters here and it is easy to get backwards.
		#
		# If there is a link in flight, it has to be redeemed BEFORE the island
		# is claimed. Claiming first would hand this brand-new identity an island
		# of its own, and the redeem that followed would then be a genuine
		# collision between the player's real island and the empty one this code
		# had just created -- so the game would stop and ask the player to choose
		# between their island and nothing, which is not a question.
		#
		# Redeeming first attaches the identity to the island that already
		# exists, and the claim that follows simply finds it.
		if _pending_link() != "":
			_redeem_pending()
		else:
			session_ready.emit()
	_post("/auth/v1/token?grant_type=id_token", {
		"provider": provider,
		"id_token": id_token,
		"nonce": nonce,
	}, done, false)


func _take_session(body: Dictionary) -> void:
	_access = str(body.get("access_token", ""))
	_refresh = str(body.get("refresh_token", ""))
	_expires_at = _now() + float(body.get("expires_in", 3600.0))
	_save_session()


# The first call after any sign-in. `local` is the save that is on this device
# right now -- it seeds the island if the server has never seen this identity.
#
# Passing it is not optional in practice. Everybody who reaches a sign-in button
# has already been playing, because main.gd draws no sign-in at all on an Apple
# platform until Sign in with Apple exists -- the title screen is one green
# START PLAYING button. So the ordinary case is a real island meeting the server
# for the first time, and sending nothing would create an empty row and strand
# it.
func claim(local: Dictionary, name: String, emoji: String,
		rank: int, level: int, coins: int, shields: int, buildings: Array) -> void:
	_rpc("claim_player", {
		"p_save": local,
		"p_display_name": name,
		"p_emoji": emoji,
		"p_rank_stars": rank,
		"p_island_level": level,
		"p_vault_coins": coins,
		"p_shields": shields,
		"p_buildings": buildings,
	}, func(code: int, body) -> void:
		if code != 200 or typeof(body) != TYPE_DICTIONARY:
			_set_state("error")
			sign_in_failed.emit(_reason(body, "Could not open your island"))
			return
		var p = body.get("player", {})
		_player = p if typeof(p) == TYPE_DICTIONARY else {}
		_save_session()
		_set_state("synced")
		var remote = body.get("save", null)
		signed_in.emit(_player.duplicate(true), bool(body.get("is_new", false)),
				remote if typeof(remote) == TYPE_DICTIONARY else {})
		fetch_raids()
		fetch_gifts()
		# Before the game has had a chance to hand out a daily bonus against a
		# clock nobody has checked.
		refresh_time()
	)


# =============================================================================
#  The save
# =============================================================================
#
# main.gd calls this wherever it already calls _save_game(). It marks the copy
# dirty and returns; _process sends it at most every PUSH_GAP seconds.
# `force` is for the one case where a lower rank is the truth rather than a
# stale device: the player was shown both islands and deliberately chose the
# smaller one. Without it push_save rejects the write, main.gd is handed the
# server's island again, and the two sides argue for ever over a decision that
# has already been made.
func note_save(data: Dictionary, rank: int, level: int,
		coins: int, shields: int, buildings: Array, force := false) -> void:
	if not linked():
		return
	_pending = {
		"p_save": data,
		"p_rank_stars": rank,
		"p_island_level": level,
		"p_vault_coins": coins,
		"p_shields": shields,
		"p_buildings": buildings,
		"p_force": force,
	}
	_dirty = true


# For the two moments a delay is not acceptable, and they are the same two
# main.gd flushes to disk for: money changing hands, and the app being told it
# may be about to die.
func flush() -> void:
	if _dirty and not _in_flight:
		_push()


func _process(_delta: float) -> void:
	if not linked():
		return
	# Ahead of the save's own early-out on purpose. The score moves on raids
	# that do not always dirty the save in the same tick, and a tournament
	# report that only went out when a save happened to be pending would leave
	# the board stale for whole minutes at a time.
	if _t_dirty and not _t_in_flight and _now() - _t_last >= TOURNEY_GAP:
		_push_tourney()
	if not _dirty or _in_flight:
		return
	var now := _now()
	# Back off on a run of failures rather than hammering a radio that is not
	# going to come back this minute. Capped, because the player may walk back
	# into signal at any moment and should not wait ten minutes for the game to
	# notice.
	var gap := PUSH_GAP * minf(float(1 << mini(_fails, 4)), 16.0)
	if now - _last_push >= gap:
		_push()


func _push() -> void:
	if _pending.is_empty():
		_dirty = false
		return
	_in_flight = true
	_last_push = _now()
	_set_state("syncing")
	_rpc("push_save", _pending, func(code: int, body) -> void:
		_in_flight = false
		if code != 200 or typeof(body) != TYPE_DICTIONARY:
			# Left dirty on purpose: the next tick tries again. Nothing is lost
			# by failing here, because the authoritative copy is the one on
			# disk that main.gd already wrote.
			_fails += 1
			_set_state("error")
			return
		_fails = 0
		if str(body.get("status", "")) == "stale":
			# The server holds a further-along island than the one this device
			# is playing. That is not an error and must not be swallowed: it is
			# the second-phone case, and main.gd has to ask the player.
			_dirty = false
			_set_state("synced")
			var remote = body.get("save", null)
			save_rejected.emit(int(body.get("stored_rank", 0)),
					remote if typeof(remote) == TYPE_DICTIONARY else {})
			return
		_dirty = false
		_set_state("synced")
	)


# =============================================================================
#  A clock the player cannot wind
# =============================================================================
#
# main.gd measures every cooldown against its own high-water clock, which rises
# with the device and never falls. That stops the clock being wound BACK and
# does nothing about forward, which is the direction that pays: one trip to
# Settings is a full spin meter, the daily bonus, and the shop's free gift --
# and the gift carries a card, which is stars, which is the number the
# leaderboard sorts on.
#
# The device cannot referee this. So the server says what time it is, and the
# answer is carried forward with get_ticks_msec() rather than with the wall
# clock -- ticks are monotonic and, unlike Time.get_unix_time_from_system(),
# there is no setting that moves them.
#
# What this is NOT is a replacement for the local clock. It is an anchor that
# exists only when the game is signed in and has heard from the server at least
# once; main.gd falls back to its own clock otherwise, because a player with no
# account cannot reach the leaderboard and is only cheating themselves.
var _time_epoch := 0.0     # server unix time at the moment of the anchor
var _time_ticks := 0       # get_ticks_msec() at that same moment

func time_anchored() -> bool:
	return _time_epoch > 0.0

# Seconds since the epoch, according to the server plus however long this
# process has been running since it asked. Returns 0.0 when there is no anchor,
# which callers must treat as "no opinion" rather than as 1970.
func server_now() -> float:
	if _time_epoch <= 0.0:
		return 0.0
	return _time_epoch + float(Time.get_ticks_msec() - _time_ticks) / 1000.0

# Asked on every launch and again whenever the game comes back from the
# background -- which is exactly when a wound clock would otherwise be believed.
#
# get_ticks_msec() is stamped BEFORE the request rather than after it, so the
# round trip is counted as elapsed time. That errs by the latency, in the
# direction of the anchor being slightly behind real time, which costs a player
# a second on a cooldown and never pays one out early.
func refresh_time() -> void:
	if not linked():
		return
	var at := Time.get_ticks_msec()
	_rpc("server_time", {}, func(code: int, body) -> void:
		if code != 200:
			return
		var t := 0.0
		if typeof(body) == TYPE_FLOAT or typeof(body) == TYPE_INT:
			t = float(body)
		if t <= 0.0:
			return
		_time_epoch = t
		_time_ticks = at
		time_anchored_changed.emit()
	)

signal time_anchored_changed

# =============================================================================
#  Rivals and raids
# =============================================================================
#
# find_target answers with a rival or with null, and never says which kind it
# found. That is deliberate on the server side too -- see the comment on
# find_target in migration 0002. A null means the server had nobody at all in
# band, in which case main.gd uses its own local rivals and the spin resolves
# exactly as it does today.
func find_target(mode: String, then: Callable) -> void:
	if not linked():
		then.call({})
		return
	_rpc("find_target", {"p_mode": mode}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)


func record_raid(victim_id: String, mode: String, coins: int, hut: int = -1) -> void:
	if not linked() or victim_id == "":
		return
	var args := {"p_victim": victim_id, "p_mode": mode, "p_coins": coins}
	if hut >= 0:
		args["p_hut"] = hut
	_rpc("record_raid", args, func(_c: int, _b) -> void: pass)


func fetch_raids() -> void:
	if not linked():
		return
	_rpc("unseen_raids", {}, func(code: int, body) -> void:
		if code == 200 and typeof(body) == TYPE_ARRAY and not (body as Array).is_empty():
			raids_arrived.emit(body)
	)


# =============================================================================
#  Clans, and giving a spare card to somebody in one
# =============================================================================
#
# Every rule the feature depends on is enforced in the migration, not here:
# no self-sends, no 5-stars, clanmates only, and a daily cap on both giving
# and receiving. This layer only carries the call and hands back what the
# server said, because anything decided on this side is decided by the thing
# the rules are defending against.
#
# All of these degrade to "no clan" rather than erroring when the migration
# has not been applied yet: an unknown RPC comes back non-200, which every
# callback below reads as an empty answer.

# Whether the clan migration is live on this project.
#
# A build can reach the stores before the SQL is applied -- they are two
# separate hands -- and a client that cannot tell the difference offers a
# CREATE button that refuses. PostgREST is unambiguous about it: a function
# that exists but is not callable answers 401, and one that does not exist
# answers 404 with PGRST202. So the first call that comes back 404 turns the
# feature off, and it turns itself back on the moment the migration lands,
# with no build in between.
var _clans_ok := true

func clans_ready() -> bool:
	return _clans_ok

func _note_clan_code(code: int) -> void:
	if code == 404:
		_clans_ok = false
	elif code == 200:
		_clans_ok = true

func my_clan(then: Callable) -> void:
	if not linked():
		then.call({})
		return
	_rpc("my_clan", {}, func(code: int, body) -> void:
		_note_clan_code(code)
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func clan_list(then: Callable, limit := 30) -> void:
	if not linked():
		then.call([])
		return
	_rpc("clan_list", {"p_limit": limit}, func(code: int, body) -> void:
		_note_clan_code(code)
		then.call(body if code == 200 and typeof(body) == TYPE_ARRAY else [])
	)

func create_clan(name: String, emoji: String, then: Callable) -> void:
	if not linked():
		then.call({})
		return
	_rpc("create_clan", {"p_name": name, "p_emoji": emoji},
		func(code: int, body) -> void:
			then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func join_clan(clan_id: String, then: Callable) -> void:
	if not linked() or clan_id == "":
		then.call({})
		return
	_rpc("join_clan", {"p_clan": clan_id}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func leave_clan(then: Callable) -> void:
	if not linked():
		then.call({})
		return
	_rpc("leave_clan", {}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

# =============================================================================
#  Invites, join requests, and the number on the clan button
# =============================================================================
#
# Every one of these degrades to "nothing pending" rather than erroring when
# the 20260904170000 migration has not been applied yet -- the same contract
# the rest of this section keeps, and the reason the clan disc's badge simply
# stays dark on a project whose SQL is a build behind.

# THE ONE CALL THE BADGE IS DRAWN FROM.
#
# Two counts in one round trip, because this is read on launch, on returning
# from the background and on every visit to the clan page, and a badge is not
# worth two requests. `requests` comes back zero for anybody who is not the
# owner of their own clan, so the client never has to know that rule.
func clan_news(then: Callable) -> void:
	if not linked():
		then.call({})
		return
	_rpc("clan_news", {}, func(code: int, body) -> void:
		_note_clan_code(code)
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func clan_invites(then: Callable) -> void:
	if not linked():
		then.call([])
		return
	_rpc("my_clan_invites", {}, func(code: int, body) -> void:
		_note_clan_code(code)
		then.call(body if code == 200 and typeof(body) == TYPE_ARRAY else [])
	)

func accept_clan_invite(invite_id: String, then: Callable) -> void:
	if not linked() or invite_id == "":
		then.call({})
		return
	_rpc("accept_clan_invite", {"p_id": invite_id}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func decline_clan_invite(invite_id: String, then: Callable) -> void:
	if not linked() or invite_id == "":
		then.call({})
		return
	_rpc("decline_clan_invite", {"p_id": invite_id}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func invite_to_clan(player_id: String, then: Callable) -> void:
	if not linked() or player_id == "":
		then.call({})
		return
	_rpc("invite_to_clan", {"p_to": player_id}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func request_join_clan(clan_id: String, then: Callable) -> void:
	if not linked() or clan_id == "":
		then.call({})
		return
	_rpc("request_join_clan", {"p_clan": clan_id}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func clan_join_requests(then: Callable) -> void:
	if not linked():
		then.call([])
		return
	_rpc("clan_join_requests", {}, func(code: int, body) -> void:
		_note_clan_code(code)
		then.call(body if code == 200 and typeof(body) == TYPE_ARRAY else [])
	)

func answer_clan_request(request_id: String, accept: bool, then: Callable) -> void:
	if not linked() or request_id == "":
		then.call({})
		return
	_rpc("answer_clan_request", {"p_id": request_id, "p_accept": accept},
		func(code: int, body) -> void:
			then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func set_clan_open(open: bool, then: Callable) -> void:
	if not linked():
		then.call({})
		return
	_rpc("set_clan_open", {"p_open": open}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

# Prefix search over display names, for picking somebody to invite. The server
# refuses anything under three characters and only ever answers with players who
# are not already in a clan, so this sends the query as typed and does no
# filtering of its own -- see the migration for why the narrowness is the point.
func find_players(query: String, then: Callable) -> void:
	if not linked() or query.strip_edges().length() < 3:
		then.call([])
		return
	_rpc("find_players", {"p_query": query.strip_edges(), "p_limit": 12},
		func(code: int, body) -> void:
			_note_clan_code(code)
			then.call(body if code == 200 and typeof(body) == TYPE_ARRAY else [])
	)

# What is left of today's giving and receiving, so a button can be greyed out
# rather than pressed and refused.
func gift_budget(then: Callable) -> void:
	if not linked():
		then.call({})
		return
	_rpc("gift_budget", {}, func(code: int, body) -> void:
		_note_clan_code(code)
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

# THE SPARE IS NOT DEDUCTED HERE, and it must not be. main.gd takes it off
# `col_dupes` only after this call comes back `ok` -- a gift that failed at
# the cap, at the clan check or at the radio must not cost the sender a card
# they still hold. Same shape as the upgrade path, which has always paid for
# nothing until the thing bought exists.
func send_card(to_id: String, set_id: String, idx: int, stars: int, then: Callable) -> void:
	if not linked() or to_id == "":
		then.call({})
		return
	_rpc("send_card", {"p_to": to_id, "p_set": set_id, "p_idx": idx, "p_stars": stars},
		func(code: int, body) -> void:
			then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)

func fetch_gifts() -> void:
	if not linked():
		return
	_rpc("unseen_gifts", {}, func(code: int, body) -> void:
		if code == 200 and typeof(body) == TYPE_ARRAY and not (body as Array).is_empty():
			gifts_arrived.emit(body)
	)

# The same retry the raid ack has, for the same reason: unseen_gifts keeps
# returning a gift until seen_at is set, so a dropped ack means the card
# arrives again on the next launch. main.gd dedupes on the id as well, which
# is the half that holds even if this never lands.
func ack_gifts(ids: Array, attempt: int = 0) -> void:
	if not linked() or ids.is_empty():
		return
	_rpc("ack_gifts", {"p_ids": ids}, func(code: int, _b) -> void:
		if code == 200 or attempt >= ACK_RETRIES:
			return
		var t := get_tree().create_timer(2.0 * float(attempt + 1))
		t.timeout.connect(func() -> void: ack_gifts(ids, attempt + 1))
	)

# An ack that does not land is not cosmetic. unseen_raids keeps returning a raid
# until seen_at is set, so a dropped ack means the same raid arrives again on the
# next launch -- and main.gd applies whatever arrives. The coins come out twice.
#
# main.gd now refuses to apply an id it has already applied, which is the half of
# the fix that holds even if this call never succeeds. This is the other half:
# keep asking, rather than firing once into an ignored callback, so the server
# stops sending it.
const ACK_RETRIES := 3

func ack_raids(ids: Array, attempt: int = 0) -> void:
	if not linked() or ids.is_empty():
		return
	_rpc("ack_raids", {"p_ids": ids}, func(code: int, _b) -> void:
		if code == 200 or attempt >= ACK_RETRIES:
			return
		# Backing off rather than hammering: the usual reason an ack fails is
		# the radio, and the radio is not helped by being asked again at once.
		var t := get_tree().create_timer(2.0 * float(attempt + 1))
		t.timeout.connect(func() -> void: ack_raids(ids, attempt + 1))
	)


# =============================================================================
#  Name, face, and the two things Guideline 1.2 requires
# =============================================================================
#
# Every rule about a name is enforced on the server -- length, characters, the
# word list, and whether anyone (or any bot) already holds it. This asks; it does
# not decide. A client that decided could be edited into deciding differently.
#
# There is no separate "is it free" call here on purpose: set_display_name
# answers with the reason it refused, so one round trip does the work of two and
# there is no window in which a name is free when checked and taken when saved.
func set_display_name(name: String, then: Callable) -> void:
	_rpc("set_display_name", {"p_name": name}, func(code: int, body) -> void:
		var d = body if typeof(body) == TYPE_DICTIONARY else {}
		if code == 200 and bool(d.get("ok", false)):
			_player["name"] = str(d.get("name", name))
			_save_session()
		then.call(d)
	)


func set_emoji(emoji: String, then: Callable) -> void:
	_rpc("set_emoji", {"p_emoji": emoji}, func(code: int, body) -> void:
		var d = body if typeof(body) == TYPE_DICTIONARY else {}
		if code == 200 and bool(d.get("ok", false)):
			_player["emoji"] = emoji
			_save_session()
		then.call(d)
	)


# Reports and blocks in one move, which is deliberate: somebody upset enough to
# report a name wants it gone now, not after a review, and making them press two
# buttons in sequence to get that protects the wrong person.
func report_player(player_id: String, reason: String, then: Callable) -> void:
	if not linked() or player_id == "":
		then.call(false)
		return
	_rpc("report_player", {"p_player": player_id, "p_reason": reason},
		func(code: int, _b) -> void: then.call(code == 200))


# Crash reports, faults and feature counters, batched. See diag.gd for what is
# in them and why none of it identifies anybody.
#
# The only call in this file that is allowed to be dropped on the floor. Every
# other RPC here moves something a player owns; this one moves an observation
# about the game, and a diagnostics pipeline that retries hard enough to matter
# has become part of the problem it was installed to watch. One attempt, and
# `then(false)` means the caller should keep them for later -- or not.
func report_diagnostics(install: String, platform: String, os_version: String,
		model: String, build: int, events: Array, then: Callable) -> void:
	if not linked() or events.is_empty():
		then.call(false)
		return
	_rpc("report_diagnostics", {
		"p_install":  install,
		"p_platform": platform,
		"p_os":       os_version,
		"p_model":    model,
		"p_build":    build,
		"p_events":   events,
	}, func(code: int, _b) -> void: then.call(code == 200))


func leaderboard(then: Callable) -> void:
	if not linked():
		then.call([])
		return
	_rpc("leaderboard", {"p_limit": 50}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_ARRAY else [])
	)


# =============================================================================
#  The tournament
# =============================================================================
#
# A separate call from push_save rather than four more parameters on it, and
# that is worth a paragraph because the obvious thing is to add them.
#
# push_save carries the whole island and is REJECTED when it arrives out of
# order -- that is the second-phone rule, and it is the right rule for a save.
# A tournament score is neither: it is one small integer that changes on every
# raid, and a device holding a fresher score than the server's has nothing to
# argue about. Riding it on push_save would mean a player whose save is in
# conflict (a real state, which the game asks them to resolve) silently stops
# scoring in the tournament while they think about it.
#
# So it has its own debounce and its own cadence. Failure is ignored: the score
# on the phone is the authoritative copy, the next tick re-sends it, and a
# player in a tunnel who is never asked about the board loses nothing.
const TOURNEY_GAP := 25.0

var _t_pending: Dictionary = {}
var _t_dirty := false
var _t_last := 0.0
var _t_in_flight := false


# main.gd calls this wherever the score moves. Only the newest value is kept --
# a run of raids inside one window sends one number, not five.
func note_tourney(id: int, points: int) -> void:
	if not linked():
		return
	_t_pending = {"p_tourney_id": id, "p_points": maxi(0, points)}
	_t_dirty = true


# The league board: everyone at this player's stage, this cycle, by points.
# Each row is a public_player with a `points` field set on it.
func tourney_board(then: Callable, limit := 40) -> void:
	if not linked():
		then.call([])
		return
	_rpc("tourney_board", {"p_limit": limit}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_ARRAY else [])
	)


# Where this island finished in a cycle that has ended: {place, field, points}.
# An empty dictionary means the question could not be answered -- no signal, or
# a build that is ahead of the migration -- and main.gd treats that as "ask
# again later" rather than as "you won nothing".
func tourney_result(cycle: int, then: Callable) -> void:
	if not linked():
		then.call({})
		return
	_rpc("tourney_result", {"p_tourney_id": cycle}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)


func _push_tourney() -> void:
	if _t_pending.is_empty():
		_t_dirty = false
		return
	_t_in_flight = true
	_t_last = _now()
	_rpc("tourney_report", _t_pending, func(_code: int, _body) -> void:
		_t_in_flight = false
		_t_dirty = false
	)


# =============================================================================
#  Linking a second sign-in
# =============================================================================
#
# See the note on link_tokens in migration 0002 for why this is two steps and
# not one: a player cannot hold two provider sessions at once, so the island
# hands out a token before the switch and the new session redeems it after.
func create_link_token(then: Callable) -> void:
	_rpc("create_link_token", {}, func(code: int, body) -> void:
		then.call(str(body) if code == 200 else "")
	)


func _pending_link() -> String:
	if not FileAccess.file_exists(LINK_PATH):
		return ""
	var f := FileAccess.open(LINK_PATH, FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return ""
	# The server gives a token ten minutes; expiring it here as well means a
	# stale file from a sign-in the player abandoned last week does not quietly
	# attach the next one to an island they have forgotten about.
	if _now() - float(d.get("at", 0.0)) > 600.0:
		DirAccess.remove_absolute(LINK_PATH)
		return ""
	return str(d.get("token", ""))


func _clear_pending_link() -> void:
	if FileAccess.file_exists(LINK_PATH):
		DirAccess.remove_absolute(LINK_PATH)


# Step one, run while still signed in as the FIRST provider: ask the island for
# a token and write it down. `then` fires once it is safely on disk, and only
# then may the caller start the second sign-in -- which replaces this session.
func begin_link(then: Callable) -> void:
	if not linked():
		then.call(false)
		return
	create_link_token(func(token: String) -> void:
		if token == "":
			then.call(false)
			return
		var f := FileAccess.open(LINK_PATH, FileAccess.WRITE)
		if f == null:
			then.call(false)
			return
		f.store_string(JSON.stringify({"token": token, "at": _now()}))
		f.close()
		then.call(true)
	)


# Step two, after the second sign-in has replaced the session. Called
# automatically; see the ordering note in sign_in.
func _redeem_pending() -> void:
	var token := _pending_link()
	if token == "":
		session_ready.emit()
		return
	redeem_link_token(token, "", func(body: Dictionary) -> void:
		var status := str(body.get("status", "expired"))
		if status == "conflict":
			# Left on disk: resolve_link needs it, and the player has not
			# answered yet.
			var mine = body.get("mine", {})
			var theirs = body.get("theirs", {})
			link_result.emit("conflict",
					mine if typeof(mine) == TYPE_DICTIONARY else {},
					theirs if typeof(theirs) == TYPE_DICTIONARY else {})
			return
		_clear_pending_link()
		var who = body.get("player", {})
		if typeof(who) == TYPE_DICTIONARY:
			_player = who
			_save_session()
		link_result.emit(status, {}, {})
		# Whatever happened, the game still needs its island. An expired token
		# is not a reason to leave the player signed in with nothing.
		session_ready.emit()
	)


# The player picked. `keep_player_id` is the id of the island that survives.
func resolve_link(keep_player_id: String) -> void:
	var token := _pending_link()
	if token == "":
		session_ready.emit()
		return
	redeem_link_token(token, keep_player_id, func(body: Dictionary) -> void:
		_clear_pending_link()
		var who = body.get("player", {})
		if typeof(who) == TYPE_DICTIONARY:
			_player = who
			_save_session()
		link_result.emit(str(body.get("status", "expired")), {}, {})
		session_ready.emit()
	)


# Which providers already open this island. Answered by the server, not by this
# device: on a second phone the local answer is wrong, and a second phone is
# exactly what linking is for.
func identities(then: Callable) -> void:
	if not linked():
		then.call([])
		return
	_rpc("my_identities", {}, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_ARRAY else [])
	)


func redeem_link_token(token: String, keep_player_id: String, then: Callable) -> void:
	var args := {"p_token": token}
	if keep_player_id != "":
		args["p_keep"] = keep_player_id
	_rpc("redeem_link_token", args, func(code: int, body) -> void:
		then.call(body if code == 200 and typeof(body) == TYPE_DICTIONARY else {})
	)


# App Store guideline 5.1.1(v). Mandatory from the moment the game creates
# accounts, and it has to be reachable from inside the game.
func delete_account(then: Callable) -> void:
	_rpc("delete_account", {}, func(code: int, _body) -> void:
		if code == 200:
			sign_out()
		then.call(code == 200)
	)


# =============================================================================
#  Transport
# =============================================================================
func _rpc(fn: String, args: Dictionary, then: Callable) -> void:
	if not configured():
		then.call(0, null)
		return
	_with_fresh_token(func() -> void:
		_post("/rest/v1/rpc/" + fn, args, then, true)
	)


# Refreshes first if the token is close to expiry, so no caller has to think
# about it. A refresh that fails still runs the request: it may be a token that
# is fine and a network that is not, and the 401 that comes back is a cheaper
# way to find out than a second state machine.
#
# ONE REFRESH AT A TIME, and this is not a tidiness guard -- it is the fix for a
# silent sign-out that fired on an ordinary resume.
#
# GoTrue ROTATES refresh tokens: spending one issues a new one and retires the
# old. This used to fire a request per caller, and callers arrive together.
# _resume_from_away calls refresh_time() and then _flush_save(), which marks the
# copy dirty, so cloud's own _process pushes a frame or two later -- while the
# first refresh is still on the wire and _expires_at is therefore still stale.
# Two requests then spent the SAME refresh token. Supabase forgives that inside
# its reuse interval (ten seconds by default) and hands both the same session,
# which is why this survived being looked at. Outside it -- a slow radio, a
# retry, a second request that simply took longer -- the loser gets a 400 for a
# token that was already spent, and the branch below reads that as "revoked in
# Settings" and signs the player out. Reuse detection can also revoke the whole
# token family, which signs them out on every device at once.
#
# So the first caller sends the request and everyone who arrives while it is in
# flight waits in line. They are all called back afterwards -- including when
# the refresh failed -- because a caller whose `then` never runs is a request
# that silently disappears.
var _refreshing := false
var _refresh_waiters: Array = []

func _with_fresh_token(then: Callable) -> void:
	if _refresh == "" or _now() < _expires_at - REFRESH_MARGIN:
		then.call()
		return
	_refresh_waiters.append(then)
	if _refreshing:
		return
	_refreshing = true
	# Read once, here. sign_out() below clears _refresh, and the request must
	# carry the token this call set out with either way.
	var spending := _refresh
	var done := func(code: int, body) -> void:
		_refreshing = false
		if code == 200 and typeof(body) == TYPE_DICTIONARY and (body as Dictionary).has("access_token"):
			_take_session(body)
		elif code == 400 or code == 401:
			# The refresh token is gone for good -- revoked in Settings,
			# password changed, account deleted elsewhere. Signing out is
			# honest; retrying forever is not. Only ever reached by the one
			# caller that actually spent the token, never by a queued sibling
			# that would have spent it a second time.
			sign_out()
		# Taken and cleared before any of them run: a waiter is free to make
		# another request, and that request must queue behind the NEXT refresh
		# rather than land in the list being drained.
		var waiting: Array = _refresh_waiters.duplicate()
		_refresh_waiters.clear()
		for w in waiting:
			(w as Callable).call()
	_post("/auth/v1/token?grant_type=refresh_token", {"refresh_token": spending}, done, false)


func _post(path: String, body: Variant, then: Callable, authed: bool) -> void:
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT
	add_child(http)

	var headers := PackedStringArray([
		"apikey: " + _key,
		"Content-Type: application/json",
		# PostgREST returns a bare scalar for a function that returns one, which
		# a JSON parser will not accept as a document without this.
		"Accept: application/json",
	])
	if authed and _access != "":
		headers.append("Authorization: Bearer " + _access)
	else:
		# Unauthenticated calls still have to present something: GoTrue reads
		# the publishable key from here as well as from apikey.
		headers.append("Authorization: Bearer " + _key)

	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS:
				# No connection, DNS failure, timeout. Not distinguished,
				# because there is nothing different to do about any of them.
				then.call(0, null)
				return
			var text := raw.get_string_from_utf8()
			var parsed = JSON.parse_string(text) if text != "" else null
			then.call(code, parsed)
	)

	var err := http.request(_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		then.call(0, null)


# Supabase reports failures in more than one shape depending on which service
# answered. None of these strings are shown raw to a player; they exist so a
# banner can say something truer than "something went wrong" when it has to.
func _reason(body: Variant, fallback: String) -> String:
	if typeof(body) != TYPE_DICTIONARY:
		return fallback
	for k in ["error_description", "msg", "message", "error"]:
		var v = (body as Dictionary).get(k, "")
		if typeof(v) == TYPE_STRING and v != "":
			return v
	return fallback


func _now() -> float:
	return Time.get_unix_time_from_system()
