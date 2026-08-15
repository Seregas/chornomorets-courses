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

# Віджет вимагає App Group, а її треба один раз зареєструвати в Developer-порталі
# (Identifiers → App Groups + галочка App Groups на обох App ID). Поки цього не
# зроблено, підпис падає на entitlement. WITHOUT_WIDGET=1 збирає застосунок без
# віджета — решта функціональності на місці, віджет додасться наступною збіркою.
SPEC=project.yml
if [[ "${WITHOUT_WIDGET:-0}" == "1" ]]; then
  echo "→ Збірка БЕЗ віджета (App Group ще не зареєстрована)"
  SPEC=project.generated.yml
  grep -v -e '- target: CoursesWidgets' \
          -e 'CODE_SIGN_ENTITLEMENTS: CoursesApp/CoursesApp.entitlements' \
          project.yml > "$SPEC"
fi

echo "→ Генерую проєкт (team $TEAM_ID)"
DEVELOPMENT_TEAM="$TEAM_ID" API_BASE_URL="$API_BASE_URL" xcodegen generate --spec "$SPEC"

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

# Вивантажити можна трьома способами — беремо перший доступний.
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  echo "→ Вивантажую за App Store Connect API-ключем"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
elif [[ -n "${ASC_USERNAME:-}" ]]; then
  # Запасний шлях, коли App Store Connect API-ключ створити не можна (він
  # потребує ролі Admin): звичайний Apple ID + пароль застосунку.
  #
  # Пароль застосунку привʼязаний до Apple ID, а не до застосунку, тож той,
  # що вже лежить у ~/.zshenv, підходить і сюди:
  #
  #   source ~/.zshenv
  #   TEAM_ID=GW39JC2R67 API_BASE_URL=https://courses-api.sirohas.space \
  #   ASC_USERNAME="$APPLE_ID" ASC_PASSWORD="$APPCONNECT_GENOMICS_DEPLOY_PW" \
  #   ./scripts/testflight.sh
  #
  # Без ASC_PASSWORD береться з keychain (security add-generic-password -s AC_PASSWORD).
  echo "→ Вивантажую за Apple ID $ASC_USERNAME"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --username "$ASC_USERNAME" --password "${ASC_PASSWORD:-@keychain:AC_PASSWORD}"
else
  echo
  echo "Ні API-ключа, ні ASC_USERNAME — вивантаження пропускаю."
  echo "Завантажте вручну: відкрийте застосунок Transporter і перетягніть"
  echo "  $IPA"
  echo "або в Xcode: Window → Organizer → Distribute App."
  exit 0
fi

echo "→ Вивантажено. Обробка збірки в App Store Connect триває кілька хвилин."
