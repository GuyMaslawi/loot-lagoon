class_name GoogleAuth
extends Node

signal login_finished(profile: Dictionary)
signal login_failed(reason: String)

# This is a public OAuth client: it ships inside the app, so anyone can read
# whatever is in it. That is fine for the client id and fatal for a secret, so
# the flow is PKCE-only -- the code_verifier below is generated per login and
# never leaves the device, which is what replaces the secret. Use an "iOS" (or
# "Desktop app") client type in Google Cloud; a "Web application" client
# demands a secret and must not be used here.

const REDIRECT_PORT := 42815

var _server: TCPServer
var _verifier := ""
var _state := ""
# A browser request line and headers, and nothing like this much of one. The
# read used to be however many bytes the peer felt like sending.
const MAX_REQUEST_BYTES := 8192
var _client_id := ""
var _poll_timer: Timer
# The OIDC nonce, and it is not the same mechanism as the PKCE verifier above.
# PKCE binds the authorization *code* to this device, so a stolen code cannot be
# exchanged. The nonce binds the resulting *identity token* to this particular
# sign-in, so a token captured from one session cannot be replayed into another
# -- which is exactly what Supabase checks when the token is handed to it.
#
# Sent raw, unlike Apple's. Google follows OIDC and copies the value into the
# token's `nonce` claim unmodified, so the raw value is what verifies; Apple
# takes a SHA-256 of it and expects the raw one alongside. Getting those two
# backwards produces a token that verifies nowhere, so they are kept apart on
# purpose: this is raw end to end, and sign_in_with_apple.mm takes the hash.
var _nonce := ""
var _id_token := ""

