#!/bin/bash

# =============================
# Network Diagnostic Toolkit
# Author: Zachary Albanese
# =============================

HOST="$1"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_DIR="./logs/$(date '+%Y-%m-%d')"
OUTFILE="$LOG_DIR/report_${HOST//./_}_$TIMESTAMP.txt"

# Ensure host is provided
if [ -z "$HOST" ]; then
  echo "Usage: $0 <hostname_or_ip>"
  exit 1
fi

# Create log directory
mkdir -p "$LOG_DIR"

# Begin report
{
  echo "===== Network Diagnostic Report ====="
  echo "Target: $HOST"
  echo "Generated: $(date)"
  echo "====================================="
  echo ""

  echo "[+] Local System Info"
  echo "Hostname: $(hostname)"
  echo "Local IP: $(hostname -I | awk '{print $1}')"
  echo "Public IP: $(curl -s ifconfig.me)"
  echo "Gateway: $(ip route | grep default | awk '{print $3}')"
  echo "DNS: $(grep 'nameserver' /etc/resolv.conf | awk '{print $2}' | paste -sd ',' -)"
  echo ""

  echo "[+] Pinging Host..."
  ping -c 4 "$HOST"
  echo ""

  echo "[+] Traceroute to Host..."
  (traceroute "$HOST" || command -v mtr && mtr -rwzbc 10 "$HOST")
  echo ""

  echo "[+] DNS Lookup"
  nslookup "$HOST" || dig "$HOST"
  echo ""

  echo "[+] HTTP(S) Reachability"
  curl -Is --max-time 5 "http://$HOST" | head -n 1
  curl -Is --max-time 5 "https://$HOST" | head -n 1
  echo ""

  echo "[+] SSL Certificate Check"
  echo | openssl s_client -servername "$HOST" -connect "$HOST:443" 2>/dev/null | openssl x509 -noout -dates
  echo ""

  if command -v nc >/dev/null; then
  echo "[+] Fast port scan using netcat..."
  for PORT in 22 80 443 3306 5432 8080; do
    nc -z -w1 "$HOST" $PORT && echo "Port $PORT open" || echo "Port $PORT closed"
  done
else
  echo "[+] Fallback scan (slower)..."
  for PORT in 22 80 443 3306 5432 8080; do
    timeout 1 bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null &&
      echo "Port $PORT open" || echo "Port $PORT closed"
  done
fi
  echo ""

} >> "$OUTFILE"

echo "Diagnostics complete. Report saved to: $OUTFILE"
