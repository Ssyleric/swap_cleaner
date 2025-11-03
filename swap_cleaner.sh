#!/bin/bash
# swap_cleaner.sh — purge le swap si > 90% pendant 2h et envoie une notif Discord
# Exécuter en root (PVE), sans sudo.

set -euo pipefail

# --- Config -------------------------------------------------------------------
WEBHOOK="https://discord.com/api/webhooks/12345678900987865432/sahogfuhwsaoghowpishagnopwisghjpiwrjgwpiqjgknvdsoag
THRESHOLD=${THRESHOLD:-90}        # % de swap utilisé (override possible via env)
CHECK_EVERY_MIN=${CHECK_EVERY_MIN:-10}  # fréquence du cron en minutes
DURATION_MIN=${DURATION_MIN:-120}       # durée continue requise au-dessus du seuil
STATE_FILE="/var/tmp/swap_usage_count.txt"
LOG="/var/log/swap_cleaner.log"
HOST="$(hostname)"

# --- Pré-requis ---------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  apt update -y && apt install -y jq
fi

mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE" "$LOG"

# --- Fonctions ----------------------------------------------------------------
limit_checks() {
  python3 - "$CHECK_EVERY_MIN" "$DURATION_MIN" <<'PY'
import sys, math
every = int(sys.argv[1]); duration = int(sys.argv[2])
print(max(1, math.ceil(duration / every)))
PY
}

discord_notify() {
  # $1 = message (multi-ligne), $2 = fichier joint (optionnel)
  local msg="$1" file="${2:-}"
  # marge stricte < 2000 caractères
  if [ "${#msg}" -gt 1900 ]; then msg="${msg:0:1900}\n…(truncated)"; fi
  printf "%s" "$msg" | jq -Rs '{content: .}' > /tmp/payload.json
  if [ -n "${file}" ] && [ -f "${file}" ]; then
    curl -sS -f \
      -F "payload_json=@/tmp/payload.json;type=application/json" \
      -F "file=@${file};type=text/plain" \
      "$WEBHOOK" >/dev/null || true
  else
    curl -sS -f -H "Content-Type: application/json" \
      -d @/tmp/payload.json "$WEBHOOK" >/dev/null || true
  fi
  rm -f /tmp/payload.json
}

swap_usage_percent() {
  local total used
  read -r total used _ < <(free -m | awk '/^Swap:/ {print $2, $3, $4}')
  if [ "${total:-0}" -gt 0 ]; then echo $(( used * 100 / total )); else echo 0; fi
}

log() { echo "$(date '+%F %T') $*" | tee -a "$LOG" >/dev/null; }

# --- Single instance (évite chevauchements) -----------------------------------
exec 9>/var/tmp/.swap_cleaner.lock
flock -n 9 || exit 0

# --- Logic --------------------------------------------------------------------
COUNT="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"
USAGE="$(swap_usage_percent)"
LIMIT="$(limit_checks)"

if [ "$USAGE" -ge "$THRESHOLD" ]; then
  COUNT=$((COUNT + 1)); echo "$COUNT" > "$STATE_FILE"
  log "[INFO] Swap ${USAGE}% (>=${THRESHOLD}%). Compteur ${COUNT}/${LIMIT}."
  if [ "$COUNT" -ge "$LIMIT" ]; then
    log "[ACTION] ${DURATION_MIN} min >= ${THRESHOLD}% — swapoff -a && swapon -a"
    BEFORE="$(free -h)"
    if swapoff -a && swapon -a; then
      AFTER="$(free -h)"; echo "0" > "$STATE_FILE"
      MSG="🧹 **Swap cleaner (PVE: ${HOST})**\nSeuil: ${THRESHOLD}% maintenu ${DURATION_MIN} min.\nAction: \`swapoff -a && swapon -a\`\n\nAvant:\n${BEFORE}\n\nAprès:\n${AFTER}\n\nLog: ${LOG}"
      discord_notify "$MSG" "$LOG"
    else
      log "[ERROR] Échec swapoff/swapon."
      discord_notify "⚠️ **Swap cleaner (PVE: ${HOST})**\nÉchec de \`swapoff -a && swapon -a\` (swap=${USAGE}%)." "$LOG"
    fi
  fi
else
  if [ "$COUNT" -ne 0 ]; then log "[INFO] Swap à ${USAGE}%, reset compteur."; fi
  echo "0" > "$STATE_FILE"
fi
