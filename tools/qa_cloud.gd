extends Node
# Temporary QA harness -- the session, and the two ways it used to be lost.
# Not shipped.
#
# Neither of these is about the game being wrong. They are about a signed-in
# player being quietly turned into a signed-out one, which on this project is
# the worst non-money failure there is: the whole reason cloud.gd exists is that
# losing the phone should not mean losing the island.
#
# Nothing here touches the real server. _url is pointed at a dead local port so
# every request fails as "no connection" -- code 0, which is deliberately the
# one answer that must NOT sign anybody out.

var fails := 0

const DEAD := "http://127.0.0.1:1"

func _ready() -> void:
	await _t_single_flight_refresh()
	await _t_network_failure_keeps_session()
	_t_session_write_is_atomic()
	_t_survives_a_kill_between_the_two_writes()
	_t_sign_out_takes_the_scratch_file()
	print("QA-CLOUD: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _chk(name: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1

# A session that is due a refresh, talking to nothing.
func _arm(refresh := "refresh-token-1") -> void:
	Cloud._url = DEAD
	Cloud._key = "test-key"
	Cloud._access = "access-token-1"
	Cloud._refresh = refresh
	Cloud._expires_at = 0.0          # long past, so every call wants a refresh
	Cloud._refreshing = false
	Cloud._refresh_waiters.clear()

func _wipe() -> void:
	for f in [Cloud.SESSION_PATH, Cloud.SESSION_TMP]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)

# --- two callers, one refresh token -----------------------------------------
#
# GoTrue rotates refresh tokens, so spending one retires it. _resume_from_away
# calls refresh_time() and then flushes, and cloud's own _process pushes a frame
# later -- while the first refresh is still on the wire. Both used to spend the
# same token, and the loser's 400 was read as "revoked" and signed the player
# out, on every device at once if reuse detection fired.
func _t_single_flight_refresh() -> void:
	print("two callers arriving on the same expired token")
	_arm()
	var ran := [0, 0]
	Cloud._with_fresh_token(func() -> void: ran[0] += 1)
	_chk("the first caller sends the refresh", Cloud._refreshing)
	_chk("and waits rather than proceeding on a stale token", ran[0] == 0)

	Cloud._with_fresh_token(func() -> void: ran[1] += 1)
	_chk("the second caller does NOT send a second one", Cloud._refreshing)
	_chk("both are queued behind the one request", Cloud._refresh_waiters.size() == 2,
		 str(Cloud._refresh_waiters.size()))

	# The request fails as "no connection". Everyone still gets their turn.
	await get_tree().create_timer(3.0).timeout
	_chk("both callers are released once it comes back", ran == [1, 1], str(ran))
	_chk("and the queue is empty afterwards", Cloud._refresh_waiters.is_empty())
	_chk("the flag is cleared, so the next call may refresh again",
		 not Cloud._refreshing)

# --- a dead radio is not a revoked token ------------------------------------
func _t_network_failure_keeps_session() -> void:
	print("the refresh could not be sent at all")
	_arm()
	var ran := [0]
	Cloud._with_fresh_token(func() -> void: ran[0] += 1)
	await get_tree().create_timer(3.0).timeout
	_chk("the caller ran", ran[0] == 1)
	_chk("and a failure to connect did not sign anybody out",
		 Cloud._refresh == "refresh-token-1", Cloud._refresh)
	_chk("the access token is untouched", Cloud._access == "access-token-1")

# --- killed halfway through writing the session -----------------------------
#
# Opening the real path with WRITE truncates it first. A process killed in that
# window left a half-written file, which _load_session reads as "not a
# dictionary" and skips -- a silent sign-out. The write now lands on a scratch
# path and is renamed into place.
func _t_session_write_is_atomic() -> void:
	print("killed mid-write")
	_wipe()
	Cloud._access = "A"
	Cloud._refresh = "R"
	Cloud._expires_at = 12345.0
	Cloud._player = {"id": "p1"}
	Cloud._save_session()
	_chk("the session reached the disk", FileAccess.file_exists(Cloud.SESSION_PATH))
	_chk("and the scratch file was not left behind",
		 not FileAccess.file_exists(Cloud.SESSION_TMP))

	# A truncated scratch file from a previous death must not be read as the
	# session, and must not survive the next successful write.
	var f := FileAccess.open(Cloud.SESSION_TMP, FileAccess.WRITE)
	f.store_string('{"access_token": "half')
	f.close()
	Cloud._access = ""
	Cloud._refresh = ""
	Cloud._player = {}
	Cloud._load_session()
	_chk("a leftover half-written file is never the session read back",
		 Cloud._access == "A" and Cloud._refresh == "R", Cloud._access)
	_chk("and the player came back with it", str(Cloud._player.get("id", "")) == "p1")

	Cloud._save_session()
	_chk("the next save clears the leftover", not FileAccess.file_exists(Cloud.SESSION_TMP))

# --- signing out has to take both files --------------------------------------
#
# Otherwise a stale scratch file is renamed into place by the next save and a
# signed-out device quietly has a session again.
func _t_sign_out_takes_the_scratch_file() -> void:
	print("signing out with a scratch file on disk")
	_wipe()
	Cloud._url = DEAD
	Cloud._access = "A"
	Cloud._refresh = "R"
	Cloud._save_session()
	var f := FileAccess.open(Cloud.SESSION_TMP, FileAccess.WRITE)
	f.store_string("leftover")
	f.close()
	Cloud.sign_out()
	_chk("the session file is gone", not FileAccess.file_exists(Cloud.SESSION_PATH))
	_chk("and so is the scratch file", not FileAccess.file_exists(Cloud.SESSION_TMP))
	_chk("the tokens are forgotten", Cloud._access == "" and Cloud._refresh == "")

# --- killed between the remove and the rename --------------------------------
#
# The atomic write is two operations, because rename() will not replace a file
# that exists. A death in between leaves a whole session under the scratch name
# and nothing under the real one -- which, without the fallback, reads exactly
# like never having signed in.
func _t_survives_a_kill_between_the_two_writes() -> void:
	print("killed between the remove and the rename")
	_wipe()
	Cloud._access = "A2"
	Cloud._refresh = "R2"
	Cloud._expires_at = 999.0
	Cloud._player = {"id": "p2"}
	Cloud._save_session()
	# Exactly the state that window leaves: the scratch file, and no real one.
	var f := FileAccess.open(Cloud.SESSION_PATH, FileAccess.READ)
	var whole := f.get_as_text()
	f.close()
	DirAccess.remove_absolute(Cloud.SESSION_PATH)
	var t := FileAccess.open(Cloud.SESSION_TMP, FileAccess.WRITE)
	t.store_string(whole)
	t.close()

	Cloud._access = ""
	Cloud._refresh = ""
	Cloud._player = {}
	Cloud._load_session()
	_chk("a session stranded under the scratch name is still found",
		 Cloud._access == "A2" and Cloud._refresh == "R2", Cloud._access)
	_chk("with the island it belongs to", str(Cloud._player.get("id", "")) == "p2")

	# And the half-written case must NOT be adopted, or the fallback has simply
	# traded one silent sign-out for a corrupt session.
	_wipe()
	var h := FileAccess.open(Cloud.SESSION_TMP, FileAccess.WRITE)
	h.store_string('{"access_token": "hal')
	h.close()
	Cloud._access = ""
	Cloud._refresh = ""
	Cloud._load_session()
	_chk("but a half-written scratch file is not", Cloud._access == "", Cloud._access)
	_wipe()
