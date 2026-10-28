#!/bin/bash

# Path to the Conky configuration file
CONKY_CONFIG="$HOME/.config/conky/conky.conf"

# Set language to C locale for consistent behavior
export LC_ALL=C

# Function to fetch the latest Tumbleweed snapshot version
fetch_version() {
    local version
    
    # Try openSUSE Factory mailing list feed first (more reliable)
    version=$(curl -fs --max-time 5 "https://lists.opensuse.org/archives/list/factory@lists.opensuse.org/feed/" | grep -oP '(?<=<title>).*?(?=</title>)' | grep -E 'Tumbleweed snapshot.*release' | head -1 | grep -Poh '\d+')
    
    # Fallback to openQA dashboard if needed
    if [[ -z "$version" ]]; then
        version=$(curl -fs --max-time 5 "https://factory-dashboard.opensuse.org/" | grep 'https://download.opensuse.org/tumbleweed/iso/' | head -1 | grep -Poh '\d+')
        curl -fs --max-time 5 "https://download.opensuse.org/tumbleweed/iso/Changes.$version.txt" > /dev/null 2>&1 || version=""
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

# Update amdgpu_top stats/processes about once per second (-s 1000 paces the loop).
# One jq pass: first line = stats, following lines = top GPU processes.
while true; do
    if ! amdgpu_top --json -n 1 -s 1000 --no-pc 2>/dev/null | jq -r '
      .devices[0] as $d
      | (
          [
            ($d.gpu_activity.GFX.value // 0),
            ($d.VRAM["Total VRAM Usage"].value // 0),
            ($d.VRAM["Total VRAM"].value // 0),
            ($d.Sensors.GFX_SCLK.value // 0),
            ($d.Sensors.GFX_MCLK.value // 0)
          ] | @tsv
        ),
        (
          [
            $d.fdinfo // {} | to_entries[] |
            {
              name: ((.value.name // "?")[:15]),
              gfx: (.value.usage.usage.GFX.value // 0)
            }
          ]
          | sort_by(-.gfx)
          | .[:3][]
          | [.name, .gfx]
          | @tsv
        )
    ' | {
        IFS= read -r stats || exit 1
        printf '%s\n' "$stats" > /tmp/amdgpu_top.1.tmp
        cat > /tmp/amdgpu_gpu_top.1.tmp
    }; then
        sleep 1
        continue
    fi
    mv -f /tmp/amdgpu_top.1.tmp /tmp/amdgpu_top.tmp
    mv -f /tmp/amdgpu_gpu_top.1.tmp /tmp/amdgpu_gpu_top.tmp
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
        conky -d -c "$CONKY_CONFIG" -x -3410 -y 40
    fi
fi

