package com.guymaslawi.lootlagoon.notifications;

import android.app.Activity;
import android.app.NotificationManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Collections;
import java.util.Set;

/**
 * Local notifications on Android.
 *
 * The whole retention half of this game was already written -- alerts.gd works
 * out every future moment worth pinging about and hands the list over on the
 * way to the background -- and on Android it went nowhere at all, because the
 * singleton it looks for was an iOS plugin. `_plugin` was null, every call was
 * a silent no-op, and the platform about to get twenty-five testers had no
 * retention pings whatsoever.
 *
 * SO THIS IS DELIBERATELY NOT A NEW API. The name below is "LocalNotifications"
 * -- the same string the iOS plugin registers -- and every method matches the
 * iOS one, so alerts.gd finds it with the code it already had. The single
 * exception is schedule(), and the reason is in its comment.
 */
public class LootLagoonNotifications extends GodotPlugin {

	private static final String PLUGIN_NAME = "LocalNotifications";

	private static final String SIGNAL_PERMISSION = "permission_result";

	private static final String PERM_POST = "android.permission.POST_NOTIFICATIONS";

	private static final int REQ_POST = 0x10CA;

	/**
	 * Android cannot tell "never asked" from "asked and refused" -- both are
	 * simply "not granted". iOS can, and alerts.gd leans on the difference:
	 * can_ask() decides whether putting the system prompt in front of a player
	 * is still worth anything. So the fact of having asked is remembered here.
	 */
	private static final String KEY_ASKED = "asked_post_notifications";

	public LootLagoonNotifications(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return PLUGIN_NAME;
	}

	@Override
	public Set<SignalInfo> getPluginSignals() {
		return Collections.singleton(new SignalInfo(SIGNAL_PERMISSION, Boolean.class));
	}

	// -----------------------------------------------------------------------
	//  Permission
	// -----------------------------------------------------------------------

	/**
	 * The same five strings the iOS plugin returns, so alerts.gd's granted()
	 * and can_ask() need no branch. "provisional" and "ephemeral" are iOS
	 * concepts and are never produced here.
	 */
	@UsedByGodot
	public String permission_status() {
		Context c = getContext();
		if (c == null) {
			return "unavailable";
		}

		// Below 13 there is no runtime permission, but the player can still
		// turn the app off in Settings -- and an app that believes it is
		// authorised will happily schedule into a void.
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
			NotificationManager nm =
					(NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
			if (nm != null && !nm.areNotificationsEnabled()) {
				return "denied";
			}
			return "authorized";
		}

		if (c.checkSelfPermission(PERM_POST) == PackageManager.PERMISSION_GRANTED) {
			return "authorized";
		}
		return prefs().getBoolean(KEY_ASKED, false) ? "denied" : "notDetermined";
	}

	@UsedByGodot
	public void request_permission() {
		final Activity a = getActivity();
		final Context c = getContext();
		if (a == null || c == null) {
			emitSignal(SIGNAL_PERMISSION, false);
			return;
		}
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
			// Nothing to ask for. Answer with the truth rather than with `true`:
			// notifications may still be off in Settings, and a caller that is
			// told "granted" will schedule a plan nobody will ever see.
			emitSignal(SIGNAL_PERMISSION, "authorized".equals(permission_status()));
			return;
		}
		if (c.checkSelfPermission(PERM_POST) == PackageManager.PERMISSION_GRANTED) {
			emitSignal(SIGNAL_PERMISSION, true);
			return;
		}
		prefs().edit().putBoolean(KEY_ASKED, true).apply();
		runOnUiThread(new Runnable() {
			@Override
			public void run() {
				a.requestPermissions(new String[] { PERM_POST }, REQ_POST);
			}
		});
	}

	@Override
	public void onMainRequestPermissionsResult(int requestCode, String[] permissions,
			int[] grantResults) {
		if (requestCode != REQ_POST) {
			return;
		}
		boolean ok = grantResults != null
				&& grantResults.length > 0
				&& grantResults[0] == PackageManager.PERMISSION_GRANTED;
		emitSignal(SIGNAL_PERMISSION, ok);
	}

	// -----------------------------------------------------------------------
	//  The plan
	// -----------------------------------------------------------------------

	/**
	 * Replaces whatever was pending with this plan.
	 *
	 * TAKES JSON, WHICH IS THE ONE PLACE THIS DIVERGES FROM THE iOS PLUGIN, and
	 * it is a deliberate trade. Godot marshals an Array of Dictionaries across
	 * JNI as Object[] of org.godotengine.godot.Dictionary, with every number
	 * arriving as some boxed type the caller did not choose -- and this plugin
	 * cannot be exercised anywhere except a real Android device, so the failure
	 * mode for getting that wrong is a silent no-op discovered by a tester who
	 * never got a notification. A String crosses JNI exactly one way. alerts.gd
	 * branches once, on OS.get_name(), and says so.
	 *
	 * Each entry is {id, in, title, body} where `in` is seconds from now --
	 * a delay and not a date, because main.gd's clock is a high-water mark that
	 * can sit hours ahead of the device's after somebody winds their phone
	 * forward. Only the gap between two readings is trustworthy.
	 */
	@UsedByGodot
	public void schedule(String json) {
		Context c = getContext();
		if (c == null) {
			return;
		}
		// Whatever was pending was planned against a state the player has since
		// changed. Clearing first also makes this call idempotent, which
		// matters because iOS sends two lifecycle events for one screen lock
		// and main.gd's _go_away therefore runs twice.
		Plan.disarmAll(c);

		JSONArray incoming;
		try {
			incoming = new JSONArray(json == null ? "[]" : json);
		} catch (Exception e) {
			return;
		}

		long now = System.currentTimeMillis();
		JSONArray stored = new JSONArray();
		for (int i = 0; i < incoming.length(); i++) {
			JSONObject e = incoming.optJSONObject(i);
			if (e == null) {
				continue;
			}
			String id = e.optString("id", "");
			if (id.isEmpty()) {
				continue;
			}
			long at = now + (long) (e.optDouble("in", 0.0) * 1000.0);
			String title = e.optString("title", "");
			String body  = e.optString("body", "");

			Plan.arm(c, id, at, title, body);

			JSONObject row = new JSONObject();
			try {
				row.put("id", id);
				row.put("at", at);      // absolute, so a reboot can rebuild it
				row.put("title", title);
				row.put("body", body);
			} catch (Exception ignored) {
				continue;
			}
			stored.put(row);
		}
		Plan.write(c, stored);
	}

	@UsedByGodot
	public void cancel_all() {
		Context c = getContext();
		if (c != null) {
			Plan.disarmAll(c);
		}
	}

	/**
	 * A no-op, honestly rather than fakely.
	 *
	 * Android has no badge API. The dot a launcher draws comes from the app's
	 * ACTIVE notifications and is not a number the app may set; the libraries
	 * that appeared to do this worked by talking to individual OEM launchers,
	 * are unmaintained, and do nothing on a stock Pixel. alerts.gd calls this
	 * on every resume and background, so it has to exist -- but it must not
	 * pretend, because the next reader would otherwise go looking for the bug
	 * in why the number is wrong.
	 */
	@UsedByGodot
	public void set_badge(int count) {
	}

	@UsedByGodot
	public void clear_delivered() {
		Context c = getContext();
		if (c == null) {
			return;
		}
		NotificationManager nm =
				(NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
		if (nm != null) {
			nm.cancelAll();
		}
	}

	private SharedPreferences prefs() {
		return Plan.prefs(getContext());
	}
}
