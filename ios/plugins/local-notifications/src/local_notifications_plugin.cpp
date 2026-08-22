/**************************************************************************/
/*  local_notifications_plugin.cpp                                        */
/**************************************************************************/

#import "local_notifications_plugin.h"
#import "local_notifications.h"

#import "core/config/engine.h"

LocalNotificationsPlugin *local_notifications_plugin;

void godot_local_notifications_init() {
	local_notifications_plugin = memnew(LocalNotificationsPlugin);
	Engine::get_singleton()->add_singleton(Engine::Singleton("LocalNotifications", local_notifications_plugin));
}

void godot_local_notifications_deinit() {
	if (local_notifications_plugin) {
		memdelete(local_notifications_plugin);
		local_notifications_plugin = nullptr;
	}
}
