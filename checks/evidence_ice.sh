#!/bin/sh
# Evidence of the ice scripts (read-only, D28): their text with the secrets redacted
# (the content of /tmp/.test, passwords, sshpass, echo | sudo -S, private keys), plus
# metadata. Nothing is changed and ice is never run. The report goes to the PUBLIC repo
# (results/evidence-<vm>/): it is checked that no line of /tmp/.test is in it.
# Run on each VM:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/evidence_ice.sh

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if ip -4 -o addr show | grep -q ' 10\.4\.255\.11/'; then VM=welcome
elif ip -4 -o addr show | grep -q ' 10\.4\.255\.10/'; then VM=ns1
else echo "ERROR: run it on welcome (10.4.255.11) or ns1 (10.4.255.10)." >&2; exit 1
fi
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/evidence-ice-$VM.txt
if python3 -I "$DIR/evidence_ice.py" "$VM" "$OUT" > /dev/null; then
    echo "Report: $OUT ($(wc -l < "$OUT") lines, secrets redacted)"
    sh "$DIR/push-results.sh" "evidence-$VM" "$OUT"
else
    echo "ERROR: report not written (see above); nothing pushed."
fi
