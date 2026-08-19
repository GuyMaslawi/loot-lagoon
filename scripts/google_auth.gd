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
var _client_id := ""
var _poll_timer: Timer

static func load_config() -> Dictionary:
	if FileAccess.file_exists("res://google_oauth.json"):
		var f := FileAccess.open("res://google_oauth.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
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
	_server = TCPServer.new()
	if _server.listen(REDIRECT_PORT, "127.0.0.1") != OK:
		return false
	var redirect := "http://127.0.0.1:%d" % REDIRECT_PORT
	var url := "https://accounts.google.com/o/oauth2/v2/auth?client_id=%s&redirect_uri=%s&response_type=code&scope=%s&code_challenge=%s&code_challenge_method=S256" % [
		_client_id.uri_encode(), redirect.uri_encode(), "openid profile email".uri_encode(), challenge]
	OS.shell_open(url)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.4
	_poll_timer.timeout.connect(_poll)
	add_child(_poll_timer)
	_poll_timer.start()
	return true

static func _b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

func _poll() -> void:
	if _server == null or not _server.is_connection_available():
		return
	_poll_timer.stop()
	var conn := _server.take_connection()
	await get_tree().create_timer(0.3).timeout
	var request_text := ""
	var n := conn.get_available_bytes()
	if n > 0:
		request_text = conn.get_utf8_string(n)
	var html := "<html><body style='font-family:sans-serif;text-align:center;padding-top:80px'><h2>Login complete!</h2>You can close this window and return to Loot Lagoon.</body></html>"
	conn.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" + html).to_utf8_buffer())
	await get_tree().create_timer(0.2).timeout
	conn.disconnect_from_host()
	_server.stop()
	_server = null
	var code := ""
	for part in request_text.split(" "):
		if part.begins_with("/?"):
			for kv in part.trim_prefix("/?").split("&"):
				var pair := kv.split("=")
				if pair.size() == 2 and pair[0] == "code":
					code = pair[1].uri_decode()
	if code == "":
		login_failed.emit("No authorization code received")
		return
	_exchange(code)

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
		})
	)
	http.request("https://openidconnect.googleapis.com/v1/userinfo",
		PackedStringArray(["Authorization: Bearer " + token]))
