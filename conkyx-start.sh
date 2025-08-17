#!/bin/bash

# Path to the Conky configuration file
CONKY_CONFIG="$HOME/.config/conky/conky.conf"

# Function to fetch the latest Tumbleweed snapshot version
fetch_version() {
    # URL for the openSUSE Factory mailing list
    local url="https://factory-dashboard.opensuse.org/"
    # Fetch the page, find the latest snapshot release, extract version number and save to temp file
    curl -s "$url" | grep 'https://download.opensuse.org/tumbleweed/iso/' | head -1 | grep -Poh '\d+' > /tmp/version_id.tmp
}

# Kill any existing sleep processes and Conky instances
killall -s SIGKILL sleep;
killall -s SIGKILL conky;

# Fetch version initially
fetch_version

# Start background process to update version every hour
while sleep 3600; do
    fetch_version
done &

# Wait for system to settle
sleep 20

# Run turbostat script with elevated privileges and start Conky if successful
if pkexec ~/.config/conky/turbostat.sh; then
    # Wait for turbostat to initialize
    sleep 5
    # Start main Conky instance
    LANG=C conky -c "$CONKY_CONFIG"
    # Start second Conky instance with offset position (for multi-monitor setup)
    LANG=C conky -c "$CONKY_CONFIG" -x -3410 -y 50
fi

