#!/bin/sh
# DNS used by ns1 itself = resolver of the course 10.4.255.254 (W34), as fix 10 of fix_welcome.sh.
# Seen on 2026-11-18: from ns1 the pages of the other groups give "Server Not Found":
# 'dig welcome.group7.umons' (asked to its own BIND) gives nothing, '@10.4.255.254' gives 10.7.255.10.
# The BIND of ns1 still answers for group4.umons to everybody: only the resolver of ns1 itself changes.
# Structure of the fixes: current state, reason, confirmation, backup, change, check, then checks/full.sh.
# Run on ns1:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/fix_ns1_dns.sh
# Manual steps: DOCUMENTATION.md 10.28.
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
{ [ "$(hostname)" = ns1 ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.10/'; } || { echo "ERROR: run this script on ns1." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
COURSE_DNS=10.4.255.254

ask "Did you take a PVE snapshot of ns1?" || { echo "Take it first: PVE > ns1 > Snapshots > Take Snapshot."; exit 1; }

conn=$(nmcli -g GENERAL.CONNECTION device show ens18 2>/dev/null)
cur=$(nmcli -g ipv4.dns connection show "$conn" 2>/dev/null)
echo
echo "== Fix 1/1: DNS of ns1 = resolver of the course $COURSE_DNS (W34)"
echo "   now: profile '$conn', DNS '$cur'; resolv.conf: $(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf)"
echo "   test now: own BIND -> '$(dig +short +time=2 +tries=1 @127.0.0.1 welcome.group7.umons | head -1)',"
echo "             course resolver -> '$(dig +short +time=2 +tries=1 @$COURSE_DNS welcome.group7.umons | head -1)'"
echo "   Why: ns1 asks its own BIND first; BIND validates DNSSEC and takes the lab TLD .umons for"
echo "        non-existent (signed answer of the Internet root), so the names of the other groups do not"
echo "        resolve on ns1 (pages, tests). The resolver of the course knows them. The zone group4.umons"
echo "        is not touched: the course resolver asks ns1 for it, through pfSense."
if [ "$cur" = "$COURSE_DNS" ]; then
    echo "   already done"
elif [ -z "$conn" ]; then
    echo "   ERROR: no NetworkManager profile on ens18: change it by hand (DOCUMENTATION 10.28)"
elif ask "   Apply? (nmcli device reapply: no interruption of the network)"; then
    mkdir -p "$BK"
    for f in /etc/NetworkManager/system-connections/*; do [ -f "$f" ] && cp -a "$f" "$BK/"; done
    nmcli connection modify "$conn" ipv4.dns "$COURSE_DNS" ipv4.ignore-auto-dns yes
    nmcli device reapply ens18 >/dev/null 2>&1 || nmcli connection up "$conn" >/dev/null
    sleep 3
    g7=$(getent hosts welcome.group7.umons | awk '{print $1}')
    g4=$(getent hosts welcome.group4.umons | awk '{print $1}')
    echo "   done: DNS of the profile $(nmcli -g ipv4.dns connection show "$conn"); resolv.conf: $(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf)"
    if [ -n "$g7" ] && [ -n "$g4" ]; then
        echo "   OK: welcome.group7.umons -> $g7, welcome.group4.umons -> $g4"
    else
        echo "   WARN: welcome.group7.umons -> '${g7:-nothing}', welcome.group4.umons -> '${g4:-nothing}'"
        echo "         to undo: sudo nmcli connection modify \"$conn\" ipv4.dns \"$cur\" && sudo nmcli device reapply ens18"
    fi
fi

echo
echo "== Running checks/full.sh (full regression test)"
sh "$REPO/checks/full.sh"
