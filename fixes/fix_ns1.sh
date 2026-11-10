#!/bin/sh
# Fixes for the ns1 VM (10.4.255.10). For each fix: current state, reason,
# confirmation [y/N], backup of the files it changes, change, check.
# At the end it runs checks/ns1.sh, which pushes the result.
# Take a PVE snapshot of ns1 first. Run fixes/fix_welcome.sh on welcome before fix 2.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/fix_ns1.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
ip -4 -o addr show | grep -q ' 10\.4\.255\.10/' || { echo "ERROR: run this script on ns1 (10.4.255.10)." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
mkdir -p "$BK"
IF=ens18
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }

ask "Did you take a PVE snapshot of ns1?" || { echo "Take it first: PVE > ns1 (Fabio-machine) > Snapshots > Take Snapshot."; exit 1; }

echo
echo "== Fix 1/2: one tool only for the network of $IF (W7)"
echo "   Why: NetworkManager and /etc/network/interfaces both configure $IF; networking.service"
echo "        fails at every boot, and after a reboot NetworkManager may leave $IF to ifupdown,"
echo "        which does not set the DNS 127.0.0.1. Keep NetworkManager (as on welcome)."
conn=$(nmcli -g GENERAL.CONNECTION device show "$IF" 2>/dev/null)
stanza=$(grep -nE "^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+$IF([[:space:]]|$)" /etc/network/interfaces 2>/dev/null)
echo "   NetworkManager profile: '${conn:-none}'"
[ -n "$conn" ] && echo "     $(nmcli -g ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns connection show "$conn" | tr '\n' ' ')"
echo "   /etc/network/interfaces lines for $IF: ${stanza:-none}"
if [ -z "$conn" ]; then
    echo "   STOP: $IF has no NetworkManager profile, nothing changed."
elif [ -z "$stanza" ] && [ "$(nmcli -g ipv4.dns connection show "$conn")" = "127.0.0.1,10.4.255.254" ]; then
    echo "   already done"
elif ask "   Apply? (the network of ns1 stops for a few seconds)"; then
    cp -a /etc/network/interfaces "$BK/"
    cp -a /etc/NetworkManager/system-connections "$BK/" 2>/dev/null || true
    nmcli connection modify "$conn" ipv4.method manual ipv4.addresses 10.4.255.10/16 \
        ipv4.gateway 10.4.255.254 ipv4.dns "127.0.0.1 10.4.255.254" ipv4.ignore-auto-dns yes
    # drop the auto/allow-hotplug line and the iface block of ens18 (indented lines below it); keep lo
    awk -v IF="$IF" '
        $1 ~ /^(auto|allow-hotplug)$/ && $2 == IF && NF == 2 { next }
        $1 == "iface" && $2 == IF { skip = 1; next }
        skip && /^[ \t]+[^ \t]/ { next }
        { skip = 0; print }
    ' /etc/network/interfaces > "$BK/interfaces.new"
    cat "$BK/interfaces.new" > /etc/network/interfaces
    nmcli connection up "$conn" >/dev/null
    systemctl reset-failed networking 2>/dev/null || true
    sleep 2
    echo "   now: $(nmcli -g ipv4.addresses,ipv4.gateway,ipv4.dns connection show "$conn" | tr '\n' ' ')"
    echo "   default route: $(ip -4 route show default | head -1)"
    echo "   resolv.conf: $(grep '^nameserver' /etc/resolv.conf | tr '\n' ' ')"
    echo "   /etc/network/interfaces now:"; sed 's/^/      /' /etc/network/interfaces
    if dig +short +time=2 +tries=1 @127.0.0.1 welcome.group4.umons | grep -q 10.4.255.11; then
        echo "   OK: DNS answers"
    else
        echo "   WARN: DNS does not answer, check the network (backup in $BK)"
    fi
fi

echo
echo "== Fix 2/2: one PTR for 10.4.255.11 (W25)"
echo "   Why: 10.4.255.11 has two reverse names (welcome, mail). Mail servers compare the"
echo "        reverse name of the sender with the name announced by Postfix (mail.group4.umons)."
echo "        The web page is not affected (browsers do not use reverse DNS)."
ZF=/etc/bind/db.10.4.255
ptr11=$(grep -nE '^11[[:space:]].*PTR' "$ZF" 2>/dev/null)
echo "   Lines for 11 in $ZF:"; echo "$ptr11" | sed 's/^/      /'
if [ -z "$ptr11" ]; then
    echo "   STOP: no PTR line for 11 found, nothing changed."
elif ! echo "$ptr11" | grep -q 'mail\.group4\.umons\.'; then
    echo "   STOP: no PTR to mail.group4.umons. in the file, nothing changed."
elif [ "$(echo "$ptr11" | wc -l)" -eq 1 ]; then
    echo "   already done"
elif ask "   Keep only 'mail.group4.umons.' and raise the serial?"; then
    cp -a "$ZF" "$BK/"
    old=$(grep -oE '[0-9]{10}' "$ZF" | head -1)
    new=$(date +%Y%m%d)01
    [ "$new" -gt "$old" ] || new=$((old + 1))
    awk -v OLD="$old" -v NEW="$new" '
        /^11[ \t].*PTR/ && $0 !~ /mail\.group4\.umons\./ { next }
        !done && index($0, OLD) { sub(OLD, NEW); done = 1 }
        { print }
    ' "$BK/db.10.4.255" > "$ZF"
    if named-checkzone 255.4.10.in-addr.arpa "$ZF"; then
        systemctl reload named
        sleep 1
        echo "   done: serial $old -> $new"
        echo "   dig -x 10.4.255.11: $(dig +short +time=2 +tries=1 @127.0.0.1 -x 10.4.255.11 | tr '\n' ' ')"
    else
        cp -a "$BK/db.10.4.255" "$ZF"
        echo "   ERROR: named-checkzone failed, file restored, BIND not reloaded"
    fi
fi

echo
echo "== Backups in $BK"
echo "== Running checks/ns1.sh"
sh "$REPO/checks/ns1.sh"
