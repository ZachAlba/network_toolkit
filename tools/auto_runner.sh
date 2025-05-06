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
  echo
done

echo "Batch scan complete."
