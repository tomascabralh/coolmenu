#!/usr/bin/env bash
# Packages a release build into dist/: CoolMenu-<version>.zip and CoolMenu-<version>.dmg.
# Usage: scripts/package.sh
#
# Without a Developer ID the app is only self-signed (or ad-hoc), and Gatekeeper blocks it on
# other Macs until the user right-clicks > Open (or runs `xattr -dr com.apple.quarantine`).
# For a build that opens cleanly anywhere, set both:
#   COOLMENU_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   COOLMENU_NOTARY_PROFILE=<profile>   # created once with:
#     xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <TEAMID>
# The app is then notarized and the ticket stapled to both the app and the dmg.
set -euo pipefail

cd "$(dirname "$0")/.."
identity="${COOLMENU_SIGN_IDENTITY:-}"
if [[ -n "${COOLMENU_NOTARY_PROFILE:-}" && "$identity" != "Developer ID Application"* ]]; then
  echo "COOLMENU_NOTARY_PROFILE needs COOLMENU_SIGN_IDENTITY set to a Developer ID Application identity" >&2
  exit 1
fi
scripts/build-app.sh

app=build/CoolMenu.app
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
name="CoolMenu-$version"
mkdir -p dist
zip="dist/$name.zip"
dmg="dist/$name.dmg"
rm -f "$zip" "$dmg"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$COOLMENU_NOTARY_PROFILE" --wait
}

if [[ -n "${COOLMENU_NOTARY_PROFILE:-}" ]]; then
  # notarytool takes a zip, not a bare .app.
  ditto -c -k --keepParent "$app" "$zip"
  notarize "$zip"
  xcrun stapler staple "$app"
  rm "$zip"
else
  echo "warning: not notarized; Gatekeeper will block this build on other Macs (see the header of this script)" >&2
fi

# Zip from the (possibly stapled) app, keeping signature-relevant metadata.
ditto -c -k --keepParent "$app" "$zip"

# Dmg with the app and an /Applications shortcut for drag-to-install. Built and signed outside the
# repo for the same iCloud reason as the app (see build-app.sh), then moved into dist/.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/root"
ditto "$app" "$work/root/CoolMenu.app"
ln -s /Applications "$work/root/Applications"
hdiutil create -quiet -volname CoolMenu -srcfolder "$work/root" -fs HFS+ -format UDZO "$work/$name.dmg"

if [[ -n "${COOLMENU_NOTARY_PROFILE:-}" ]]; then
  codesign --force --timestamp --sign "$identity" "$work/$name.dmg"
  notarize "$work/$name.dmg"
  xcrun stapler staple "$work/$name.dmg"
fi
mv "$work/$name.dmg" "$dmg"

echo "Packaged $zip and $dmg"
