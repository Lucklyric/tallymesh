#!/usr/bin/env bash
# Bench Groth16 prover wall-clock + RSS across active-receipt counts.
# Circuit MAX is fixed at 1024; varying N changes only witness-gen work.
# Each (N, trial) builds input.json then runs prove_fixture.js under /usr/bin/time -v.
set -euo pipefail

OUTPUT_CSV=${1:-zk_prover_bench.csv}
NS=(1 16 64 256 512 1024)
TRIALS=3

cd "$(dirname "$0")/.."

echo "N,trial,wall_clock_s,user_s,sys_s,cpu_pct,max_rss_kb,exit_code,timestamp" > "$OUTPUT_CSV"

for N in "${NS[@]}"; do
  for TRIAL in $(seq 1 $TRIALS); do
    echo "=== N=$N trial=$TRIAL $(date -u +%H:%M:%S) ==="
    node scripts/build_input_n.js "$N" > /dev/null

    TMP_TIME=$(mktemp)
    set +e
    /usr/bin/time -v -o "$TMP_TIME" node scripts/prove_fixture.js > /dev/null 2>&1
    EXIT=$?
    set -e

    WALL=$(grep "Elapsed (wall clock)" "$TMP_TIME" | awk -F': ' '{print $NF}')
    USER=$(grep "User time" "$TMP_TIME" | awk -F': ' '{print $NF}')
    SYS=$(grep "System time" "$TMP_TIME" | awk -F': ' '{print $NF}')
    CPU=$(grep "Percent of CPU" "$TMP_TIME" | awk -F': ' '{print $NF}' | tr -d '%')
    RSS=$(grep "Maximum resident set size" "$TMP_TIME" | awk -F': ' '{print $NF}')

    WALL_S=$(echo "$WALL" | awk -F: '{ if (NF==2) printf "%.2f", $1*60+$2; else if (NF==3) printf "%.2f", $1*3600+$2*60+$3; else printf "%.2f", $1 }')

    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "$N,$TRIAL,$WALL_S,$USER,$SYS,$CPU,$RSS,$EXIT,$TS" >> "$OUTPUT_CSV"
    echo "    wall=${WALL_S}s rss=${RSS}KB cpu=${CPU}% exit=${EXIT}"
    rm "$TMP_TIME"
  done
done

echo "Done. Results in $OUTPUT_CSV"
