/**************************************************************************/
/*  sign_in_with_apple_plugin.cpp                                         */
/**************************************************************************/

#import "sign_in_with_apple_plugin.h"
#import "sign_in_with_apple.h"

#import "core/config/engine.h"

SignInWithApple *sign_in_with_apple_plugin;

void godot_sign_in_with_apple_init() {
	sign_in_with_apple_plugin = memnew(SignInWithApple);
	Engine::get_singleton()->add_singleton(Engine::Singleton("SignInWithApple", sign_in_with_apple_plugin));
}

void godot_sign_in_with_apple_deinit() {
	if (sign_in_with_apple_plugin) {
		memdelete(sign_in_with_apple_plugin);
		sign_in_with_apple_plugin = nullptr;
	}
}
