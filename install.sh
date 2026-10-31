#!/bin/sh
# Atmora installer — https://github.com/zakhefron/atmora
#
# There is no binary to download on purpose: an app moved onto a Mac by hand arrives
# quarantined, and an unsigned one is then refused by Gatekeeper ("Apple could not verify").
# An app built on the machine it lands on carries no quarantine — so this fetches the
# sources, builds here, and installs.
#
# With only the Command Line Tools (no Xcode), the installer downloads a prebuilt
# Atmora.zip from GitHub Releases instead — the same app, built once by the
# maintainer, unpacked here so it carries no quarantine.
#
# The sources and the build cache live in ~/Library/Caches/Atmora: the first install
# compiles once, and later installs rebuild only what changed, in seconds.
set -u

CACHE="$HOME/Library/Caches/Atmora"
URL="https://github.com/zakhefron/atmora.git"
RELEASE_URL="https://github.com/zakhefron/atmora/releases/latest/download/Atmora.zip"
SPIN=0
LAST=''

# Colour only when the runner is interactive; the brand amber is Atmora's own.
AMBER='' GREEN='' RED='' DIM='' BOLD='' RESET=''
if [ -t 1 ]; then
    AMBER=$(printf '\033[38;5;208m') GREEN=$(printf '\033[32m') RED=$(printf '\033[1;31m')
    DIM=$(printf '\033[2m') BOLD=$(printf '\033[1m') RESET=$(printf '\033[0m')
fi

begin() { LAST="$1"; printf '  %s⋅%s %-34s' "$AMBER" "$RESET" "$1"; }

finish() { # $1 label, $2 seconds, $3 note — replaces the pending line
    [ -t 1 ] && printf '\r\033[K'
    printf '  %s✓%s %-34s' "$GREEN" "$RESET" "$1"
    [ -n "${2:-}" ] && printf '  %ss%s' "$2" "$RESET"
    [ -n "${3:-}" ] && printf '  · %s%s%s' "$DIM" "$3" "$RESET"
    printf '\n'
}

fail() { printf '\n  ✗ %s\n' "$1"; exit 1; }

spin() { # $1 = pid; animated progress bar + elapsed time
    local width=24 i=0 t0
    t0=$(date +%s)
    while kill -0 "$1" 2>/dev/null; do
        i=$(( (i + 1) % (width + 4) ))
        bar=""
        j=0
        while [ $j -lt $width ]; do
            pos=$(( j - i + 4 ))
            if [ $pos -ge 0 ] && [ $pos -lt 4 ]; then
                bar="${bar}█"
            else
                bar="${bar}░"
            fi
            j=$((j + 1))
        done
        now=$(date +%s)
        elapsed=$(( now - t0 ))
        printf '\r\033[K  %s⋅%s %-34s%s[%s]%s  %ss' "$AMBER" "$RESET" "$LAST" "$AMBER" "$bar" "$RESET" "$elapsed"
        sleep 0.06
    done
}

printf '\n'
printf '  %s●%s %sAtmora%s %sinstaller%s\n' "$AMBER" "$RESET" "$BOLD" "$RESET" "$DIM" "$RESET"
printf '  %sambient soundscapes for macOS · builds from source · CC0 audio%s\n\n' "$DIM" "$RESET"

# ---- toolchain ----------------------------------------------------------
begin "Toolchain"
if xcodebuild -version >/dev/null 2>&1; then
    SWIFT=$(swift --version 2>/dev/null | head -1 | sed 's/^Swift version //;s/^Apple Swift version /Swift /;s/ (swiftlang.*//')
    [ -n "$SWIFT" ] || fail "the Swift toolchain is not installed."
    XCV=$(xcodebuild -version 2>/dev/null | head -1)
    printf '%s  %s%s\n' "$XCV" "$SWIFT" "$RESET"
    BUILD_FROM_SOURCE=1
