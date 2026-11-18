#!/bin/sh
# Raise the serial of our two zones on ns1 (rule of DOCUMENTATION 10.9: every change of records raises
# the serial). On 2026-11-17 the A records moved to 10.4.255.1 and the reverse zone to 2.4.10 with the
# old serials (TIMELINE 18.1). Structure of the fixes: current state, reason, confirmation, backup,
# check (named-checkzone; the file is restored if it fails), reload, verification of the served serial.
# Run on ns1:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/fix_dns_serial.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
{ [ "$(hostname)" = ns1 ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.10/'; } || { echo "ERROR: run this script on ns1." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
TODAY=$(date +%Y%m%d)

ask "Did you take a PVE snapshot of ns1?" || { echo "Take it first: PVE > ns1 > Snapshots > Take Snapshot."; exit 1; }
mkdir -p "$BK"
conf=$(named-checkconf -p 2>/dev/null)
n=0
for zone in group4.umons 2.4.10.in-addr.arpa; do
    n=$((n + 1))
    file=$(echo "$conf" | awk -v z="$zone" '$0 ~ "zone \""z"\"" {f = 1} f && /file "/ {gsub(/[";]/, "", $2); print $2; exit}')
    echo
    echo "== Fix $n/2: serial of the zone $zone ($file)"
    [ -f "$file" ] || { echo "   ERROR: zone file not found in the configuration"; continue; }
    old=$(named-checkzone -D -o - "$zone" "$file" 2>/dev/null | awk '$4 == "SOA" {print $7; exit}')
    served=$(dig +short +time=2 +tries=1 @127.0.0.1 "$zone" SOA | awk '{print $3}')
    echo "   now: serial in the file $old, served by named $served"
    echo "   Why: the records changed on 2026-11-17 with the same serial; the serial tells every copy of the"
    echo "        zone that it changed (10.9). Format YYYYMMDDNN, it must grow."
    if [ "${old#"$TODAY"}" != "$old" ]; then
        echo "   already raised today ($old)"
        continue
    fi
    new=${TODAY}01
    [ "$new" -gt "$old" ] || new=$((old + 1))
    if ask "   Raise $old -> $new?"; then
        cp -a "$file" "$BK/"
        # only the first occurrence of the old serial (the SOA line)
        sed -i "0,/\b$old\b/s//$new/" "$file"
        if named-checkzone "$zone" "$file" >/dev/null; then
            rndc reload "$zone" >/dev/null 2>&1 || systemctl reload named
            sleep 2
            echo "   done: serial in the file $(named-checkzone -D -o - "$zone" "$file" 2>/dev/null | awk '$4 == "SOA" {print $7; exit}'), served $(dig +short +time=2 +tries=1 @127.0.0.1 "$zone" SOA | awk '{print $3}')"
        else
            cp -a "$BK/$(basename "$file")" "$file"
            echo "   ERROR: named-checkzone failed, file restored"
        fi
    fi
done

echo
echo "== Backups in $BK"
echo "== Running checks/full.sh (full regression test)"
sh "$REPO/checks/full.sh"
