#!/usr/bin/env bash
# Ставить бекенд у автозапуск як LaunchAgent, щоб він піднімався після
# перезавантаження Mac і сам перезапускався, якщо впаде.
#
#   ./deploy/install-agent.sh          # поставити й запустити
#   ./deploy/install-agent.sh remove   # прибрати
#
# Чому генеруємо plist скриптом, а не тримаємо готовий: launchd не бачить ні
# PATH користувача, ні nvm — шлях до node треба вписати абсолютний, а він у
# кожного свій.
set -euo pipefail

LABEL="com.chornomorets.courses-api"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERVER_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" == "remove" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Прибрано: $LABEL"
  exit 0
fi

NODE_BIN="$(command -v node)"
[[ -n "$NODE_BIN" ]] || { echo "node не знайдено в PATH"; exit 1; }
NODE_DIR="$(dirname "$NODE_BIN")"
TSX_BIN="$SERVER_DIR/node_modules/.bin/tsx"
[[ -x "$TSX_BIN" ]] || { echo "не знайдено $TSX_BIN — виконайте npm install"; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents" "$SERVER_DIR/logs"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$NODE_BIN</string>
		<string>$TSX_BIN</string>
		<string>src/index.ts</string>
	</array>
	<!-- launchd не успадковує PATH користувача, а tsx запускає дочірні
	     процеси node. Без цього агент падає з «env: node: No such file». -->
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>$NODE_DIR:/usr/bin:/bin:/usr/sbin:/sbin</string>
	</dict>
	<key>WorkingDirectory</key>
	<string>$SERVER_DIR</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$SERVER_DIR/logs/api.log</string>
	<key>StandardErrorPath</key>
	<string>$SERVER_DIR/logs/api.error.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 2

if curl -sf -m 5 http://localhost:3000/health > /dev/null; then
  echo "Запущено: $LABEL → http://localhost:3000"
  echo "Логи: $SERVER_DIR/logs/api.log"
else
  echo "Агент поставлено, але /health не відповідає. Дивіться $SERVER_DIR/logs/api.error.log"
  exit 1
fi
