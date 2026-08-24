/**************************************************************************/
/*  sign_in_with_apple.mm                                                 */
/**************************************************************************/

#import "sign_in_with_apple.h"

#import "core/variant/variant.h"

#import <AuthenticationServices/AuthenticationServices.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

SignInWithApple *sign_in_with_apple_singleton = NULL;

SignInWithApple *SignInWithApple::get_singleton() {
	return sign_in_with_apple_singleton;
}

static String to_godot(NSString *p_str) {
	if (p_str == nil) {
		return String();
	}
	const char *utf8 = [p_str UTF8String];
	return utf8 ? String::utf8(utf8) : String();
}

// Apple hands the token back as raw NSData holding UTF-8 JWT bytes.
static String data_to_godot(NSData *p_data) {
	if (p_data == nil) {
		return String();
	}
	NSString *str = [[NSString alloc] initWithData:p_data encoding:NSUTF8StringEncoding];
	return to_godot(str);
}

// Every signal leaves here rather than from the delegate directly, because
// Apple answers on a thread of its choosing and Godot objects are not
// thread-safe. call_deferred lands it at the top of a frame instead of halfway
// through one -- the same reason local_notifications.mm defers its own.
static void emit_deferred(const char *p_signal) {
	if (sign_in_with_apple_singleton) {
		sign_in_with_apple_singleton->call_deferred("emit_signal", String(p_signal));
	}
}

static void emit_deferred(const char *p_signal, const Variant &p_arg) {
	if (sign_in_with_apple_singleton) {
		sign_in_with_apple_singleton->call_deferred("emit_signal", String(p_signal), p_arg);
	}
}

/**************************************************************************/
/*  Delegate                                                              */
/**************************************************************************/

@interface GodotSIWADelegate : NSObject <ASAuthorizationControllerDelegate,
											   ASAuthorizationControllerPresentationContextProviding>
@end

@implementation GodotSIWADelegate

- (void)authorizationController:(ASAuthorizationController *)controller
		didCompleteWithAuthorization:(ASAuthorization *)authorization {
	if (![authorization.credential isKindOfClass:[ASAuthorizationAppleIDCredential class]]) {
		// Only ever ASAuthorizationAppleIDRequest is asked for, so this is not
		// reachable -- but a cast on an unchecked class is how it stops being
		// unreachable after somebody adds a password request later.
		emit_deferred("sign_in_failed", String("Unexpected credential type"));
		return;
	}
	ASAuthorizationAppleIDCredential *cred = (ASAuthorizationAppleIDCredential *)authorization.credential;

	Dictionary out;

	// Stable, and scoped to this developer team. It is NOT an email and bears
	// no relation to the player's Google `sub`: the cross-provider link is a
	// row somebody deliberately wrote, never something inferred from these.
	out["user_id"] = to_godot(cred.user);
	out["id_token"] = data_to_godot(cred.identityToken);
	out["auth_code"] = data_to_godot(cred.authorizationCode);

	// THE FIRST-AUTHORIZATION TRAP.
	//
	// Apple returns fullName and email on the very first authorization for this
	// app and never again -- not on the next sign-in, not after a reinstall.
	// The only way back is the player revoking the app under Settings > Apple
	// ID > Sign in with Apple and starting over, which nobody will do because
	// nobody knows it exists.
	//
	// So whatever arrives here must be persisted by the caller on receipt.
	// Treating these as "available whenever we need them" is the single most
	// common Sign in with Apple bug, and it presents as every account after the
	// first being called "Islander" forever.
	//
	// Also: the email may be a @privaterelay.appleid.com address if the player
	// chose Hide My Email, and it may be absent entirely. It is here for
	// display and support, and must never be used to match accounts.
	out["email"] = to_godot(cred.email);
	out["given_name"] = to_godot(cred.fullName.givenName);
	out["family_name"] = to_godot(cred.fullName.familyName);
	out["is_first_authorization"] = cred.fullName.givenName != nil || cred.email != nil;

	emit_deferred("sign_in_succeeded", out);
}

- (void)authorizationController:(ASAuthorizationController *)controller
			didCompleteWithError:(NSError *)error {
	// A player who backs out of the sheet has not hit an error, and telling them
	// "sign-in failed" for changing their mind is how a title screen starts
	// feeling hostile. Cancellation gets its own signal so the caller can stay
	// silent.
	if (error.code == ASAuthorizationErrorCanceled) {
		emit_deferred("sign_in_cancelled");
		return;
	}
	NSString *reason = error.localizedDescription ?: @"Sign in with Apple failed";
	NSLog(@"SignInWithApple: %ld %@", (long)error.code, reason);
	emit_deferred("sign_in_failed", to_godot(reason));
}

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		UIWindowScene *window_scene = (UIWindowScene *)scene;
		for (UIWindow *window in window_scene.windows) {
			if (window.isKeyWindow) {
				return window;
			}
		}
		if (window_scene.windows.count > 0) {
			return window_scene.windows.firstObject;
		}
	}
	// Godot creates its window before any of this can be called, so the loop
	// above finds it. This is the belt-and-braces path for an iOS that reports
	// no connected scenes.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	return UIApplication.sharedApplication.windows.firstObject;
