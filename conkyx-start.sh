#!/bin/bash
killall -s SIGKILL sleep;
killall -s SIGKILL conky;
curl -s https://lists.opensuse.org/archives/list/factory@lists.opensuse.org/latest | grep -E 'Tumbleweed snapshot.*release' | head -1 | grep -Poh '\d+' >> /tmp/version_id.tmp; while sleep 3600; do curl -s https://lists.opensuse.org/archives/list/factory@lists.opensuse.org/latest | grep -E 'Tumbleweed snapshot.*release' | head -1 | grep -Poh '\d+' >> /tmp/version_id.tmp; done &
sleep 20
pkexec ~/.config/conky/turbostat.sh &&
sleep 5
conky -c ~/.config/conky/conky.conf -x -3410 -y 50
conky -c ~/.config/conky/conky.conf

