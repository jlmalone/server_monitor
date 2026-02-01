#!/bin/bash

# Server Monitor Uninstaller

echo "🗑️  Uninstalling Server Monitor..."

# 1. Quit App
killall ServerMonitor 2>/dev/null || true

# 2. Remove App
if [ -d "/Applications/ServerMonitor.app" ]; then
    rm -rf "/Applications/ServerMonitor.app"
    echo "✅ Removed Application"
fi

# 3. Remove CLI binary
if [ -f "/usr/local/bin/sm" ]; then
    rm "/usr/local/bin/sm"
    echo "✅ Removed CLI tool"
fi

# 4. Remove Configuration (Optional - ask user?)
# For now, we leave config/logs to be safe, or just print typical paths
echo "ℹ️  Note: Configuration and logs were NOT removed from:"
echo "   ~/Library/Application Support/ServerMonitor"
echo "   ~/ios_code/server_monitor/logs"

echo "✅ Uninstall complete."
