#!/bin/zsh
# Сборка Time Checker.app (нужны только Command Line Tools, Xcode не обязателен)
#   ./build.sh            — собрать в build/
#   ./build.sh install    — собрать и положить в /Applications, запустить
set -e
cd "$(dirname "$0")"
APP=build/"Time Checker.app"
mkdir -p build

echo "→ тесты логики"
./test.sh

echo "→ компиляция"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# UNIVERSAL=1 ./build.sh — бинарник сразу под Apple Silicon и Intel (для релиза)
ARCHS=("$(uname -m)")
[[ "$UNIVERSAL" == "1" ]] && ARCHS=(arm64 x86_64)
BINS=()
for ARCH in $ARCHS; do
  swiftc -swift-version 5 -O -parse-as-library \
    -target "$ARCH-apple-macos15.0" \
    Sources/Core/*.swift Sources/App/*.swift \
    -o "build/TimeChecker-$ARCH"
  BINS+=("build/TimeChecker-$ARCH")
done
lipo -create $BINS -output "$APP/Contents/MacOS/TimeChecker"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ иконка"
if [[ ! -f build/AppIcon.icns ]]; then
  swiftc -O Tools/make_icon.swift -o build/make_icon
  ./build/make_icon build/icon_1024.png
  ICONSET=build/AppIcon.iconset; rm -rf $ICONSET; mkdir -p $ICONSET
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon_1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ICONSET -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "→ подпись (ad-hoc)"
# Требование только по bundle id — доступы macOS (Универсальный доступ, Автоматизация) переживают пересборку
codesign --force --sign - --requirements Resources/requirement.txt "$APP"

if [[ "$1" == "install" ]]; then
  # Мягкий выход: приложение успевает сохранить текущий день
  osascript -e 'quit app id "com.lexus.timechecker"' 2>/dev/null || true
  sleep 1
  pkill -x TimeChecker 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/Time Checker.app"
  cp -R "$APP" /Applications/
  open "/Applications/Time Checker.app"
  echo "✓ установлено в /Applications и запущено"
else
  echo "✓ готово: $APP"
fi
