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
echo "== Fix 1/8: hostname 'welcome' (now: $(hostname))"
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
echo "== Fix 2/8: Postfix myhostname (now: $(postconf -h myhostname))"
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
echo "== Fix 3/8: remove BIND from welcome (W23)"
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
echo "== Fix 4/8: mynetworks only local (W3, W26)"
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
echo "== Fix 5/8: one mailbox format, Maildir (W27, D20)"
hm=$(postconf -h home_mailbox); mc=$(postconf -h mailbox_command)
inbox=$(doveconf -h mail_inbox_path 2>/dev/null)
echo "   now: Postfix home_mailbox='$hm' mailbox_command='$mc' | Dovecot mail_driver=$(doveconf -h mail_driver 2>/dev/null) mail_path=$(doveconf -h mail_path 2>/dev/null) mail_inbox_path='$inbox'"
echo "   Why: Postfix delivers to /var/mail/<user> (mbox) while Dovecot reads ~/Maildir:"
echo "        customers would not see their received mail over IMAP. Maildir: one file per mail."
if [ "$hm" = "Maildir/" ] && [ -z "$mc" ] && [ -z "$inbox" ]; then
    echo "   already done"
elif ask "   Apply?"; then
    cp -a /etc/postfix/main.cf "$BK/main.cf.fix5"
    files=$(grep -rlE '^[[:space:]]*mail_inbox_path[[:space:]]*=' /etc/dovecot 2>/dev/null)
    for f in $files; do cp -a --parents "$f" "$BK/"; done
    postconf -e 'home_mailbox = Maildir/'
    [ -n "$mc" ] && postconf -e 'mailbox_command ='
    for f in $files; do sed -i -E 's/^([[:space:]]*mail_inbox_path[[:space:]]*=.*)$/# \1   # group4 D20: Maildir, INBOX in ~\/Maildir/' "$f"; done
    if postfix check && doveconf -n >/dev/null 2>&1; then
        systemctl reload postfix; systemctl restart dovecot
        printf 'Subject: group4 Maildir test %s\n\nLocal test of fix 5.\n' "$(date '+%F %T')" | sendmail user
        sleep 3
        n=$(ls /home/user/Maildir/new 2>/dev/null | wc -l)
        echo "   done: home_mailbox=$(postconf -h home_mailbox), Dovecot mail_inbox_path='$(doveconf -h mail_inbox_path 2>/dev/null)'"
        if [ "$n" -gt 0 ]; then echo "   OK: local test mail delivered in /home/user/Maildir/new ($n file)"; else echo "   WARN: test mail not found in /home/user/Maildir/new (see: journalctl -t postfix/local)"; fi
    else
        cp -a "$BK/main.cf.fix5" /etc/postfix/main.cf
        for f in $files; do cp -a "$BK$f" "$f"; done
        echo "   ERROR: postfix check or doveconf failed, files restored"
    fi
fi

echo
ACCOUNTS="calogero"
echo "== Fix 6/8: dedicated mail accounts ($ACCOUNTS), mail login only for the group mailusers (W1, D24)"
echo "   now: group mailusers: $(getent group mailusers | cut -d: -f4)"
echo "        PAM rule in /etc/pam.d/dovecot: $(grep -c 'pam_succeed_if.so user ingroup mailusers' /etc/pam.d/dovecot 2>/dev/null)"
echo "   Why: the template password of 'user' must not open the mail; a mail account gets"
echo "        shell nologin (mail only, no login on the VM). Only members of mailusers can log in"
echo "        to IMAP (and later to 587): 'user' and 'mother' are excluded."
todo=""
for a in $ACCOUNTS; do id "$a" >/dev/null 2>&1 && id -nG "$a" | grep -qw mailusers || todo=1; done
grep -q 'pam_succeed_if.so user ingroup mailusers' /etc/pam.d/dovecot 2>/dev/null || todo=1
if [ -z "$todo" ]; then
    echo "   already done"
