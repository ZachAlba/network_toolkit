#!/bin/bash

# =============================
# Diagnostics - Network Toolkit
# Author: Zachary Albanese
# =============================

HOST="$1"
FLAG="$2"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_DIR="./logs/$(date '+%Y-%m-%d')"
mkdir -p "$LOG_DIR"

BASENAME="report_${HOST//./_}_$TIMESTAMP"
TXT_OUT="$LOG_DIR/$BASENAME.txt"
JSON_OUT="$LOG_DIR/$BASENAME.json"
CSV_OUT="$LOG_DIR/$BASENAME.csv"

if [ -z "$HOST" ]; then
  echo "Usage: $0 <host> [--txt|--json|--csv|--all]"
  exit 1
fi

txt_output=""
json_output="{\n  \"host\": \"$HOST\",\n  \"timestamp\": \"$TIMESTAMP\",\n  \"results\": {\n"
csv_output="timestamp,host,check_type,result\n"

append_txt() { txt_output+="$1"$'\n'; }
append_json() {
  local key="$1"
  local val="$2"
  val=$(echo "$val" | sed 's/"/\\"/g' | tr -d '\r')
  json_output+="    \"${key}\": \"${val}\",\n"
}
append_csv() { csv_output+="$TIMESTAMP,$HOST,$1,$2\n"; }

# Ping
append_txt "[+] Ping Test"
ping_result=$(ping -c 3 -W 2 "$HOST")
if [[ $? -eq 0 ]]; then
  append_txt "Ping: success"
  append_json "ping" "success"
else
  append_txt "Ping: failed"
  append_json "ping" "failed"
fi

LOSS=$(echo "$ping_result" | grep -oP '\d+(?=% packet loss)')
RTT=$(echo "$ping_result" | awk -F'/' '/rtt/ {print $5}')

append_json "ping_packet_loss" "${LOSS:-0}"
append_json "ping_avg_rtt" "${RTT:-0}"
append_csv "ping_packet_loss" "${LOSS:-0}"
append_csv "ping_avg_rtt" "${RTT:-0}"

# HTTP status check
append_txt "\n[+] HTTP/HTTPS Status"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST")
HTTPS_CODE=$(curl -s -o /dev/null -w '%{http_code}' "https://$HOST")

append_txt "HTTP status: $HTTP_CODE"
append_txt "HTTPS status: $HTTPS_CODE"
append_json "http_status" "$HTTP_CODE"
append_json "https_status" "$HTTPS_CODE"
append_csv "http_status" "$HTTP_CODE"
append_csv "https_status" "$HTTPS_CODE"

# HTTP content check
append_txt "\n[+] HTTP Content Check"
HTTP_BODY=$(curl -sL --max-redirs 5 --max-time 5 "http://$HOST")

if echo "$HTTP_BODY" | grep -qiE 'welcome|nginx|apache|html'; then
  CONTENT_MATCH="yes"
else
  CONTENT_MATCH="no"
fi

REDIRECT_COUNT=$(curl -sIL --max-redirs 10 -o /dev/null -w '%{num_redirects}' "http://$HOST")

append_txt "Keyword match: $CONTENT_MATCH"
append_txt "Redirect chain length: $REDIRECT_COUNT"

append_json "http_keyword_match" "$CONTENT_MATCH"
append_json "http_redirects" "$REDIRECT_COUNT"
append_csv "http_keyword_match" "$CONTENT_MATCH"
append_csv "http_redirects" "$REDIRECT_COUNT"

# Port scan
append_txt "\n[+] Port Scan"
PORTS=(22 80 443 3306 5432 8080)
for PORT in "${PORTS[@]}"; do
  if command -v nc >/dev/null; then
    nc -z -w1 "$HOST" $PORT >/dev/null 2>&1 && STATE="open" || STATE="closed"
  else
    timeout 1 bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null && STATE="open" || STATE="closed"
  fi
  append_txt "Port $PORT: $STATE"
  append_json "port_$PORT" "$STATE"
  append_csv "port_$PORT" "$STATE"
done

append_txt "\n[+] UDP Port Scan (53 DNS, 123 NTP, 161 SNMP)"

UDP_PORTS=(53 123 161)
UDP_RESULTS=()

if command -v nmap >/dev/null; then
  NMAP_UDP_OUT=$(nmap -sU -p 53,123,161 --open --reason --max-retries 1 --host-timeout 10s "$HOST" 2>/dev/null)
  for PORT in "${UDP_PORTS[@]}"; do
    STATUS=$(echo "$NMAP_UDP_OUT" | awk "/$PORT\\/udp/"'{print $2}')
    [ -z "$STATUS" ] && STATUS="filtered"
    append_txt "UDP port $PORT: $STATUS"
    append_json "udp_port_$PORT" "$STATUS"
    append_csv "udp_port_$PORT" "$STATUS"
  done
else
  append_txt "nmap not available — skipping UDP scan."
  for PORT in "${UDP_PORTS[@]}"; do
    append_json "udp_port_$PORT" "skipped"
    append_csv "udp_port_$PORT" "skipped"
  done
fi

# ----------------------
# Write Output
# ----------------------

# Close JSON properly
json_output="${json_output%}"
json_output+="\n  }\n}"

[[ "$FLAG" == "--txt" || "$FLAG" == "--all" ]] && echo "$txt_output" >"$TXT_OUT"
[[ "$FLAG" == "--json" || "$FLAG" == "--all" ]] && echo -e "$json_output" >"$JSON_OUT"
[[ "$FLAG" == "--csv" || "$FLAG" == "--all" ]] && echo "$csv_output" >"$CSV_OUT"

echo "Diagnostics complete. Output saved to:"
[[ "$FLAG" == "--txt" || "$FLAG" == "--all" ]] && echo "  - $TXT_OUT"
[[ "$FLAG" == "--json" || "$FLAG" == "--all" ]] && echo "  - $JSON_OUT"
[[ "$FLAG" == "--csv" || "$FLAG" == "--all" ]] && echo "  - $CSV_OUT"
echo "====================================="
