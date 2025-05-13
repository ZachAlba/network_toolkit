#!/bin/bash

# ---- Terminal Colors ----
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BGBLUE='\033[44m'
RESET='\033[0m'

# =============================
# Network Diagnostic Toolkit - GUM UI
# Author: Zachary Albanese
# =============================

if ! command -v gum &>/dev/null; then
  echo "gum is required but not installed. Install via: brew install gum OR manually from GitHub"
  exit 1
fi

banner() {
  echo -e "${BGBLUE}${CYAN}"
  echo "╔═════════════════════════════════════════════════╗"
  echo "║     🛠️  NETWORK DIAGNOSTIC TOOLKIT CLI MENU      ║"
  echo "╚═════════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

build_output_flag() {
  FORMAT="json"

  CHOICE=$(gum choose --cursor "👉" "json (default)" "txt" "csv" "all")

  case "$CHOICE" in
  "txt") FORMAT="json,txt" ;;
  "csv") FORMAT="json,csv" ;;
  "all") FORMAT="json,txt,csv" ;;
  *) FORMAT="json" ;;
  esac

  echo "$FORMAT"
}

scan_host() {
  TYPE=$(gum choose "Diagnostics" "Security")
  HOST=$(gum input --placeholder "Enter target host")
  [[ -z "$HOST" ]] && echo "No host entered." && return

  gum style --foreground 212 "⚠️  Alerts require JSON output. JSON will always be included."
  FORMAT=$(build_output_flag)
  START_TIME=$(date +%s)

  gum spin --spinner dot --title "Running $TYPE scan on $HOST..." -- bash -c "
    if [[ \"$TYPE\" == \"Diagnostics\" ]]; then
      bash tools/diagnostics.sh \"$HOST\" \"--$FORMAT\"
    else
      bash tools/security_scan.sh \"$HOST\" \"--$FORMAT\"
    fi
  "

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  echo -e "${GREEN}Scan completed in ${DURATION}s.${RESET}"
}

batch_mode() {
  bash tools/auto_runner.sh
}

view_logs() {
  gum style --foreground 212 "Recent log files:"
  find logs -mindepth 2 -type f \( -name "*.txt" -o -name "*.json" -o -name "*.csv" \) | sort | tail -n 10 | gum pager
}

view_alerts() {
  bash tools/alerts.sh
}

edit_config() {
  gum style --foreground 212 "Updating config.ini..."

  HOSTS=$(gum input --placeholder "e.g. google.com,1.1.1.1")
  gum style --foreground 212 "⚠️  Alerts require JSON. JSON will always be included."
  EXTRA_FORMATS=$(gum choose --no-limit --cursor "👉" txt csv)
  MODE="json"
  [[ "$EXTRA_FORMATS" == *"txt"* ]] && MODE="$MODE,txt"
  [[ "$EXTRA_FORMATS" == *"csv"* ]] && MODE="$MODE,csv"

  DAYS=$(gum input --placeholder "Log retention in days")
  EMAIL=$(gum input --placeholder "Admin email for alerts")

  echo -e "[Targets]\nhosts = $HOSTS\n\n[Settings]\noutput_mode = $MODE\nlog_retention_days = $DAYS\n\n[Admin]\nadmin_email = $EMAIL" >config.ini

  echo -e "${GREEN}config.ini updated successfully.${RESET}"
}

main_menu() {

  while true; do
    clear
    banner
    CHOICE=$(gum choose --cursor "👉" \
      "🔎 Scan a host" \
      "🗂  Batch scan (auto mode)" \
      "📂 View recent logs" \
      "🚨 View alerts" \
      "⚙️  Configure settings" \
      "❌ Exit")

    case "$CHOICE" in
    "🔎 Scan a host") scan_host ;;
    "🗂  Batch scan (auto mode)") batch_mode ;;
    "📂 View recent logs") view_logs ;;
    "🚨 View alerts") view_alerts ;;
    "⚙️  Configure settings") edit_config ;;
    "❌ Exit")
      echo -e "${GREEN}Goodbye.${RESET}"
      exit 0
      ;;
    esac
  done
}

main_menu
