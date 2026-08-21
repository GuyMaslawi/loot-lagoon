#!/bin/zsh
# Build a signed Loot Lagoon build for TestFlight / the App Store.
#
#   ./ship.sh              export, archive and write build/ios-release/LootLagoon.ipa
#   ./ship.sh --build 7    ...using 7 as the build number
#
# It deliberately stops at the .ipa. Uploading is a separate, outward-facing
# step -- see the note at the bottom.
#
# WHY THE SED: Godot writes CODE_SIGN_STYLE = Automatic *and* an explicit
# CODE_SIGN_IDENTITY = "Apple Distribution" into the Release configuration,
# and Xcode refuses the combination ("has conflicting provisioning settings").
# Deleting the identity outright is worse: the archive then builds completely
# unsigned and is only rejected at upload. So it becomes "Apple Development",
# which is what automatic signing actually issues -- the archive is signed for
# development and -exportArchive re-signs it for distribution below. That is
# Apple's normal split, not a workaround.
# It has to happen here rather than by hand, because every --export-release
# regenerates the whole Xcode project and wipes any edit made in Xcode.
set -e

cd "$(dirname "$0")"

OUT="build/ios-release"
PROJ="$OUT/LootLagoon.xcodeproj"
ARCHIVE="$OUT/LootLagoon.xcarchive"
TEAM=$(sed -n 's/^application\/app_store_team_id="\(.*\)"/\1/p' export_presets.cfg)
BUNDLE=$(sed -n 's/^application\/bundle_identifier="\(.*\)"/\1/p' export_presets.cfg)

while [ $# -gt 0 ]; do
	case "$1" in
		# Checked here rather than left to the upload: Apple only rejects a bad
		# CFBundleVersion at the very end, after a full export and archive have
		# already been paid for. One to three period-separated integers.
		--build)
			[[ "$2" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
				echo "build number must be one to three period-separated integers, got: $2" >&2
				exit 2
			}
			sed -i '' "s|^application/version=.*|application/version=\"$2\"|" export_presets.cfg; shift 2 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done
BUILD_NO=$(sed -n 's/^application\/version="\(.*\)"/\1/p' export_presets.cfg)
echo "==> $BUNDLE  build $BUILD_NO  team $TEAM"

# The flag that links the StoreKit plugin lives in export_presets.cfg, which is
# not in git. Lose it -- a fresh clone, a preset rebuilt in the editor -- and
# everything still exports, archives and uploads perfectly, except that IAP
# quietly falls back to its simulated store and every purchase is free. That is
# far too quiet a way to ship a game that takes money.
grep -q '^plugins/IOSInAppPurchase=true' export_presets.cfg || {
	echo "export_presets.cfg is missing plugins/IOSInAppPurchase=true" >&2
	echo "without it the build ships a simulated store -- add it before shipping" >&2
	exit 2
}

# --- 1. regenerate the Xcode project from the current source ---
echo "==> exporting release project"
rm -rf "$OUT"
mkdir -p "$OUT"            # Godot refuses to export into a missing directory
godot --headless --export-release "iOS" "$PWD/$OUT/LootLagoon.ipa" 2>&1 \
	| grep -iE "^ERROR|error:" && exit 1 || true

sed -i '' 's/CODE_SIGN_IDENTITY = "Apple Distribution";/CODE_SIGN_IDENTITY = "Apple Development";/' "$PROJ/project.pbxproj"

# --- 2. archive ---
echo "==> archiving (creates the certificate and profile on first run)"
xcodebuild -project "$PROJ" -scheme LootLagoon -sdk iphoneos \
	-configuration Release -destination 'generic/platform=iOS' \
	-archivePath "$ARCHIVE" -allowProvisioningUpdates \
	ENABLE_USER_SCRIPT_SANDBOXING=NO archive > /tmp/lootlagoon_archive.log 2>&1 || {
		echo "archive failed -- see /tmp/lootlagoon_archive.log" >&2
		grep -E "error:" /tmp/lootlagoon_archive.log | head -5 >&2
		exit 1
	}

# Signed, or did it quietly fall through unsigned? An unsigned archive builds
# perfectly happily and is only rejected at upload. codesign reports the lack
# in plain words, which is a steadier signal than looking for a field whose
# presence depends on the verbosity level.
SIG=$(codesign -dv "$ARCHIVE/Products/Applications/LootLagoon.app" 2>&1)
case "$SIG" in
	*"not signed at all"*) echo "archive is NOT signed -- refusing to package it" >&2; exit 1 ;;
esac
echo "==> archive signed for team $(printf '%s' "$SIG" | sed -n 's/^TeamIdentifier=//p')"

# --- 3. package the ipa ---
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>$TEAM</string>
	<key>uploadSymbols</key><true/>
	<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

echo "==> exporting ipa"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
	-exportOptionsPlist "$OUT/ExportOptions.plist" \
	-exportPath "$OUT" -allowProvisioningUpdates > /tmp/lootlagoon_export.log 2>&1 || {
		echo "export failed -- see /tmp/lootlagoon_export.log" >&2
		grep -E "error:" /tmp/lootlagoon_export.log | head -5 >&2
		exit 1
	}

ls -lh "$OUT"/*.ipa

# --- 4. upload: not done here, on purpose ---
# Sending the build to App Store Connect publishes it to your testers, so it
# stays a deliberate command rather than the tail of a build script:
#
#   xcrun altool --upload-app -f build/ios-release/LootLagoon.ipa -t ios \
#     -u <apple-id> -p <app-specific-password>
#
# The password is not your Apple ID password -- generate one at
# account.apple.com under Sign-In and Security > App-Specific Passwords.
