#!/bin/bash
# Собирает SpeedReader.app (Release, ad-hoc подпись, только для запуска на этом Маке)
# и упаковывает его в обычный .dmg с ярлыком на /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SpeedReader"
SCHEME="SpeedReader-macOS"
BUILD_DIR="build"
STAGE_DIR="$BUILD_DIR/dmg_stage"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Собираю Release .app..."
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  clean build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Сборка не удалась: $APP_PATH не найден"
  exit 1
fi

echo "==> Готовлю содержимое DMG..."
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Создаю DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

echo "==> Готово: $DMG_PATH"
open "$BUILD_DIR"
