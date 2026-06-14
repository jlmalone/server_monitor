#!/bin/bash
# Simple server monitor - runs until Swift app is ready
# Usage: ./monitor.sh &

LOG_FILE=~/ios_code/server_monitor/monitor.log
CHECK_INTERVAL=5

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_alert() {
    local service=$1
    local message=$2

    # macOS notification
    osascript -e "display notification \"$message\" with title \"Server Monitor\" subtitle \"$service\""

    # Log
    log "ALERT: $service - $message"
}

check_launchd_service() {
    local identifier=$1
    local name=$2

    if launchctl list | grep -q "$identifier"; then
        return 0  # Running
    else
        return 1  # Stopped
    fi
}

check_process() {
    local process_name=$1
    local name=$2

    if pgrep -f "$process_name" > /dev/null; then
        return 0  # Running
    else
        return 1  # Stopped
    fi
}

restart_launchd() {
    local identifier=$1
    log "Restarting LaunchAgent: $identifier"
    launchctl stop "$identifier"
    sleep 2
    launchctl start "$identifier"
}

restart_process() {
    local start_command=$1
    log "Restarting process: $start_command"
    eval "$start_command"
}

# Service states
declare -A service_states
declare -A restart_counts

# Initialize
service_states=(
    ["clawdbot"]="unknown"
    ["https-server"]="unknown"
    ["log-server"]="unknown"
    ["debug-server"]="unknown"
)

log "=== Server Monitor Started ==="
log "Check interval: ${CHECK_INTERVAL}s"
log "Monitoring 4 services..."

while true; do
    # Check Clawdbot Gateway
    if check_launchd_service "com.clawdbot.gateway" "Clawdbot Gateway"; then
        if [ "${service_states[clawdbot]}" == "stopped" ]; then
            log "✅ Clawdbot Gateway is back up"
            send_alert "Clawdbot Gateway" "Service restored"
        fi
        service_states["clawdbot"]="running"
    else
        if [ "${service_states[clawdbot]}" != "stopped" ]; then
            log "❌ Clawdbot Gateway is DOWN"
            send_alert "Clawdbot Gateway" "Service is DOWN!"

            # Auto-restart
            restart_launchd "com.clawdbot.gateway"
        fi
        service_states["clawdbot"]="stopped"
    fi

    # Check HTTPS Server
    if check_process "https-server.js" "Redo HTTPS Server"; then
        if [ "${service_states[https-server]}" == "stopped" ]; then
            log "✅ HTTPS Server is back up"
            send_alert "HTTPS Server" "Service restored"
        fi
        service_states["https-server"]="running"
    else
        if [ "${service_states[https-server]}" != "stopped" ]; then
            log "❌ HTTPS Server is DOWN"
            send_alert "HTTPS Server" "Service is DOWN!"

            # Auto-restart (if LaunchAgent exists)
            if [ -f ~/Library/LaunchAgents/com.redo.https-server.plist ]; then
                restart_launchd "com.redo.https-server"
            else
                log "⚠️  No LaunchAgent - manual restart needed"
            fi
        fi
        service_states["https-server"]="stopped"
    fi

    # Check Log Server
    if check_process "log-server.j" "Redo Log Server"; then
        service_states["log-server"]="running"
    else
        if [ "${service_states[log-server]}" != "stopped" ]; then
            log "⚠️  Log Server is down (non-critical)"
        fi
        service_states["log-server"]="stopped"
    fi

    # Check Debug Server
    if check_process "debug-server" "Redo Debug Server"; then
        service_states["debug-server"]="running"
    else
        if [ "${service_states[debug-server]}" != "stopped" ]; then
            log "⚠️  Debug Server is down (non-critical)"
        fi
        service_states["debug-server"]="stopped"
    fi

    # Status summary every 10 checks
    if [ $((SECONDS % 50)) -eq 0 ]; then
        log "Status: Clawdbot=${service_states[clawdbot]} HTTPS=${service_states[https-server]} Log=${service_states[log-server]} Debug=${service_states[debug-server]}"
    fi

    sleep "$CHECK_INTERVAL"
done
