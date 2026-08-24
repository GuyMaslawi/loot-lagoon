class_name AppleAuth
extends Node

# Sign in with Apple, native.
#
# Deliberately the same shape as google_auth.gd -- start(), then exactly one of
# login_finished / login_failed / login_cancelled -- so main.gd can treat the
# two providers as one thing and the sign-in screen does not grow a branch per
# provider. Everything below the surface is different: Google is an OAuth dance
# this game runs itself over a loopback socket, Apple is a system sheet the
# SignInWithApple plugin puts on screen.
#
# There is no simulation fallback here, unlike iap.gd. A sign-in that pretends
# to succeed would hand cloud.gd a token Supabase will reject, and the failure
# would surface three steps away from its cause. available() answers honestly
# and main.gd simply does not draw the button.

signal login_finished(profile: Dictionary)
signal login_failed(reason: String)
signal login_cancelled()

const PLUGIN := "SignInWithApple"

# The raw nonce for this attempt. The plugin is given a SHA-256 of it and never
# sees this value; Supabase is given this value and never sees the hash. See
# _hash_nonce for why that asymmetry exists.
var _nonce := ""
var _plugin: Object = null


static func available() -> bool:
	if not Engine.has_singleton(PLUGIN):
		return false
	var p := Engine.get_singleton(PLUGIN)
	return p != null and p.is_available()


func start() -> bool:
	if not available():
		return false
	_plugin = Engine.get_singleton(PLUGIN)

	var crypto := Crypto.new()
	# 32 bytes, hex-encoded, so the value is safe in a URL, in a JWT claim and
	# in a JSON body without anybody having to think about escaping it.
	_nonce = crypto.generate_random_bytes(32).hex_encode()

	_plugin.sign_in_succeeded.connect(_on_success, CONNECT_ONE_SHOT)
	_plugin.sign_in_failed.connect(_on_failed, CONNECT_ONE_SHOT)
	_plugin.sign_in_cancelled.connect(_on_cancelled, CONNECT_ONE_SHOT)
	_plugin.sign_in(_hash_nonce(_nonce))
	return true


# Apple takes the HASH and puts the hash in the token; Supabase takes the RAW
# value and hashes it to compare. Google does neither -- it copies the raw value
# into the token untouched, which is why google_auth.gd sends its nonce raw.
#
# Getting these two backwards produces a token that verifies nowhere, with an
# error message that says nothing about nonces. It has its own function so that
# there is exactly one place where the hashing happens and one comment
# explaining it.
static func _hash_nonce(raw: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _on_success(cred: Dictionary) -> void:
	_disconnect()

	# THE FIRST-AUTHORIZATION TRAP, restated here because this is where the
	# consequence lands.
	#
	# Apple sends the player's name once -- on the very first authorization this
	# app ever gets -- and never again. Not on the next sign-in, not after a
	# reinstall, not on a new phone. The only way to make it come back is for
	# the player to revoke the app under Settings > Apple ID and start over,
	# which nobody will ever do because nobody knows it exists.
	#
	# So the name goes out in this signal and main.gd writes it to
	# user://profile.json immediately. The symptom of getting this wrong is
	# every account after the first being called "Islander" for ever, and by
	# then it is unfixable for the players it already happened to.
	var given := str(cred.get("given_name", ""))
	var family := str(cred.get("family_name", ""))
	var name := (given + " " + family).strip_edges()

	login_finished.emit({
		"name": name,
		"email": str(cred.get("email", "")),
		"provider": "apple",
		# Stable, and scoped to this developer team. Kept so credential_state()
		# can be asked about it on later launches -- a player who revoked us in
		# Settings believes they are backed up and is not.
		"user_id": str(cred.get("user_id", "")),
		"id_token": str(cred.get("id_token", "")),
		"nonce": _nonce,
		# False on every sign-in after the first. main.gd uses it to know that
		# an empty name here is Apple being Apple rather than a player with no
		# name, and to keep the one it already stored.
		"is_first": bool(cred.get("is_first_authorization", false)),
	})


func _on_failed(reason: String) -> void:
	_disconnect()
	login_failed.emit(reason)


# Backing out of the sheet is the most common outcome of tapping a sign-in
# button, and it is a decision rather than a fault. It gets its own signal for
# the same reason iap.gd gives purchase_cancelled one: answering a deliberate
# choice with a red banner is how a title screen starts feeling hostile.
func _on_cancelled() -> void:
	_disconnect()
	login_cancelled.emit()


# CONNECT_ONE_SHOT drops the connection that fired, but not the other two, and
# this object usually outlives the attempt. Left alone, a second sign-in would
# stack a second set and the next answer would be emitted twice.
func _disconnect() -> void:
	if _plugin == null:
		return
	for pair in [["sign_in_succeeded", _on_success], ["sign_in_failed", _on_failed],
			["sign_in_cancelled", _on_cancelled]]:
		if _plugin.is_connected(pair[0], pair[1]):
			_plugin.disconnect(pair[0], pair[1])


# "authorized", "revoked", "notFound", "transferred" or "unknown".
#
# Asked on launch for a player who signed in with Apple, because revocation
# happens in iOS Settings while the game is not running and there is no other
# way to hear about it. "unknown" means iOS did not answer in time and must be
# treated as "ask again later", never as a revocation.
static func credential_state(user_id: String) -> String:
	if not Engine.has_singleton(PLUGIN) or user_id == "":
		return "unknown"
	return str(Engine.get_singleton(PLUGIN).credential_state(user_id))
