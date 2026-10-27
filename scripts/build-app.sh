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

# The bundle is assembled and signed in a temp folder, then moved into build/. If the repo lives
# in an iCloud-synced Desktop/Documents, the file provider tags bundles there with FinderInfo at
# random, which codesign rejects mid-build ("detritus"). build/ also carries the provider's ignore
# marker so the finished bundle isn't tagged afterwards; the marker only takes effect on a fresh
# folder, and build/ is entirely generated, so it's recreated when the marker is missing.
if ! xattr -p 'com.apple.fileprovider.ignore#P' build >/dev/null 2>&1; then
  rm -rf build
  mkdir build
  xattr -w 'com.apple.fileprovider.ignore#P' 1 build
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
staged="$stage/CoolMenu.app"
mkdir -p "$staged/Contents/MacOS" "$staged/Contents/Resources"
cp "$bin" "$staged/Contents/MacOS/CoolMenu"
cp Resources/Info.plist "$staged/Contents/Info.plist"
cp Resources/AppIcon.icns "$staged/Contents/Resources/AppIcon.icns"

# CFBundleShortVersionString lives in Resources/Info.plist; the build number is the commit count so
# every build from a new commit sorts after the last one.
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$staged/Contents/Info.plist"

default_identity=-
if security find-identity -p codesigning 2>/dev/null | grep -q '"CoolMenu Dev"'; then
  default_identity="CoolMenu Dev"
else
  echo "warning: ad-hoc signing; Accessibility must be re-granted after every build (run scripts/make-dev-cert.sh once)" >&2
fi
identity="${COOLMENU_SIGN_IDENTITY:-$default_identity}"
# Copied sources can carry quarantine attributes, which codesign also rejects.
xattr -cr "$staged"
sign_flags=(--force --options runtime --sign "$identity")
# Notarization requires a secure timestamp, which only a real (Developer ID) identity can get.
[[ "$identity" == "Developer ID Application"* ]] && sign_flags+=(--timestamp)
codesign "${sign_flags[@]}" "$staged" >/dev/null

app=build/CoolMenu.app
rm -rf "$app"
mv "$staged" "$app"
echo "Built $app (signed: $identity)"

if $open_after; then
  pkill -x CoolMenu 2>/dev/null || true
  # LaunchServices refuses to open the app (-600) while the old instance is still exiting.
  while pgrep -x CoolMenu >/dev/null; do sleep 0.2; done
  open "$app"
fi
