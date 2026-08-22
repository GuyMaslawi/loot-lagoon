/**************************************************************************/
/*  local_notifications.h                                                 */
/*  Loot Lagoon -- iOS local notifications for Godot 4.                   */
/**************************************************************************/

#ifndef local_notifications_implementation_h
#define local_notifications_implementation_h

#include "core/object/class_db.h"
#include "core/version.h"

class LocalNotificationsPlugin : public Object {
	GDCLASS(LocalNotificationsPlugin, Object);

	static void _bind_methods();

public:
	static LocalNotificationsPlugin *get_singleton();

	// "notDetermined", "denied", "authorized", "provisional", "ephemeral".
	// Asked rather than cached: the player can revoke us in Settings between
	// one launch and the next, and a cached "authorized" would then have the
	// game scheduling into a void and telling the player it had not.
	String permission_status();

	// Puts iOS's one-time prompt on screen. Answers on permission_result.
	// Calling this when the status is anything but "notDetermined" does not
	// show a prompt -- iOS only ever asks once -- so it simply reports the
	// standing answer instead of leaving the caller waiting.
	void request_permission();

	// Replaces the whole pending set: every entry we previously scheduled is
	// cancelled first. The game recomputes the full plan every time it goes to
	// the background, so anything still pending from the last time is by
	// definition stale -- an incremental API here would need the game to track
	// which of its own notifications iOS was still holding, which is a second
	// copy of the truth and a second thing to get wrong.
	//
	// Each entry: {"id": String, "in": float, "title": String, "body": String}
	// where "in" is SECONDS FROM NOW, not an absolute date. See the note in
	// alerts.gd: the game's clock is a high-water mark that can sit ahead of
	// the device's, so only the delta between the two is trustworthy.
	void schedule(Array p_entries);

	void cancel_all();

	// The red dot on the app icon. Set to 0 to clear it.
	void set_badge(int p_count);

	// Drops what is already sitting in Notification Centre. Called when the
	// player comes back, so a stack of "your spins are full" from three days
	// of absences does not still be there after they have spent them.
	void clear_delivered();

	LocalNotificationsPlugin();
	~LocalNotificationsPlugin();
};

#endif /* local_notifications_implementation_h */
