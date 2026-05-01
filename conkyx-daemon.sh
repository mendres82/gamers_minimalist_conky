#!/bin/bash

# Set language to C locale for consistent behavior
export LC_ALL=C

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

# Start turbostat in background to monitor package power consumption
turbostat --no-msr --Summary --quiet --show PkgWatt --interval 5 --out /tmp/turbostat.tmp &

# Start a background process to monitor turbostat
(
while true; do
    # Check if the last reading is "0.00" which indicates a potential issue
    # If found, restart turbostat process
    if [ "$(tail -1 /tmp/turbostat.tmp)" = "0.00" ]; then
        pkill -f "turbostat --no-msr --Summary --quiet --show PkgWatt"
        turbostat --no-msr --Summary --quiet --show PkgWatt --interval 5 --out /tmp/turbostat.tmp &
    fi
    sleep 5
done
) &

# Start a background process to monitor SMART status
(
while true; do
    /usr/sbin/smartctl -H /dev/nvme0n1 | grep "SMART overall-health" | awk -F': ' '{print $2}' > /tmp/smartctl.tmp
    sleep 3600
done
) &

# Exit the script while leaving the monitoring processes running in background
exit 0