static func load_config() -> Dictionary:
	if FileAccess.file_exists("res://google_oauth.json"):
		var f := FileAccess.open("res://google_oauth.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				# This file is packed into the shipped app, so anything in it
				# is readable by anyone who unzips the build. The flow is
				# PKCE-only and has no use for a secret; if one is present the
				# person who set this up followed the old instructions, and the
				# only useful thing to do is drop it on the floor and say so
				# loudly rather than ship it to Google from a public client.
				if d.has("client_secret"):
					push_error("google_oauth.json contains a client_secret. Remove it -- it ships inside the app and is not a secret once it does. This flow uses PKCE and does not need one.")
					d.erase("client_secret")
				return d
	return {}

func start() -> bool:
	var cfg := load_config()
	_client_id = str(cfg.get("client_id", ""))
	if _client_id == "":
		return false
	var crypto := Crypto.new()
	_verifier = _b64url(crypto.generate_random_bytes(48))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(_verifier.to_utf8_buffer())
	var challenge := _b64url(ctx.finish())
	_nonce = _b64url(crypto.generate_random_bytes(32))
	# Names this particular sign-in. The loopback listener answers to anything
	# that can open a TCP connection to localhost -- another app on the machine,
	# or any web page the player has open, via an <img src="http://127.0.0.1:
	# 42815/?code=..."> the browser fetches without being asked. Without a
	# state to check, the first such request was taken as the callback: the
	# listener shut down, and the genuine redirect a second later found nothing
	# listening. PKCE already stopped an injected code from being *exchanged*,
	# so the prize was never the account -- but sign-in could be broken on
	# demand, from a browser tab, and the player was told Google had failed.
	_state = _b64url(crypto.generate_random_bytes(24))
	_server = TCPServer.new()
	if _server.listen(REDIRECT_PORT, "127.0.0.1") != OK:
		return false
	var redirect := "http://127.0.0.1:%d" % REDIRECT_PORT
	var url := "https://accounts.google.com/o/oauth2/v2/auth?client_id=%s&redirect_uri=%s&response_type=code&scope=%s&state=%s&nonce=%s&code_challenge=%s&code_challenge_method=S256" % [
		_client_id.uri_encode(), redirect.uri_encode(), "openid profile email".uri_encode(),
		_state.uri_encode(), _nonce.uri_encode(), challenge]
	OS.shell_open(url)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.4
	_poll_timer.timeout.connect(_poll)
	add_child(_poll_timer)
	_poll_timer.start()
	_deadline = Time.get_ticks_msec() + int(LOGIN_TIMEOUT * 1000.0)
	return true

# Most sign-ins that do not succeed do not fail either: the browser opens, the
# player closes the tab or never finishes, and nothing ever comes back. Without
# a deadline this object then sits there for the rest of the session polling a
# TCP server that is holding port 42815 -- so a second attempt cannot even bind
# it, and the button reports "Could not start Google login" for a reason that
# has nothing to do with Google. Giving up releases the port and lets the
# player try again.
const LOGIN_TIMEOUT := 300.0
var _deadline := 0

func _shutdown() -> void:
	if _poll_timer != null:
		_poll_timer.stop()
	if _server != null:
		_server.stop()
		_server = null

static func _b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

func _poll() -> void:
	if _server == null:
		return
	if not _server.is_connection_available():
		if _deadline > 0 and Time.get_ticks_msec() > _deadline:
			_shutdown()
			login_failed.emit("Sign-in timed out")
		return
	# Paused, not stopped: if this turns out to be somebody else's request the
	# real callback is still coming and we have to be here for it.
	_poll_timer.stop()
	var conn := _server.take_connection()
	await get_tree().create_timer(0.3).timeout
	# Freed across the await -- the login sheet was closed, the scene reloaded
	# -- and everything below would be touching a dead node and a null tree.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if conn == null:
		_resume()
		return
	var request_text := ""
	var n := mini(conn.get_available_bytes(), MAX_REQUEST_BYTES)
	if n > 0:
		request_text = conn.get_utf8_string(n)
	var params := _query_params(request_text)
	# Constant-time is not the concern here; being the right sign-in is. An
	# empty stored state would match an absent one, so require both.
	var mine := _state != "" and String(params.get("state", "")) == _state
	var body := "<h2>Login complete!</h2>You can close this window and return to Loot Lagoon."
	if not mine:
		body = "<h2>Not expecting this</h2>This request did not come from a sign-in Loot Lagoon started."
	var html := "<html><body style='font-family:sans-serif;text-align:center;padding-top:80px'>" + body + "</body></html>"
	conn.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" + html).to_utf8_buffer())
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	conn.disconnect_from_host()
	if not mine:
		# Somebody else knocking. Go back to waiting for the real redirect.
		_resume()
		return
	_shutdown()
	# Google reports a refusal on the redirect too, and it is not a missing
	# code -- saying so beats "No authorization code received".
	var err := String(params.get("error", ""))
	if err != "":
		login_failed.emit("Google refused the sign-in (%s)" % err)
		return
	var code := String(params.get("code", ""))
	if code == "":
		login_failed.emit("No authorization code received")
		return
	_exchange(code)

# Back to listening, unless the clock has run out on this attempt.
func _resume() -> void:
	if _server == null or _poll_timer == null:
		return
	if _deadline > 0 and Time.get_ticks_msec() > _deadline:
		_shutdown()
		login_failed.emit("Sign-in timed out")
		return
	_poll_timer.start()

# The query string off the request line, decoded. Anything malformed is simply
# absent rather than an error -- this parses whatever a stranger sent.
static func _query_params(request_text: String) -> Dictionary:
	var out := {}
	for part in request_text.split(" "):
		if not part.begins_with("/?"):
			continue
		for kv in part.trim_prefix("/?").split("&"):
			var pair := kv.split("=")
			if pair.size() == 2:
				out[pair[0].uri_decode()] = pair[1].uri_decode()
	return out

func _exchange(code: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var fields := "code=%s&client_id=%s&redirect_uri=%s&grant_type=authorization_code&code_verifier=%s" % [
		code.uri_encode(), _client_id.uri_encode(),
		("http://127.0.0.1:%d" % REDIRECT_PORT).uri_encode(), _verifier.uri_encode()]
	http.request_completed.connect(func(_r: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		var d = JSON.parse_string(body.get_string_from_utf8())
		if response_code != 200 or typeof(d) != TYPE_DICTIONARY or not d.has("access_token"):
			login_failed.emit("Token exchange failed (%d)" % response_code)
			return
		# Google returns this because the scope asks for `openid`, and until now
		# it was parsed and discarded -- the flow only ever wanted a display
		# name. It is the credential Supabase actually authenticates with, so
		# from here it is carried through to login_finished rather than thrown
		# away and re-fetched by some second, weaker means later.
		_id_token = str(d.get("id_token", ""))
		_userinfo(str(d["access_token"]))
	)
	http.request("https://oauth2.googleapis.com/token",
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST, fields)

func _userinfo(token: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		var d = JSON.parse_string(body.get_string_from_utf8())
		if response_code != 200 or typeof(d) != TYPE_DICTIONARY:
			login_failed.emit("Failed to fetch profile")
			return
		login_finished.emit({
			"name": str(d.get("name", "Player")),
			"email": str(d.get("email", "")),
			"provider": "google",
			# What cloud.gd trades for a Supabase session. Both halves are
			# needed: the token carries the nonce claim, and the raw nonce is
			# what Supabase compares it against.
			"id_token": _id_token,
			"nonce": _nonce,
		})
	)
	http.request("https://openidconnect.googleapis.com/v1/userinfo",
		PackedStringArray(["Authorization: Bearer " + token]))
