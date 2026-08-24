#!/bin/bash
# Собирает SpeedReader.app с подписью Developer ID, нотаризует у Apple
# и упаковывает в .dmg, готовый к раздаче кому угодно без предупреждений Gatekeeper.
#
# Перед первым запуском один раз сохраните пароль для нотаризации:
#   xcrun notarytool store-credentials "speedreader-notary" \
#     --apple-id "you@example.com" --team-id "37ZC9H35VN"
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SpeedReader"
SCHEME="SpeedReader-macOS"
TEAM_ID="37ZC9H35VN"
NOTARY_PROFILE="speedreader-notary"

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/${APP_NAME}.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
STAGE_DIR="$BUILD_DIR/dmg_stage"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Архивирую (Developer ID)..."
xcodebuild archive \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

cat > "$EXPORT_OPTIONS" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST

echo "==> Экспортирую подписанный .app..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

APP_PATH="$EXPORT_PATH/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Экспорт не удался: $APP_PATH не найден"
  exit 1
fi

echo "==> Отправляю на нотаризацию Apple (может занять несколько минут)..."
ZIP_PATH="$BUILD_DIR/${APP_NAME}-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Прикрепляю тикет нотаризации к приложению..."
xcrun stapler staple "$APP_PATH"

echo "==> Готовлю DMG..."
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

echo ""
echo "==> Готово (нотаризовано): $DMG_PATH"
echo "    Проверить: spctl -a -vv -t install \"$STAGE_DIR/${APP_NAME}.app\""
