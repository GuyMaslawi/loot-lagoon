package com.guymaslawi.lootlagoon.authreturn;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * Brings Loot Lagoon back to the front after a Google sign-in in the browser,
 * and does nothing else.
 *
 * WHY THIS EXISTS. Sign-in leaves the game: OS.shell_open hands the foreground
 * to Chrome, Android sends the activity onPause then onStop, and Godot's main
 * loop is suspended. The loopback listener in google_auth.gd is answered from
 * a plain Thread precisely so that it still works in that state -- the account
 * really is signed in by the time the browser renders the page. What was
 * missing was any way back: the tab said "close this tab and go back to Loot
 * Lagoon" and then it was on the player to work out how. PrimeTestLab's report
 * 6935 recorded the result as "the sign-in did not complete during our
 * session", which is what that reads like from the outside.
 *
 * So the page now points at lootlagoon://auth, this activity answers it, and
 * the game comes forward on its own.
 *
 * WHY IT CANNOT JUST finish() INTO THE GAME. The obvious shape -- put this
 * activity in the app's own task, let finish() drop through to the game
 * underneath -- cannot work here: Godot's template declares GodotApp with
 * android:launchMode="singleInstancePerTask", which means GodotApp is the only
 * activity its task will ever hold. Anything else lands in a task of its own.
 *
 * So instead of falling through to the game, this re-launches it the same way
 * the launcher icon does, which is the one gesture Android is certain to treat
 * as "bring that task forward" rather than "start a new copy":
 * getLaunchIntentForPackage resolves to the exported GodotAppLauncher alias
 * (ACTION_MAIN / CATEGORY_LAUNCHER), and against a singleInstancePerTask
 * activity that is already alive, the existing instance is resumed and given
 * onNewIntent. Nothing is reloaded and no progress is lost.
 *
 * It carries no data. The authorization code never travels through here -- it
 * was delivered over the loopback socket and is already in the game's memory
 * before the browser is redirected. This activity is a doorbell, and keeping it
 * empty is deliberate: an exported activity that accepted a code could be
 * handed one by any app on the phone.
 */
public class AuthReturnActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch != null) {
            // NEW_TASK because we are starting from our own throwaway task and
            // the game's task is a different one. No CLEAR_TOP and no
            // CLEAR_TASK: both would tear down the running game, which is the
            // exact thing this is here to avoid.
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launch);
        }

        // Gone before it is ever drawn. The theme is translucent and the
        // manifest marks it noHistory, so a player who hits back from the game
        // never lands here and it never appears in Recents.
        finish();
    }
}
