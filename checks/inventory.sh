#!/bin/sh
# Inventory of the new structure (read-only): network, our names as the other groups see them, zones (ns1),
# Postfix/Dovecot/MariaDB and web (welcome). Passwords masked. Used to update the checks after the
# changes of 2026-11-17 (pfSense DMZ/NAT, virtual mailboxes).
# Run on each VM:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/inventory.sh
# Output: /tmp/inventory-<vm>.txt, pushed to results/inventory-<vm>/.
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if { [ "$(hostname)" = welcome ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.11/'; }; then VM=welcome
elif { [ "$(hostname)" = ns1 ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.10/'; }; then VM=ns1
else echo "ERROR: run it on welcome or ns1." >&2; exit 1
fi
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/inventory-$VM.txt
python3 -I "$DIR/inventory.py" "$VM" "$OUT" > /dev/null || { echo "ERROR: inventory failed"; exit 1; }
cat "$OUT"
echo "Full output: $OUT (less $OUT)"
sh "$DIR/push-results.sh" "inventory-$VM" "$OUT"