elif ask "   Apply? (you will type a password for each new account)"; then
    cp -a /etc/pam.d/dovecot "$BK/pam.d-dovecot"
    groupadd -f mailusers
    for a in $ACCOUNTS; do
        if ! id "$a" >/dev/null 2>&1; then
            adduser --disabled-password --gecos "" --shell /usr/sbin/nologin "$a" >/dev/null
            echo "   password for $a (mail login):"
            until passwd "$a"; do echo "   try again"; done
        fi
        usermod -aG mailusers "$a"
    done
    if ! grep -q 'pam_succeed_if.so user ingroup mailusers' /etc/pam.d/dovecot; then
        if head -1 /etc/pam.d/dovecot | grep -q '^#%PAM'; then
            sed -i '1a auth    required    pam_succeed_if.so user ingroup mailusers quiet' /etc/pam.d/dovecot
        else
            sed -i '1i auth    required    pam_succeed_if.so user ingroup mailusers quiet' /etc/pam.d/dovecot
        fi
    fi
    echo "   done: mailusers = $(getent group mailusers | cut -d: -f4)"
    echo "   Test the login (type the password when asked):"
    for a in $ACCOUNTS; do doveadm auth test "$a" 2>&1 | grep -E 'succeeded|failed' | sed 's/^/      /'; done
    echo "   Test that 'user' is refused (type its password 'user'):"
    doveadm auth test user 2>&1 | grep -E 'succeeded|failed' | sed 's/^/      /'
fi

echo
echo "== Fix 7/8: IMAP only on 993, port 143 closed (W24, D25)"
echo "   now: listening on 143: $(ss -Htln | awk '{print $4}' | grep -cE '[:.]143$') socket(s)"
echo "   Why: on 143 a client may send the password before switching to TLS; 993 is TLS from the first byte."
DROP=/etc/dovecot/conf.d/99-group4.conf
if ! ss -Htln | awk '{print $4}' | grep -qE '[:.]143$'; then
    echo "   already done"
elif ask "   Apply?"; then
    [ -f "$DROP" ] && cp -a "$DROP" "$BK/"
    cat >> "$DROP" <<'EOF'
# group4 D25: no IMAP on 143, only IMAP over TLS on 993
service imap-login {
  inet_listener imap {
    port = 0
  }
}
EOF
    if doveconf -n >/dev/null 2>&1; then
        systemctl restart dovecot; sleep 2
        echo "   done: 143 $(ss -Htln | awk '{print $4}' | grep -qE '[:.]143$' && echo STILL OPEN || echo closed), 993 $(ss -Htln | awk '{print $4}' | grep -qE '[:.]993$' && echo open || echo CLOSED)"
    else
        if [ -f "$BK/99-group4.conf" ]; then cp -a "$BK/99-group4.conf" "$DROP"; else rm -f "$DROP"; fi
        echo "   ERROR: doveconf failed ($(doveconf -n 2>&1 | head -1)), file restored"
    fi
fi

echo
echo "== Fix 8/8: Postfix protections (D26)"
echo "   now: VRFY disabled=$(postconf -h disable_vrfy_command), HELO required=$(postconf -h smtpd_helo_required), banner='$(postconf -h smtpd_banner)', connections per client per minute=$(postconf -h smtpd_client_connection_rate_limit)"
echo "   Why: VRFY lists valid users; the banner names the software; crude spam and scan tools"
echo "        send no HELO; without a limit one client can open hundreds of connections."
if [ "$(postconf -h disable_vrfy_command)" = yes ] && [ "$(postconf -h smtpd_helo_required)" = yes ] \
   && [ "$(postconf -h smtpd_banner)" = '$myhostname ESMTP' ] && [ "$(postconf -h smtpd_client_connection_rate_limit)" = 30 ]; then
    echo "   already done"
elif ask "   Apply?"; then
    cp -a /etc/postfix/main.cf "$BK/main.cf.fix8"
    postconf -e 'disable_vrfy_command = yes' 'smtpd_helo_required = yes' 'smtpd_banner = $myhostname ESMTP' 'smtpd_client_connection_rate_limit = 30'
    if postfix check; then
        systemctl reload postfix
        echo "   done: greeting $(python3 -I -c 'import socket; s = socket.create_connection(("127.0.0.1", 25), 3); print(s.recv(200).decode().strip())' 2>/dev/null)"
    else
        cp -a "$BK/main.cf.fix8" /etc/postfix/main.cf
        echo "   ERROR: postfix check failed, main.cf restored"
    fi
fi

echo
echo "== Backups in $BK"
echo "== Running checks/welcome.sh"
sh "$REPO/checks/welcome.sh"
