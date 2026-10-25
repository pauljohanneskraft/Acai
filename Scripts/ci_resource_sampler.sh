#!/bin/bash
# Samples host load, memory, swap and disk every ~6s into <DIR>/samples.log, to time-align with journey stalls (#410).
#
# Usage: Scripts/ci_resource_sampler.sh start|mark|stop <DIR>
#   mark  records when the tests start, so `stop` reports the test phase on its own
set -uo pipefail

ACTION="${1:?usage: Scripts/ci_resource_sampler.sh start|mark|stop <DIR>}"
DIR="${2:?usage: Scripts/ci_resource_sampler.sh start|mark|stop <DIR>}"
OUT="$DIR/samples.log"
CORESIM_LOG="$HOME/Library/Logs/CoreSimulator/CoreSimulator.log"

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
                echo "device identity errors: $(grep -c 'Failed to get a device identity' "$CORESIM_LOG" 2>/dev/null)"
                echo "simulator apsd: $(pgrep -f 'RuntimeRoot/.*ApplePushService.framework/apsd' | tr '\n' ' ')"
                echo "booted simulators: $(pgrep -x launchd_sim | wc -l | tr -d ' ')"
                echo "spotlight indexers: $(pgrep -x mdworker_shared | wc -l | tr -d ' ')"
                sysctl vm.loadavg vm.swapusage kern.memorystatus_vm_pressure_level
                memory_pressure -Q
                vm_stat | grep -E "free|active|wired|compressor|Compressions|Decompressions|Pageins|Pageouts|Swap"
                # Footprints rather than RSS, which counts every shared page once per process.
                { ps -axo pid=,comm= | sed 's/^/P /'; top -l 1 -stats pid,mem | sed 's/^/T /'; } | awk '
                    $1 == "P" { pid = $2; $1 = $2 = ""; sim[pid] = $0 ~ /CoreSimulator|RuntimeRoot|\.simruntime/; next }
                    $1 == "T" && $2 ~ /^[0-9]+$/ {
                        m = $3; sub(/[+-]$/, "", m); u = substr(m, length(m)); v = substr(m, 1, length(m) - 1) + 0
                        mb = u == "G" ? v * 1024 : u == "M" ? v : u == "K" ? v / 1024 : 0
                        if (sim[$2]) s += mb; else h += mb
                    }
                    END { printf "footprint simulator: %dM host: %dM\n", s, h }'
                # Both tools' first report averages since boot; the second covers the last second.
                iostat -d -K -c 2 -w 1
                top -l 2 -s 1 -n 12 -o cpu -stats pid,command,cpu,mem,state | tail -n 13
                # MEM includes the process's compressed pages, which a CPU-sorted list never shows for idle processes.
                echo "--- by memory"
                top -l 1 -n 20 -o mem -stats pid,command,mem,cmprs | tail -n 21
            } >> "$OUT" 2>&1
            sleep 3
        done
        ;;
    mark)
        date -u +%Y-%m-%dT%H:%M:%SZ > "$DIR/tests.start"
        ;;
    stop)
        [ -f "$DIR/sampler.pid" ] && kill "$(cat "$DIR/sampler.pid")" 2>/dev/null
        rm -f "$DIR/sampler.pid"
        [ -f "$OUT" ] || exit 0
        xcrun simctl list devices booted >> "$OUT" 2>&1
        TESTS_START=$(cat "$DIR/tests.start" 2>/dev/null)
        # The loop takes ~6s per sample, so a longer gap means the host itself stalled.
        awk -v start="$TESTS_START" '
            /^=== / {
                ts = $2; cmd = "date -j -u -f %Y-%m-%dT%H:%M:%SZ " ts " +%s"; cmd | getline now; close(cmd)
                intest = start != "" && ts >= start
                if (prev && now - prev > 10) {
                    g = now - prev; gaps++; if (g > longest) { longest = g; longestEnd = ts }
                    if (intest) { tgaps++; tsum += g; if (g > tlongest) { tlongest = g; tlongestEnd = ts } }
                }
                prev = now; samples++; if (intest) tsamples++
            }
            /kern.memorystatus_vm_pressure_level: 2/ && intest { tlevel2++ }
            /^Pages wired down/ { w = $4 * 16384 / 1048576; if (w > wired) wired = w }
            /^Pages occupied by compressor/ { c = $5 * 16384 / 1048576; if (c > comp) comp = c }
            /^footprint simulator/ { s = $3 + 0; if (s > simmem) simmem = s }
            /^booted simulators/ { if ($3 > booted) booted = $3 }
            END {
                printf "- samples: %d\n", samples
                printf "- sampler gaps over 10s: %d; longest: %ds ending %s\n", gaps, longest, longestEnd
                if (tsamples) {
                    printf "- during tests: %d gaps over 10s totalling %ds; longest: %ds ending %s\n", tgaps, tsum, tlongest, tlongestEnd
                    printf "- during tests at pressure level 2: %d%%\n", 100 * tlevel2 / tsamples
                }
                printf "- peak wired: %dM; peak compressor: %dM; peak simulator footprint: %dM\n", wired, comp, simmem
                printf "- most simulators booted at once: %d\n", booted
            }' "$OUT" > "$DIR/summary.md"
        {
            echo "### Host resources"
            echo
            cat "$DIR/summary.md"
            echo "- simulator device identity errors: $(grep 'device identity errors' "$OUT" | tail -1 | cut -d: -f2)"
            echo "- peak swap used: $(grep -o 'used = [0-9.]*M' "$OUT" | sort -t= -k2 -n | tail -1)"
            echo "- memory pressure level counts (1 normal, 2 warn, 4 critical):" \
                "$(grep 'kern.memorystatus_vm_pressure_level' "$OUT" | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
            echo "- peak 1-minute load: $(grep -o 'vm.loadavg: { [0-9.]*' "$OUT" | cut -d' ' -f3 | sort -n | tail -1)"
            echo "- largest footprints seen (MB):"
            awk '/^--- by memory/ { on = 1; next } /^=== / { on = 0 }
                on && $1 ~ /^[0-9]+$/ {
                    m = $(NF - 1); sub(/[+-]$/, "", m); u = substr(m, length(m)); v = substr(m, 1, length(m) - 1) + 0
                    mb = u == "G" ? v * 1024 : u == "M" ? v : u == "K" ? v / 1024 : 0
                    name = $2; for (i = 3; i <= NF - 2; i++) name = name " " $i
                    if (mb > peak[name]) peak[name] = mb
                }
                END { for (n in peak) printf "%d %s\n", peak[n], n }' "$OUT" | sort -rn | head -15 | sed 's/^/  - /'
        } >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
        ;;
    *)
        echo "✗ Unknown action '$ACTION'" >&2
        exit 1
        ;;
esac
