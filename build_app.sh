#!/bin/bash
# Compile mSTICK.app (release), avec son icône, ses langues et la signature stable.
# Usage : ./build_app.sh   (produit ./mSTICK.app ; NO_INSTALL=1 pour ne pas l'installer)
# MSTICK_EDITION=test : édition de test vierge (autre identifiant, autres données), jamais installée.
set -euo pipefail
cd "$(dirname "$0")"

TOOLS=/Volumes/SKYRIM/TOOLS
DEST="${MSTICK_INSTALL_DIR:-$HOME/Applications/Applications Personnelles}"
# Sans VERSION, la version de la dernière publication (étiquette git vX.Y.Z) : une copie locale numérotée 1.0.0 serait
# remplacée par la mise à jour automatique, même par une publication plus ancienne que son code (incident du 14/11/2026).
VERSION="${VERSION:-$(git tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -1 | sed 's/^v//')}"
VERSION="${VERSION:-1.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
BUNDLE_ID=fr.stephan.mstick
APP=mSTICK.app
if [ "${MSTICK_EDITION:-}" = test ]; then BUNDLE_ID=fr.stephan.mstick.test; APP=mSTICK-test.app; NO_INSTALL=1; fi

# Socle vit hors de l'arborescence parcourue par sync_apps.sh : copie reprise à chaque build.
if [ -f "$TOOLS/DESIGN/Socle/swift/Socle.swift" ]; then
    cp "$TOOLS/DESIGN/Socle/swift/Socle.swift" Sources/mSTICK/Socle.swift
fi
# Modules communs de mise à jour automatique.
for f in Updater.swift UpdaterView.swift; do
    [ -f "$TOOLS/MAC/_TOOLS/shared/$f" ] && cp "$TOOLS/MAC/_TOOLS/shared/$f" "Sources/mSTICK/$f"
done

if [ ! -f assets/mSTICK.icns ]; then
    mkdir -p assets
    TMP="$(mktemp -d)"
    swift scripts/make_icon.swift "$TMP/icon.png"
    mkdir "$TMP/mSTICK.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$TMP/mSTICK.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/mSTICK.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$TMP/mSTICK.iconset" -o assets/mSTICK.icns
    cp "$TMP/icon.png" assets/mSTICK.png
    rm -rf "$TMP"
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/mSTICK"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mSTICK"
cp assets/mSTICK.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
EXTRA=""
[ "${MSTICK_EDITION:-}" = test ] && EXTRA='<key>SkyrimUpdateAcceptBundleID</key><string>fr.stephan.mstick</string><key>LSEnvironment</key><dict><key>MSTICK_DATA_DIR</key><string>~/Library/Application Support/mSTICK-test</string></dict>'
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>mSTICK</string>
    <key>CFBundleDisplayName</key><string>mSTICK</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>mSTICK</string>
    <key>CFBundleIconFile</key><string>mSTICK</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string><string>es</string><string>it</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    $EXTRA
    <key>NSHumanReadableCopyright</key><string>© 2026 Starbudweiser</string>
</dict>
</plist>
PLIST

if [ -x "$TOOLS/MAC/_tools/sign_app.sh" ]; then
    "$TOOLS/MAC/_tools/sign_app.sh" "$APP"
else
    codesign --force --deep --sign - "$APP"   # signature ad hoc hors de ma machine
fi

if [ "${NO_INSTALL:-0}" != 1 ]; then
    mkdir -p "$DEST"
    osascript -e 'tell application id "fr.stephan.mstick" to quit' 2>/dev/null || true
    rm -rf "$DEST/$APP"
    cp -R "$APP" "$DEST/"
    echo "Installé : $DEST/$APP"
fi
