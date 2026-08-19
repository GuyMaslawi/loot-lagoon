#!/bin/zsh
# Run Loot Lagoon in the iOS Simulator.
#
#   ./sim.sh                  export the pck, install, launch
#   ./sim.sh --shot out.png   ...and write a screenshot when it's up
#   ./sim.sh --build          force a full Xcode relink first (rarely needed)
#
# GDScript and assets all live in LootLagoon.pck, so a normal iteration only
# re-exports that (~2s) and drops it into the already-linked .app. The 97MB
# binary only needs rebuilding when the Godot version or export options change.
#
# ARCH CONSTRAINT: the installed Godot 4.7.1 iOS export template ships a
# simulator libgodot.a containing ONLY x86_64 -- its xcframework claims
# arm64+x86_64 but the arm64 objects aren't there, so an arm64 link fails with
# undefined symbols. x86_64 apps are refused by iOS 26 runtimes ("Failed to
# find matching arch"), and only iOS 18.x runtimes still translate them. Hence
# the iOS 18.x pin below. To lift it, build an iOS template from Godot source
# with `scons platform=ios target=template_debug arch=arm64 ios_simulator=yes`.
set -e

cd "$(dirname "$0")"

PROJ="build/ios/LootLagoon.xcodeproj"
DERIVED="build/ios/DerivedData"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/LootLagoon.app"
BUNDLE_ID="com.lootlagoon.dev"
RUNTIME_PREFIX="com.apple.CoreSimulator.SimRuntime.iOS-18"

SHOT=""
FORCE_BUILD=0
while [ $# -gt 0 ]; do
	case "$1" in
		--shot) SHOT="$2"; shift 2 ;;
		--build) FORCE_BUILD=1; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

# --- 1. relink only when we have to ---
if [ ! -x "$APP/LootLagoon" ] || [ "$FORCE_BUILD" -eq 1 ]; then
	echo "==> linking app (x86_64 simulator, a few minutes)"
	xcodebuild -project "$PROJ" -scheme LootLagoon -sdk iphonesimulator \
		-configuration Debug -arch x86_64 -derivedDataPath "$DERIVED" \
		CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
		ENABLE_USER_SCRIPT_SANDBOXING=NO build > /tmp/lootlagoon_xcb.log 2>&1 || {
			echo "xcodebuild failed -- see /tmp/lootlagoon_xcb.log" >&2
			grep -E "error:" /tmp/lootlagoon_xcb.log | head -10 >&2
			exit 1
		}
fi

# --- 2. pack the current source straight into the bundle ---
echo "==> exporting pck"
godot --headless --export-pack "iOS" "$PWD/$APP/LootLagoon.pck" 2>&1 | grep -iE "^ERROR|error:" && exit 1 || true

# --- 3. pick a simulator on a runtime that can actually run the binary ---
DEV=$(xcrun simctl list devices -j | python3 -c "
import json, sys
data = json.load(sys.stdin)['devices']
booted = shutdown = None
for rt, devs in data.items():
    if not rt.startswith('$RUNTIME_PREFIX'):
        continue
    for d in devs:
        if not d.get('isAvailable') or 'iPhone' not in d['name']:
            continue
        if d['state'] == 'Booted' and not booted:
            booted = d['udid']
        elif not shutdown:
            shutdown = d['udid']
print(booted or shutdown or '')
")
if [ -z "$DEV" ]; then
	echo "no iOS 18.x iPhone simulator available -- install one via Xcode > Settings > Components" >&2
	exit 1
fi

xcrun simctl bootstatus "$DEV" -b > /dev/null 2>&1 || xcrun simctl boot "$DEV" > /dev/null 2>&1 || true
open -a Simulator

# --- 4. reinstall and relaunch ---
echo "==> installing on $DEV"
xcrun simctl terminate "$DEV" "$BUNDLE_ID" > /dev/null 2>&1 || true
xcrun simctl install "$DEV" "$APP"
xcrun simctl launch "$DEV" "$BUNDLE_ID"

if [ -n "$SHOT" ]; then
	sleep 12
	xcrun simctl io "$DEV" screenshot "$SHOT" 2>&1 | tail -1
fi
