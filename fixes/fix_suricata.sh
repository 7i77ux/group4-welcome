#!/bin/sh
# Repair of Suricata on welcome after the installation by hand (D10, D31). It finds what is wrong and
# fixes it, one fix at a time: current state, reason, confirmation [y/N], backup, check.
# Errors of /var/log/suricata/suricata.log that it solves:
#   "af-packet: enp1s0: failed to find interface type: No such device" -> wrong network card (fix 1)
#   "No rule files match the pattern /var/lib/suricata/rules/suricata.rules",
#   "0 signatures processed" -> rules folder or rules missing (fixes 4 and 5)
# The network card is the one of the default route (ens18 today), not a fixed name.
# Manual steps: DOCUMENTATION.md 10.17, "Repair by hand". At the end it runs checks/suricata.sh.
# Run on welcome:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/fix_suricata.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if [ "$(hostname)" != welcome ] && ! ip -4 -o addr show | grep -q ' 10\.4\.255\.11/'; then
    echo "ERROR: run this script on welcome." >&2; exit 1
fi
REPO=$(cd "$(dirname "$0")/.." && pwd)
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
cnt() { n=$(grep -c "$1" "$2" 2>/dev/null); echo "${n:-0}"; }   # matching lines, 0 if none or no file
Y=/etc/suricata/suricata.yaml
DEF=/etc/default/suricata
RULES=/var/lib/suricata/rules
LOG=/var/log/suricata
NET='[10.4.0.0/16]'
IFACE=$(ip -4 route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
[ -n "$IFACE" ] || IFACE=ens18

dpkg -l suricata 2>/dev/null | grep -q '^ii' || { echo "Suricata is not installed: DOCUMENTATION.md 10.17 step 1 (or sudo sh fixes/suricata_welcome.sh)."; exit 1; }
[ -f "$Y" ] || { echo "ERROR: $Y not found"; exit 1; }
since_start() { awk '/This is Suricata version/ {buf = ""} {buf = buf $0 "\n"} END {printf "%s", buf}' "$LOG/suricata.log" 2>/dev/null; }

echo "== Repair of Suricata on welcome"
echo "   network card of the default route: $IFACE ($(ip -4 -br addr show "$IFACE" 2>/dev/null | awk '{print $3}'))"
echo "   service: $(systemctl is-active suricata 2>/dev/null), at boot: $(systemctl is-enabled suricata 2>/dev/null)"
echo "   errors in suricata.log since the last start:"
since_start | grep -E 'Error|<E>' | tail -5 | cut -c1-150 | sed 's/^/      /'
ask "Did you take a PVE snapshot of welcome?" || { echo "Take it first: PVE > welcome > Snapshots > Take Snapshot."; exit 1; }
mkdir -p "$BK"
cp -a "$Y" "$BK/suricata.yaml.before"            # restored if the configuration test fails
[ -f "$DEF" ] && cp -a "$DEF" "$BK/default-suricata.before"
restore() {
    cp -a "$BK/suricata.yaml.before" "$Y"
    [ -f "$BK/default-suricata.before" ] && cp -a "$BK/default-suricata.before" "$DEF"
    echo "   configuration restored from $BK"
}
# line number of the first '- interface:' under af-packet that is not 'default' (any spacing, quotes or comment)
afp_line() {
    awk '/^af-packet:/ {f = 1; next} f && /^[^[:space:]#]/ {f = 0}
         f && /^[[:space:]]*-[[:space:]]*interface:/ {v = $0; sub(/.*interface:[[:space:]]*/, "", v); sub(/[[:space:]#].*/, "", v); gsub(/["\047]/, "", v)
                                                     if (v != "default") {print NR; exit}}' "$Y"
}
afp_if() { n=$(afp_line); [ -n "$n" ] && sed -n "${n}p" "$Y" | sed -E 's/.*interface:[[:space:]]*//; s/[[:space:]#].*//' | tr -d "\"'"; }

echo
cur_if=$(afp_if)
def_if=$(sed -n 's/^IFACE=//p' "$DEF" 2>/dev/null | tr -d "\"'")
echo "== Fix 1/7: network card ($IFACE)"
echo "   now: af-packet '${cur_if:-none}'${def_if:+, $DEF IFACE=$def_if}"
echo "   Why: Suricata listens on the card named here. 'enp1s0' is only the example of the quickstart;"
echo "        with a card that does not exist Suricata does not start ('No such device')."
if [ "$cur_if" = "$IFACE" ] && { [ -z "$def_if" ] || [ "$def_if" = "$IFACE" ]; }; then
    echo "   already done"
elif ask "   Apply?"; then
    ln=$(afp_line)
    if [ -n "$ln" ]; then
        echo "   line $ln before: $(sed -n "${ln}p" "$Y" | cat -A | cut -c1-100)"
        sed -i -E "${ln}s/(interface:[[:space:]]*)[^[:space:]#]+/\1$IFACE/" "$Y"
    fi
    [ -n "$def_if" ] && sed -i -E "s|^IFACE=.*|IFACE=$IFACE|" "$DEF"
    if [ -n "$ln" ] && [ "$(afp_if)" = "$IFACE" ]; then
        echo "   done: line $ln is now: $(sed -n "${ln}p" "$Y" | sed 's/^[[:space:]]*//')${def_if:+; IFACE=$IFACE}"
    else
        restore
        echo "   ERROR: the card could not be changed. Lines under af-packet (cat -A shows hidden characters):"
        sed -n '/^af-packet:/,/^[^[:space:]#]/p' "$Y" | grep -n 'interface' | head -5 | cat -A | cut -c1-100 | sed 's/^/      /'
        echo "   Edit $Y by hand: DOCUMENTATION.md 10.17, repair a."
        exit 1
    fi
fi

echo
lm=$(sed -n 's/^LISTENMODE=//p' "$DEF" 2>/dev/null | tr -d "\"'")
cm=$(sed -n '/^af-packet:/,/^[^[:space:]#]/p' "$Y" | grep -E '^[[:space:]]*copy-mode:' | head -1 | awk '{print $2}')
echo "== Fix 2/7: watch only (IDS, D10)"
echo "   now: ${lm:+$DEF LISTENMODE=$lm, }af-packet copy-mode '${cm:-none}'"
echo "   Why: nfqueue or copy-mode ips/tap put Suricata in the path of the traffic (IPS): without the"
echo "        matching firewall rules it sees nothing, and a wrong rule could block customer mail."
if { [ -z "$lm" ] || [ "$lm" = af-packet ]; } && [ -z "$cm" ]; then
    echo "   already done"
elif [ -n "$cm" ]; then
    echo "   WARN: 'copy-mode: $cm' under af-packet: comment that line by hand (#) in $Y (10.17, repair b)"
elif ask "   Set LISTENMODE=af-packet?"; then
    sed -i -E "s|^LISTENMODE=.*|LISTENMODE=af-packet|" "$DEF"
    echo "   done: $(grep '^LISTENMODE=' "$DEF")"
fi

echo
hn=$(grep -E '^[[:space:]]*HOME_NET:' "$Y" | head -1 | sed -E 's/^[[:space:]]*HOME_NET:[[:space:]]*//')
echo "== Fix 3/7: our network (HOME_NET)"
echo "   now: HOME_NET: $hn"
echo "   Why: the rules 'from outside to us' need to know what is ours: 10.4.0.0/16. The other groups"
echo "        are 10.X.0.0/16: with the default 10.0.0.0/8 they would count as ours."
if [ "$hn" = "\"$NET\"" ]; then
    echo "   already done"
elif ask "   Apply?"; then
    sed -i -E "s|^([[:space:]]*HOME_NET:[[:space:]]*).*|\1\"$NET\"|" "$Y"
    echo "   done: $(grep -E '^[[:space:]]*HOME_NET:' "$Y" | head -1 | sed 's/^[[:space:]]*//')"
fi

echo
rp=$(sed -n 's/^default-rule-path:[[:space:]]*//p' "$Y" | head -1 | tr -d "\"'")
rf=$(sed -n '/^rule-files:/,/^[^[:space:]#]/p' "$Y" | grep -E '^[[:space:]]*-[[:space:]]' | awk '{print $2}' | tr '\n' ' ')
echo "== Fix 4/7: rules folder"
echo "   now: default-rule-path '${rp:-none}', rule-files: ${rf:-none}"
echo "   Why: suricata-update writes the rules to $RULES/suricata.rules: Suricata must read them"
echo "        there ('No rule files match the pattern' otherwise)."
if [ "$rp" = "$RULES" ] && echo " $rf " | grep -q ' suricata.rules '; then
    echo "   already done"
elif ask "   Apply?"; then
    if grep -q '^default-rule-path:' "$Y"; then
        sed -i -E "s|^default-rule-path:.*|default-rule-path: $RULES|" "$Y"
    else
        printf '\ndefault-rule-path: %s\n' "$RULES" >> "$Y"
    fi
    if ! echo " $rf " | grep -q ' suricata.rules '; then
        if grep -q '^rule-files:' "$Y"; then
            awk '{print} /^rule-files:/ {print "  - suricata.rules"}' "$Y" > "$BK/suricata.yaml.tmp" && cat "$BK/suricata.yaml.tmp" > "$Y"
        else
            printf 'rule-files:\n  - suricata.rules\n' >> "$Y"
        fi
    fi
    echo "   done: default-rule-path $(sed -n 's/^default-rule-path:[[:space:]]*//p' "$Y" | head -1), rule-files: $(sed -n '/^rule-files:/,/^[^[:space:]#]/p' "$Y" | grep -E '^[[:space:]]*-[[:space:]]' | awk '{print $2}' | tr '\n' ' ')"
fi

echo
n=$(cnt '^alert' "$RULES/suricata.rules")
age=""
[ -f "$RULES/suricata.rules" ] && age=$(( ($(date +%s) - $(stat -c %Y "$RULES/suricata.rules")) / 86400 ))
echo "== Fix 5/7: rules (ET Open)"
echo "   now: $n active rules in $RULES/suricata.rules${age:+, $age day(s) old}"
echo "   Why: without rules Suricata starts but detects nothing ('0 signatures processed')."
if [ "$n" -gt 1000 ] && [ "${age:-99}" -le 7 ]; then
    echo "   already done (to update them anyway: sudo suricata-update)"
elif ask "   Download them now with suricata-update?"; then
    command -v suricata-update >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -q suricata-update >/dev/null
    if command -v suricata-update >/dev/null; then
        suricata-update --no-test 2>&1 | tail -3 | sed 's/^/      /'
        echo "   done: $(cnt '^alert' "$RULES/suricata.rules") active rules"
    else
        echo "   ERROR: suricata-update not available (sudo apt install suricata-update)"
    fi
fi

echo
echo "== Fix 6/7: test of the configuration, then start (now and at every boot)"
tmp=$(mktemp -d)
out=$(suricata -T -v -c "$Y" -l "$tmp" 2>&1)
rm -rf "$tmp"
echo "$out" | grep -oE '[0-9]+ rules successfully loaded, [0-9]+ rules failed' | head -1 | sed 's/^/   /'
if echo "$out" | grep -q 'successfully loaded. Exiting'; then
    echo "   OK: configuration valid"
else
    echo "   ERROR: suricata -T failed:"
    echo "$out" | grep -E 'Error|<E>' | head -5 | cut -c1-150 | sed 's/^/      /'
    restore
    exit 1
fi
if ask "   Restart Suricata now?"; then
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
    errs=$(tail -n +$((start + 1)) "$LOG/suricata.log" 2>/dev/null | grep -E 'Error|<E>')
    if tail -n +$((start + 1)) "$LOG/suricata.log" 2>/dev/null | grep -qi 'engine started'; then
        echo "   OK: engine started on $IFACE"
    else
        echo "   WARN: no 'engine started' yet: sudo tail -f $LOG/suricata.log"
    fi
    [ -n "$errs" ] && { echo "   errors since this start:"; echo "$errs" | tail -5 | cut -c1-150 | sed 's/^/      /'; }
fi

echo
echo "== Fix 7/7: test alert (rule 2100498, harmless page made for this)"
if ask "   Download http://testmynids.org/uid/index.html and look for the alert?"; then
    before=$(cnt 2100498 "$LOG/fast.log")
    curl -s -o /dev/null --max-time 10 http://testmynids.org/uid/index.html
    i=0
    while [ "$(cnt 2100498 "$LOG/fast.log")" -le "$before" ] && [ $i -lt 8 ]; do sleep 2; i=$((i + 1)); done
    if [ "$(cnt 2100498 "$LOG/fast.log")" -gt "$before" ]; then
        echo "   OK: alert raised:"; grep 2100498 "$LOG/fast.log" | tail -1 | cut -c1-160 | sed 's/^/      /'
    else
        echo "   WARN: no alert. Engine still loading? (try again in a minute), outgoing HTTP blocked, or wrong card"
    fi
fi

echo
echo "== Backups in $BK (suricata.yaml.before = the file before this repair)"
echo "== Running checks/suricata.sh (answer N to its test alert if you just did it)"
sh "$REPO/checks/suricata.sh"
