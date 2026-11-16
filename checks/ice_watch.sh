#!/bin/sh
# What ice and mother do now, compared with what we saw on 2026-11-12 (read-only, attack detection):
# programs and their hashes, scheduled jobs, processes, SSH logins of mother, sudo commands,
# accounts and keys, orders of the command servers (saved, NOT executed), open connections.
# Every line says SAME (as on 2026-11-12) or CHANGED (the attacker changed something).
# Secrets are redacted; the report is checked for them before it is saved and pushed.
# Run on each VM:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/ice_watch.sh
# Output: /tmp/ice-watch-<vm>.txt, pushed to results/ice-watch-<vm>/.
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if ip -4 -o addr show | grep -q ' 10\.4\.255\.11/'; then VM=welcome
elif ip -4 -o addr show | grep -q ' 10\.4\.255\.10/'; then VM=ns1
else VM=$(hostname)
fi
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/ice-watch-$VM.txt
if python3 -I "$DIR/ice_watch.py" "$VM" "$OUT" > /dev/null; then
    cat "$OUT"
    echo "Full output: $OUT (less $OUT)"
    sh "$DIR/push-results.sh" "ice-watch-$VM" "$OUT"
else
    echo "ERROR: report not written (see above); nothing pushed."
fi
