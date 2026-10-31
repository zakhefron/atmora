#!/usr/bin/env bash
# Build and install Atmora as a normal macOS application.
#
# Default destination is automatic: an existing install is upgraded in place;
# otherwise Atmora goes to /Applications when it is writable, and to
# ~/Applications otherwise. Use --user or --system to choose explicitly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Atmora.app"
BUNDLE_ID="com.atmora.app"
SOURCE_APP="$ROOT/dist/$APP_NAME"
DESTINATION="auto"
OPEN_AFTER=0
SKIP_BUILD=0
REMOVE_OTHER=1

usage() {
    cat <<'EOF'
Usage: Scripts/install_app.sh [--user | --system | --auto] [options]

Destinations:
  --auto       Upgrade in place if already installed; otherwise /Applications
               when writable, else ~/Applications. This is the default.
  --user       Install to ~/Applications/Atmora.app
  --system     Install to /Applications/Atmora.app

Options:
  --skip-build      Use the existing dist/Atmora.app instead of rebuilding.
  --open            Launch the installed app when finished.
  --keep-other      Do not remove a second Atmora copy from the other
                    standard Applications folder.
  -h, --help        Show this help.

Notes:
  * Installation replaces any existing Atmora.app at the chosen destination,
    so repeated installs never create duplicate bundles.
  * The build is ad-hoc signed for local use. It is not Developer ID signed and
    not notarized. Gatekeeper may still require a manual open on another Mac.
  * If /Applications is not writable, build as your user and then run:
      sudo Scripts/install_app.sh --system --skip-build
EOF
}

for argument in "$@"; do
    case "$argument" in
        --auto) DESTINATION="auto" ;;
        --user) DESTINATION="user" ;;
        --system) DESTINATION="system" ;;
        --open) OPEN_AFTER=1 ;;
        --skip-build) SKIP_BUILD=1 ;;
        --keep-other) REMOVE_OTHER=0 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown option: $argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "$EUID" -eq 0 && "$SKIP_BUILD" -eq 0 ]]; then
    echo "Refusing to build as root. Build as your user, then re-run with:" >&2
    echo "  sudo Scripts/install_app.sh --system --skip-build" >&2
    exit 2
fi

# Resolve the invoking user's home even when the installer runs under sudo, so
# the per-user Applications folder is the real one.
if [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    [[ -n "$USER_HOME" ]] || USER_HOME="$HOME"
else
    USER_HOME="$HOME"
fi
USER_APPLICATIONS="$USER_HOME/Applications"
SYSTEM_APPLICATIONS="/Applications"

resolve_destination() {
    case "$DESTINATION" in
        user)
            TARGET_DIR="$USER_APPLICATIONS"
            ;;
        system)
            TARGET_DIR="$SYSTEM_APPLICATIONS"
            ;;
        auto)
            if [[ -d "$USER_APPLICATIONS/$APP_NAME" ]]; then
                TARGET_DIR="$USER_APPLICATIONS"
            elif [[ -d "$SYSTEM_APPLICATIONS/$APP_NAME" ]]; then
                TARGET_DIR="$SYSTEM_APPLICATIONS"
            elif [[ -w "$SYSTEM_APPLICATIONS" ]]; then
                TARGET_DIR="$SYSTEM_APPLICATIONS"
            else
                TARGET_DIR="$USER_APPLICATIONS"
            fi
            ;;
    esac
}

resolve_destination
TARGET_APP="$TARGET_DIR/$APP_NAME"

echo "Atmora installer"
echo "  Source:      $SOURCE_APP"
echo "  Destination: $TARGET_APP"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    "$ROOT/Scripts/build_app.sh"
elif [[ ! -d "$SOURCE_APP" ]]; then
    echo "dist/$APP_NAME does not exist. Run without --skip-build first." >&2
    exit 1
fi

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Expected a built app at $SOURCE_APP" >&2
    exit 1
fi

# --- Verify the source bundle before touching an existing installation. -----

fail() {
    echo "Installation stopped: $1" >&2
    exit 1
}

