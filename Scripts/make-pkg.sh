#!/bin/bash
# Packages a built SoundSourceClone.app into a double-click macOS installer (.pkg).
#
#   Scripts/make-pkg.sh <path/to/SoundSourceClone.app> <version> <output.pkg>
#
# The installer puts "SoundSource Clone.app" in /Applications, quits any running copy first, and
# opens the new copy for the signed-in user when it finishes. Requires macOS 14.2+ to install.
#
# Optional: set PKG_SIGN_IDENTITY to a "Developer ID Installer: …" identity to sign the package.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <path/to/SoundSourceClone.app> <version> <output.pkg>" >&2
  exit 64
fi

APP_SOURCE=$1
VERSION=$2
OUTPUT=$3
APP_NAME="SoundSource Clone"
MIN_MACOS="14.2"

[[ -d "$APP_SOURCE/Contents/MacOS" ]] || { echo "error: $APP_SOURCE is not an app bundle" >&2; exit 66; }
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_SOURCE/Contents/Info.plist")
PKG_ID="$BUNDLE_ID.pkg"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/soundsource-pkg.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/Applications" "$WORK/scripts" "$WORK/resources" "$WORK/packages"

# Payload: the app under the name people see in /Applications.
ditto --norsrc --noextattr "$APP_SOURCE" "$WORK/root/Applications/$APP_NAME.app"
codesign --verify --deep --strict "$WORK/root/Applications/$APP_NAME.app"

# By default pkgbuild marks apps "relocatable": Installer would then update any other copy with the
# same bundle ID (for example an Xcode build) in place instead of installing into /Applications.
# Newer pkgbuild versions omit the key instead of writing true, so always write it explicitly.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" > /dev/null
/usr/libexec/PlistBuddy -c "Delete :0:BundleIsRelocatable" "$WORK/component.plist" 2> /dev/null || true
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$WORK/component.plist"

cat > "$WORK/scripts/preinstall" <<'SCRIPT'
#!/bin/sh
# Quit a running copy so the new version replaces it cleanly. Its audio taps end with the process,
# so every app's sound goes back to normal immediately.
/usr/bin/pkill -x SoundSourceClone 2>/dev/null || true
sleep 1
exit 0
SCRIPT

cat > "$WORK/scripts/postinstall" <<SCRIPT
#!/bin/sh
# Start the freshly installed app for the person who ran the installer (it lives in the menu bar).
[ "\$3" = "/" ] || exit 0
CONSOLE_USER=\$(/usr/bin/stat -f %Su /dev/console)
if [ -n "\$CONSOLE_USER" ] && [ "\$CONSOLE_USER" != "root" ] && [ "\$CONSOLE_USER" != "loginwindow" ]; then
  CONSOLE_UID=\$(/usr/bin/id -u "\$CONSOLE_USER")
  /bin/launchctl asuser "\$CONSOLE_UID" /usr/bin/sudo -u "\$CONSOLE_USER" /usr/bin/open "/Applications/$APP_NAME.app" || true
fi
exit 0
SCRIPT
chmod 755 "$WORK/scripts/preinstall" "$WORK/scripts/postinstall"

pkgbuild \
  --root "$WORK/root" \
  --component-plist "$WORK/component.plist" \
  --scripts "$WORK/scripts" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --install-location / \
  "$WORK/packages/SoundSourceClone-component.pkg" > /dev/null

cat > "$WORK/resources/welcome.html" <<HTML
<!DOCTYPE html>
<html><body style="font-family: -apple-system, sans-serif; font-size: 13px;">
<h2>$APP_NAME $VERSION</h2>
<p>Per-app volume, equalizer and output routing for your Mac, in the menu bar.</p>
<p>This installs <b>$APP_NAME</b> in your Applications folder and starts it when installation finishes.
Requires macOS $MIN_MACOS or later.</p>
</body></html>
HTML

cat > "$WORK/resources/conclusion.html" <<HTML
<!DOCTYPE html>
<html><body style="font-family: -apple-system, sans-serif; font-size: 13px;">
<h2>$APP_NAME is running</h2>
<p>Look for the speaker-cabinet icon in your menu bar and click it to open the panel.</p>
<p>When macOS asks, click <b>Allow</b> for <b>System Audio Recording</b>: per-app volume, effects and routing need it.
To start it automatically, turn on <b>Launch at Login</b> in the panel's gear menu.</p>
</body></html>
HTML

cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>$APP_NAME</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="$MIN_MACOS"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="$PKG_ID"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$PKG_ID" visible="false">
        <pkg-ref id="$PKG_ID"/>
    </choice>
    <pkg-ref id="$PKG_ID" version="$VERSION" onConclusion="none">SoundSourceClone-component.pkg</pkg-ref>
</installer-gui-script>
XML

SIGN_ARGS=()
if [[ -n "${PKG_SIGN_IDENTITY:-}" ]]; then
  SIGN_ARGS=(--sign "$PKG_SIGN_IDENTITY" --timestamp)
fi

mkdir -p "$(dirname "$OUTPUT")"
productbuild \
  --distribution "$WORK/distribution.xml" \
  --resources "$WORK/resources" \
  --package-path "$WORK/packages" \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
  "$OUTPUT" > /dev/null

echo "Created $OUTPUT ($APP_NAME $VERSION, $(du -h "$OUTPUT" | cut -f1 | tr -d ' '))"
