package com.guymaslawi.lootlagoon.notifications;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * The pending plan, on disk.
 *
 * AlarmManager forgets everything on reboot, and a phone reboots more often
 * than most people open a slot game -- so an alarm that only ever lived inside
 * AlarmManager is an alarm that quietly stops existing. Every scheduled entry
 * is therefore written here too, and {@link BootReceiver} lays them out again.
 *
 * It is also what makes cancel_all() possible at all. A PendingIntent can only
 * be cancelled by rebuilding an equal one, which means remembering the request
 * code of every alarm that is out there; nothing on the Android side enumerates
 * them for you.
 */
final class Plan {

	private static final String PREFS = "lootlagoon_notifications";
	private static final String KEY   = "plan";

	private Plan() {}

	static SharedPreferences prefs(Context c) {
		return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
	}

	static JSONArray read(Context c) {
		String raw = prefs(c).getString(KEY, "[]");
		try {
			return new JSONArray(raw);
		} catch (Exception e) {
			return new JSONArray();
		}
	}

	static void write(Context c, JSONArray plan) {
		prefs(c).edit().putString(KEY, plan.toString()).apply();
	}

	/**
	 * The request code an alarm is filed under. Derived from the id string
	 * rather than counted, because it has to be reproducible from a cold start:
	 * BootReceiver rebuilds these with no memory of the process that made them.
	 */
	static int codeFor(String id) {
		// Kept non-negative and away from 0 so it cannot collide with a default.
		return (id.hashCode() & 0x7fffffff) | 1;
	}

	static PendingIntent intentFor(Context c, String id, String title, String body) {
		Intent i = new Intent(c, AlarmReceiver.class);
		// The id rides in the data URI, not only in the extras: two Intents are
		// "equal" for PendingIntent purposes when action, data, type, class and
		// categories match -- extras are NOT compared. Without this every entry
		// would collapse onto the same PendingIntent and only the last one
		// would survive.
		i.setData(android.net.Uri.parse("lootlagoon://alert/" + android.net.Uri.encode(id)));
		i.putExtra(AlarmReceiver.EXTRA_ID, id);
		i.putExtra(AlarmReceiver.EXTRA_TITLE, title);
		i.putExtra(AlarmReceiver.EXTRA_BODY, body);

		int flags = PendingIntent.FLAG_UPDATE_CURRENT;
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			flags |= PendingIntent.FLAG_IMMUTABLE;
		}
		return PendingIntent.getBroadcast(c, codeFor(id), i, flags);
	}

	/**
	 * Hands one entry to AlarmManager.
	 *
	 * Inexact and allowed to fire in Doze. Exact alarms need a restricted
	 * permission that Play makes you argue for, and nothing this game says is
	 * worth arguing for -- a retention ping that lands a few minutes late has
	 * lost nothing at all.
	 */
	static void arm(Context c, String id, long atMillis, String title, String body) {
		AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
		if (am == null) {
			return;
		}
		PendingIntent pi = intentFor(c, id, title, body);
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi);
		} else {
			am.set(AlarmManager.RTC_WAKEUP, atMillis, pi);
		}
	}

	static void disarmAll(Context c) {
		AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
		JSONArray plan = read(c);
		for (int i = 0; i < plan.length(); i++) {
			JSONObject e = plan.optJSONObject(i);
			if (e == null) {
				continue;
			}
			PendingIntent pi = intentFor(c, e.optString("id"), e.optString("title"), e.optString("body"));
			if (am != null) {
				am.cancel(pi);
			}
			pi.cancel();
		}
		write(c, new JSONArray());
	}

	/** Drops one entry from the stored plan, after it has fired. */
	static void forget(Context c, String id) {
		JSONArray plan = read(c);
		JSONArray kept = new JSONArray();
		for (int i = 0; i < plan.length(); i++) {
			JSONObject e = plan.optJSONObject(i);
			if (e != null && !id.equals(e.optString("id"))) {
				kept.put(e);
			}
		}
		write(c, kept);
	}
}
