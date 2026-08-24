#!/usr/bin/env bash
# Build a Godot iOS plugin in ios/plugins/<name> into <name>.xcframework.
#
#   tools/build_ios_plugin.sh sign-in-with-apple
#
# Why this script exists:
#
# The two xcframeworks already in ios/plugins were compiled on 2026-08-22 by a
# toolchain that left nothing behind -- no build script, no engine checkout, no
# recorded flags. Their .mm sources are committed, but nothing in the repo could
# turn those sources back into the binaries beside them. A binary you cannot
# rebuild is a binary you cannot patch, and the first time that matters is the
# first security fix you need in one.
#
# A plugin compiles against the engine's own headers (see the includes in
# sign_in_with_apple.h), four of which SCons generates rather than commits. This
# fetches a sparse checkout of the matching Godot tag, drives those four
# generators directly via tools/godot_gen_headers.py, and compiles -- seconds,
# rather than the best part of an hour a full engine build would cost.
set -euo pipefail

PLUGIN="${1:-}"
if [ -z "$PLUGIN" ]; then
	echo "usage: $0 <plugin-dir-name>   e.g. sign-in-with-apple" >&2
	exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/ios/plugins/$PLUGIN"
SRC="$DIR/src"
[ -d "$SRC" ] || { echo "no such plugin: $DIR" >&2; exit 1; }

# Pinned to the engine the game is exported with. A plugin built against
# different engine headers than the template it links into is undefined
# behaviour that presents as a launch crash, so this is read from the project
# rather than assumed.
GODOT_TAG="${GODOT_TAG:-$(sed -n 's/.*config\/features=PackedStringArray("\([0-9.]*\)".*/\1/p' "$ROOT/project.godot")}"
case "$GODOT_TAG" in
	*.*.*) ;;                      # already major.minor.patch
	*) GODOT_TAG="${GODOT_TAG}.1" ;;   # project.godot records only major.minor
esac
GODOT_SRC="${GODOT_SRC:-$HOME/.cache/lootlagoon/godot-${GODOT_TAG}}"

MIN_IOS="${MIN_IOS:-$(sed -n 's/.*application\/min_ios_version="\([0-9.]*\)".*/\1/p' "$ROOT/export_presets.cfg")}"
MIN_IOS="${MIN_IOS:-15.0}"

echo "==> plugin      $PLUGIN"
echo "==> godot       $GODOT_TAG  ($GODOT_SRC)"
echo "==> min ios     $MIN_IOS"

# --- 1. engine headers ------------------------------------------------------
if [ ! -f "$GODOT_SRC/core/object/class_db.h" ]; then
	echo "==> fetching godot $GODOT_TAG headers (sparse, ~75MB)"
	mkdir -p "$(dirname "$GODOT_SRC")"
	git clone --depth 1 --branch "${GODOT_TAG}-stable" --filter=blob:none --no-checkout \
		https://github.com/godotengine/godot.git "$GODOT_SRC"
	git -C "$GODOT_SRC" sparse-checkout init --cone
	git -C "$GODOT_SRC" sparse-checkout set core platform/ios modules servers scene drivers misc thirdparty
	git -C "$GODOT_SRC" checkout
fi
if [ ! -f "$GODOT_SRC/core/extension/gdextension_interface.gen.h" ]; then
	echo "==> generating engine headers"
	python3 "$ROOT/tools/godot_gen_headers.py" --src "$GODOT_SRC"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SOURCES=$(find "$SRC" -name '*.mm' -o -name '*.cpp' | sort)
[ -n "$SOURCES" ] || { echo "no sources in $SRC" >&2; exit 1; }

# One slice = one (sdk, arch, target-triple) combination.
compile_slice() {
	local cfg="$1" sdk="$2" arch="$3" triple="$4" out="$5"
	local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
	local defines=(-DIOS_ENABLED -DUNIX_ENABLED)
	local optim=(-O2 -DNDEBUG)
	# Godot's own debug template is built with DEBUG_ENABLED; a plugin linking
	# into it must agree, because the macro changes struct layouts in the engine
	# headers both sides share.
	if [ "$cfg" = debug ]; then
		defines+=(-DDEBUG_ENABLED)
		optim=(-O0 -g)
	fi
	local objs=()
	local n=0
	while IFS= read -r f; do
		local o="$WORK/$(basename "$f").$cfg.$sdk.$arch.$n.o"
		clang++ -c -fobjc-arc -std=gnu++17 -fno-exceptions -fvisibility=hidden \
			-isysroot "$sysroot" -target "$triple" \
			-I "$GODOT_SRC" -I "$GODOT_SRC/platform/ios" -I "$SRC" \
			"${defines[@]}" "${optim[@]}" \
			"$f" -o "$o"
		objs+=("$o")
		n=$((n + 1))
	done <<< "$SOURCES"
	ar rcs "$out" "${objs[@]}"
}

for cfg in debug release; do
	FW="$DIR/$PLUGIN.$cfg.xcframework"
	echo "==> building $cfg"
	rm -rf "$FW"
	mkdir -p "$FW/ios-arm64" "$FW/ios-arm64_x86_64-simulator"

	compile_slice "$cfg" iphoneos arm64 "arm64-apple-ios${MIN_IOS}" \
		"$FW/ios-arm64/$PLUGIN.a"

	# The simulator slice carries both architectures because the iOS simulator
	# export template is x86_64 -- see the note in the project's own tooling --
	# while an Apple-silicon Mac also wants arm64. Shipping one of the two makes
	# the plugin silently unavailable in whichever simulator you did not build.
	compile_slice "$cfg" iphonesimulator arm64 "arm64-apple-ios${MIN_IOS}-simulator" \
		"$WORK/sim-arm64.a"
	compile_slice "$cfg" iphonesimulator x86_64 "x86_64-apple-ios${MIN_IOS}-simulator" \
		"$WORK/sim-x86_64.a"
	lipo -create "$WORK/sim-arm64.a" "$WORK/sim-x86_64.a" \
		-output "$FW/ios-arm64_x86_64-simulator/$PLUGIN.a"

	cat > "$FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>BinaryPath</key><string>$PLUGIN.a</string>
			<key>LibraryIdentifier</key><string>ios-arm64</string>
			<key>LibraryPath</key><string>$PLUGIN.a</string>
			<key>SupportedArchitectures</key><array><string>arm64</string></array>
			<key>SupportedPlatform</key><string>ios</string>
		</dict>
		<dict>
			<key>BinaryPath</key><string>$PLUGIN.a</string>
			<key>LibraryIdentifier</key><string>ios-arm64_x86_64-simulator</string>
			<key>LibraryPath</key><string>$PLUGIN.a</string>
			<key>SupportedArchitectures</key><array><string>arm64</string><string>x86_64</string></array>
			<key>SupportedPlatform</key><string>ios</string>
			<key>SupportedPlatformVariant</key><string>simulator</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key><string>XFWK</string>
	<key>XCFrameworkFormatVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
done

echo
echo "==> built:"
find "$DIR" -name '*.a' -exec sh -c 'printf "    %-72s %s\n" "${1#'"$ROOT"'/}" "$(lipo -archs "$1" 2>/dev/null || file -b "$1")"' _ {} \;
echo
echo "Remember: export_presets.cfg needs the plugin switched on, e.g."
echo "    plugins/SignInWithApple=true"
