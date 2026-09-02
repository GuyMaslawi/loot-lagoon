package com.guymaslawi.lootlagoon.notifications;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/**
 * One alarm came due. This is the only code in the feature that runs while the
 * game is not running, which is the entire point of it -- alerts.gd hands the
 * whole plan over on the way to the background precisely because nothing in the
 * game can execute after that.
 */
public class AlarmReceiver extends BroadcastReceiver {

	static final String EXTRA_ID    = "id";
	static final String EXTRA_TITLE = "title";
	static final String EXTRA_BODY  = "body";

	static final String CHANNEL_ID = "lootlagoon_alerts";

	@Override
	public void onReceive(Context context, Intent intent) {
		if (intent == null) {
			return;
		}
		String id    = intent.getStringExtra(EXTRA_ID);
		String title = intent.getStringExtra(EXTRA_TITLE);
		String body  = intent.getStringExtra(EXTRA_BODY);
		if (id == null) {
			return;
		}

		NotificationManager nm =
				(NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
		if (nm == null) {
			return;
		}
		ensureChannel(nm);

		// Tapping it opens the game rather than anything deeper. Every message
		// this game sends is about the island as a whole -- spins refilled, a
		// rival came by -- and the island is what the launcher intent opens.
		PendingIntent tap = null;
		Intent open = context.getPackageManager()
				.getLaunchIntentForPackage(context.getPackageName());
		if (open != null) {
			open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
			int flags = PendingIntent.FLAG_UPDATE_CURRENT;
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
				flags |= PendingIntent.FLAG_IMMUTABLE;
			}
			tap = PendingIntent.getActivity(context, Plan.codeFor(id), open, flags);
		}

		Notification.Builder b;
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			b = new Notification.Builder(context, CHANNEL_ID);
		} else {
			b = new Notification.Builder(context);
		}
		b.setContentTitle(title == null ? "" : title)
		 .setContentText(body == null ? "" : body)
		 // The app's own icon. Measured on an Android 16 emulator on
		 // 2026-09-02 rather than assumed: it renders in FULL COLOUR in the
		 // notification shade -- the raccoon, not the white blob this comment
		 // used to warn about. Android still silhouettes small icons in the
		 // status bar itself, which was not checked. The alternative is
		 // shipping a drawable inside the .aar, which means resource merging,
		 // which means aapt2 in the plugin build; the shade is where a player
		 // actually reads this, so it is not worth it.
		 .setSmallIcon(context.getApplicationInfo().icon)
		 .setAutoCancel(true);
		if (body != null && body.length() > 40) {
			// Otherwise Android truncates mid-sentence in the shade.
			b.setStyle(new Notification.BigTextStyle().bigText(body));
		}
		if (tap != null) {
			b.setContentIntent(tap);
		}

		// Posted under the plan's own id, so a message that replaces an earlier
		// one replaces it in the shade instead of stacking beneath it. This is
		// the same guarantee the iOS side gets from its identifier, and the
		// reason alerts.gd insists every planned entry carries a unique id.
		nm.notify(Plan.codeFor(id), b.build());

		Plan.forget(context, id);
	}

	static void ensureChannel(NotificationManager nm) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
			return;
		}
		if (nm.getNotificationChannel(CHANNEL_ID) != null) {
			return;
		}
		NotificationChannel ch = new NotificationChannel(
				CHANNEL_ID, "Island news", NotificationManager.IMPORTANCE_DEFAULT);
		ch.setDescription("Spins refilled, rivals, and shield warnings.");
		// IMPORTANCE_DEFAULT makes a sound; HIGH would also push a heads-up
		// banner over whatever the player is doing. Nothing this game has to
		// say earns an interruption of that size.
		nm.createNotificationChannel(ch);
	}
}
