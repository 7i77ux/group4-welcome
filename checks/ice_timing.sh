#!/bin/sh
# How often ice attacks (read-only, D28): intervals between the SSH logins of mother per source,
# rounds of the local copies of ice, installations, and who is on the DHCP addresses .41-.50 now.
# Run on each VM:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/ice_timing.sh
# Output: /tmp/ice-timing-<vm>.txt, pushed to results/ice-timing-<vm>/.

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if ip -4 -o addr show | grep -q ' 10\.4\.255\.11/'; then VM=welcome
elif ip -4 -o addr show | grep -q ' 10\.4\.255\.10/'; then VM=ns1
else echo "ERROR: run it on welcome (10.4.255.11) or ns1 (10.4.255.10)." >&2; exit 1
fi
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/ice-timing-$VM.txt
python3 -I "$DIR/ice_timing.py" "$VM" 2>&1 | tee "$OUT"
echo "Full output: $OUT (less $OUT)"
sh "$DIR/push-results.sh" "ice-timing-$VM" "$OUT"
