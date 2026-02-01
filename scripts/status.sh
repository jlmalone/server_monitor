#!/bin/bash
# status.sh - Show status of all monitored services
# Usage: ./status.sh [--json]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/services.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║              🖥️  SERVER MONITOR STATUS                        ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Timestamp:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

check_launchd_service() {
    local identifier=$1
    local name=$2
    local port=$3
    local health_url=$4
    
    echo -e "${BOLD}$name${NC}"
    echo -e "  LaunchD ID: ${CYAN}$identifier${NC}"
    
    # Check if loaded
    local status=$(launchctl list 2>/dev/null | grep "$identifier")
    
    if [ -n "$status" ]; then
        local pid=$(echo "$status" | awk '{print $1}')
        local exit_code=$(echo "$status" | awk '{print $2}')
        
        if [ "$pid" != "-" ] && [ "$pid" != "0" ]; then
            echo -e "  Status:     ${GREEN}● RUNNING${NC} (PID: $pid)"
            
            # Check port
            if [ -n "$port" ]; then
                local port_check=$(netstat -an 2>/dev/null | grep -E "LISTEN.*\.$port " | head -1)
                if [ -n "$port_check" ]; then
                    echo -e "  Port:       ${GREEN}● $port listening${NC}"
                else
                    echo -e "  Port:       ${YELLOW}○ $port (checking...)${NC}"
                fi
            fi
            
            # Health check via curl
            if [ -n "$health_url" ]; then
                local response=$(curl -sk --max-time 3 "$health_url" 2>/dev/null | head -c 100)
                if [ -n "$response" ]; then
                    echo -e "  Health:     ${GREEN}● Responding${NC}"
                else
                    echo -e "  Health:     ${YELLOW}○ No response${NC}"
                fi
            fi
        else
            echo -e "  Status:     ${RED}○ STOPPED${NC} (exit: $exit_code)"
        fi
    else
        echo -e "  Status:     ${RED}○ NOT LOADED${NC}"
    fi
    
    # Show log info
    local short_name="${identifier##*.}"
    local log_file="$PROJECT_DIR/logs/${short_name}.log"
    if [ -f "$log_file" ]; then
        local log_size=$(ls -lh "$log_file" 2>/dev/null | awk '{print $5}')
        local last_mod=$(stat -f "%Sm" -t "%H:%M" "$log_file" 2>/dev/null)
        echo -e "  Log:        $log_file (${log_size}, last: ${last_mod})"
    fi
    
    echo ""
}

check_process() {
    local pattern=$1
    local name=$2
    local port=$3
    
    echo -e "${BOLD}$name${NC}"
    echo -e "  Process:    ${CYAN}$pattern${NC}"
    
    local pid=$(pgrep -f "$pattern" 2>/dev/null | head -1)
    
    if [ -n "$pid" ]; then
        echo -e "  Status:     ${GREEN}● RUNNING${NC} (PID: $pid)"
        
        if [ -n "$port" ]; then
            local port_check=$(netstat -an 2>/dev/null | grep -E "LISTEN.*\.$port ")
            if [ -n "$port_check" ]; then
                echo -e "  Port:       ${GREEN}● $port listening${NC}"
            else
                echo -e "  Port:       ${YELLOW}○ $port not detected${NC}"
            fi
        fi
    else
        echo -e "  Status:     ${RED}○ NOT RUNNING${NC}"
    fi
    echo ""
}

show_all_jmalone_services() {
    echo -e "${BOLD}${BLUE}═══ All jmalone LaunchD Services ═══${NC}"
    echo ""
    
    local services=$(launchctl list 2>/dev/null | grep "jmalone")
    
    if [ -n "$services" ]; then
        echo "$services" | while read line; do
            local pid=$(echo "$line" | awk '{print $1}')
            local exit=$(echo "$line" | awk '{print $2}')
            local name=$(echo "$line" | awk '{print $3}')
            
            if [ "$pid" != "-" ] && [ "$pid" != "0" ]; then
                echo -e "  ${GREEN}●${NC} $name (PID: $pid)"
            else
                echo -e "  ${RED}○${NC} $name (exit: $exit)"
            fi
        done
    else
        echo -e "  ${YELLOW}No jmalone services found${NC}"
    fi
    echo ""
}

show_active_ports() {
    echo -e "${BOLD}${BLUE}═══ Active Development Ports ═══${NC}"
    echo ""
    
    # Check common dev ports
    local found=0
    for port in 3000 3001 3333 3443 3444 3445 4000 5000 8000 8080 8443 9000; do
        local listeners=$(netstat -an 2>/dev/null | grep -E "LISTEN.*\.$port ")
        if [ -n "$listeners" ]; then
            echo -e "  ${GREEN}●${NC} Port $port - in use"
            ((found++))
        fi
    done
    
    if [ $found -eq 0 ]; then
        echo -e "  ${YELLOW}No common dev ports in use${NC}"
    fi
    echo ""
}

show_summary() {
    echo -e "${BOLD}${BLUE}═══ Summary ═══${NC}"
    
    local total=$(launchctl list 2>/dev/null | grep -c "jmalone" || echo "0")
    local running=$(launchctl list 2>/dev/null | grep "jmalone" | awk '$1 != "-" && $1 != "0"' | wc -l | tr -d ' ')
    local stopped=$((total - running))
    
    echo "  Total services: $total"
    echo -e "  Running:        ${GREEN}$running${NC}"
    echo -e "  Stopped:        ${RED}$stopped${NC}"
    echo ""
    
    if [ "$stopped" -eq 0 ] && [ "$total" -gt 0 ]; then
        echo -e "  ${GREEN}✓ All services healthy!${NC}"
    elif [ "$total" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠ No services installed. Run: ./install.sh${NC}"
    else
        echo -e "  ${YELLOW}⚠ Some services need attention${NC}"
    fi
    echo ""
}

show_quick_commands() {
    echo -e "${BOLD}${BLUE}═══ Quick Commands ═══${NC}"
    echo "  View logs:    tail -f $PROJECT_DIR/logs/*.log"
    echo "  Install:      $SCRIPT_DIR/install.sh"
    echo "  Uninstall:    $SCRIPT_DIR/uninstall.sh"
    echo "  Monitor:      $SCRIPT_DIR/monitor.sh"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

print_header

echo -e "${BOLD}${BLUE}═══ Monitored Services ═══${NC}"
echo ""

# Check our known services
check_launchd_service "com.jmalone.redo-https" "Redo HTTPS Server" "3443" "https://localhost:3443"
check_launchd_service "com.clawdbot.gateway" "Clawdbot Gateway" "3333" "http://localhost:3333/health"

echo -e "${BOLD}${BLUE}═══ Additional Processes ═══${NC}"
echo ""
check_process "log-server" "Redo Log Server" "3444"
check_process "debug-server" "Redo Debug Server" "3445"

show_all_jmalone_services
show_active_ports
show_summary
show_quick_commands
