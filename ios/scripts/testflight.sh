#!/usr/bin/env bash
# Збирає архів і вивантажує його в TestFlight.
#
# Що треба мати ДО запуску (одноразово, у вашому обліковому записі Apple):
#   1. У Developer-порталі зареєстровані App ID:
#        com.chornomorets.courses          (основний застосунок)
#        com.chornomorets.courses.widgets  (віджет)
#      і для обох увімкнена App Group `group.com.chornomorets.courses`.
#   2. В App Store Connect створений запис застосунку з bundle ID
#      com.chornomorets.courses.
#   3. App Store Connect API-ключ (Users and Access → Integrations → App Store Connect API):
#      файл AuthKey_XXXXXXXXXX.p8 покласти в ~/.appstoreconnect/private_keys/
#
# Запуск:
#   TEAM_ID=XXXXXXXXXX \
#   API_BASE_URL=https://ваш-домен \
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
#   ./scripts/testflight.sh
#
# Без ASC_KEY_ID/ASC_ISSUER_ID скрипт зупиниться після експорту .ipa —
# файл можна завантажити вручну через застосунок Transporter.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${TEAM_ID:?вкажіть TEAM_ID — Team ID вашого акаунта Apple Developer}"
: "${API_BASE_URL:?вкажіть API_BASE_URL — публічну https-адресу бекенда}"

BUILD_DIR="${BUILD_DIR:-build}"
ARCHIVE="$BUILD_DIR/CoursesApp.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

echo "→ Генерую проєкт (team $TEAM_ID)"
DEVELOPMENT_TEAM="$TEAM_ID" API_BASE_URL="$API_BASE_URL" xcodegen generate

echo "→ Архівую (API: $API_BASE_URL)"
xcodebuild archive \
  -project CoursesApp.xcodeproj \
  -scheme CoursesApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  API_BASE_URL="$API_BASE_URL" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates

mkdir -p "$EXPORT_DIR"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

echo "→ Експортую .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates

IPA=$(find "$EXPORT_DIR" -name '*.ipa' | head -1)
echo "→ Готово: $IPA"

if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
  echo
  echo "ASC_KEY_ID/ASC_ISSUER_ID не задані — вивантаження пропускаю."
  echo "Завантажте $IPA вручну через Transporter."
  exit 0
fi

echo "→ Вивантажую в App Store Connect"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "→ Вивантажено. Обробка збірки в App Store Connect триває кілька хвилин."
