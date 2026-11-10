#!/bin/sh
# Fixes for the welcome VM (10.4.255.11). For each fix: current state, reason,
# confirmation [y/N], backup of the files it changes, change, check.
# At the end it runs checks/welcome.sh, which pushes the result.
# Take a PVE snapshot of welcome first.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/fix_welcome.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
ip -4 -o addr show | grep -q ' 10\.4\.255\.11/' || { echo "ERROR: run this script on welcome (10.4.255.11)." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
mkdir -p "$BK"
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }

ask "Did you take a PVE snapshot of welcome?" || { echo "Take it first: PVE > welcome > Snapshots > Take Snapshot."; exit 1; }

echo
echo "== Fix 1/4: hostname 'welcome' (now: $(hostname))"
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
echo "== Fix 2/4: Postfix myhostname (now: $(postconf -h myhostname))"
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
echo "== Fix 3/4: remove BIND from welcome (W23)"
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
LOCAL='127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128'
cur=$(postconf -h mynetworks)
echo "== Fix 4/4: mynetworks only local (W3, W26)"
echo "   now: $cur"
echo "   Why: entries like 10.1.255.0/16 have host bits set: Postfix cannot evaluate them and"
echo "        answers '451 Temporary lookup failure' to every remote sender (seen from ns1 at"
echo "        19:07), so no mail from the other groups reaches us. The list also aimed to let"
echo "        every group send through us without login (open relay)."
echo "        Local only: programs on welcome can still send; customers will send with login on 587."
if [ "$cur" = "$LOCAL" ]; then
    echo "   already done"
elif ask "   Apply?"; then
    cp -a /etc/postfix/main.cf "$BK/main.cf.fix4"
    postconf -e "mynetworks = $LOCAL"
    if postfix check; then
        systemctl reload postfix
        echo "   done: mynetworks = $(postconf -h mynetworks)"
        echo "   check from ns1: sudo sh checks/ns1.sh (section 8: relay 554, postmaster 250, unknown user 550)"
    else
        cp -a "$BK/main.cf.fix4" /etc/postfix/main.cf
        echo "   ERROR: postfix check failed, main.cf restored"
    fi
fi

echo
echo "== Backups in $BK"
echo "== Running checks/welcome.sh"
sh "$REPO/checks/welcome.sh"
