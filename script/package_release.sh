#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${MAC_FISHING_BOT_ARCH:-$(uname -m)}"

"$ROOT/script/build_cli.sh" >/dev/null
"$ROOT/script/build_app.sh" >/dev/null

cd "$ROOT/dist"
rm -f "MacFishingBotControl-macOS-${ARCH}.zip" "mac-fishing-bot-cli-macOS-${ARCH}.zip"
xattr -cr MacFishingBotControl.app mac-fishing-bot 2>/dev/null || true
ditto -c -k --norsrc --keepParent MacFishingBotControl.app "MacFishingBotControl-macOS-${ARCH}.zip"
ditto -c -k --norsrc --keepParent mac-fishing-bot "mac-fishing-bot-cli-macOS-${ARCH}.zip"

echo "$ROOT/dist/MacFishingBotControl-macOS-${ARCH}.zip"
echo "$ROOT/dist/mac-fishing-bot-cli-macOS-${ARCH}.zip"
