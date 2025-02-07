#!/bin/bash

# Find and kill any other running instances of this script
# This ensures only one instance runs at a time
OLD_PIDS=$(pgrep -f "turbostat.sh" | grep -v "$$")
if [ ! -z "$OLD_PIDS" ]; then
    kill $OLD_PIDS 2>/dev/null
fi

# Kill any existing turbostat processes
pkill -f "turbostat --Summary --quiet --show PkgWatt"

# Start turbostat in background to monitor package power consumption
# --Summary: provides summary only
# --quiet: reduces output verbosity
# --show PkgWatt: shows package power consumption
# --interval 5: updates every 5 seconds
# Output is written to /tmp/turbostat.tmp
turbostat --Summary --quiet --show PkgWatt --interval 5 --out /tmp/turbostat.tmp &

# Start a background process to monitor turbostat
(
while true; do
    # Check if the last reading is "0.00" which indicates a potential issue
    # If found, restart turbostat process
    if [ "$(tail -1 /tmp/turbostat.tmp)" = "0.00" ]; then
        pkill -f "turbostat --Summary --quiet --show PkgWatt"
        turbostat --Summary --quiet --show PkgWatt --interval 5 --out /tmp/turbostat.tmp &
    fi
    sleep 5
done
) &

# Exit the script while leaving the monitoring processes running in background
exit 0

