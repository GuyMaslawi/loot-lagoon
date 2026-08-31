#!/bin/zsh
# Build a signed Loot Lagoon build for Google Play.
#
#   ./ship_android.sh              export build/android-release/LootLagoon.aab
#   ./ship_android.sh --apk        ...an installable .apk instead, for a device
#   ./ship_android.sh --build 41   ...overriding the version code
#
# The Android twin of ship.sh, and deliberately the same shape: derive the
# number, check the things that fail silently, export, verify the signature,
# stop before anything leaves the machine.
#
# THE TWO NUMBERS, again. `version/name` ("1.0") is what a buyer sees on the
# Play listing and is edited by hand in export_presets.cfg. `version/code` is
# the integer Play orders builds by: it must strictly increase, nobody outside
# the console ever reads it, and typing it by hand is how you upload a bundle
# numbered "N". So it is the commit count on HEAD, exactly as CFBundleVersion
# is on iOS -- which also means an iOS build and an Android build cut from the
# same commit carry the same number, and a tester's "build 41" is unambiguous
# across both stores. Two builds of one commit collide; commit first, or pass
# --build.
#
# AAB, NOT APK. Play has required the App Bundle format for new apps since
# August 2021 and will reject a .apk outright. The .apk path here is for
# putting a build on a real phone or the emulator, and is never what ships.
#
# THE SIGNING SPLIT, which is the part worth understanding before the first
# upload. Play App Signing means Google holds the *app signing key* -- the one
# whose fingerprint devices actually check -- and this machine holds an *upload
# key*, which only proves to Google that a bundle came from us. They are not
# the same key and the upload key is not precious in the way the old v1 signing
# key was: if it is ever lost or stolen, Google can reset it and the app keeps
# updating. That is why this script generates nothing and asks for nothing --
# the key already exists, outside the repo, at $KEYSTORE below.
#
# WHY THE PASSWORD IS NOT IN A FILE. Godot will read the keystore path, alias
# and password out of export_presets.cfg, and that is the usual way it is done
# -- but export_presets.cfg is a file in the project directory that a future
# session, a screen share or a stray `git add -f` can expose. Godot also reads
# all three from the environment, so they are pulled out of the login Keychain
# here and never written down. Same reasoning as AC_PASSWORD on the iOS side.
set -e

cd "$(dirname "$0")"

KEYSTORE="$HOME/.keystores/lootlagoon-upload.keystore"
KEY_ALIAS="upload"
KEYCHAIN_ITEM="LOOTLAGOON_KEYSTORE_PASS"
JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
# Per-format, so building one does not delete the other: the out dir is wiped on
# every run, and a shared one meant the .apk you sideloaded silently took the
# .aab you were about to upload with it.
OUT_AAB="build/android-release"
OUT_APK="build/android-device"

