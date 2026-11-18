#!/bin/sh
# What the other groups get for our names (read-only, a few seconds): answer of the course resolver
# (10.4.255.254) and of ns1, time left before the course resolver asks us again, and the clock time
# at which an old answer expires by itself. Expected since 2026-11-17: 10.4.255.1 (pfSense).
# Run on any VM:  cd ~/Desktop/group4-welcome && git pull && sh checks/public_dns.sh
PUBLIC=10.4.255.1
now=$(date +%s)
echo "== Our names for the other groups ($(date '+%Y-%m-%d %H:%M')); expected $PUBLIC"
for name in welcome.group4.umons mail.group4.umons ns1.group4.umons; do
    line=$(dig +noall +answer +time=2 +tries=1 @10.4.255.254 "$name" A | awk '$4 == "A" {print $2, $5; exit}')
    ttl=${line%% *}; ip=${line#* }
    ns1=$(dig +short +time=2 +tries=1 @10.4.2.10 "$name" A | head -1)
    if [ -z "$line" ]; then
        echo "FAIL  $name: no answer from the course resolver (ns1 answers ${ns1:-nothing})"
    elif [ "$ip" = "$PUBLIC" ]; then
        echo "OK    $name -> $ip for the other groups (ns1: ${ns1:-?})"
    else
        echo "FAIL  $name -> $ip for the other groups (old answer kept in memory); it expires in $((ttl / 60)) min, at $(date -d "@$((now + ttl))" '+%H:%M'); ns1 already answers ${ns1:-?}"
    fi
done
mx=$(dig +short +time=2 +tries=1 @10.4.255.254 group4.umons MX)
echo "INFO  MX of group4.umons for the other groups: ${mx:-none}"
echo "When every line is OK: open http://welcome.group4.umons from a machine outside (WAN side)."
echo "To get there before the expiry: IP alias 10.4.255.11 on the WAN of pfSense with the same forwards"
echo "(DOCUMENTATION.md 7.4), or ask the teacher to clear the cache of his resolver."
