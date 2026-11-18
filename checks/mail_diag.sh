#!/bin/sh
# What went wrong with the mail on welcome (read-only test battery): who changed what today, Dovecot,
# Postfix, MariaDB, mailboxes, live tests on 25 and 993, findings. Changes nothing. Passwords masked.
# Run on welcome BEFORE fixes/mail_virtual.sh:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/mail_diag.sh
# Output: /tmp/mail-diag.txt, pushed to results/mail-diag/ (not pushed if something looks like a password).
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
{ [ "$(hostname)" = welcome ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.11/'; } || { echo "ERROR: run this script on welcome." >&2; exit 1; }
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/mail-diag.txt
python3 -I "$DIR/mail_diag.py" "$OUT" "$(dirname "$DIR")" || { echo "ERROR: diagnosis failed"; exit 1; }
chmod 600 "$OUT"
cat "$OUT"
echo "Full output: $OUT (less $OUT)"
# last safety net before a public push: the passwords of the database users must not appear
leak=0
for f in /etc/group4-mail/*.pw; do [ -s "$f" ] && grep -qF -f "$f" "$OUT" && leak=1; done
grep -qiE "identified by '[^<]|password *[=:] *[^<[:space:]]" "$OUT" && leak=1
if [ "$leak" = 1 ]; then
    echo "NOT pushed: the output may contain a password. Send screenshots of $OUT instead."
else
    sh "$DIR/push-results.sh" mail-diag "$OUT"
fi
