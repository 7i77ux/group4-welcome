#!/bin/sh
# Full regression test (read-only): checks everything the documentation says is done,
# on this VM and on the other VM as the other groups see it. It changes nothing,
# sends no mail, only observes the account mother (D28).
# On welcome it first offers the mail login test (doveadm auth test, D24): you type the
# password of calogero (must succeed) and the REAL password of user (must be refused).
# The passwords are read by doveadm itself: never stored, never in the output.
# Run on each VM:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/full.sh
# Output: /tmp/check-full-<vm>.txt, pushed to results/full-<vm>/.

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if ip -4 -o addr show | grep -q ' 10\.4\.255\.11/'; then VM=welcome
elif ip -4 -o addr show | grep -q ' 10\.4\.255\.10/'; then VM=ns1
else echo "ERROR: run it on welcome (10.4.255.11) or ns1 (10.4.255.10)." >&2; exit 1
fi
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/check-full-$VM.txt

DV=""
if [ "$VM" = welcome ] && [ -t 0 ] && command -v doveadm >/dev/null; then
    echo "Mail login test (D24): calogero must succeed, user must be refused even with its real password."
    printf "Run it now? You will type 2 passwords. [y/N] "
    read -r a
    if [ "$a" = y ] || [ "$a" = Y ]; then
        DV=$(mktemp /tmp/full-doveadm.XXXXXX)
        chmod 600 "$DV"
        for u in calogero user; do
            echo "-- password of $u:"
            doveadm auth test "$u" 2>&1 | tee -a "$DV"
        done
    fi
fi

python3 -I "$DIR/full.py" "$VM" "$DIR/.." $DV 2>&1 | tee "$OUT"
[ -n "$DV" ] && rm -f "$DV"
echo "Full output: $OUT (less $OUT)"
sh "$DIR/push-results.sh" "full-$VM" "$OUT"
