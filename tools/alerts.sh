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

shopt -s nullglob
json_files=("$LATEST_LOG_DIR"/*.json)

if [ ${#json_files[@]} -eq 0 ]; then
    echo "No JSON log files found in $LATEST_LOG_DIR."
    exit 0
fi

echo "Scanning logs in: $LATEST_LOG_DIR"
echo

for LOG in "${json_files[@]}"; do
    HOST=$(basename "$LOG" .json | sed 's/^report_//;s/_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_.*$//' | tr '_' '.')
    JSON=$(<"$LOG")

    get_json_value() {
        echo "$JSON" | grep "\"$1\"" | head -n1 | cut -d: -f2- | tr -d '", \r\n'
    }

    PING=$(get_json_value "ping")
    PORT80=$(get_json_value "port_80")
    PORT443=$(get_json_value "port_443")
    SSL_RAW=$(get_json_value "ssl_expiry")
    HTTP_STATUS=$(get_json_value "http_status")
    HTTPS_STATUS=$(get_json_value "https_status")
    UDP53=$(get_json_value "udp_port_53")
    UDP123=$(get_json_value "udp_port_123")
    UDP161=$(get_json_value "udp_port_161")

    ALERTS=()

    # Standard alerts
    [[ "$PING" != "success" ]] && ALERTS+=("Ping failed")
    [[ "$PORT80" == "closed" ]] && ALERTS+=("Port 80 closed")
    [[ "$PORT443" == "closed" ]] && ALERTS+=("Port 443 closed")
    [[ ! "$HTTP_STATUS" =~ 200 ]] && ALERTS+=("Non-200 HTTP status: $HTTP_STATUS")
    [[ ! "$HTTPS_STATUS" =~ 200 ]] && ALERTS+=("Non-200 HTTPS status: $HTTPS_STATUS")

    # SSL expiration
    if [[ -n "$SSL_RAW" ]]; then
        SSL_EPOCH=$(date -d "$SSL_RAW" +%s 2>/dev/null)
        NOW_EPOCH=$(date +%s)
        SEVEN_DAYS=$((60 * 60 * 24 * 7))
        if [[ "$SSL_EPOCH" -lt $((NOW_EPOCH + SEVEN_DAYS)) ]]; then
            ALERTS+=("SSL certificate expires soon: $SSL_RAW")
        fi
    fi
    
    # UDP port alerts
    if [[ "$UDP161" == "open" ]]; then
        ALERTS+=("SNMP port 161/udp is open — unexpected exposure")
    fi
    if [[ "$UDP53" != "open" && "$UDP53" != "skipped" ]]; then
        ALERTS+=("DNS port 53/udp not open — DNS may be blocked")
    fi
    if [[ "$UDP123" != "open" && "$UDP123" != "skipped" ]]; then
        ALERTS+=("NTP port 123/udp not open — time sync may fail")
    fi

    if [[ ${#ALERTS[@]} -gt 0 ]]; then
        echo "ALERTS for host: $HOST"
        for alert in "${ALERTS[@]}"; do
            echo "  - $alert"
        done
        echo
    fi
done

echo "Alert scan complete."
echo "==============================="
