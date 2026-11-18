#!/bin/sh
# Check of Suricata on welcome after the installation by hand (DOCUMENTATION.md 10.17), read-only:
# packages, settings (HOME_NET, interface, rules folder), rules, configuration test, service,
# capture, alerts, eve.json. Every FAIL names the step of 10.17 to redo.
# Optional (asked first): the test alert, by downloading http://testmynids.org/uid/index.html.
# Run on welcome:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/suricata.sh
# Output: /tmp/check-suricata.txt, pushed to results/suricata/.

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
{ [ "$(hostname)" = welcome ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.11/'; } || { echo "ERROR: run it on welcome." >&2; exit 1; }
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/check-suricata.txt
TEST=""
if [ -t 0 ] && dpkg -l suricata 2>/dev/null | grep -q '^ii'; then
    printf "Also trigger the test alert now (curl http://testmynids.org/uid/index.html, harmless)? [y/N] "
    read -r a
    case "$a" in y|Y) TEST=--test-alert;; esac
fi
python3 -I "$DIR/suricata.py" $TEST 2>&1 | tee "$OUT"
echo "Full output: $OUT (less $OUT)"
sh "$DIR/push-results.sh" suricata "$OUT"
