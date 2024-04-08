#!/bin/bash
killall -s SIGKILL turbostat; turbostat --Summary --quiet --show PkgWatt --interval 5 --out /tmp/turbostat.tmp &

