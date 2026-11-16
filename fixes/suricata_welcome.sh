#!/bin/sh
# Suricata on welcome as IDS: it only watches and raises alerts, it blocks nothing (D10, task S5).
# Course guide (session of 2026-11-10): Suricata quickstart steps 2.1, 2.2 and 2.4, adapted to
# Debian 13: the package comes from Debian (apt); the Ubuntu PPA (add-apt-repository) does not work here.
# Four steps, each shown first and confirmed [y/N]:
#   1. install the Debian packages suricata and suricata-update
#   2. HOME_NET = our network [10.4.0.0/16]; capture on ens18 (af-packet without copy-mode = IDS)
#   3. rules: suricata-update (ET Open), test of the configuration (suricata -T)
#   4. start now and at every boot; test alert (curl http://testmynids.org/uid/index.html)
# Backup of the configuration in /root/fixes-backup-<date>. At the end it runs checks/full.sh.
# Take a PVE snapshot of welcome first.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/suricata_welcome.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
ip -4 -o addr show | grep -q ' 10\.4\.255\.11/' || { echo "ERROR: run this script on welcome (10.4.255.11)." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
mkdir -p "$BK"
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
cnt() { n=$(grep -c "$1" "$2" 2>/dev/null); echo "${n:-0}"; }   # matching lines, 0 if none or no file
Y=/etc/suricata/suricata.yaml
IFACE=ens18
NET='[10.4.0.0/16]'
RULES=/var/lib/suricata/rules
LOG=/var/log/suricata

echo "== Suricata on welcome (IDS, alerts only; D10, S5)"
echo "   now: package $(dpkg-query -W -f='${Status} ${Version}' suricata 2>/dev/null || echo 'not installed'), service $(systemctl is-active suricata 2>/dev/null)"
ask "Did you take a PVE snapshot of welcome?" || { echo "Take it first: PVE > welcome > Snapshots > Take Snapshot."; exit 1; }

echo
echo "== Step 1/4: install suricata and suricata-update (guide step 2.1)"
if dpkg -l suricata 2>/dev/null | grep -q '^ii' && command -v suricata-update >/dev/null; then
    echo "   already installed: $(suricata -V 2>/dev/null)"
elif ask "   Install from the Debian repositories?"; then
    apt-get update -q >/dev/null
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -q suricata >/dev/null; then
        echo "   ERROR: apt-get install suricata failed"; exit 1
    fi
    command -v suricata-update >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -q suricata-update >/dev/null \
        || echo "   WARN: suricata-update not available: step 3 will not download the rules"
    systemctl stop suricata 2>/dev/null   # it starts with the default settings: configured first, started in step 4
    echo "   done: $(suricata -V)"
else
    echo "Nothing installed: stop."; exit 0
fi
[ -f "$Y" ] || { echo "ERROR: $Y not found"; exit 1; }

echo
echo "== Step 2/4: our network and the network card (guide step 2.2)"
cur_net=$(grep -E '^[[:space:]]*HOME_NET:' "$Y" | head -1 | sed 's/^[[:space:]]*//')
cur_if=$(sed -n '/^af-packet:/,/^[^[:space:]#]/p' "$Y" | grep -E '^[[:space:]]*- interface:' | grep -v default | head -1 | sed 's/^[[:space:]]*//')
def_if=$(grep -E '^IFACE=' /etc/default/suricata 2>/dev/null)
echo "   now: $cur_net | af-packet $cur_if${def_if:+ | /etc/default/suricata $def_if}"
echo "   service command: $(systemctl cat suricata 2>/dev/null | grep -m1 '^ExecStart=')"
echo "   Why: HOME_NET tells the rules what is ours (10.4.0.0/16; the other groups are 10.X.0.0/16)."
echo "        ens18 is the network card of welcome. af-packet without copy-mode only watches (IDS)."
if [ "$cur_net" = "HOME_NET: \"$NET\"" ] && [ "$cur_if" = "- interface: $IFACE" ] && { [ -z "$def_if" ] || [ "$def_if" = "IFACE=$IFACE" ]; }; then
    echo "   already done"
elif ask "   Apply?"; then
    cp -a "$Y" "$BK/suricata.yaml.step2"
    [ -f /etc/default/suricata ] && cp -a /etc/default/suricata "$BK/default-suricata"
    sed -i -E "s|^([[:space:]]*HOME_NET:[[:space:]]*).*|\1\"$NET\"|" "$Y"
    sed -i -E "/^af-packet:/,/^[^[:space:]#]/ s|^([[:space:]]*- interface:[[:space:]]*)([^d[:space:]#][^[:space:]]*)[[:space:]]*\$|\1$IFACE|" "$Y"
    [ -n "$def_if" ] && sed -i -E "s|^IFACE=.*|IFACE=$IFACE|" /etc/default/suricata
    new_net=$(grep -E '^[[:space:]]*HOME_NET:' "$Y" | head -1 | sed 's/^[[:space:]]*//')
    new_if=$(sed -n '/^af-packet:/,/^[^[:space:]#]/p' "$Y" | grep -E '^[[:space:]]*- interface:' | grep -v default | head -1 | sed 's/^[[:space:]]*//')
    if [ "$new_net" = "HOME_NET: \"$NET\"" ] && [ "$new_if" = "- interface: $IFACE" ]; then
        echo "   done: $new_net | af-packet $new_if"
    else
        cp -a "$BK/suricata.yaml.step2" "$Y"
        echo "   ERROR: the file does not look as expected ($new_net | $new_if): restored. Edit $Y by hand."
        exit 1
    fi
fi

echo
echo "== Step 3/4: rules (guide step 2.4)"
dump=$(suricata --dump-config -c "$Y" 2>/dev/null)
rp=$(echo "$dump" | sed -n 's/^default-rule-path = //p')
rf=$(echo "$dump" | sed -n 's/^rule-files\.[0-9]* = //p' | tr '\n' ' ')
echo "   now: rules folder $rp, rule files: $rf, rules in $RULES/suricata.rules: $(cnt '^alert' "$RULES/suricata.rules")"
echo "   Why: suricata-update downloads the free ET Open rules (scans, exploits, malware traffic) into $RULES."
if ask "   Download or update the rules now?"; then
    if command -v suricata-update >/dev/null; then
        suricata-update --no-test 2>&1 | tail -3 | sed 's/^/      /'
    else
        echo "   WARN: suricata-update missing: rules not downloaded"
    fi
    if [ "$rp" != "$RULES" ]; then
        cp -a "$Y" "$BK/suricata.yaml.step3"
        sed -i -E "s|^default-rule-path:.*|default-rule-path: $RULES|" "$Y"
        echo "   rules folder set to $RULES (was $rp)"
    fi
    echo " $rf " | grep -q ' suricata.rules ' || echo "   WARN: 'suricata.rules' is not under rule-files in $Y: add the line '  - suricata.rules' there"
    echo "   rules now: $(cnt '^alert' "$RULES/suricata.rules")"
fi
echo "   test of the configuration (suricata -T, takes up to a minute):"
out=$(suricata -T -v -c "$Y" 2>&1)
echo "$out" | grep -oE '[0-9]+ rules successfully loaded, [0-9]+ rules failed' | head -1 | sed 's/^/      /'
if echo "$out" | grep -q 'successfully loaded. Exiting'; then
    echo "   OK: configuration valid"
else
    echo "$out" | grep -iE 'error|<E>' | head -5 | sed 's/^/      /'
    for f in suricata.yaml.step3 suricata.yaml.step2; do
        [ -f "$BK/$f" ] && { cp -a "$BK/$f" "$Y"; echo "   configuration restored from $BK/$f"; break; }
    done
    echo "   ERROR: suricata -T failed: Suricata not started."
    exit 1
fi

echo
echo "== Step 4/4: start now and at every boot, then a test alert"
echo "   Test: welcome downloads http://testmynids.org/uid/index.html, a harmless page made to trigger"
echo "        the rule 2100498 'GPL ATTACK_RESPONSE id check returned root'."
if ask "   Start Suricata?"; then
    systemctl enable suricata >/dev/null 2>&1
    start=$(cat "$LOG/suricata.log" 2>/dev/null | wc -l)
    systemctl restart suricata
    printf '   waiting for the engine (rules are loading, up to 2.5 minutes)'
    i=0
    until tail -n +$((start + 1)) "$LOG/suricata.log" 2>/dev/null | grep -qi 'engine started' || [ $i -ge 30 ]; do
        printf '.'; sleep 5; i=$((i + 1))
    done
    echo
    echo "   service: $(systemctl is-active suricata), at boot: $(systemctl is-enabled suricata)"
    echo "   last lines of $LOG/suricata.log:"
    tail -4 "$LOG/suricata.log" 2>/dev/null | sed 's/^/      /'
    before=$(cnt 2100498 "$LOG/fast.log")
    curl -s -o /dev/null --max-time 10 http://testmynids.org/uid/index.html
    sleep 8
    after=$(cnt 2100498 "$LOG/fast.log")
    if [ "$after" -gt "$before" ]; then
        echo "   OK: test alert raised:"
        grep 2100498 "$LOG/fast.log" | tail -1 | cut -c1-160 | sed 's/^/      /'
    else
        echo "   WARN: no test alert in $LOG/fast.log. Possible causes: engine still loading (try again"
        echo "         in a minute: curl -s http://testmynids.org/uid/index.html; tail $LOG/fast.log),"
        echo "         no outgoing HTTP, wrong interface (see $LOG/suricata.log)."
    fi
fi

echo
echo "== Alerts: sudo tail -f $LOG/fast.log"
echo "== Backups in $BK"
echo "== Running checks/full.sh (full regression test)"
sh "$REPO/checks/full.sh"
