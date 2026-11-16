#!/bin/sh
# Menu of the activities on the VMs: update the scripts, checks (read-only), changes (with confirmation).
# It shows only the activities of the VM where it runs, with the date of the last result of each check.
# Run as user (it asks the sudo password when needed):
#   cd ~/Desktop/group4-welcome && sh action.sh
cd "$(dirname "$0")" || exit 1

if ip -4 -o addr show | grep -q ' 10\.4\.255\.11/' || [ "$(hostname)" = welcome ]; then VM=welcome
elif ip -4 -o addr show | grep -q ' 10\.4\.255\.10/' || [ "$(hostname)" = ns1 ]; then VM=ns1
else echo "ERROR: run it on welcome or ns1." >&2; exit 1
fi

# key | VM (both, welcome, ns1) | command | results folder | description
LIST='p|both|git pull|-|Update the scripts (always first)
1|both|sudo sh checks/full.sh|full-VM|Full test of everything documented (on welcome it also asks for the mail login test)
2|welcome|sudo sh checks/suricata.sh|suricata|Suricata: installation, settings, rules, running, test alert (DOCUMENTATION 10.17)
3|both|sudo sh checks/ice_watch.sh|ice-watch-VM|What ice and mother do now, compared with 2026-11-12 (SAME / CHANGED)
4|both|sudo sh checks/ice_timing.sh|ice-timing-VM|How often ice attacks (logins of mother per source, rounds of ice)
5|welcome|sudo sh checks/mail_exchange.sh|mail-exchange|Mail exchange with the other providers (sends a test mail only if you choose a group)
6|both|sudo sh checks/evidence_ice.sh|evidence-VM|Evidence of ice: its code with secrets redacted, orders of the servers (not executed)
7|welcome|sudo sh deploy.sh|-|CHANGE: publish the welcome page from index.md
8|welcome|sudo sh fixes/fix_welcome.sh|-|CHANGE: fixes 1-9 of welcome (each asks y/N; "already done" when nothing to do)
9|welcome|sudo sh fixes/fix_suricata.sh|-|CHANGE: repair Suricata (card, HOME_NET, rules, test, start, test alert)
10|ns1|sudo sh fixes/fix_ns1.sh|-|CHANGE: fixes of ns1 (network by NetworkManager, one PTR)
11|both|sudo sh checks/save_volatile.sh|volatile-VM|CHANGE: before a reboot, save the evidence of /tmp in /root/evidence (root only)'

# recommended order for each VM (key r)
if [ "$VM" = welcome ]; then SEQ="p 2 1 3 5"; else SEQ="p 1 3"; fi

last() {  # date of the last result of a check
    d=$(echo "$1" | sed "s/VM/$VM/")
    [ "$d" = - ] && return
    f=$(ls results/"$d"/ 2>/dev/null | grep -v latest | sort | tail -1)
    [ -n "$f" ] && printf '   (last: %s)' "$(echo "$f" | sed 's/\.txt$//; s/_/ /')" || printf '   (never run)'
}

run() {  # run one activity by key
    line=$(echo "$LIST" | awk -F'|' -v k="$1" '$1 == k')
    [ -n "$line" ] || { echo "No activity '$1'."; return; }
    vm=$(echo "$line" | cut -d'|' -f2); cmd=$(echo "$line" | cut -d'|' -f3)
    if [ "$vm" != both ] && [ "$vm" != "$VM" ]; then echo "Activity $1 is for $vm, not for $VM."; return; fi
    echo; echo ">>> $cmd"
    if [ "$1" = p ]; then
        git pull && echo "Commit now: $(git log -1 --oneline)" && exec sh "$0"
    else
        sh -c "$cmd"
    fi
    echo; printf 'Done. Press Enter for the menu. '; read -r _
}

while :; do
    echo
    echo "== Activities on $VM ($(git log -1 --format='%h %cd' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null), $(date '+%Y-%m-%d %H:%M'))"
    echo "$LIST" | while IFS='|' read -r k vm cmd res desc; do
        [ "$vm" = both ] || [ "$vm" = "$VM" ] || continue
        printf '  %3s  %s%s\n' "$k" "$desc" "$(last "$res")"
    done
    echo "    r  Recommended order for $VM: $SEQ (asks before each one)"
    echo "    q  Quit"
    printf 'Choice: '; read -r c
    case "$c" in
        q|Q|'') exit 0 ;;
        r|R)
            for k in $SEQ; do
                desc=$(echo "$LIST" | awk -F'|' -v k="$k" '$1 == k {print $5}')
                printf '\nNext: %s. Run it? [y/N/q] ' "$desc"; read -r a
                case "$a" in
                    y|Y) if [ "$k" = p ]; then git pull && echo "Commit now: $(git log -1 --oneline)"; else run "$k"; fi ;;
                    q|Q) break ;;
                esac
            done ;;
        *) run "$c" ;;
    esac
done
