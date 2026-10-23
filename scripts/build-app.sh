#!/usr/bin/env bash
# Builds CoolMenu.app into ./build. Usage: scripts/build-app.sh [--open] [--debug]
#
# Signing: macOS ties the Accessibility grant to the code signature. Ad-hoc signing (the default)
# changes on every build, so the grant has to be re-toggled after each rebuild. Set
# COOLMENU_SIGN_IDENTITY to a stable identity (e.g. a self-signed "CoolMenu Dev" certificate made in
# Keychain Access, or a Developer ID) to keep it across builds.
set -euo pipefail

cd "$(dirname "$0")/.."
config=release
open_after=false
for arg in "$@"; do
  case "$arg" in
    --open) open_after=true ;;
    --debug) config=debug ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

swift build -c "$config" --product CoolMenu
bin="$(swift build -c "$config" --show-bin-path)/CoolMenu"

app=build/CoolMenu.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/CoolMenu"
cp Resources/Info.plist "$app/Contents/Info.plist"

default_identity=-
if security find-identity -p codesigning 2>/dev/null | grep -q '"CoolMenu Dev"'; then
  default_identity="CoolMenu Dev"
else
  echo "warning: ad-hoc signing; Accessibility must be re-granted after every build (run scripts/make-dev-cert.sh once)" >&2
fi
identity="${COOLMENU_SIGN_IDENTITY:-$default_identity}"
codesign --force --options runtime --sign "$identity" "$app" >/dev/null
echo "Built $app (signed: $identity)"

if $open_after; then
  pkill -x CoolMenu 2>/dev/null || true
  # LaunchServices refuses to open the app (-600) while the old instance is still exiting.
  while pgrep -x CoolMenu >/dev/null; do sleep 0.2; done
  open "$app"
fi
