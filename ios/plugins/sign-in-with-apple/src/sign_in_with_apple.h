/**************************************************************************/
/*  sign_in_with_apple.h                                                  */
/*  Loot Lagoon -- native Sign in with Apple for Godot 4.                 */
/**************************************************************************/

#ifndef sign_in_with_apple_implementation_h
#define sign_in_with_apple_implementation_h

#include "core/object/class_db.h"
#include "core/version.h"

// Why this exists as native code at all, when google_auth.gd does OAuth in
// pure GDScript over a loopback TCPServer:
//
// Apple's web flow will not do loopback. Google allows http://127.0.0.1 for a
// native client; Apple requires an HTTPS redirect URI and answers with a POST,
// which means a server. More to the point, on iOS a browser bounce is the wrong
// experience and the wrong answer to Guideline 4.8 -- reviewers expect the
// system sheet with Face ID, not Safari. So iOS gets this, and Android reuses
// the web flow (which Apple does support off-platform) for the linking case.
class SignInWithApple : public Object {
	GDCLASS(SignInWithApple, Object);

	static void _bind_methods();

public:
	static SignInWithApple *get_singleton();

	// False on anything before iOS 13. The game must not draw the button when
	// this is false: a black Apple button that opens nothing is Guideline 2.1,
	// the same rejection main.gd's `ready` flag already guards against.
	bool is_available();

	// Presents the system sheet.
	//
	// `hashed_nonce` is the SHA-256 hex of a nonce the CALLER generated and is
	// still holding. Apple embeds it in the returned identity token; the raw
	// value goes to Supabase alongside the token, and Supabase checks that one
	// hashes to the other. Without it, a token captured from one session can be
	// replayed into another. The plugin never sees the raw nonce, deliberately
	// -- it has no reason to, and the less of it that exists the better.
	//
	// Answers on exactly one of sign_in_succeeded / sign_in_failed /
	// sign_in_cancelled.
	void sign_in(const String &p_hashed_nonce);

	// "authorized", "revoked", "notFound", "transferred", or "unknown".
	//
	// A player can revoke this app's Apple ID credential in iOS Settings at any
	// time, including while the app is not running. Checked on launch, because
	// a stale session against a revoked credential is a player who thinks they
	// are backed up and is not.
	String credential_state(const String &p_user_id);

	SignInWithApple();
	~SignInWithApple();
};

#endif /* sign_in_with_apple_implementation_h */
