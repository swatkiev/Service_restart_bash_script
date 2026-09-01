#!/bin/bash

# Script to monitor service errors with strict timing and limits
SERVICE_NAME="your_service_name"
LOG_FILE="/var/log/syslog"
JOURNAL_UNIT="your_service_name"
MAX_RESTARTS=1              # Max 1 restart per hour
RESTART_COOLDOWN=3600       # 1 hour (3600 seconds) between restarts
CHECK_INTERVAL=300          # 5 minutes between checks
STATE_DIR="/var/lib/your_service_name-monitor"

# Combined error patterns
ERROR_PATTERNS=(
    'add your error patterns'
)

# State files
RESTART_COUNT_FILE="$STATE_DIR/restart_count"
LAST_RESTART_FILE="$STATE_DIR/last_restart"
LAST_ERROR_FILE="$STATE_DIR/last_error"
LAST_CHECK_FILE="$STATE_DIR/last_check"
LOCK_FILE="$STATE_DIR/monitor.lock"

# Initialize files
mkdir -p "$STATE_DIR"
[ ! -f "$RESTART_COUNT_FILE" ] && echo "0" > "$RESTART_COUNT_FILE"
[ ! -f "$LAST_RESTART_FILE" ] && echo "0" > "$LAST_RESTART_FILE"
[ ! -f "$LAST_ERROR_FILE" ] && echo "0" > "$LAST_ERROR_FILE"
[ ! -f "$LAST_CHECK_FILE" ] && echo "0" > "$LAST_CHECK_FILE"

# Lock file
[ -f "$LOCK_FILE" ] && { echo "Script is already running"; exit 1; }
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Function to update last_check with timestamp
update_last_check() {
    local timestamp=$(date +%s)
    echo "$timestamp" > "$LAST_CHECK_FILE"
    # Force file update even if content is same
    echo "$timestamp" > "$LAST_CHECK_FILE.tmp"
    mv "$LAST_CHECK_FILE.tmp" "$LAST_CHECK_FILE"
}

# Check if we can restart (with proper reset after 1 hour)
can_restart() {
    local current_time=$(date +%s)
    local count=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo "0")
    local last_restart=$(cat "$LAST_RESTART_FILE" 2>/dev/null || echo "0")

    # Reset count if more than 1 hour has passed
    if [ $((current_time - last_restart)) -ge $RESTART_COOLDOWN ]; then
        echo "0" > "$RESTART_COUNT_FILE"
        count=0
    fi

    # Check if we've hit the restart limit
    if [ "$count" -ge "$MAX_RESTARTS" ]; then
        return 1
    fi

    # Check cooldown period
    if [ $((current_time - last_restart)) -lt $RESTART_COOLDOWN ]; then
        return 1
    fi

    return 0
}

# Restart with safety checks
restart_your_service_name() {
    if ! can_restart; then
        return 1
    fi

    local current_time=$(date +%s)
    echo "$current_time" > "$LAST_ERROR_FILE"

    systemctl restart "$SERVICE_NAME"

    for i in {1..60}; do
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            local count=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo "0")
            echo "$((count + 1))" > "$RESTART_COUNT_FILE"
            echo "$current_time" > "$LAST_RESTART_FILE"
            return 0
        fi
        sleep 1
    done

    return 1
}

# Check logs for new errors (last 5 minutes only)
check_logs() {
    local current_time=$(date +%s)
    local last_error=$(cat "$LAST_ERROR_FILE" 2>/dev/null || echo "0")
    local five_minutes_ago=$(date -d "5 minutes ago" +%s)

    # Only check if we haven't seen an error recently
    if [ $((current_time - last_error)) -lt $RESTART_COOLDOWN ]; then
        return 1
    fi

    # Check journal logs (most reliable)
    journalctl -u "$SERVICE_NAME" --since "@$five_minutes_ago" 2>/dev/null | while IFS= read -r line; do
        for pattern in "${ERROR_PATTERNS[@]}"; do
            if echo "$line" | grep -q "$pattern"; then
                if restart_your_service_name; then
                    return 0
                fi
            fi
        done
    done

    # Check system logs (fallback)
    if [ -f "$LOG_FILE" ]; then
        tail -n +1 "$LOG_FILE" 2>/dev/null | awk -v start_time="$five_minutes_ago" '$1" "$2" "$3 >= start_time' | while IFS= read -r line; do
            for pattern in "${ERROR_PATTERNS[@]}"; do
                if echo "$line" | grep -q "$pattern"; then
                    if restart_your_service_name; then
                        return 0
                    fi
                fi
            done
        done
    fi

    return 1
}

# Main loop with exact 5-minute intervals
main() {
    update_last_check  # Initial update

    while true; do
        # Wait until next check interval (exactly 5 minutes)
        local sleep_time=$((CHECK_INTERVAL - ($(date +%s) % CHECK_INTERVAL)))
        sleep $sleep_time

        # Update last_check (GUARANTEED)
        update_last_check

        # Perform the check
        check_logs

        # Update last_check again (redundant but guaranteed)
        update_last_check
    done
}

main
