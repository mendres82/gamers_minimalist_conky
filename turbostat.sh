#!/bin/bash

if pgrep -f "turbostat.sh" | grep -v "$$" > /dev/null; then
    exit 0
fi

pkill -f "turbostat --Summary --quiet --show PkgWatt"
turbostat --Summary --quiet --show PkgWatt --interval 5 --out /tmp/turbostat.tmp &

(
while true; do
    if [ "$(tail -1 /tmp/turbostat.tmp)" = "0.00" ]; then
        pkill -f "turbostat --Summary --quiet --show PkgWatt"
        turbostat --Summary --quiet --show PkgWatt --interval 5 --out /tmp/turbostat.tmp &
    fi
    sleep 5
done
) &

exit 0

