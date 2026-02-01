#!/bin/bash
# uninstall.sh - Remove all server monitor launchd services
# Usage: ./uninstall.sh [--keep-logs]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHD_DIR="$PROJECT_DIR/launchd"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

KEEP_LOGS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--keep-logs]"
            echo ""
            echo "Options:"
            echo "  --keep-logs    Keep log files after uninstalling services"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${YELLOW}🗑️  Uninstalling server monitor services...${NC}"
echo ""

# Track what we're removing
removed=0
failed=0

# Stop and unload each plist we manage
for plist in "$LAUNCHD_DIR"/*.plist; do
    if [ -f "$plist" ]; then
        name=$(basename "$plist")
        identifier=$(basename "$name" .plist)
        
        echo -e "  Removing ${identifier}..."
        
        # Check if it's loaded
        if launchctl list 2>/dev/null | grep -q "$identifier"; then
            # Stop first
            launchctl stop "$identifier" 2>/dev/null
            sleep 1
            
            # Unload
            if launchctl unload "$LAUNCH_AGENTS/$name" 2>/dev/null; then
                echo -e "    ${GREEN}✓${NC} Unloaded from launchctl"
            else
                echo -e "    ${YELLOW}⚠${NC} Was not loaded in launchctl"
            fi
        else
            echo -e "    ${YELLOW}⚠${NC} Not currently loaded"
        fi
        
        # Remove from LaunchAgents
        if [ -f "$LAUNCH_AGENTS/$name" ]; then
            rm "$LAUNCH_AGENTS/$name"
            echo -e "    ${GREEN}✓${NC} Removed from ~/Library/LaunchAgents/"
            ((removed++))
        else
            echo -e "    ${YELLOW}⚠${NC} Not found in ~/Library/LaunchAgents/"
        fi
        
        echo ""
    fi
done

# Kill any lingering processes
echo "Cleaning up lingering processes..."
pkill -f "https-server.js" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Killed https-server.js processes"
pkill -f "log-server.j" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Killed log-server processes"
pkill -f "debug-server" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Killed debug-server processes"
echo ""

# Handle logs
if [ "$KEEP_LOGS" = true ]; then
    echo -e "${YELLOW}📁 Keeping logs at: $PROJECT_DIR/logs/${NC}"
else
    if [ -d "$PROJECT_DIR/logs" ]; then
        # Move to trash instead of deleting
        if command -v trash &> /dev/null; then
            trash "$PROJECT_DIR/logs"
            echo -e "${GREEN}✓${NC} Moved logs to trash"
        else
            # Archive logs before removing
            archive_name="logs_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$PROJECT_DIR/$archive_name" -C "$PROJECT_DIR" logs 2>/dev/null
            rm -rf "$PROJECT_DIR/logs"
            echo -e "${GREEN}✓${NC} Archived logs to $archive_name and removed"
        fi
    fi
fi

echo ""
echo -e "${GREEN}✅ Uninstall complete!${NC}"
echo ""
echo "Removed $removed service(s)"
echo ""

# Verify nothing is running
echo "Verification:"
remaining=$(launchctl list 2>/dev/null | grep "jmalone" | grep -v "grep")
if [ -z "$remaining" ]; then
    echo -e "  ${GREEN}✓${NC} No jmalone services running"
else
    echo -e "  ${YELLOW}⚠${NC} Some services still present:"
    echo "$remaining" | sed 's/^/    /'
fi

echo ""
echo "To reinstall: $SCRIPT_DIR/install.sh"
