#!/bin/bash
set -uo pipefail

cd "$(dirname "$0")/../.."
HARNESS=scripts/harness/harness.sh
PROFILE="${1:-default}"
RUNS="${RUNS:-7}"
PAGE="$($HARNESS url)settle.html"

cli() {
    $HARNESS cli -p "$PROFILE" "$@"
}

now() {
    python3 -c 'import time; print(int(time.monotonic() * 1000))'
}

id_of() {
    cli query "button \"$1\"" | awk 'NR == 1 { print $1 }'
}

center_of() {
    cli query "button \"$1\"" | awk 'NR == 1 { print $NF }' | tr ',' ' '
}

median() {
    sort -n | awk '{ value[NR] = $1 } END { print (NR % 2) ? value[(NR + 1) / 2] : int((value[NR / 2] + value[NR / 2 + 1]) / 2) }'
}

measure() {
    local name="$1" expected="$2"
    shift 2
    local times=() correct=0
    for run in $(seq "$RUNS"); do
        cli go "$PAGE" >/dev/null
        local resolved=()
        for word in "$@"; do
            case "$word" in
                @*) resolved+=("$(id_of "${word#@}")") ;;
                ^*) read -r x y <<<"$(center_of "${word#^}")"; resolved+=("$x" "$y") ;;
                %) resolved+=("text $run") ;;
                *) resolved+=("$word") ;;
            esac
        done
        local start reply end
        start=$(now)
        reply=$(cli "${resolved[@]}" 2>&1)
        end=$(now)
        times+=($((end - start)))
        grep -q -- "$expected" <<<"$reply" && correct=$((correct + 1))
    done
    printf '%-28s median %5d ms  runs %s  correct %d/%d\n' "$name" "$(printf '%s\n' "${times[@]}" | median)" "${times[*]}" "$correct" "$RUNS"
}

$HARNESS cli status | grep -q "^$PROFILE  (open" || cli open "$PAGE" >/dev/null
$HARNESS cli -p "$PROFILE" live >/dev/null 2>&1 &
LIVE=$!
trap 'kill $LIVE 2>/dev/null' EXIT

measure "act press (changes page)" "Immediate change" act @"Change now" press
measure "act press (does nothing)" "no visible change" act @"Do nothing" press
measure "do field = text" "text" do Name = %
measure "click x y" "Immediate change" click ^"Change now"
measure "act press (navigates)" "Harness Home" act @"Open home" press
measure "act press (fetch, 300 ms)" "Fetched 300 ms" act @"Fetch then change in 300 ms" press
measure "act press (fetch, 1 s)" "Fetched 1 s" act @"Fetch then change in 1 s" press
measure "act press (timer, 300 ms)" "Timed 300 ms" act @"Change in 300 ms" press