[[ -x "$SOURCE_APP/Contents/MacOS/Atmora" ]] || fail "the app executable is missing"
[[ -f "$SOURCE_APP/Contents/Info.plist" ]] || fail "Info.plist is missing"
[[ -f "$SOURCE_APP/Contents/Resources/AppIcon.icns" ]] || fail "the app icon is missing"

SOURCE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
[[ "$SOURCE_BUNDLE_ID" == "$BUNDLE_ID" ]] || fail "unexpected bundle identifier: $SOURCE_BUNDLE_ID"

AUDIO_COUNT="$(find "$SOURCE_APP/Contents/Resources/Audio" -name '*.m4a' 2>/dev/null | wc -l | tr -d ' ')"
WALLPAPER_COUNT="$(find "$SOURCE_APP/Contents/Resources/Wallpapers" -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')"
[[ "$AUDIO_COUNT" -eq 19 ]] || fail "expected 19 audio files, found $AUDIO_COUNT"
[[ "$WALLPAPER_COUNT" -eq 6 ]] || fail "expected 6 wallpapers, found $WALLPAPER_COUNT"

codesign --verify --strict "$SOURCE_APP" >/dev/null 2>&1 || fail "the built bundle does not pass codesign verification"

mkdir -p "$TARGET_DIR" || fail "could not create $TARGET_DIR"
[[ -w "$TARGET_DIR" ]] || fail "$TARGET_DIR is not writable. Use --user, or run with sudo --skip-build"

# --- Copy into a staging path, then swap. This avoids a half-written app if a
# copy fails, and replacing the old bundle prevents duplicate installs. -------

STAGING="$TARGET_DIR/.$APP_NAME.installing.$$"
trap 'rm -rf "$STAGING"' EXIT

rm -rf "$STAGING"
ditto "$SOURCE_APP" "$STAGING" || fail "could not copy the app into $TARGET_DIR"
rm -rf "$TARGET_APP"
mv "$STAGING" "$TARGET_APP"
trap - EXIT

# Refresh Launch Services and the Finder icon cache for the new bundle.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
fi
touch "$TARGET_APP"

# --- Remove a second copy from the other standard Applications folder. ------

if [[ "$REMOVE_OTHER" -eq 1 ]]; then
    for other_dir in "$SYSTEM_APPLICATIONS" "$USER_APPLICATIONS"; do
        [[ "$other_dir" == "$TARGET_DIR" ]] && continue
        other_app="$other_dir/$APP_NAME"
        [[ -d "$other_app" ]] || continue

        if [[ -w "$other_dir" ]]; then
            rm -rf "$other_app"
            echo "  Removed duplicate copy at $other_app"
        else
            echo "  Warning: another copy exists at $other_app but $other_dir is not writable." >&2
            echo "           Remove it manually to avoid two Atmora entries in Launchpad." >&2
        fi
    done
fi

# --- Verify the installed bundle, including resources from its real path. ---

codesign --verify --strict "$TARGET_APP" >/dev/null 2>&1 || fail "the installed bundle does not pass codesign verification"

ASSET_OUTPUT="$("$TARGET_APP/Contents/MacOS/Atmora" --asset-check 2>&1)" || {
    echo "$ASSET_OUTPUT" >&2
    fail "the installed app could not resolve its bundled assets"
}

echo
echo "Installed Atmora"
echo "  Location:  $TARGET_APP"
echo "  Bundle ID: $BUNDLE_ID"
echo "  Version:   $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET_APP/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TARGET_APP/Contents/Info.plist"))"
echo "  Resources: $AUDIO_COUNT audio files, $WALLPAPER_COUNT wallpapers"
echo "  Signature: ad-hoc (not Developer ID, not notarized)"
echo "$ASSET_OUTPUT" | sed 's/^/  /'
echo
echo "  Launch:    open \"$TARGET_APP\""
echo "  Or find it in Finder, Spotlight, or Launchpad."

if [[ "$OPEN_AFTER" -eq 1 ]]; then
    open "$TARGET_APP"
fi