FORMAT_APK=0
while [ $# -gt 0 ]; do
	case "$1" in
		--apk) FORMAT_APK=1; shift ;;
		# Checked here rather than left to the upload: Play only rejects a bad
		# version code at the very end, after a full bundle has been built and
		# sent. A plain positive integer, and Play's own ceiling is 2100000000.
		--build)
			[[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -gt 0 ] && [ "$2" -le 2100000000 ] || {
				echo "version code must be a positive integer up to 2100000000, got: $2" >&2
				exit 2
			}
			BUILD_NO="$2"; shift 2 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

# --- the things that fail silently ----------------------------------------
#
# export_presets.cfg is gitignored, so a fresh clone has no Android preset at
# all and every check below is what stands between that and a build that looks
# fine and is not.
grep -q '^\[preset.1\]' export_presets.cfg || {
	echo "export_presets.cfg has no Android preset -- see the Android notes before building" >&2
	exit 1
}
# Without gradle there is no way to link an Android plugin, so the bundle comes
# out complete, installable, and missing whatever the plugin was for. On this
# project that is Google Play Billing, i.e. the entire shop.
# Not fatal, because a build that refuses to exist is worse than one whose
# purchases are checked only by Google's own service. But it is money, so it is
# said every time rather than once in a README nobody opens.
if [ ! -f play_billing.json ] || ! grep -q '"license_key" *: *"[^"]' play_billing.json 2>/dev/null; then
	echo "!! no play_billing.json license_key -- Play purchase signatures will NOT be checked" >&2
	echo "   Play Console > Monetise > Monetisation setup > Licensing; see play_billing.example.json" >&2
fi

grep -q '^gradle_build/use_gradle_build=true' export_presets.cfg || {
	echo "export_presets.cfg is missing gradle_build/use_gradle_build=true" >&2
	echo "without it no Android plugin can be linked -- including billing" >&2
	exit 1
}
# The gradle build template is 200MB of unpacked Android sources, gitignored for
# the same reason build/ is. A clone without it fails deep inside the export
# with "no version info for it exists", which does not obviously mean this.
[ -f android/.build_version ] || {
	echo "no Android build template installed" >&2
	echo "in the Godot editor: Project > Install Android Build Template" >&2
	exit 1
}
grep -q '^package/signed=true' export_presets.cfg || {
	echo "export_presets.cfg is missing package/signed=true" >&2
	exit 1
}
[ -f "$KEYSTORE" ] || {
	echo "no upload keystore at $KEYSTORE" >&2
	echo "this is the key Play identifies our uploads by -- restore it from backup" >&2
	exit 1
}
KEYSTORE_PASS=$(security find-generic-password -a "$KEY_ALIAS" -s "$KEYCHAIN_ITEM" -w 2>/dev/null) || {
	echo "keystore password not in the Keychain under '$KEYCHAIN_ITEM'" >&2
	exit 1
}

BUILD_NO=${BUILD_NO:-$(git rev-list --count HEAD)}
PACKAGE=$(sed -n 's|^package/unique_name="\(.*\)"|\1|p' export_presets.cfg)
sed -i '' "s|^version/code=.*|version/code=$BUILD_NO|" export_presets.cfg
SHORT=$(sed -n 's|^version/name="\(.*\)"|\1|p' export_presets.cfg)
COMMIT=$(git rev-parse --short HEAD)

if [ "$FORMAT_APK" = "1" ]; then
	sed -i '' 's|^gradle_build/export_format=.*|gradle_build/export_format=0|' export_presets.cfg
	OUT="$OUT_APK"
	ARTIFACT="$OUT/LootLagoon.apk"
else
	sed -i '' 's|^gradle_build/export_format=.*|gradle_build/export_format=1|' export_presets.cfg
	OUT="$OUT_AAB"
	ARTIFACT="$OUT/LootLagoon.aab"
fi

echo "==> $PACKAGE  v$SHORT code $BUILD_NO  commit $COMMIT  -> ${ARTIFACT##*/}"

# Read back by BuildID and printed on the title screen, so a device can say
# which build it is running. Generated, git-ignored, and packed automatically --
# Godot exports loose json from the project root without any filter help. Same
# file the iOS build writes, and it must be rewritten here: leaving ship.sh's
# copy in place would put an iOS build number on an Android title screen.
cat > build_info.json <<JSON
{"version": "$SHORT", "build": "$BUILD_NO", "commit": "$COMMIT"}
JSON

# --- export ----------------------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT"            # Godot refuses to export into a missing directory

# Godot reads these three in preference to whatever is in export_presets.cfg,
# which is how the password stays out of the project directory.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KEY_ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KEYSTORE_PASS"

echo "==> exporting (gradle)"
# The export's own exit code decides, and then the log is scanned as well --
# the same two-step ship.sh uses, and for the same reason: a Godot export can
# print a fatal error and still leave a stale artifact lying around from the
# previous run, which the checks below would then happily verify.
export_log="$OUT/export.log"
if ! godot --headless --export-release "Android" "$PWD/$ARTIFACT" > "$export_log" 2>&1; then
	echo "!! godot export failed" >&2
	tail -40 "$export_log" >&2
	exit 1
fi
if grep -iE "^ERROR|error:" "$export_log"; then
	echo "!! godot export reported errors" >&2
	exit 1
fi
[ -f "$ARTIFACT" ] || { echo "!! no artifact at $ARTIFACT" >&2; exit 1; }

# --- signed, or did it fall through unsigned? ------------------------------
#
# The Android version of the trap ship.sh guards on iOS. Godot treats a
# keystore it cannot read as a warning, not an error: the export succeeds, the
# bundle is written, and it is unsigned -- which Play only tells you at the end
# of an upload. Ask the artifact itself rather than trusting the exit code.
echo "==> verifying signature"
if [ "$FORMAT_APK" = "1" ]; then
	APKSIGNER=$(ls -1 "$HOME/Library/Android/sdk/build-tools"/*/apksigner 2>/dev/null | sort -V | tail -1)
	[ -n "$APKSIGNER" ] || { echo "!! no apksigner in the Android SDK build-tools" >&2; exit 1; }
	"$APKSIGNER" verify --print-certs "$ARTIFACT" > "$OUT/signature.txt" 2>&1 || {
		echo "!! apk is NOT signed -- refusing to hand it over" >&2
		cat "$OUT/signature.txt" >&2
		exit 1
	}
	grep -m1 'Signer #1 certificate SHA-256' "$OUT/signature.txt" || true
else
	# An .aab is a jar, so jarsigner is the tool. `-verify` alone exits 0 on an
	# unsigned archive with "jar is unsigned" on stdout, which is exactly the
	# quiet pass this check exists to catch -- so the text is what decides.
	"$JBR/bin/jarsigner" -verify -verbose:summary "$ARTIFACT" > "$OUT/signature.txt" 2>&1 || true
	if ! grep -q 'jar verified' "$OUT/signature.txt"; then
		echo "!! bundle is NOT signed -- refusing to hand it over" >&2
		tail -20 "$OUT/signature.txt" >&2
		exit 1
	fi
	echo "    jar verified against $KEY_ALIAS"
fi

ls -lh "$ARTIFACT"

# --- upload: not done here, on purpose ------------------------------------
# Sending a bundle to Play Console publishes it to whichever track it lands in,
# so it stays a deliberate act rather than the tail of a build script. There is
# no altool equivalent worth scripting for a first release: upload the .aab by
# hand at play.google.com/console the first time, and only then consider
# automating it.