#pragma clang diagnostic pop
}

@end

// Both are held for the life of the process. Under ARC a file-static is a
// strong reference, which is the point: the controller is released the moment
// performRequests returns if nothing retains it, and its delegate is then never
// called -- the sheet appears and nothing ever comes back.
static GodotSIWADelegate *siwa_delegate = nil;
static ASAuthorizationController *siwa_controller = nil;

/**************************************************************************/
/*  Plugin                                                               */
/**************************************************************************/

SignInWithApple::SignInWithApple() {
	ERR_FAIL_COND(sign_in_with_apple_singleton != NULL);
	sign_in_with_apple_singleton = this;

	siwa_delegate = [[GodotSIWADelegate alloc] init];

	// Revocation arrives as a notification, and it can arrive at any time --
	// including for something the player did in Settings while the game was not
	// running, which surfaces on the next foreground. The game has to hear about
	// it, because a session held against a revoked credential is a player who
	// believes their island is backed up and whose next push will be rejected.
	[[NSNotificationCenter defaultCenter]
			addObserverForName:ASAuthorizationAppleIDProviderCredentialRevokedNotification
						object:nil
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification *note) {
						emit_deferred("credential_revoked");
					}];
}

SignInWithApple::~SignInWithApple() {
	if (sign_in_with_apple_singleton == this) {
		sign_in_with_apple_singleton = NULL;
	}
	siwa_controller = nil;
	siwa_delegate = nil;
}

void SignInWithApple::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &SignInWithApple::is_available);
	ClassDB::bind_method(D_METHOD("sign_in", "hashed_nonce"), &SignInWithApple::sign_in);
	ClassDB::bind_method(D_METHOD("credential_state", "user_id"), &SignInWithApple::credential_state);

	ADD_SIGNAL(MethodInfo("sign_in_succeeded", PropertyInfo(Variant::DICTIONARY, "credential")));
	ADD_SIGNAL(MethodInfo("sign_in_failed", PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("sign_in_cancelled"));
	ADD_SIGNAL(MethodInfo("credential_revoked"));
}

bool SignInWithApple::is_available() {
	if (@available(iOS 13.0, *)) {
		return ASAuthorizationAppleIDProvider.class != nil;
	}
	return false;
}

void SignInWithApple::sign_in(const String &p_hashed_nonce) {
	if (!is_available()) {
		emit_deferred("sign_in_failed", String("Sign in with Apple needs iOS 13 or later"));
		return;
	}
	// A sign-in with no nonce is a sign-in whose token can be replayed. Refusing
	// here rather than in GDScript means no future caller can forget.
	if (p_hashed_nonce.is_empty()) {
		emit_deferred("sign_in_failed", String("Missing nonce"));
		return;
	}

	NSString *nonce = [NSString stringWithUTF8String:p_hashed_nonce.utf8().get_data()];

	// UIKit, and the sheet, are main-thread only.
	dispatch_async(dispatch_get_main_queue(), ^{
		ASAuthorizationAppleIDProvider *provider = [[ASAuthorizationAppleIDProvider alloc] init];
		ASAuthorizationAppleIDRequest *request = [provider createRequest];
		request.requestedScopes = @[ ASAuthorizationScopeFullName, ASAuthorizationScopeEmail ];
		request.nonce = nonce;

		siwa_controller = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[ request ]];
		siwa_controller.delegate = siwa_delegate;
		siwa_controller.presentationContextProvider = siwa_delegate;
		[siwa_controller performRequests];
	});
}

// Synchronous by the same trade local_notifications.mm makes for
// permission_status: every caller wants the answer in the frame it asked, and
// the alternative is a second signal plus a state machine in GDScript for
// something iOS answers in microseconds. If iOS does not answer inside the
// ceiling we report "unknown", which the caller treats as "ask again later"
// rather than as a revocation.
String SignInWithApple::credential_state(const String &p_user_id) {
	if (!is_available() || p_user_id.is_empty()) {
		return String("unknown");
	}
	NSString *user_id = [NSString stringWithUTF8String:p_user_id.utf8().get_data()];

	__block String out = String("unknown");
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);

	ASAuthorizationAppleIDProvider *provider = [[ASAuthorizationAppleIDProvider alloc] init];
	[provider getCredentialStateForUserID:user_id
							   completion:^(ASAuthorizationAppleIDProviderCredentialState state, NSError *_Nullable error) {
								   switch (state) {
									   case ASAuthorizationAppleIDProviderCredentialAuthorized:
										   out = String("authorized");
										   break;
									   case ASAuthorizationAppleIDProviderCredentialRevoked:
										   out = String("revoked");
										   break;
									   case ASAuthorizationAppleIDProviderCredentialNotFound:
										   out = String("notFound");
										   break;
									   case ASAuthorizationAppleIDProviderCredentialTransferred:
										   out = String("transferred");
										   break;
									   default:
										   out = String("unknown");
										   break;
								   }
								   dispatch_semaphore_signal(sem);
							   }];

	dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
	return out;
}
