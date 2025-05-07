#!/bin/bash

# =============================
# Network Diagnostic Toolkit
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

# Fail if no host
if [ -z "$HOST" ]; then
  echo "Usage: $0 <host> [--txt|--json|--csv|--all]"
  exit 1
fi

# Buffers
txt_output=""
json_output="{\n  \"host\": \"$HOST\",\n  \"timestamp\": \"$TIMESTAMP\",\n  \"results\": {\n"
csv_output="timestamp,host,check_type,result\n"

# Append helpers
append_txt()   { txt_output+="$1"$'\n'; }
append_json()  { json_output+="    \"$1\": \"$2\",\n"; }
append_csv()   { csv_output+="$TIMESTAMP,$HOST,$1,$2\n"; }

# ----------------------
# Begin Diagnostics
# ----------------------

append_txt "===== Network Diagnostic Report ====="
append_txt "Target: $HOST"
append_txt "Generated: $(date)"
append_txt "====================================="

# Local system info
LOCAL_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me)
GATEWAY=$(ip route | grep default | awk '{print $3}')
DNS=$(grep 'nameserver' /etc/resolv.conf | awk '{print $2}' | paste -sd ',' -)

append_txt "\n[+] System Info"
append_txt "Local IP: $LOCAL_IP"
append_txt "Public IP: $PUBLIC_IP"
append_txt "Gateway: $GATEWAY"
append_txt "DNS: $DNS"

append_json "local_ip" "$LOCAL_IP"
append_json "public_ip" "$PUBLIC_IP"
append_json "gateway" "$GATEWAY"
append_json "dns" "$DNS"

append_csv "local_ip" "$LOCAL_IP"
append_csv "public_ip" "$PUBLIC_IP"
append_csv "gateway" "$GATEWAY"
append_csv "dns" "$DNS"

# Ping
append_txt "\n[+] Ping"
ping -c 4 "$HOST" > /dev/null 2>&1 && PING_RESULT="success" || PING_RESULT="failure"
append_txt "Ping result: $PING_RESULT"
append_json "ping" "$PING_RESULT"
append_csv "ping" "$PING_RESULT"

# Traceroute (first 5 lines)
append_txt "\n[+] Traceroute"
TRACEROUTE=$(traceroute -m 10 "$HOST" 2>&1 | head -n 5 | tr '\n' ';')
append_txt "$TRACEROUTE"
append_json "traceroute" "$TRACEROUTE"
append_csv "traceroute" "truncated"

# DNS lookup
append_txt "\n[+] DNS Lookup"
if command -v nslookup >/dev/null; then
  DNS_RES=$(nslookup "$HOST" | grep 'Address' | tail -n1 | awk '{print $2}')
else
  DNS_RES=$(dig +short "$HOST" | head -n1)
fi
append_txt "Resolved IP: $DNS_RES"
append_json "dns_lookup" "$DNS_RES"
append_csv "dns_lookup" "$DNS_RES"

# HTTP(S)
append_txt "\n[+] HTTP(S) Status"
HTTP_CODE=$(curl -Is --max-time 5 "http://$HOST" | head -n 1 | tr -d '\r\n')
HTTPS_CODE=$(curl -Is --max-time 5 "https://$HOST" | head -n 1 | tr -d '\r\n')

append_txt "HTTP: $HTTP_CODE"
append_txt "HTTPS: $HTTPS_CODE"
append_json "http_status" "$HTTP_CODE"
append_json "https_status" "$HTTPS_CODE"
append_csv "http_status" "$HTTP_CODE"
append_csv "https_status" "$HTTPS_CODE"

# SSL expiry
append_txt "\n[+] SSL Certificate Expiry"
SSL_EXPIRY=$(echo | openssl s_client -servername "$HOST" -connect "$HOST:443" 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
append_txt "SSL expires: $SSL_EXPIRY"
append_json "ssl_expiry" "$SSL_EXPIRY"
append_csv "ssl_expiry" "$SSL_EXPIRY"

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
    STATUS=$(echo "$NMAP_UDP_OUT" | awk "/$PORT\/udp/"'{print $2}')
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

[[ "$FLAG" == "--txt" || "$FLAG" == "--all" ]] && echo "$txt_output" > "$TXT_OUT"
[[ "$FLAG" == "--json" || "$FLAG" == "--all" ]] && echo -e "$json_output" > "$JSON_OUT"
[[ "$FLAG" == "--csv" || "$FLAG" == "--all" ]] && echo "$csv_output" > "$CSV_OUT"

echo "Diagnostics complete. Output saved to:"
[[ "$FLAG" == "--txt" || "$FLAG" == "--all" ]] && echo "  - $TXT_OUT"
[[ "$FLAG" == "--json" || "$FLAG" == "--all" ]] && echo "  - $JSON_OUT"
[[ "$FLAG" == "--csv" || "$FLAG" == "--all" ]] && echo "  - $CSV_OUT"
echo "====================================="
