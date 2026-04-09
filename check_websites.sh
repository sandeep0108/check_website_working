#!/bin/bash

# Website checker script
# Usage: ./check_websites.sh

# Log file location (always next to this script, regardless of working directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/website_check.log"
WORK_DIR="/tmp/website_check_$$"

# List of websites to check
WEBSITES=(
"google.com"
"yahoo.com"
)

# Color codes for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'

trap 'rm -rf "$WORK_DIR"' EXIT

# Convert a site URL to a safe temp filename
site_to_file() {
    local encoded
    encoded=$(printf '%s' "$1" | sed 's|/|__|g; s|\.|_|g')
    printf '%s' "$WORK_DIR/$encoded"
}

# check_ssl <hostname>
# Prints number of days until SSL cert expires, or "FAILED" on error.
check_ssl() {
    [[ -z "$1" ]] && echo "FAILED" && return 1

    local host=$1
    local expiry_raw
    expiry_raw=$(timeout 10 openssl s_client -connect "${host}:443" \
        -servername "$host" </dev/null 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null \
        | cut -d= -f2-)

    [ -z "$expiry_raw" ] && echo "FAILED" && return

    local expiry_epoch
    # NOTE: date -d requires GNU coreutils (Linux). Not compatible with macOS.
    expiry_epoch=$(date -d "$expiry_raw" +%s 2>/dev/null)
    [ -z "$expiry_epoch" ] && echo "FAILED" && return

    local now
    now=$(date +%s)
    local diff=$(( expiry_epoch - now ))
    if (( diff < 0 )); then
        echo $(( (diff - 86399) / 86400 ))
    else
        echo $(( diff / 86400 ))
    fi
}

# Function to check website
check_website() {
    local url=$1
    local host="${url%%/*}"
    local tmpfile
    tmpfile=$(site_to_file "$url")
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local curl_out
    curl_out=$(curl -s -o /dev/null \
        -w "%{http_code} %{time_total}" \
        --connect-timeout 10 -L \
        "https://$url" 2>/dev/null)
    local http_code="${curl_out%% *}"
    local time_total
    time_total=$(printf "%.2f" "${curl_out##* }" 2>/dev/null || echo "0.00")

    if [[ "$http_code" =~ ^[0-9]+$ ]] && \
       [ "$http_code" -ge 200 ] && [ "$http_code" -lt 500 ]; then

        local ssl_days
        ssl_days=$(check_ssl "$host")

        # Build log-friendly SSL string
        local ssl_log
        if [ "$ssl_days" = "FAILED" ]; then
            ssl_log="SSL: CHECK FAILED"
        elif [ "$ssl_days" -le 0 ] 2>/dev/null; then
            ssl_log="SSL: EXPIRED"
        elif [ "$ssl_days" -le 30 ] 2>/dev/null; then
            ssl_log="SSL: WARNING ${ssl_days} days"
        else
            ssl_log="SSL: ${ssl_days} days"
        fi

        # Temp file: line1=status, line2=http_code, line3=time, line4=ssl_days, line5=log_entry
        printf '%s\n%s\n%s\n%s\n[%s] %s - UP (HTTP: %s, %ss, %s)\n' \
            "UP" "$http_code" "$time_total" "$ssl_days" \
            "$timestamp" "$url" "$http_code" "$time_total" "$ssl_log" \
            > "$tmpfile"
    else
        [ -z "$http_code" ] && http_code="000"
        local log_entry
        if [ "$http_code" = "000" ]; then
            log_entry="[$timestamp] $url - DOWN (HTTP: 000, timeout)"
        else
            log_entry="[$timestamp] $url - DOWN (HTTP: $http_code)"
        fi
        printf '%s\n%s\n\n\n%s\n' "DOWN" "$http_code" "$log_entry" > "$tmpfile"
    fi
}

# Main execution
mkdir -p "$WORK_DIR"

echo "========================================="
echo "Website Availability Checker"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo ""

total=${#WEBSITES[@]}

# Launch all checks in parallel
for website in "${WEBSITES[@]}"; do
    check_website "$website" &
done

# Wait for all background jobs to complete
wait

up=0
down=0
ssl_issues=0

# Print results in original site order; append log entries sequentially
for website in "${WEBSITES[@]}"; do
    tmpfile=$(site_to_file "$website")

    if [ ! -f "$tmpfile" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $website - ERROR (no result file)" >> "$LOG_FILE"
        echo -e "${RED}[✗]${NC} $website — ERROR (no result)"
        ((down++))
        continue
    fi

    status=$(sed -n '1p' "$tmpfile")
    http_code=$(sed -n '2p' "$tmpfile")
    time_total=$(sed -n '3p' "$tmpfile")
    ssl_days=$(sed -n '4p' "$tmpfile")
    log_entry=$(sed -n '5p' "$tmpfile")

    # Append log entry in order (no concurrent writes)
    echo "$log_entry" >> "$LOG_FILE"

    if [ "$status" = "UP" ]; then
        ((up++))

        if [ "$ssl_days" = "FAILED" ]; then
            ssl_str="SSL: CHECK FAILED"
            ssl_color="$RED"
            ((ssl_issues++))
        elif [ -z "$ssl_days" ]; then
            ssl_str="SSL: UNKNOWN"
            ssl_color="$YELLOW"
            ((ssl_issues++))
        elif [ "$ssl_days" -le 0 ] 2>/dev/null; then
            ssl_str="SSL: EXPIRED"
            ssl_color="$RED"
            ((ssl_issues++))
        elif [ "$ssl_days" -le 30 ] 2>/dev/null; then
            ssl_str="SSL: WARNING ${ssl_days} days"
            ssl_color="$YELLOW"
            ((ssl_issues++))
        else
            ssl_str="SSL: ${ssl_days} days"
            ssl_color="$GREEN"
        fi

        echo -e "${GREEN}[✓]${NC} $website — UP (HTTP: $http_code, ${time_total}s) | ${ssl_color}${ssl_str}${NC}"
    else
        ((down++))
        if [ "$http_code" = "000" ] || [ -z "$http_code" ]; then
            echo -e "${RED}[✗]${NC} $website — DOWN (HTTP: 000, timeout)"
        else
            echo -e "${RED}[✗]${NC} $website — DOWN (HTTP: $http_code)"
        fi
    fi
done

echo ""
echo "========================================="
echo "Summary:"
echo "Total sites checked: $total"
echo -e "UP:   ${GREEN}$up${NC}"
echo -e "DOWN: ${RED}$down${NC}"
if [ "$ssl_issues" -gt 0 ]; then
    echo -e "${YELLOW}SSL issues (expired or expiring ≤30 days): $ssl_issues${NC}"
fi
echo "Log saved to: $LOG_FILE"
echo "========================================="
