#!/bin/bash
# Install all launchd services

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHD_DIR="$PROJECT_DIR/launchd"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

echo "🚀 Installing server monitor services..."

# Create logs directory
mkdir -p "$PROJECT_DIR/logs"

# Kill any existing node https-server processes
pkill -f "https-server.js" 2>/dev/null

# Install each plist
for plist in "$LAUNCHD_DIR"/*.plist; do
    if [ -f "$plist" ]; then
        name=$(basename "$plist")
        echo "  Installing $name..."
        
        # Unload if already loaded
        launchctl unload "$LAUNCH_AGENTS/$name" 2>/dev/null
        
        # Copy to LaunchAgents
        cp "$plist" "$LAUNCH_AGENTS/"
        
        # Load the service
        launchctl load "$LAUNCH_AGENTS/$name"
        
        echo "  ✅ $name installed and started"
    fi
done

echo ""
echo "📊 Service status:"
launchctl list | grep salient || echo "  No services found"

echo ""
echo "📁 Logs at: $PROJECT_DIR/logs/"
echo "🔧 To check status: $SCRIPT_DIR/status.sh"
