#!/bin/bash

# =============================
# Network Diagnostic Toolkit - Auto Runner
# Author: Zachary Albanese
# =============================

CONFIG_FILE="./config.ini"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config.ini not found in project root."
    exit 1
fi

# Parse INI
HOSTS=$(grep '^hosts' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ')
OUTPUT_MODE=$(grep '^output_mode' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ')

if [ -z "$HOSTS" ]; then
    echo "ERROR: No hosts specified in config.ini."
    exit 1
fi

if [[ ! "$OUTPUT_MODE" =~ ^(txt|json|csv|all)$ ]]; then
    echo "ERROR: Invalid output_mode in config.ini. Use: txt, json, csv, or all"
    exit 1
fi

echo "Running diagnostics for: $HOSTS"
echo "Output format: $OUTPUT_MODE"
echo

for HOST in $(echo "$HOSTS" | tr ',' ' '); do
    echo "[*] Scanning $HOST..."
    bash "$(dirname "$0")/diagnostics.sh" "$HOST" "--$OUTPUT_MODE"
    bash "$(dirname "$0")/security_scan.sh" "$HOST" "--$OUTPUT_MODE"
    echo
done

echo "Batch scan complete."

# Cleanup logs older than N days
RETENTION_DAYS=$(grep '^log_retention_days' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ')

if [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    echo "[*] Cleaning logs older than $RETENTION_DAYS days..."
    find ./logs -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;
    echo "[*] Cleanup complete."
else
    echo "[!] Invalid or missing log_retention_days in config.ini — skipping cleanup."
fi

# Email alert logic
EMAIL=$(grep '^admin_email' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ')

ALERT_TMP=$(mktemp)
bash "$(dirname "$0")/alerts.sh" >"$ALERT_TMP"

if grep -q "ALERTS for host:" "$ALERT_TMP"; then
    if command -v mail >/dev/null && [[ "$EMAIL" =~ "@" ]]; then
        mail -s "Network Toolkit Alerts - $(date '+%Y-%m-%d')" "$EMAIL" <"$ALERT_TMP"
        echo "[*] Alerts emailed to $EMAIL"
    else
        echo "[!] mail not installed or email not configured."
        echo "Alerts output:"
        cat "$ALERT_TMP"
    fi
else
    echo "[*] No alerts detected."
fi

rm "$ALERT_TMP"
