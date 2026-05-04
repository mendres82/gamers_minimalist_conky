#!/bin/bash

# Path to the Conky configuration file
CONKY_CONFIG="$HOME/.config/conky/conky.conf"

# Set language to C locale for consistent behavior
export LC_ALL=C

# Function to fetch the latest Tumbleweed snapshot version
fetch_version() {
    local version
    
    # Try openSUSE Factory mailing list feed first (more reliable)
    version=$(curl -fs --max-time 10 "https://lists.opensuse.org/archives/list/factory@lists.opensuse.org/feed/" | grep -oP '(?<=<title>).*?(?=</title>)' | grep -E 'Tumbleweed snapshot.*release' | head -1 | grep -Poh '\d+')
    
    # Fallback to openQA dashboard if needed
    if [[ -z "$version" ]]; then
        version=$(curl -fs --max-time 10 "https://factory-dashboard.opensuse.org/" | grep 'https://download.opensuse.org/tumbleweed/iso/' | head -1 | grep -Poh '\d+')
        curl -fs --max-time 10 "https://download.opensuse.org/tumbleweed/iso/Changes.$version.txt" > /dev/null 2>&1 || version=""
    fi
    
    # Write snapshot version to file
    echo "$version" > /tmp/version_id.tmp
}

script_name=$(basename "$0")

script_pgid=$(ps -o pgid= -p $$ | tr -d ' ')
old_pgids=$(ps -eo pgid,args | grep -E "$script_name" | grep -v "grep" | grep -v "$script_pgid" | awk '{print $1}' | sort -u)
old_pids=""

if [ -n "$old_pgids" ]; then
    pgid_pattern=$(echo $old_pgids | sed 's/ /|/g')
    old_pids=$(ps -eo pid,pgid,comm,args | awk -v pat="^($pgid_pattern)$" '$2 ~ pat' | grep -vE "gnome-session|gsd-|systemd" | awk '{print $1}' | sort -rnu)
fi

if [ -n "$old_pids" ]; then
    for pid in $old_pids; do
        kill -TERM "$pid" 2>/dev/null
    done
fi

killall conky 2>/dev/null

# Fetch version initially
fetch_version

# Start background process to update version every hour
while sleep 3600; do
    fetch_version
done &

# Start background process to update sensors stats every second
while sleep 1; do
    LC_ALL=C.UTF-8 sensors > /tmp/sensors.1.tmp &&
    mv -f /tmp/sensors.1.tmp /tmp/sensors.tmp
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
    conky -d -c "$CONKY_CONFIG"
    # Start second Conky instance with offset position (for multi-monitor setup)
    if [ "$(grep -l "^connected$" /sys/class/drm/card*-*/status | wc -l)" -ge 2 ]; then
        conky -d -c "$CONKY_CONFIG" -x -3410 -y 50
    fi
fi

