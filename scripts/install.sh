#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/bundle.sh

osascript -e 'tell application id "app.trouser.browser" to quit' 2>/dev/null || true
rm -rf /Applications/Trouser.app
cp -R build/Trouser.app /Applications/

mkdir -p "$HOME/.local/bin"
ln -sf /Applications/Trouser.app/Contents/MacOS/Trouser "$HOME/.local/bin/trouser"
echo "installed /Applications/Trouser.app and $HOME/.local/bin/trouser"
