#!/bin/sh
# Full regression test (read-only): checks everything the documentation says is done,
# on this VM and on the other VM as the other groups see it. It changes nothing,
# logs in nowhere, sends no mail, only observes the account mother (D28).
# Run on each VM:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/full.sh
# Output: /tmp/check-full-<vm>.txt, pushed to results/full-<vm>/.

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if ip -4 -o addr show | grep -q ' 10\.4\.255\.11/'; then VM=welcome
elif ip -4 -o addr show | grep -q ' 10\.4\.255\.10/'; then VM=ns1
else echo "ERROR: run it on welcome (10.4.255.11) or ns1 (10.4.255.10)." >&2; exit 1
fi
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/check-full-$VM.txt
python3 -I "$DIR/full.py" "$VM" "$DIR/.." 2>&1 | tee "$OUT"
echo "Full output: $OUT (less $OUT)"
sh "$DIR/push-results.sh" "full-$VM" "$OUT"
