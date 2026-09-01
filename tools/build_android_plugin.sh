#!/usr/bin/env bash
# Build the LocalNotifications Android plugin into a pair of .aar files.
#
# The twin of tools/build_ios_plugin.sh, and it exists for the same reason: a
# committed binary nobody can reproduce is a binary nobody can patch. One
# command, from source, offline.
#
# DELIBERATELY NOT GRADLE. An .aar is a zip holding a classes.jar and a
# manifest, and this plugin has no resources and no third-party dependencies --
# so the whole build is javac plus jar plus zip, with nothing to resolve and
# no Android Gradle Plugin version to keep in step with Godot's build template.
# Adding a resource (a status-bar drawable, say) would need aapt2 and would be
# the moment to reach for gradle; see the note on setSmallIcon in
# AlarmReceiver.java for why there is not one.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="LocalNotificationsAndroid"
SRC="$ROOT/addons/$PLUGIN/src"
OUT="$ROOT/addons/$PLUGIN/bin"

SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
[ -d "$SDK/platforms" ] || { echo "no Android SDK at $SDK (set ANDROID_HOME)" >&2; exit 1; }

# Highest installed platform, so this does not pin a version that gets removed.
PLATFORM="$(ls -1 "$SDK/platforms" | sort -V | tail -1)"
ANDROID_JAR="$SDK/platforms/$PLATFORM/android.jar"
[ -f "$ANDROID_JAR" ] || { echo "no android.jar in $SDK/platforms/$PLATFORM" >&2; exit 1; }

command -v javac >/dev/null || { echo "javac not on PATH" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- the Godot classes to compile against ------------------------------------
# Taken from the installed build template rather than from Maven, so the plugin
# is always built against the exact engine the game is exported with. If this
# path is missing the template is not installed -- Project > Install Android
# Build Template -- which is also the state in which ship_android.sh refuses.
build_one() {
	local variant="$1"        # debug | release
	local lib="$ROOT/android/build/libs/$variant/godot-lib.template_$variant.aar"
	if [ ! -f "$lib" ]; then
		echo "no $lib -- install the Android build template first" >&2
		exit 1
	fi

	local stage="$WORK/$variant"
	mkdir -p "$stage/godot" "$stage/classes"
	unzip -oq "$lib" classes.jar -d "$stage/godot"

	echo "==> compiling ($variant, against $PLATFORM)"
	# -nowarn: the bootclasspath warning fires on every android.jar build and
	# says nothing. Everything else is left on and treated as it comes.
	find "$SRC" -name '*.java' > "$stage/sources.txt"
	javac -nowarn \
		-source 17 -target 17 \
		-cp "$ANDROID_JAR:$stage/godot/classes.jar" \
		-d "$stage/classes" \
		@"$stage/sources.txt"

	echo "==> packaging ($variant)"
	( cd "$stage/classes" && jar cf "$stage/classes.jar" . )
	cp "$SRC/AndroidManifest.xml" "$stage/AndroidManifest.xml"
	# R.txt is required by the .aar format even with no resources in it.
	: > "$stage/R.txt"

	mkdir -p "$OUT/$variant"
	local aar="$OUT/$variant/$PLUGIN-$variant.aar"
	rm -f "$aar"
	( cd "$stage" && zip -qr "$aar" AndroidManifest.xml classes.jar R.txt )
	echo "    $aar"
}

build_one debug
build_one release

echo
echo "==> verifying"
# Each listing is captured before it is searched, deliberately. `unzip | grep -q`
# looks like the obvious spelling and is a trap under `set -o pipefail`: grep -q
# exits the moment it matches, unzip takes SIGPIPE, and the pipeline reports
# failure for a file that is perfectly correct. That cost a build here.
for variant in debug release; do
	aar="$OUT/$variant/$PLUGIN-$variant.aar"
	listing="$(unzip -l "$aar")"
	manifest="$(unzip -p "$aar" AndroidManifest.xml)"

	# The plugin is found by a manifest meta-data entry, not by its class name,
	# so an .aar that compiles and is missing this line produces a build with no
	# notifications in it and no error anywhere.
	case "$manifest" in
		*org.godotengine.plugin.v2.LocalNotifications*) ;;
		*) echo "    $variant: manifest does not register the plugin" >&2; exit 1 ;;
	esac
	case "$listing" in
		*classes.jar*) ;;
		*) echo "    $variant: no classes.jar" >&2; exit 1 ;;
	esac

	# And that the classes are actually in it -- an empty jar zips fine.
	classes="$(unzip -p "$aar" classes.jar | jar t 2>/dev/null | grep -c '\.class$' || true)"
	[ "${classes:-0}" -ge 4 ] \
		|| { echo "    $variant: only $classes classes in the jar" >&2; exit 1; }
	echo "    $variant ok ($classes classes)"
done
echo
echo "BUILT. Enable res://addons/$PLUGIN/plugin.cfg in project.godot or the"
echo "export will succeed and silently ship without notifications."
