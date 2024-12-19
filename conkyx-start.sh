#!/bin/bash

CONKY_CONFIG="$HOME/.config/conky/conky.conf"

fetch_version() {
    local url="https://factory-dashboard.opensuse.org"
    curl -s "$url" | grep -E 'download.opensuse.org/tumbleweed/iso/' | head -1 | grep -Poh '\d+' > /tmp/version_id.tmp
}

killall -s SIGKILL sleep;
killall -s SIGKILL conky;

fetch_version
while sleep 3600; do
    fetch_version
done &

sleep 20

if pkexec ~/.config/conky/turbostat.sh; then
    sleep 5
    LANG=C conky -c "$CONKY_CONFIG"
    LANG=C conky -c "$CONKY_CONFIG" -x -3410 -y 50
fi

