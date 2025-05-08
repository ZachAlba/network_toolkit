#!/bin/bash

# =============================
# Security Scanner - Diagnostic Toolkit
# Author: Zachary Albanese
# =============================

HOST="$1"
FLAG="$2"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_DIR="./logs/$(date '+%Y-%m-%d')"
mkdir -p "$LOG_DIR"

BASENAME="security_${HOST//./_}_$TIMESTAMP"
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
  val=$(echo "$val" | sed 's/"/\\"/g' | tr -d '\r') # escape quotes + CR
  json_output+="    \"${key}\": \"${val}\",\n"
}

append_csv() { csv_output+="$TIMESTAMP,$HOST,$1,$2\n"; }

# -------- Banner Grabs --------

append_txt "[+] Port Banner Grabs"

BANNERS=(22 21 25 80 443)
for PORT in "${BANNERS[@]}"; do
  BANNER=""
  if [[ "$PORT" == "443" ]]; then
    BANNER=$(echo | timeout 2 openssl s_client -connect "$HOST:$PORT" 2>/dev/null | grep -m1 "Server:" || echo "None")
  else
    BANNER=$(echo | timeout 2 nc "$HOST" "$PORT" 2>/dev/null | head -n 1 || echo "None")
  fi
  append_txt "Port $PORT: $BANNER"
  append_json "banner_$PORT" "$BANNER"
  append_csv "banner_$PORT" "$BANNER"
done

# -------- Database Exposure --------

append_txt "\n[+] Exposed Databases"

for DB in 6379 27017 9200 3306; do
  timeout 1 bash -c "echo > /dev/tcp/$HOST/$DB" 2>/dev/null && STATE="open" || STATE="closed"
  append_txt "Port $DB (likely $( [[ $DB == 6379 ]] && echo Redis || [[ $DB == 27017 ]] && echo Mongo || [[ $DB == 9200 ]] && echo Elasticsearch || echo MySQL )): $STATE"
  append_json "db_$DB" "$STATE"
  append_csv "db_$DB" "$STATE"
done

# -------- Security Headers --------

append_txt "\n[+] HTTP Header Security Check"
HEADERS=$(curl -sI --max-time 5 "http://$HOST")
for hdr in "Strict-Transport-Security" "X-Frame-Options" "Content-Security-Policy" "Access-Control-Allow-Origin"; do
  VAL=$(echo "$HEADERS" | grep -i "$hdr" | cut -d: -f2- | tr -d '\r\n')
  [ -z "$VAL" ] && VAL="missing"
  append_txt "$hdr: $VAL"
  append_json "header_$(echo $hdr | tr 'A-Z-' 'a-z_')" "$VAL"
  append_csv "$hdr" "$VAL"
done

# -------- Sensitive File Probes --------

append_txt "\n[+] Sensitive File Check"
FILES=("/robots.txt" "/sitemap.xml" "/.env" "/.git/config")
for path in "${FILES[@]}"; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$HOST$path")
  append_txt "$path: HTTP $CODE"
  append_json "file_$path" "$CODE"
  append_csv "$path" "$CODE"
done

# -------- PHP & phpMyAdmin Checks --------

append_txt "\n[+] PHP & phpMyAdmin Checks"

# phpinfo
PHPINFO=$(curl -s "http://$HOST/phpinfo.php" | grep -i "php version" | wc -l)
[[ "$PHPINFO" -gt 0 ]] && FOUND="exposed" || FOUND="not_found"
append_txt "/phpinfo.php: $FOUND"
append_json "phpinfo" "$FOUND"
append_csv "phpinfo" "$FOUND"

# phpMyAdmin
PMA_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$HOST/phpmyadmin/")
[[ "$PMA_CODE" == "200" ]] && PMA="exposed" || PMA="not_found"
append_txt "/phpmyadmin/: $PMA"
append_json "phpmyadmin" "$PMA"
append_csv "phpmyadmin" "$PMA"

# -------- Output --------

# Remove trailing comma
json_output=$(echo -e "$json_output" | sed '$s/,\s*$//')
json_output+="\n  }\n}"


[[ "$FLAG" == "--txt" || "$FLAG" == "--all" ]] && echo "$txt_output" >"$TXT_OUT"
[[ "$FLAG" == "--json" || "$FLAG" == "--all" ]] && echo -e "$json_output" >"$JSON_OUT"
[[ "$FLAG" == "--csv" || "$FLAG" == "--all" ]] && echo "$csv_output" >"$CSV_OUT"

echo "Security scan complete. Output saved to:"
[[ "$FLAG" == "--txt" || "$FLAG" == "--all" ]] && echo "  - $TXT_OUT"
[[ "$FLAG" == "--json" || "$FLAG" == "--all" ]] && echo "  - $JSON_OUT"
[[ "$FLAG" == "--csv" || "$FLAG" == "--all" ]] && echo "  - $CSV_OUT"
echo "====================================="
