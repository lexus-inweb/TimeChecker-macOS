#!/bin/zsh
# Готовит zip для GitHub Releases: универсальная сборка (Apple Silicon + Intel).
#   ./release.sh  →  build/release/TimeChecker-<версия>-macos-universal.zip
set -e
cd "$(dirname "$0")"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
UNIVERSAL=1 ./build.sh
mkdir -p build/release
ZIP="build/release/TimeChecker-$VERSION-macos-universal.zip"
rm -f "$ZIP"
# ditto сохраняет подпись и атрибуты бандла, в отличие от zip
ditto -c -k --sequesterRsrc --keepParent "build/Time Checker.app" "$ZIP"
echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"
