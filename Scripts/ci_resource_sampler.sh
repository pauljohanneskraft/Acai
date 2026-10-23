#!/bin/bash
# Samples host load, memory, swap and disk every 5s into <DIR>/samples.log, to time-align with journey stalls (#410).
#
# Usage: Scripts/ci_resource_sampler.sh start|stop <DIR>
set -uo pipefail

ACTION="${1:?usage: Scripts/ci_resource_sampler.sh start|stop <DIR>}"
DIR="${2:?usage: Scripts/ci_resource_sampler.sh start|stop <DIR>}"
OUT="$DIR/samples.log"

case "$ACTION" in
    start)
        mkdir -p "$DIR"
        { echo "boot: $(sysctl -n kern.boottime)"; sysctl hw.ncpu hw.memsize; } > "$OUT"
        nohup "$0" loop "$DIR" > /dev/null 2>&1 &
        echo $! > "$DIR/sampler.pid"
        echo "▸ Sampling resources into $OUT (pid $!)"
        ;;
    loop)
        while true; do
            {
                echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ)"
                sysctl vm.loadavg vm.swapusage kern.memorystatus_vm_pressure_level
                memory_pressure -Q
                vm_stat | grep -E "free|active|wired|compressor|Compressions|Decompressions|Pageins|Pageouts|Swap"
                # Both tools' first report averages since boot; the second covers the last second.
                iostat -d -K -c 2 -w 1
                top -l 2 -s 1 -n 12 -o cpu -stats pid,command,cpu,mem,state | tail -n 13
            } >> "$OUT" 2>&1
            sleep 3
        done
        ;;
    stop)
        [ -f "$DIR/sampler.pid" ] && kill "$(cat "$DIR/sampler.pid")" 2>/dev/null
        rm -f "$DIR/sampler.pid"
        [ -f "$OUT" ] || exit 0
        {
            echo "### Host resources"
            echo
            echo "- samples: $(grep -c '^=== ' "$OUT")"
            echo "- peak swap used: $(grep -o 'used = [0-9.]*M' "$OUT" | sort -t= -k2 -n | tail -1)"
            echo "- memory pressure level counts (1 normal, 2 warn, 4 critical):" \
                "$(grep 'kern.memorystatus_vm_pressure_level' "$OUT" | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
            echo "- peak 1-minute load: $(grep -o 'vm.loadavg: { [0-9.]*' "$OUT" | cut -d' ' -f3 | sort -n | tail -1)"
        } >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
        ;;
    *)
        echo "✗ Unknown action '$ACTION'" >&2
        exit 1
        ;;
esac
