#!/bin/bash

# Path to the Conky configuration file
CONKY_CONFIG="$HOME/.config/conky/conky.conf"

# Set language to C locale for consistent behavior
LANG=C

# Function to fetch the latest Tumbleweed snapshot version
fetch_version() {
    local version
    
    # Try openSUSE Factory mailing list feed first (more reliable)
    version=$(curl -s --max-time 10 "https://lists.opensuse.org/archives/list/factory@lists.opensuse.org/feed/" | grep -oP '(?<=<title>).*?(?=</title>)' | grep -E 'Tumbleweed snapshot.*release' | head -1 | grep -Poh '\d+')
    
    # Fallback to openQA dashboard if needed
    [[ -z "$version" ]] && version=$(curl -s --max-time 10 "https://factory-dashboard.opensuse.org/" | grep 'https://download.opensuse.org/tumbleweed/iso/' | head -1 | grep -Poh '\d+')
    
    # Write snapshot version to file
    [[ -n "$version" ]] && echo "$version" > /tmp/version_id.tmp
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

# Start background process to update radeontop stats every 5 seconds
while sleep 5; do
    radeontop -d- -l1 | tail -1 > /tmp/radeontop.1.tmp &&
    mv -f /tmp/radeontop.1.tmp /tmp/radeontop.tmp
done &

# Wait for system to settle
sleep 20

# Run turbostat script with elevated privileges and start Conky if successful
if pkexec ~/.config/conky/conkyx-daemon.sh; then
    # Wait for turbostat to initialize
    sleep 5
    # Start main Conky instance
    conky -c "$CONKY_CONFIG"
    # Start second Conky instance with offset position (for multi-monitor setup)
    conky -c "$CONKY_CONFIG" -x -3410 -y 50
fi