elif swift --version >/dev/null 2>&1; then
    SWIFT=$(swift --version 2>/dev/null | head -1 | sed 's/^Swift version //;s/^Apple Swift version /Swift /;s/ (swiftlang.*//')
    [ -n "$SWIFT" ] || fail "the Swift toolchain is not installed."
    printf 'Swift %s%s\n' "$SWIFT" "$RESET"
    BUILD_FROM_SOURCE=1
else
    printf '%sCommand Line Tools only — will download a prebuilt build%s\n' "$DIM" "$RESET"
    BUILD_FROM_SOURCE=0
fi

# ---- sources / prebuilt -------------------------------------------------
if [ "${BUILD_FROM_SOURCE:-0}" = "1" ]; then
begin "Fetching sources…"
START=$(date +%s)
NOTE=''
if [ -d "$CACHE/.git" ]; then
    OLD=$(git -C "$CACHE" rev-parse HEAD 2>/dev/null)
    if git -C "$CACHE" fetch --quiet --depth 1 origin main 2>/dev/null &&
       git -C "$CACHE" reset --hard --quiet origin/main 2>/dev/null; then
        NEW=$(git -C "$CACHE" rev-parse HEAD)
        [ "$OLD" = "$NEW" ] && NOTE='already current' || NOTE='updated'
    else
        NOTE='offline - using cached sources'
    fi
fi
if [ ! -d "$CACHE/.git" ]; then
    if git clone --quiet --depth 1 "$URL" "$CACHE" 2>/dev/null; then
        NOTE='fresh clone'
    else
        fail "the clone failed.
  If it says 'Could not resolve host: github.com', this Mac has no DNS servers.
  Fix it once with:  sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8
  Or download the zip manually from https://github.com/zakhefron/atmora"
    fi
fi
T=$(( $(date +%s) - START ))
finish "Sources" "$T" "$NOTE"

# ---- build --------------------------------------------------------------
begin "Building (release)…"
START=$(date +%s)
(cd "$CACHE" && Scripts/build_app.sh >"$CACHE/build.log" 2>&1) &
BPID=$!
spin "$BPID" &
SPINPID=$!
if ! wait "$BPID"; then
    kill "$SPINPID" 2>/dev/null
    wait "$SPINPID" 2>/dev/null
    printf '\r\033[K\n'
    printf '%s\n' '--- last 25 lines of the build log ---'
    tail -25 "$CACHE/build.log"
    printf '%s\n' '-------------------------------------'
    fail "the build failed. The full log is kept at $CACHE/build.log"
fi
kill "$SPINPID" 2>/dev/null
wait "$SPINPID" 2>/dev/null
printf '\r\033[K'
T=$(( $(date +%s) - START ))
finish "Build (release) — the only slow step" "$T" \
    'first install builds once; afterwards this is seconds'
else
# ---- download prebuilt (no Xcode) --------------------------------------
begin "Downloading prebuilt build…"
START=$(date +%s)
mkdir -p "$CACHE" || fail "could not create cache at $CACHE"
TMPZIP="$CACHE/Atmora.zip"
rm -f "$TMPZIP"
curl -fsSL "$RELEASE_URL" -o "$TMPZIP" &
DLBPID=$!
spin "$DLBPID" &
SPINPID=$!
if ! wait "$DLBPID"; then
    kill "$SPINPID" 2>/dev/null
    wait "$SPINPID" 2>/dev/null
    printf '\r\033[K'
    fail "could not download the prebuilt build (404 = no release published yet).
  Either install Xcode to build from source:
    xcode-select --install
  or ask the maintainer to run ./Scripts/package.sh and upload
  build/Atmora.zip to GitHub Releases."
fi
kill "$SPINPID" 2>/dev/null
wait "$SPINPID" 2>/dev/null
printf '\r\033[K'
rm -rf "$CACHE/Atmora.app"
rm -rf "$CACHE/dist"
mkdir -p "$CACHE/dist"
unzip -q "$TMPZIP" -d "$CACHE/dist" || fail "could not extract the build."
rm -f "$TMPZIP"
T=$(( $(date +%s) - START ))
finish "Downloaded prebuilt build" "$T" "no Xcode needed"
fi

