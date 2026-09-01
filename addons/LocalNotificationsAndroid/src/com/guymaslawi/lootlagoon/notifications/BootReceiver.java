package com.guymaslawi.lootlagoon.notifications;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * A reboot clears every alarm the system was holding, and an app update clears
 * them too. Without this the plan is silently gone and the player simply stops
 * hearing from the game -- which looks exactly like a feature that was never
 * built, and is the failure this whole class exists to prevent.
 */
public class BootReceiver extends BroadcastReceiver {

	@Override
	public void onReceive(Context context, Intent intent) {
		if (intent == null || intent.getAction() == null) {
			return;
		}
		String action = intent.getAction();
		if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
				&& !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
			return;
		}

		long now = System.currentTimeMillis();
		JSONArray plan = Plan.read(context);
		JSONArray kept = new JSONArray();
		for (int i = 0; i < plan.length(); i++) {
			JSONObject e = plan.optJSONObject(i);
			if (e == null) {
				continue;
			}
			long at = e.optLong("at", 0L);
			// Anything already due while the phone was off is dropped rather
			// than fired now. A notification is a promise about the state the
			// game will be in when it is opened -- see the note at the top of
			// alerts.gd -- and one that came due yesterday has no idea whether
			// it is still true.
			if (at <= now) {
				continue;
			}
			Plan.arm(context, e.optString("id"), at, e.optString("title"), e.optString("body"));
			kept.put(e);
		}
		Plan.write(context, kept);
	}
}
