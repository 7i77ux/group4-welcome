#!/bin/sh
# Mail exchange with the other mail providers (project statement, case 1: mail MUST be exchangeable
# across providers). Run on welcome. It checks our side as the others see it, finds the other groups
# with a mail server (MX + port 25 greeting), sends ONE test mail per group you choose (asking for a
# reply to calogero@group4.umons), shows the delivery result and the replies received.
# It sends mail only after your choice; nothing in the configuration is changed.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/mail_exchange.sh
# Output: /tmp/check-mail-exchange.txt, pushed to results/mail-exchange/.
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
[ "$(hostname)" = welcome ] || ip -4 -o addr show | grep -q ' 10\.4\.255\.11/' || { echo "ERROR: run it on welcome." >&2; exit 1; }
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/check-mail-exchange.txt
python3 -I -u "$DIR/mail_exchange.py" 2>&1 | tee "$OUT"
echo "Full output: $OUT (less $OUT)"
sh "$DIR/push-results.sh" mail-exchange "$OUT"
