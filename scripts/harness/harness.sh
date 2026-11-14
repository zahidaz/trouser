#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."
NAME="${HARNESS_NAME:-}"
ID="app.trouser.browser.harness${NAME:+.$NAME}"
WORK="${HARNESS_DIR:-$TMPDIR/trouser-harness${NAME:+-$NAME}}"
APP="$WORK/TrouserHarness.app"
PORT="${HARNESS_PORT:-8765}"
CONTAINER="$HOME/Library/Containers/$ID/Data"
export TROUSER_SOCKET="$CONTAINER/tmp/trouser.sock"

build() {
    scripts/bundle.sh
    rm -rf "$APP"
    cp -R build/Trouser.app "$APP"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" -c "Set :CFBundleName Trouser Harness" -c "Set :CFBundleDisplayName Trouser Harness" "$APP/Contents/Info.plist"
    codesign --force --sign - --options runtime --entitlements Resources/Trouser.entitlements "$APP"
    mkdir -p "$CONTAINER/Library/Preferences"
    for kind in pointer keyboard submit download; do
        defaults write "$CONTAINER/Library/Preferences/$ID" "policy.$kind" -string allow
    done
}

start() {
    local settings="$CONTAINER/Library/Application Support/Trouser/history"
    mkdir -p "$settings"
    echo '{"blockedHosts": ["harness.invalid"], "liveScreenshot": true}' >"$settings/default.settings.json"
    echo '{"blockedHosts": ["harness.invalid"], "liveScreenshot": true, "preciseMode": true}' >"$settings/precise.settings.json"
    python3 -m http.server "$PORT" --bind 127.0.0.1 --directory scripts/harness/pages >"$WORK/server.log" 2>&1 &
    echo $! >"$WORK/server.pid"
    open -n "$APP" --env "TROUSER_SOCKET=$TROUSER_SOCKET"
    for _ in $(seq 50); do
        [ -S "$TROUSER_SOCKET" ] && break
        sleep 0.1
    done
    echo "http://127.0.0.1:$PORT/"
}

stop() {
    osascript -e "tell application id \"$ID\" to quit" 2>/dev/null || true
    [ -f "$WORK/server.pid" ] && kill "$(cat "$WORK/server.pid")" 2>/dev/null || true
    rm -f "$WORK/server.pid"
}

cli() {
    exec "$APP/Contents/MacOS/Trouser" "$@"
}

mkdir -p "$WORK"
command="$1"
shift
case "$command" in
    build|start|stop) "$command" ;;
    url) echo "http://127.0.0.1:$PORT/" ;;
    cli) cli "$@" ;;
    *) echo "usage: harness.sh build|start|stop|url|cli <arguments>" >&2; exit 2 ;;
esac
