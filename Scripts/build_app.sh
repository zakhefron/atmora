#!/usr/bin/env bash
# Build Atmora.app from the Swift package. This is a local, ad-hoc-signed
# bundle: it is not Developer ID signed and not notarized.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${ATMORA_VERSION:-1.0.0}"
BUILD_NUMBER="${ATMORA_BUILD:-1}"
BUNDLE_ID="com.atmora.app"
APP="$ROOT/dist/Atmora.app"
LAUNCH=0
SKIP_BUILD=0

for argument in "$@"; do
    case "$argument" in
        --open) LAUNCH=1 ;;
        --skip-build) SKIP_BUILD=1 ;;
        -h|--help)
            echo "Usage: Scripts/build_app.sh [--open] [--skip-build]"
            echo "  ATMORA_VERSION=1.0.0  Override CFBundleShortVersionString"
            echo "  ATMORA_BUILD=1        Override CFBundleVersion"
            exit 0
            ;;
        *)
            echo "Unknown option: $argument" >&2
            exit 2
            ;;
    esac
done

if [[ ! -f "$ROOT/Assets/AppIcon.icns" ]]; then
    echo "App icon missing; generating it…"
    python3 "$ROOT/Tools/generate_icon.py"
fi

WALLPAPERS=(rainy-cabin train sakura-night cloud-library sunset-drive seaside-records)
missing_wallpaper=0
for identifier in "${WALLPAPERS[@]}"; do
    [[ -f "$ROOT/Assets/Wallpapers/$identifier.jpg" ]] || missing_wallpaper=1
done
if [[ "$missing_wallpaper" -eq 1 ]]; then
    echo "Wallpapers missing; generating them…"
    python3 "$ROOT/Tools/generate_wallpapers.py"
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo "Building release binary…"
    swift build -c release
fi

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/Atmora"
if [[ ! -x "$BINARY" ]]; then
    echo "Release binary not found at $BINARY" >&2
    exit 1
fi

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Atmora"
chmod 755 "$APP/Contents/MacOS/Atmora"

cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist" >/dev/null
plutil -lint "$APP/Contents/Info.plist" >/dev/null

cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Assets/AppIconMenuBar.png" "$APP/Contents/Resources/AppIconMenuBar.png"
cp "$ROOT/Assets/AppMark.png" "$APP/Contents/Resources/AppMark.png"
ditto "$ROOT/Assets/Audio" "$APP/Contents/Resources/Audio"
ditto "$ROOT/Assets/Wallpapers" "$APP/Contents/Resources/Wallpapers"
printf 'APPL????' > "$APP/Contents/PkgInfo"

LAYER_COUNT="$(find "$APP/Contents/Resources/Audio" -name '*.m4a' | wc -l | tr -d ' ')"
WALLPAPER_COUNT="$(find "$APP/Contents/Resources/Wallpapers" -name '*.jpg' | wc -l | tr -d ' ')"

if [[ "$LAYER_COUNT" -ne 19 ]]; then
    echo "Expected 19 audio files, found $LAYER_COUNT" >&2
    exit 1
fi
if [[ "$WALLPAPER_COUNT" -ne 6 ]]; then
    echo "Expected 6 wallpapers, found $WALLPAPER_COUNT" >&2
    exit 1
fi

# Ad-hoc signature: enough for local launch and to keep macOS from re-signing
# the bundle when it is moved. It is not a distribution identity.
xattr -cr "$APP"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null
codesign --verify --strict "$APP"

SIZE="$(du -sh "$APP" | awk '{print $1}')"

echo
echo "Built Atmora $VERSION ($BUILD_NUMBER) — $LAYER_COUNT audio files, $WALLPAPER_COUNT wallpapers, $SIZE"
echo "  Bundle:    $APP"
echo "  Bundle ID: $BUNDLE_ID"
echo "  Signature: ad-hoc (not Developer ID, not notarized)"
echo "  Install:   Scripts/install_app.sh --user"
echo "  Launch:    open \"$APP\""

if [[ "$LAUNCH" -eq 1 ]]; then
    open "$APP"
fi
