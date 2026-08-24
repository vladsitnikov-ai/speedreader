#!/bin/bash
# Двойной клик по этому файлу собирает SpeedReader.app и упаковывает в .dmg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SpeedReader"
SCHEME="SpeedReader-macOS"
BUILD_DIR="build"
STAGE_DIR="$BUILD_DIR/dmg_stage"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"

echo "========================================"
echo " Сборка $APP_NAME"
echo "========================================"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo ""
  echo "ОШИБКА: не найден полный Xcode."
  echo "Установите Xcode из App Store, откройте его один раз (примет лицензию),"
  echo "затем запустите этот файл снова."
  echo ""
  read -p "Нажмите Enter, чтобы закрыть окно..."
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo ""
echo "==> Собираю приложение (может занять пару минут)..."
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
  read -p "Нажмите Enter, чтобы закрыть окно..."
  exit 1
fi

echo "==> Готовлю DMG..."
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

echo ""
echo "========================================"
echo " Готово! DMG лежит здесь:"
echo " $DMG_PATH"
echo "========================================"
open "$BUILD_DIR"
read -p "Нажмите Enter, чтобы закрыть окно..."
