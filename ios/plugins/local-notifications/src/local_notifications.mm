/**************************************************************************/
/*  local_notifications.mm                                                */
/**************************************************************************/

#import "local_notifications.h"

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <UIKit/UIKit.h>

// Everything we schedule carries this prefix, so cancel_all() can clear our
// own pending requests without reaching for anything another part of the app
// (or a future push payload) put there.
static NSString *const kIdPrefix = @"lootlagoon.";

LocalNotificationsPlugin *local_notifications_singleton = NULL;

LocalNotificationsPlugin *LocalNotificationsPlugin::get_singleton() {
	return local_notifications_singleton;
}

LocalNotificationsPlugin::LocalNotificationsPlugin() {
	ERR_FAIL_COND(local_notifications_singleton != NULL);
	local_notifications_singleton = this;
}

LocalNotificationsPlugin::~LocalNotificationsPlugin() {
	if (local_notifications_singleton == this) {
		local_notifications_singleton = NULL;
	}
}

void LocalNotificationsPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("permission_status"), &LocalNotificationsPlugin::permission_status);
	ClassDB::bind_method(D_METHOD("request_permission"), &LocalNotificationsPlugin::request_permission);
	ClassDB::bind_method(D_METHOD("schedule", "entries"), &LocalNotificationsPlugin::schedule);
	ClassDB::bind_method(D_METHOD("cancel_all"), &LocalNotificationsPlugin::cancel_all);
	ClassDB::bind_method(D_METHOD("set_badge", "count"), &LocalNotificationsPlugin::set_badge);
	ClassDB::bind_method(D_METHOD("clear_delivered"), &LocalNotificationsPlugin::clear_delivered);

	ADD_SIGNAL(MethodInfo("permission_result", PropertyInfo(Variant::BOOL, "granted")));
}

static String status_name(UNAuthorizationStatus status) {
	switch (status) {
		case UNAuthorizationStatusNotDetermined: return String("notDetermined");
		case UNAuthorizationStatusDenied: return String("denied");
		case UNAuthorizationStatusAuthorized: return String("authorized");
		case UNAuthorizationStatusProvisional: return String("provisional");
		default: break;
	}
	// .ephemeral (App Clips) and anything a later iOS adds. Not authorized in
	// any way we can rely on, and not a refusal we should stop asking about.
	return String("ephemeral");
}

// getNotificationSettingsWithCompletionHandler is asynchronous, and every
// caller of this wants an answer in the same frame -- the alternative is a
// second signal and a state machine in GDScript for a value iOS can produce in
// microseconds. A semaphore with a short ceiling is the honest trade: if iOS
// somehow does not answer, we report "notDetermined" and the caller asks
// again later rather than the game hanging.
String LocalNotificationsPlugin::permission_status() {
	__block String out = String("notDetermined");
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	[[UNUserNotificationCenter currentNotificationCenter]
			getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
				out = status_name(settings.authorizationStatus);
				dispatch_semaphore_signal(sem);
			}];
	dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
	return out;
}

void LocalNotificationsPlugin::request_permission() {
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
	[center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
		if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) {
			// iOS shows its prompt exactly once in the lifetime of an install.
			// Asking again is not an error and not a second prompt -- it is a
			// no-op that never calls back -- so report the standing answer
			// rather than leaving the game waiting on a signal that will not
			// come.
			bool granted = settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
					settings.authorizationStatus == UNAuthorizationStatusProvisional;
			if (local_notifications_singleton) {
				local_notifications_singleton->call_deferred("emit_signal", "permission_result", granted);
			}
			return;
		}
		UNAuthorizationOptions opts = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
		[center requestAuthorizationWithOptions:opts
				completionHandler:^(BOOL granted, NSError *_Nullable error) {
					if (error != nil) {
						NSLog(@"LocalNotifications: authorization failed: %@", error.localizedDescription);
					}
					// Off the arbitrary thread iOS answers on. Godot objects
					// are not thread-safe and a signal emitted from here lands
					// in GDScript mid-frame.
					if (local_notifications_singleton) {
						local_notifications_singleton->call_deferred("emit_signal", "permission_result", (bool)granted);
					}
				}];
	}];
}

void LocalNotificationsPlugin::schedule(Array p_entries) {
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

	// Ours only. Anything else pending was not put there by this call's
	// caller and is not this call's to throw away.
	[center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *requests) {
		NSMutableArray<NSString *> *mine = [NSMutableArray array];
		for (UNNotificationRequest *r in requests) {
			if ([r.identifier hasPrefix:kIdPrefix]) {
				[mine addObject:r.identifier];
			}
		}
		[center removePendingNotificationRequestsWithIdentifiers:mine];
	}];

	for (int i = 0; i < p_entries.size(); i++) {
		Dictionary entry = p_entries[i];
		double delay = (double)entry.get("in", 0.0);
		// UNTimeIntervalNotificationTrigger rejects anything <= 0 by raising,
		// which would take the whole app down. A due-in-the-past entry is a
		// caller bug, not a crash.
		if (delay < 1.0) {
			continue;
		}
		String id = entry.get("id", String());
		String title = entry.get("title", String());
		String body = entry.get("body", String());

		UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
		content.title = [NSString stringWithUTF8String:title.utf8().get_data()];
		content.body = [NSString stringWithUTF8String:body.utf8().get_data()];
		content.sound = [UNNotificationSound defaultSound];

		UNTimeIntervalNotificationTrigger *trigger =
				[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:delay repeats:NO];

		NSString *identifier = [kIdPrefix stringByAppendingString:[NSString stringWithUTF8String:id.utf8().get_data()]];
		UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
																			 content:content
																			 trigger:trigger];
		[center addNotificationRequest:request
				withCompletionHandler:^(NSError *_Nullable error) {
					if (error != nil) {
						NSLog(@"LocalNotifications: could not schedule %@: %@", identifier, error.localizedDescription);
					}
				}];
	}
}

void LocalNotificationsPlugin::cancel_all() {
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
	[center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *requests) {
		NSMutableArray<NSString *> *mine = [NSMutableArray array];
		for (UNNotificationRequest *r in requests) {
			if ([r.identifier hasPrefix:kIdPrefix]) {
				[mine addObject:r.identifier];
			}
		}
		[center removePendingNotificationRequestsWithIdentifiers:mine];
	}];
}

void LocalNotificationsPlugin::set_badge(int p_count) {
	int count = p_count < 0 ? 0 : p_count;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (@available(iOS 16.0, *)) {
			[[UNUserNotificationCenter currentNotificationCenter] setBadgeCount:count
															 withCompletionHandler:nil];
		} else {
			[UIApplication sharedApplication].applicationIconBadgeNumber = count;
		}
	});
}

void LocalNotificationsPlugin::clear_delivered() {
	[[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];
}
