#!/bin/sh
# Before a reboot (reboot test of ns1, open point 2): saves what a reboot destroys, so the
# evidence of the incident (W29: account mother, ice.py, ice2.py) is not lost.
# - Writes ONLY into /root/evidence/<vm>-<time>/ (root only, mode 700). Nothing else changes:
#   mother, ice, cron and the services are not touched (D28).
# - The saved files stay on the VM: some contain the password of mother (/tmp/.test, ice*.py).
#   Only the list of the saved files (name, size, sha256; no content) is pushed to
#   results/volatile-<vm>/. The hash of /tmp/.test is not published (short secret).
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/save_volatile.sh

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if ip -4 -o addr show | grep -q ' 10\.4\.255\.11/'; then VM=welcome
elif ip -4 -o addr show | grep -q ' 10\.4\.255\.10/'; then VM=ns1
else echo "ERROR: run it on welcome (10.4.255.11) or ns1 (10.4.255.10)." >&2; exit 1
fi
DIR=$(cd "$(dirname "$0")" && pwd)
TS=$(date '+%Y-%m-%d_%H%M')
D=/root/evidence/$VM-$TS

echo "== Save the volatile evidence of $VM before a reboot"
echo "Why: /tmp is emptied at boot and the running processes end. In /tmp there are the files"
echo "of ice (ice.py, .isice*, poiuytre*, .test) and the processes show since when ice runs."
echo "What is saved into $D (root only):"
echo "  - copies of /tmp/ice*, /tmp/.isice*, /tmp/poiuytre*, /tmp/next*, /tmp/.test (dates kept)"
echo "  - listing of /tmp and /usr/local/bin, /etc/crontab"
echo "  - processes (tree with start times), details of the ice processes, network sockets"
echo "  - logged-in users, last logins, journal of this boot (compressed)"
echo "Nothing else is changed. mother and ice are not touched (D28)."
printf "Proceed? [y/N] "
read -r a
[ "$a" = y ] || [ "$a" = Y ] || { echo "Nothing done."; exit 0; }

umask 077
mkdir -p "$D/tmp" && chmod 700 /root/evidence "$D" || { echo "ERROR: cannot create $D"; exit 1; }
for f in /tmp/ice* /tmp/.isice* /tmp/poiuytre* /tmp/next* /tmp/.test; do
    [ -e "$f" ] && cp -a "$f" "$D/tmp/"
done
ls -la --time-style=full-iso /tmp > "$D/tmp-listing.txt" 2>&1
ls -la --time-style=full-iso /usr/local/bin > "$D/usr-local-bin-listing.txt" 2>&1
cp -a /etc/crontab "$D/crontab"
ps -eo pid,ppid,user,lstart,etime,args --forest > "$D/processes.txt"
for p in $(pgrep -f '/usr/local/bin/ice2?\.py'); do
    {
        echo "== pid $p"
        tr '\0' ' ' < "/proc/$p/cmdline"; echo
        grep -E '^(Name|State|PPid|Uid|Gid):' "/proc/$p/status"
        echo "cwd: $(readlink "/proc/$p/cwd")"
        echo "open files:"; ls -l "/proc/$p/fd" 2>/dev/null | tail -n +2
    } >> "$D/ice-processes.txt"
done
ss -tunap > "$D/sockets.txt" 2>&1
{ echo "== who"; who -a; echo "== last"; last -F -w -n 300; } > "$D/logins.txt" 2>&1
{ echo "boot: $(uptime -s)"; echo "saved: $(date '+%Y-%m-%d %H:%M:%S %Z')"; } > "$D/times.txt"
journalctl -b -o short-iso --no-pager 2>/dev/null | gzip > "$D/journal-this-boot.txt.gz"
(cd "$D" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)

# verify and summary (pushed): names, sizes, hashes; no content, no hash of .test
N=$(find "$D" -type f | wc -l)
OUT=/tmp/save-volatile-$VM.txt
{
    echo "== Volatile evidence of $VM saved before a reboot ($TS)"
    echo "Folder on the VM: $D (root only, mode $(stat -c %a "$D")), $N files, $(du -sh "$D" | cut -f1)"
    echo "Last boot of the VM: $(uptime -s)"
    echo "ice processes saved: $(pgrep -fc '/usr/local/bin/ice2?\.py')"
    echo "Files (size, sha256):"
    (cd "$D" && find . -type f ! -name SHA256SUMS -printf '%P\t%s\n' | sort) | while IFS="$(printf '\t')" read -r f s; do
        case "$f" in
            tmp/.test) h="(hash not published: short secret)";;
            *) h=$(awk -v f="./$f" '$2 == f {print $1}' "$D/SHA256SUMS");;
        esac
        echo "  $f  $s bytes  $h"
    done
} > "$OUT"
cat "$OUT"
if [ "$N" -lt 5 ]; then
    echo "WARN: only $N files saved: check $D before rebooting."
fi
echo "Next: snapshot of $VM on the PVE (tick 'Include RAM'), then reboot, then: sudo sh checks/full.sh"
sh "$DIR/push-results.sh" "volatile-$VM" "$OUT"
