#!/bin/bash
# Publie une version : compile, notarise (Developer ID) puis crée la release GitHub avec mSTICK.zip et son .sha256,
# que la mise à jour automatique de l'appli va chercher. Notes : _tools/changelogs/mSTICK_<version>.txt (4 langues).
# Usage : scripts/release.sh <version>   (ex. 1.2 ; le tag devient v1.2)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?Usage : scripts/release.sh <version>}"
NOTARIZE=/Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh
DIST="$(mktemp -d)"

swift test
VERSION="$VERSION" NO_INSTALL=1 ./build_app.sh
DIST="$DIST" "$NOTARIZE" mSTICK.app
(cd "$DIST" && shasum -a 256 mSTICK.zip > mSTICK.zip.sha256)
python3 /Volumes/SKYRIM/TOOLS/MAC/_tools/release_notes.py mSTICK "$VERSION" --sha "$DIST/mSTICK.zip.sha256" -o "$DIST/notes.md"
gh release create "v$VERSION" "$DIST/mSTICK.zip" "$DIST/mSTICK.zip.sha256" --title "mSTICK $VERSION" --notes-file "$DIST/notes.md"
rm -rf "$DIST"
