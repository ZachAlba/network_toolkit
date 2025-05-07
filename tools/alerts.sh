#!/bin/bash

# =============================
# Network Diagnostic Toolkit - Alerts
# Author: Zachary Albanese
# =============================

LATEST_LOG_DIR=$(find ./logs -type d -name "20*" | sort | tail -n 1)

if [ -z "$LATEST_LOG_DIR" ]; then
    echo "No log directories found."
    exit 1
fi

echo "Scanning latest logs in: $LATEST_LOG_DIR"
echo

if [ ${#LOG_FILES[@]} -eq 0 ]; then
    echo "No JSON log files found in $LATEST_LOG_DIR."
    exit 0
fi

for LOG in "$LATEST_LOG_DIR"/*.json; do
    [ -e "$LOG" ] || continue

    HOST=$(basename "$LOG" | cut -d'_' -f2- | cut -d'.' -f1)
    JSON=$(cat "$LOG")

    PING=$(echo "$JSON" | grep '"ping"' | cut -d: -f2 | tr -d '", ')
    PORT80=$(echo "$JSON" | grep '"port_80"' | cut -d: -f2 | tr -d '", ')
    PORT443=$(echo "$JSON" | grep '"port_443"' | cut -d: -f2 | tr -d '", ')
    SSL_RAW=$(echo "$JSON" | grep '"ssl_expiry"' | cut -d: -f2- | sed 's/^[[:space:]]*//;s/[",]//g')

    ALERTS=()

    # Ping failure
    if [[ "$PING" != "success" ]]; then
        ALERTS+=("Ping failed")
    fi

    # HTTP/HTTPS ports closed
    if [[ "$PORT80" == "closed" ]]; then
        ALERTS+=("Port 80 is closed")
    fi
    if [[ "$PORT443" == "closed" ]]; then
        ALERTS+=("Port 443 is closed")
    fi

    # SSL cert expiry check
    if [[ "$SSL_RAW" != "N/A" && -n "$SSL_RAW" ]]; then
        SSL_EPOCH=$(date -d "$SSL_RAW" +%s 2>/dev/null)
        NOW_EPOCH=$(date +%s)
        SEVEN_DAYS=$((60 * 60 * 24 * 7))
        if [[ "$SSL_EPOCH" -lt $((NOW_EPOCH + SEVEN_DAYS)) ]]; then
            ALERTS+=("SSL certificate expires soon: $SSL_RAW")
        fi
    fi

    if [[ ${#ALERTS[@]} -gt 0 ]]; then
        echo "ALERTS for host: $HOST"
        for A in "${ALERTS[@]}"; do
            echo "  - $A"
        done
        echo
    fi
done

echo "Alert scan complete."