# ---- install ------------------------------------------------------------
begin "Installing…"
START=$(date +%s)
if [ "${BUILD_FROM_SOURCE:-0}" = "1" ]; then
    (cd "$CACHE" && Scripts/install_app.sh --auto --open >"$CACHE/install.log" 2>&1) &
    IPID=$!
    spin "$IPID" &
    SPINPID=$!
    if ! wait "$IPID"; then
        kill "$SPINPID" 2>/dev/null
        wait "$SPINPID" 2>/dev/null
        printf '\r\033[K\n'
        printf '%s\n' '--- last 25 lines of the install log ---'
        tail -25 "$CACHE/install.log"
        printf '%s\n' '-------------------------------------'
        fail "the install failed. The full log is kept at $CACHE/install.log"
    fi
    kill "$SPINPID" 2>/dev/null
    wait "$SPINPID" 2>/dev/null
else
    # ---- install prebuilt -----------------------------------------------
    APP_NAME="Atmora.app"
    BUNDLE_ID="com.atmora.app"
    SOURCE_APP="$CACHE/dist/$APP_NAME"
    [ -d "$SOURCE_APP" ] || fail "the prebuilt app was not extracted correctly"

    # Resolve destination: existing install, else /Applications, else ~/Applications.
    if [ -d "/Applications/$APP_NAME" ]; then
        TARGET_DIR="/Applications"
    elif [ -d "$HOME/Applications/$APP_NAME" ]; then
        TARGET_DIR="$HOME/Applications"
    elif [ -w "/Applications" ]; then
        TARGET_DIR="/Applications"
    else
        TARGET_DIR="$HOME/Applications"
    fi
    TARGET_APP="$TARGET_DIR/$APP_NAME"

    mkdir -p "$TARGET_DIR" || fail "could not create $TARGET_DIR"
    [ -w "$TARGET_DIR" ] || fail "$TARGET_DIR is not writable"

    # Remove a duplicate copy from the other standard Applications folder.
    for other_dir in "/Applications" "$HOME/Applications"; do
        [ "$other_dir" = "$TARGET_DIR" ] && continue
        other_app="$other_dir/$APP_NAME"
        [ -d "$other_app" ] || continue
        if [ -w "$other_dir" ]; then
            rm -rf "$other_app"
        fi
    done

    STAGING="$TARGET_DIR/.$APP_NAME.installing.$$"
    trap 'rm -rf "$STAGING"' EXIT
    rm -rf "$STAGING"
    ditto "$SOURCE_APP" "$STAGING" || fail "could not copy the app into $TARGET_DIR"
    rm -rf "$TARGET_APP"
    mv "$STAGING" "$TARGET_APP"
    trap - EXIT

    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
    fi
    touch "$TARGET_APP"

    codesign --verify --strict "$TARGET_APP" >/dev/null 2>&1 || fail "the installed bundle does not pass codesign verification"

    open "$TARGET_APP" 2>/dev/null || true
fi
printf '\r\033[K'
T=$(( $(date +%s) - START ))
finish "Installed" "$T"

# ---- summary ------------------------------------------------------------
TARGET_APP=""
if [ -d "/Applications/Atmora.app" ]; then
    TARGET_APP="/Applications/Atmora.app"
elif [ -d "$HOME/Applications/Atmora.app" ]; then
    TARGET_APP="$HOME/Applications/Atmora.app"
fi

VER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TARGET_APP/Contents/Info.plist" 2>/dev/null || echo '?')
KB=$(du -sk "$TARGET_APP" 2>/dev/null | cut -f1)
SIZE=$(awk "BEGIN{printf \"%.1f\", $KB/1024}" 2>/dev/null)
printf '\n'
printf '  %s✓ Atmora %s — %s MB on disk%s\n' "$GREEN" "$VER" "$SIZE" "$RESET"
printf '  %sA quiet room for the work that needs you.%s\n\n' "$DIM" "$RESET"
