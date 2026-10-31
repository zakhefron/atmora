#!/usr/bin/env bash
# Run the Swift Testing suite.
#
# On a Mac with Xcode selected, plain `swift test` works. With only the Command
# Line Tools, the Testing framework ships in a non-standard location and its
# Foundation cross-import overlay is not installed, so the flags below point the
# compiler and linker at the framework and disable the missing overlay. This is
# a toolchain workaround, not a test setting.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
MODULES="$FRAMEWORKS/Testing.framework/Versions/A/Modules"
DEVELOPER_DIR_PATH="$(xcode-select -p 2>/dev/null || true)"

set +e
if [[ "$DEVELOPER_DIR_PATH" == *"Xcode"* ]] || [[ ! -d "$MODULES" ]]; then
    swift test --enable-swift-testing "$@"
else
    swift test --enable-swift-testing --disable-xctest \
        -Xswiftc -I -Xswiftc "$MODULES" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F -Xlinker "$FRAMEWORKS" \
        -Xlinker -framework -Xlinker Testing \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        "$@"
fi
status=$?

# The preference suites use throwaway UserDefaults domains. macOS can leave
# empty suite plists behind, so remove them once the run has finished.
rm -f "$HOME/Library/Preferences"/atmora.tests.*.plist

exit $status
