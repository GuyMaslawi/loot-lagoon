#!/usr/bin/env bash
# Build this project's Android plugins, each into a pair of .aar files.
#
# TWO PLUGINS NOW, not one, and the second is the reason this grew a table.
#
#   LocalNotificationsAndroid  retention notifications; a GDScript singleton
#   AuthReturnAndroid          one intent-filter, so a browser sign-in can
#                              bring the game back to the front
#
# Run with no arguments to build both, or name one to build just that.
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

# name : the string its merged manifest MUST contain : fewest classes it may have
#
# The marker differs per plugin because what makes a plugin work differs.
# LocalNotifications is found by its org.godotengine.plugin.v2 meta-data entry
# -- omit it and the build ships with no notifications and no error anywhere.
# AuthReturn has no meta-data at all and never will: it exposes nothing to
# GDScript, and what has to survive the merge is the activity the browser
# resolves. Checking for the meta-data there would fail a correct .aar; checking
# for the activity here is the equivalent guarantee.
PLUGINS=(
	"LocalNotificationsAndroid:org.godotengine.plugin.v2.LocalNotifications:4"
	"AuthReturnAndroid:com.guymaslawi.lootlagoon.authreturn.AuthReturnActivity:1"
)

if [ $# -gt 0 ]; then
	WANTED=("$@")
	KEEP=()
	for spec in "${PLUGINS[@]}"; do
		for w in "${WANTED[@]}"; do
			[ "${spec%%:*}" = "$w" ] && KEEP+=("$spec")
		done
	done
	[ ${#KEEP[@]} -gt 0 ] || { echo "no such plugin: $*" >&2; exit 1; }
	PLUGINS=("${KEEP[@]}")
fi

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
	local plugin="$1"
	local variant="$2"        # debug | release
	local SRC="$ROOT/addons/$plugin/src"
	local OUT="$ROOT/addons/$plugin/bin"
	local lib="$ROOT/android/build/libs/$variant/godot-lib.template_$variant.aar"
	if [ ! -f "$lib" ]; then
		echo "no $lib -- install the Android build template first" >&2
		exit 1
	fi

	local stage="$WORK/$plugin-$variant"
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

	# XML-VALID BEFORE IT IS PACKAGED, because the merger's complaint arrives
	# two minutes later and does not look like this file's fault.
	#
	# The house comment style uses a double hyphen as a dash, and XML forbids
	# one inside a comment. An .aar built from such a manifest zips perfectly,
	# and then `processStandardReleaseMainManifest` fails the whole Android
	# export with a SAXParseException naming a line number in a file the export
	# log never mentions by name. One xmllint here turns that into an error
	# about the file you just edited.
	xmllint --noout "$SRC/AndroidManifest.xml" \
		|| { echo "    $plugin: AndroidManifest.xml is not valid XML" >&2; exit 1; }

	echo "==> packaging ($variant)"
	( cd "$stage/classes" && jar cf "$stage/classes.jar" . )
	cp "$SRC/AndroidManifest.xml" "$stage/AndroidManifest.xml"
	# R.txt is required by the .aar format even with no resources in it.
	: > "$stage/R.txt"

	mkdir -p "$OUT/$variant"
	local aar="$OUT/$variant/$plugin-$variant.aar"
	rm -f "$aar"
	( cd "$stage" && zip -qr "$aar" AndroidManifest.xml classes.jar R.txt )
	echo "    $aar"
}

for spec in "${PLUGINS[@]}"; do
	plugin="${spec%%:*}"
	echo
	echo "### $plugin"
	build_one "$plugin" debug
	build_one "$plugin" release
done

echo
echo "==> verifying"
# Each listing is captured before it is searched, deliberately. `unzip | grep -q`
# looks like the obvious spelling and is a trap under `set -o pipefail`: grep -q
# exits the moment it matches, unzip takes SIGPIPE, and the pipeline reports
# failure for a file that is perfectly correct. That cost a build here.
for spec in "${PLUGINS[@]}"; do
	plugin="${spec%%:*}"
	rest="${spec#*:}"
	marker="${rest%%:*}"
	min_classes="${rest##*:}"
	for variant in debug release; do
		aar="$ROOT/addons/$plugin/bin/$variant/$plugin-$variant.aar"
		listing="$(unzip -l "$aar")"
		manifest="$(unzip -p "$aar" AndroidManifest.xml)"

		# What makes the plugin work at all, and it is never the class name --
		# nothing reads that. For a singleton it is the meta-data entry Godot
		# scans for; for AuthReturn it is the activity a browser resolves. An
		# .aar that compiles cleanly and loses either one produces a build that
		# exports fine and is missing the feature, with no error anywhere.
		case "$manifest" in
			*"$marker"*) ;;
			*) echo "    $plugin $variant: manifest is missing $marker" >&2; exit 1 ;;
		esac
		case "$listing" in
			*classes.jar*) ;;
			*) echo "    $plugin $variant: no classes.jar" >&2; exit 1 ;;
		esac

		# And that the classes are actually in it -- an empty jar zips fine.
		classes="$(unzip -p "$aar" classes.jar | jar t 2>/dev/null | grep -c '\.class$' || true)"
		[ "${classes:-0}" -ge "$min_classes" ] \
			|| { echo "    $plugin $variant: only $classes classes in the jar" >&2; exit 1; }
		echo "    $plugin $variant ok ($classes classes)"
	done
done
echo
for spec in "${PLUGINS[@]}"; do
	plugin="${spec%%:*}"
	echo "BUILT. Enable res://addons/$plugin/plugin.cfg in project.godot or the"
	echo "export will succeed and silently ship without it."
done
