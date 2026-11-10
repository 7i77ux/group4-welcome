#!/bin/sh
# Fixes for the welcome VM (10.4.255.11). For each fix: current state, reason,
# confirmation [y/N], backup of the files it changes, change, check.
# At the end it runs checks/welcome.sh, which pushes the result.
# Take a PVE snapshot of welcome first.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/welcome.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
ip -4 -o addr show | grep -q ' 10\.4\.255\.11/' || { echo "ERROR: run this script on welcome (10.4.255.11)." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
mkdir -p "$BK"
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }

ask "Did you take a PVE snapshot of welcome?" || { echo "Take it first: PVE > welcome > Snapshots > Take Snapshot."; exit 1; }

echo
echo "== Fix 1/3: hostname 'welcome' (now: $(hostname))"
echo "   Why: with the name 'debian' it is easy to work on the wrong VM (W19)."
if [ "$(hostname)" = welcome ] && grep -Eq '^127\.0\.1\.1[[:space:]]+welcome([[:space:]]|$)' /etc/hosts; then
    echo "   already done"
elif ask "   Apply?"; then
    cp -a /etc/hostname /etc/hosts "$BK/"
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
        sed -i 's/^127\.0\.1\.1.*/127.0.1.1\twelcome/' /etc/hosts
    else
        printf '127.0.1.1\twelcome\n' >> /etc/hosts
    fi
    hostnamectl set-hostname welcome
    echo "   done: hostname $(hostname), $(grep '^127\.0\.1\.1' /etc/hosts | tr '\t' ' ')"
fi

echo
echo "== Fix 2/3: Postfix myhostname (now: $(postconf -h myhostname))"
echo "   Why: it is the name announced to the other mail servers (greeting, HELO);"
echo "        it must exist in DNS and match the MX: mail.group4.umons."
if [ "$(postconf -h myhostname)" = mail.group4.umons ]; then
    echo "   already done"
elif ask "   Apply?"; then
    cp -a /etc/postfix/main.cf "$BK/"
    postconf -e 'myhostname = mail.group4.umons'
    if postfix check; then
        systemctl reload postfix
        echo "   done: myhostname = $(postconf -h myhostname)"
    else
        cp -a "$BK/main.cf" /etc/postfix/main.cf
        echo "   ERROR: postfix check failed, main.cf restored"
    fi
fi

echo
echo "== Fix 3/3: remove BIND from welcome (W23)"
if ! dpkg -l bind9 2>/dev/null | grep -q '^ii'; then
    echo "   already removed"
else
    echo "   Why: leftover from 2026-11-04 (this VM was first meant to be NS1). The DNS of"
    echo "        group4.umons is ns1; here BIND only opens port 53 on 10.4.255.11."
    echo "   Zones configured here, besides the Debian default ones:"
    named-checkconf -z 2>&1 | grep 'loaded serial' \
        | grep -vE 'zone (localhost|127\.in-addr\.arpa|0\.in-addr\.arpa|255\.in-addr\.arpa)/' \
        | sed 's/^/      /'
    dns=$(resolvectl dns 2>/dev/null | tr '\n' ' ')
    echo "   DNS servers used by welcome: $dns"
    skip=""
    case "$dns" in *127.0.0.1*|*10.4.255.11*) skip=1; echo "   STOP: welcome uses its own BIND as resolver, not removed.";; esac
    if [ -z "$skip" ] && ask "   Remove it? (backup of /etc/bind first; dig is kept)"; then
        tar -czf "$BK/etc-bind.tar.gz" -C / etc/bind
        systemctl disable --now named >/dev/null 2>&1 || true
        if apt-get purge -y -q bind9 >/dev/null; then
            echo "   done: bind9 removed (dig still at $(command -v dig))"
        else
            echo "   ERROR: apt-get purge bind9 failed"
        fi
    fi
fi

echo
echo "== Backups in $BK"
echo "== Running checks/welcome.sh"
sh "$REPO/checks/welcome.sh"
