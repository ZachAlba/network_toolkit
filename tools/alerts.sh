#!/bin/bash

# ---- Terminal Colors ----
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

# Enable only if interactive terminal
if [[ -t 1 ]]; then
    USE_COLOR=true
else
    USE_COLOR=false
fi

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
diag_jsons=("$LATEST_LOG_DIR"/report_*.json)
sec_jsons=("$LATEST_LOG_DIR"/security_*.json)

if [ ${#diag_jsons[@]} -eq 0 ] && [ ${#sec_jsons[@]} -eq 0 ]; then
    echo "No JSON log files found in $LATEST_LOG_DIR."
    exit 0
fi

[[ $USE_COLOR == true ]] && echo -e "${GREEN}Scanning logs in: $LATEST_LOG_DIR${RESET}" || echo "Scanning logs in: $LATEST_LOG_DIR"
echo

# Extract key-value from JSON
get_json_value() {
    echo "$2" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 | cut -d: -f2- | tr -d '", \r\n'
}

# ============ DIAGNOSTIC ALERTS ============ #
for LOG in "${diag_jsons[@]}"; do
    HOST=$(basename "$LOG" .json | sed 's/^report_//;s/_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_.*$//' | tr '_' '.')
    JSON=$(<"$LOG")
    ALERTS=()

    PING=$(get_json_value "ping" "$JSON")
    LOSS=$(get_json_value "ping_packet_loss" "$JSON")
    RTT=$(get_json_value "ping_avg_rtt" "$JSON")
    HTTP_STATUS=$(get_json_value "http_status" "$JSON")
    HTTPS_STATUS=$(get_json_value "https_status" "$JSON")
    UDP53=$(get_json_value "udp_port_53" "$JSON")
    UDP123=$(get_json_value "udp_port_123" "$JSON")
    UDP161=$(get_json_value "udp_port_161" "$JSON")
    PORT80=$(get_json_value "port_80" "$JSON")
    PORT443=$(get_json_value "port_443" "$JSON")

    [[ "$PING" != "success" ]] && ALERTS+=("Ping failed")
    [[ "$LOSS" =~ ^[0-9]+$ && "$LOSS" -gt 0 ]] && ALERTS+=("Packet loss detected: $LOSS%")
    [[ "$RTT" =~ ^[0-9]+$ && "$RTT" -gt 100 ]] && ALERTS+=("High average ping RTT: ${RTT}ms")

    [[ "$PORT80" == "closed" ]] && ALERTS+=("Port 80 closed")
    [[ "$PORT443" == "closed" ]] && ALERTS+=("Port 443 closed")
    [[ ! "$HTTP_STATUS" =~ 200 ]] && ALERTS+=("Non-200 HTTP status: $HTTP_STATUS")
    [[ ! "$HTTPS_STATUS" =~ 200 ]] && ALERTS+=("Non-200 HTTPS status: $HTTPS_STATUS")

    [[ "$UDP161" == "open" ]] && ALERTS+=("SNMP port 161/udp is open — unexpected exposure")
    [[ "$UDP53" != "open" && "$UDP53" != "skipped" ]] && ALERTS+=("DNS port 53/udp not open — DNS may be blocked")
    [[ "$UDP123" != "open" && "$UDP123" != "skipped" ]] && ALERTS+=("NTP port 123/udp not open — time sync may fail")

    [[ ${#ALERTS[@]} -gt 0 ]] && {
        [[ $USE_COLOR == true ]] && echo -e "${CYAN}ALERTS (Diagnostics) for host: $HOST${RESET}" || echo "ALERTS (Diagnostics) for host: $HOST"
        for alert in "${ALERTS[@]}"; do
            [[ $USE_COLOR == true ]] && echo -e "  ${YELLOW}- $alert${RESET}" || echo "  - $alert"
        done
        echo
    }
done

# ============ SECURITY ALERTS ============ #
for LOG in "${sec_jsons[@]}"; do
    HOST=$(basename "$LOG" .json | sed 's/^security_//;s/_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_.*$//' | tr '_' '.')
    JSON=$(<"$LOG")
    ALERTS=()

    PHPINFO=$(get_json_value "phpinfo" "$JSON")
    PHPMYADMIN=$(get_json_value "phpmyadmin" "$JSON")
    MYSQL=$(get_json_value "db_3306" "$JSON")
    CSP=$(get_json_value "header_content_security_policy" "$JSON")
    CORS=$(get_json_value "header_access_control_allow_origin" "$JSON")
    COOKIE_FLAGS=$(get_json_value "cookie_flags" "$JSON")
    WAF_DETECTED=$(get_json_value "waf_detected" "$JSON")
    SSL_RAW=$(get_json_value "ssl_expiry" "$JSON")
    SSL_CN_MISMATCH=$(get_json_value "ssl_cn_mismatch" "$JSON")
    SSL_SELF_SIGNED=$(get_json_value "ssl_self_signed" "$JSON")
    SSL_SIG_WEAK=$(get_json_value "ssl_sig_weak" "$JSON")

    if [[ -n "$SSL_RAW" ]]; then
        SSL_EPOCH=$(date -d "$SSL_RAW" +%s 2>/dev/null)
        NOW_EPOCH=$(date +%s)
        SEVEN_DAYS=$((60 * 60 * 24 * 7))
        [[ "$SSL_EPOCH" -lt $((NOW_EPOCH + SEVEN_DAYS)) ]] && ALERTS+=("SSL certificate expires soon: $SSL_RAW")
    fi

    [[ "$SSL_CN_MISMATCH" == "true" ]] && ALERTS+=("SSL domain mismatch (CN)")
    [[ "$SSL_SELF_SIGNED" == "true" ]] && ALERTS+=("Self-signed certificate")
    [[ "$SSL_SIG_WEAK" == "true" ]] && ALERTS+=("Weak signature algorithm")
    [[ "$PHPINFO" == "exposed" ]] && ALERTS+=("phpinfo.php exposed — leaking PHP config")
    [[ "$PHPMYADMIN" == "exposed" ]] && ALERTS+=("phpMyAdmin exposed — login panel detected")
    [[ "$MYSQL" == "open" ]] && ALERTS+=("MySQL port 3306 open — DB exposed over internet")
    [[ "$CSP" == "missing" ]] && ALERTS+=("Missing CSP header — no content policy enforcement")
    [[ "$CORS" == "*" ]] && ALERTS+=("Permissive CORS: Access-Control-Allow-Origin is '*'")
    [[ "$COOKIE_FLAGS" != "none" && "$COOKIE_FLAGS" != "0 weak" ]] && ALERTS+=("Cookies missing secure flags: $COOKIE_FLAGS")
    [[ "$WAF_DETECTED" != "none" ]] && ALERTS+=("WAF/CDN detected: $WAF_DETECTED")

    for path in ".env" ".git/config" "wp-config.php.bak" "index.php~" "config.php" "composer.lock" ".DS_Store"; do
        CODE=$(get_json_value "secret_/$path" "$JSON")
        [[ "$CODE" == "200" ]] && ALERTS+=("Exposed sensitive file: /$path (HTTP 200)")
    done

    [[ ${#ALERTS[@]} -gt 0 ]] && {
        [[ $USE_COLOR == true ]] && echo -e "${CYAN}ALERTS (Security Scan) for host: $HOST${RESET}" || echo "ALERTS (Security Scan) for host: $HOST"
        for alert in "${ALERTS[@]}"; do
            [[ $USE_COLOR == true ]] && echo -e "  ${YELLOW}- $alert${RESET}" || echo "  - $alert"
        done
        echo
    }
done

[[ $USE_COLOR == true ]] && echo -e "${GREEN}Alert scan complete.${RESET}" || echo "Alert scan complete."
[[ $USE_COLOR == true ]] && echo -e "${GREEN}===============================${RESET}" || echo "==============================="

# Wait for user to acknowledge, then clear
if command -v gum &>/dev/null; then
    gum input --prompt "Press Enter to return to menu..." >/dev/null
else
    read -rp "Press Enter to return to menu..."
fi

clear
