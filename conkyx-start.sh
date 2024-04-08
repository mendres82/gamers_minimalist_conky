#!/bin/bash
killall -s SIGKILL conky; sleep 20 && pkexec ~/.config/conky/turbostat.sh && sleep 5 && conky -c ~/.config/conky/conky.conf && conky -c ~/.config/conky/conky.conf -x -3410 -y 30 &

