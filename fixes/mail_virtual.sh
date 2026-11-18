#!/bin/sh
# Virtual mailboxes on welcome: "New 4.3" of Fabio (docs/new-4.3.md) with the five fixes of its review (2026-11-18):
#   1. Dovecot 2.4 syntax (sql_driver, mysql block, passdb/userdb sql, %{user});
#   2. one mailbox folder for Postfix and Dovecot: /var/vmail/<domain>/<user>/Maildir/;
#   3. three database users with the least rights: postfix and dovecot SELECT, register INSERT only;
#   4. postmaster@group4.umons as an alias in the database;
#   5. users with an 'active' flag: only active users receive and log in (registration with approval).
# Steps, each shown and confirmed: 1 packages, 2 user vmail, 3 database, 4 account calogero + mailbox,
# 5 Dovecot, 6 Postfix, 7 tests. If a test fails, the previous configuration is put back.
# Order chosen so that no mail is refused: the account exists before Postfix switches to the database.
# Manual steps: DOCUMENTATION.md 10.25. Mail accounts afterwards: sudo sh fixes/mail_users.sh
# Take a PVE snapshot of welcome first.
# Run on welcome:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/mail_virtual.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
{ [ "$(hostname)" = welcome ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.11/'; } || { echo "ERROR: run this script on welcome." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
DOMAIN=group4.umons
VMAIL=/var/vmail
SECRETS=/etc/group4-mail          # passwords of the database users, root only
DOVECONF=/etc/dovecot/conf.d/99-group4-virtual.conf
PFMBOX=/etc/postfix/mysql-virtual-mailbox-maps.cf
PFALIAS=/etc/postfix/mysql-virtual-alias-maps.cf
sql() { mysql -N mailserver -e "$1" 2>/dev/null; }
pw_of() {  # password of a database user: created once, kept in $SECRETS
    f="$SECRETS/$1.pw"
    [ -s "$f" ] || { umask 077; openssl rand -base64 30 | tr -d '/+=\n' | cut -c1-28 > "$f"; }
    cat "$f"
}

echo "== Virtual mailboxes on welcome (NOTES New 4.3 with the five fixes)"
dv=$(dovecot --version 2>/dev/null)
echo "   Dovecot $dv, Postfix $(postconf -h mail_version), mail domain $DOMAIN"
case "$dv" in 2.4*) ;; *) echo "ERROR: this script writes the Dovecot 2.4 syntax; found '$dv'. Nothing done."; exit 1;; esac
echo "   now: Dovecot configuration $(doveconf -n >/dev/null 2>&1 && echo loads || echo 'does NOT load'), dovecot $(systemctl is-active dovecot);"
echo "        includes in 10-auth.conf: $(grep -E '^[[:space:]]*!include auth-' /etc/dovecot/conf.d/10-auth.conf | tr -s ' ' | tr '\n' ' ')"
echo "        Postfix mydestination = $(postconf -h mydestination); virtual_mailbox_domains = '$(postconf -h virtual_mailbox_domains)'"
echo "   (a New 4.3 started by hand is completed: auth-sql include commented, missing columns added,"
echo "    user 'mailuser' with all rights removed, Postfix maps rewritten)"
ask "Did you take a PVE snapshot of welcome?" || { echo "Take it first: PVE > welcome > Snapshots > Take Snapshot."; exit 1; }
mkdir -p "$BK"
cp -a /etc/postfix/main.cf "$BK/main.cf"
for f in "$PFMBOX" "$PFALIAS"; do [ -f "$f" ] && cp -a "$f" "$BK/"; done
tar -czf "$BK/etc-dovecot.tar.gz" -C / etc/dovecot
echo "   copies of the current mail configuration in $BK"

restore() {
    echo "== Putting back the previous configuration"
    cp -a "$BK/main.cf" /etc/postfix/main.cf
    rm -f /etc/dovecot/conf.d/99-group4-virtual.conf
    tar -xzf "$BK/etc-dovecot.tar.gz" -C /
    for f in "$PFMBOX" "$PFALIAS"; do [ -f "$BK/$(basename "$f")" ] && cp -a "$BK/$(basename "$f")" "$f"; done
    postfix check && systemctl reload postfix
    if doveconf -n >/dev/null 2>&1; then
        systemctl restart dovecot
        echo "   done: Postfix and Dovecot as before (MariaDB, vmail and the database stay, unused)"
    else
        echo "   Postfix as before; the previous Dovecot configuration does not load either: Dovecot NOT restarted"
    fi
}

echo
echo "== Step 1/7: packages (MariaDB, Dovecot and Postfix modules for MySQL)"
missing=""
for p in mariadb-server dovecot-mysql postfix-mysql; do dpkg -l "$p" 2>/dev/null | grep -q '^ii' || missing="$missing $p"; done
if [ -z "$missing" ]; then
    echo "   already installed"
elif ask "   Install$missing?"; then
    apt-get update -q >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -q $missing >/dev/null \
        || { echo "   ERROR: installation failed"; exit 1; }
    echo "   done"
else
    echo "Nothing installed: stop."; exit 0
fi
systemctl enable --now mariadb >/dev/null 2>&1
echo "   MariaDB $(systemctl is-active mariadb), listening on: $(ss -Htln | awk '$4 ~ /:3306$/ {print $4}' | tr '\n' ' ')"
ss -Htln | awk '$4 ~ /:3306$/ {print $4}' | grep -vqE '^(127\.0\.0\.1|\[::1\]):3306$' && echo "   WARN: MariaDB listens on more than localhost: check bind-address in /etc/mysql/mariadb.conf.d/50-server.cnf"

echo
echo "== Step 2/7: system user vmail (uid and gid 5000), owner of all the mailboxes in $VMAIL"
echo "   Why: the mail accounts are no longer Linux accounts; one user without login keeps every mailbox."
if [ "$(id -u vmail 2>/dev/null)" = 5000 ]; then
    echo "   already there: $(getent passwd vmail)"
    case "$(getent passwd vmail | cut -d: -f7)" in
        */nologin|*/false) ;;
        *) usermod -s /usr/sbin/nologin vmail && echo "   login shell removed: $(getent passwd vmail | cut -d: -f7)" ;;
    esac
    [ -d "$VMAIL" ] && chmod 770 "$VMAIL"
elif getent passwd 5000 >/dev/null || getent group 5000 >/dev/null; then
    echo "   ERROR: uid or gid 5000 already used by another account: $(getent passwd 5000 | cut -d: -f1)"; exit 1
elif ask "   Create it?"; then
    groupadd -g 5000 vmail && useradd -g vmail -u 5000 -d "$VMAIL" -m -s /usr/sbin/nologin vmail
    chmod 770 "$VMAIL"
    echo "   done: $(getent passwd vmail)"
else
    exit 0
fi

echo
echo "== Step 3/7: database 'mailserver' (users with an 'active' flag, aliases) and its three users"
echo "   Why: fix 3 (least rights) and fix 4 (postmaster), fix 5 (approval)."
mkdir -p "$SECRETS" && chmod 700 "$SECRETS"
if ask "   Create or update the database and its users?"; then
    mysql -e "DELETE FROM mysql.global_priv WHERE User=''; DROP DATABASE IF EXISTS test; FLUSH PRIVILEGES;" 2>/dev/null
    mysql <<SQL || { echo "   ERROR: database not created"; exit 1; }
CREATE DATABASE IF NOT EXISTS mailserver CHARACTER SET utf8mb4;
USE mailserver;
CREATE TABLE IF NOT EXISTS virtual_users (
  id INT NOT NULL AUTO_INCREMENT,
  email VARCHAR(128) NOT NULL,
  password VARCHAR(255) NOT NULL,
  active TINYINT(1) NOT NULL DEFAULT 0,
  created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id), UNIQUE KEY email (email));
CREATE TABLE IF NOT EXISTS virtual_aliases (
  id INT NOT NULL AUTO_INCREMENT,
  source VARCHAR(128) NOT NULL,
  destination VARCHAR(128) NOT NULL,
  PRIMARY KEY (id), UNIQUE KEY source (source));
ALTER TABLE virtual_users
  ADD COLUMN IF NOT EXISTS active TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  MODIFY password VARCHAR(255) NOT NULL;
DROP USER IF EXISTS 'mailuser'@'127.0.0.1';
DROP USER IF EXISTS 'mailuser'@'localhost';
INSERT IGNORE INTO virtual_aliases (source, destination) VALUES ('postmaster@$DOMAIN', 'calogero@$DOMAIN');
CREATE USER IF NOT EXISTS 'postfix'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'dovecot'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'register'@'127.0.0.1';
ALTER USER 'postfix'@'127.0.0.1' IDENTIFIED BY '$(pw_of postfix)';
ALTER USER 'dovecot'@'127.0.0.1' IDENTIFIED BY '$(pw_of dovecot)';
ALTER USER 'register'@'127.0.0.1' IDENTIFIED BY '$(pw_of register)';
GRANT SELECT ON mailserver.* TO 'postfix'@'127.0.0.1';
GRANT SELECT ON mailserver.* TO 'dovecot'@'127.0.0.1';
GRANT INSERT ON mailserver.virtual_users TO 'register'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
    echo "   done: tables $(sql 'SHOW TABLES' | tr '\n' ' '); aliases: $(sql "SELECT CONCAT(source,' -> ',destination) FROM virtual_aliases" | tr '\n' ' ')"
    echo "   database passwords in $SECRETS (root only); the one of 'register' is for the web form later"
else
    exit 0
fi

echo
echo "== Step 4/7: account calogero@$DOMAIN in the database, mailbox moved to $VMAIL"
CAL="calogero@$DOMAIN"
CALDIR="$VMAIL/$DOMAIN/calogero/Maildir"
if [ "$(sql "SELECT active FROM virtual_users WHERE email='$CAL'")" = 1 ] && [ -d "$CALDIR" ]; then
    echo "   already done"
elif ask "   Create it? (you will type its new password twice; choose a long one, W31)"; then
    hash=$(doveadm pw -s SHA512-CRYPT) || { echo "   ERROR: password not set"; exit 1; }
    case "$hash" in "{SHA512-CRYPT}"*) ;; *) echo "   ERROR: unexpected hash"; exit 1;; esac
    sql "INSERT INTO virtual_users (email, password, active) VALUES ('$CAL', '$hash', 1) ON DUPLICATE KEY UPDATE password = VALUES(password), active = 1"
    mkdir -p "$VMAIL/$DOMAIN/calogero"
    if [ -d /home/calogero/Maildir ] && [ ! -d "$CALDIR" ]; then
        cp -a /home/calogero/Maildir "$CALDIR"
        echo "   old mailbox copied (the original stays in /home/calogero/Maildir)"
    fi
    chown -R vmail:vmail "$VMAIL"
    echo "   done: $(sql "SELECT CONCAT(email, ' active=', active) FROM virtual_users WHERE email='$CAL'"); mails: $(find "$CALDIR/new" "$CALDIR/cur" -type f 2>/dev/null | wc -l)"
else
    exit 0
fi

echo
echo "== Step 5/7: Dovecot logs in from the database (fix 1: Dovecot 2.4 syntax)"
if [ -f "$DOVECONF" ] && doveconf -n 2>/dev/null | grep -q 'passdb sql' \
   && ! grep -qE '^[[:space:]]*!include auth-(system|sql)\.conf\.ext' /etc/dovecot/conf.d/10-auth.conf; then
    echo "   already done"
elif ask "   Apply?"; then
    # login from the database is in $DOVECONF: the system login (PAM) and the 2.3-syntax SQL include are switched off
    sed -i -E 's/^([[:space:]]*!include auth-(system|sql)\.conf\.ext)/#\1   # group4: logins from the database (mail_virtual.sh)/' /etc/dovecot/conf.d/10-auth.conf
    umask 077
    cat > "$DOVECONF" <<EOF
# group4: virtual mailboxes (fixes/mail_virtual.sh, NOTES New 4.3 with its review)
sql_driver = mysql
mysql 127.0.0.1 {
  user = dovecot
  password = $(pw_of dovecot)
  dbname = mailserver
}
# only active users can log in (registration with approval)
passdb sql {
  query = SELECT email AS user, password FROM virtual_users WHERE email = '%{user}' AND active = 1
}
userdb sql {
  query = SELECT 5000 AS uid, 5000 AS gid FROM virtual_users WHERE email = '%{user}'
  iterate_query = SELECT email AS user FROM virtual_users
}
# one folder for Postfix and Dovecot (fix 2): /var/vmail/<domain>/<user>/Maildir
mail_home = $VMAIL/%{user | domain}/%{user | username}
mail_path = %{home}/Maildir
mail_uid = vmail
mail_gid = vmail
first_valid_uid = 5000
EOF
    chown root:dovecot "$DOVECONF"; chmod 640 "$DOVECONF"
    if doveconf -n >/dev/null 2>"$BK/doveconf.err"; then
        systemctl restart dovecot && sleep 2
        echo "   done: dovecot $(systemctl is-active dovecot); $(doveadm user "$CAL" 2>&1 | grep -E 'home|uid' | tr -s ' ' | tr '\n' ' ')"
        if doveconf -n 2>/dev/null | grep -q 'passdb pam'; then
            echo "   WARN: the old login through PAM is still active (passdb pam): comment its include by hand (DOCUMENTATION 10.25)"
        fi
    else
        echo "   ERROR: doveconf refuses the new configuration:"; head -5 "$BK/doveconf.err" | sed 's/^/      /'
        restore; exit 1
    fi
else
    exit 0
fi

echo
echo "== Step 6/7: Postfix delivers @$DOMAIN to the virtual mailboxes"
echo "   Why: $DOMAIN leaves mydestination (a domain cannot be local and virtual); recipients and aliases"
echo "        are read in the database; mails written to $VMAIL/<domain>/<user>/Maildir/ as vmail."
if [ "$(postconf -h virtual_mailbox_domains)" = "$DOMAIN" ] && [ "$(postconf -h virtual_alias_maps)" = "mysql:$PFALIAS" ] \
   && grep -q '^user = postfix' "$PFMBOX" 2>/dev/null && grep -q "/Maildir/')" "$PFMBOX"; then
    echo "   already done"
elif ask "   Apply?"; then
    umask 027
    cat > "$PFMBOX" <<EOF
user = postfix
password = $(pw_of postfix)
hosts = 127.0.0.1
dbname = mailserver
query = SELECT CONCAT(SUBSTRING_INDEX(email,'@',-1),'/',SUBSTRING_INDEX(email,'@',1),'/Maildir/') FROM virtual_users WHERE email='%s' AND active = 1
EOF
    cat > "$PFALIAS" <<EOF
user = postfix
password = $(pw_of postfix)
hosts = 127.0.0.1
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOF
    chown root:postfix "$PFMBOX" "$PFALIAS"; chmod 640 "$PFMBOX" "$PFALIAS"
    postconf -e 'mydestination = $myhostname, localhost.$mydomain, localhost' \
        "virtual_mailbox_domains = $DOMAIN" "virtual_mailbox_base = $VMAIL" \
        "virtual_mailbox_maps = mysql:$PFMBOX" "virtual_alias_maps = mysql:$PFALIAS" \
        'virtual_minimum_uid = 100' 'virtual_uid_maps = static:5000' 'virtual_gid_maps = static:5000'
    if postfix check 2>&1 | grep -q 'fatal\|error'; then
        echo "   ERROR: postfix check: $(postfix check 2>&1 | head -2)"; restore; exit 1
    fi
    systemctl reload postfix
    echo "   done: virtual_mailbox_domains = $(postconf -h virtual_mailbox_domains)"
else
    exit 0
fi

echo
echo "== Step 7/7: tests"
ok=1
r=$(postmap -q "$CAL" "mysql:$PFMBOX" 2>&1)
if [ "$r" = "$DOMAIN/calogero/Maildir/" ]; then echo "   OK   Postfix finds $CAL: $r"; else echo "   FAIL Postfix lookup of $CAL: $r"; ok=0; fi
r=$(postmap -q "postmaster@$DOMAIN" "mysql:$PFALIAS" 2>&1)
if [ "$r" = "$CAL" ]; then echo "   OK   postmaster@$DOMAIN -> $r"; else echo "   FAIL alias postmaster: $r"; ok=0; fi
r=$(doveadm user "$CAL" 2>&1 | awk '$1 == "home" {print $2}')
if [ "$r" = "$VMAIL/$DOMAIN/calogero" ]; then echo "   OK   Dovecot home of $CAL: $r"; else echo "   FAIL Dovecot home of $CAL: '$r'"; ok=0; fi
if doveadm auth test user user 2>&1 | grep -q 'auth failed'; then echo "   OK   the Linux account 'user' cannot log in to the mail"; else echo "   FAIL 'user' can log in to the mail"; ok=0; fi
echo "   Login of $CAL (type its new password):"
if doveadm auth test "$CAL" 2>&1 | tee /dev/stderr | grep -q 'auth succeeded'; then echo "   OK   login of $CAL"; else echo "   FAIL login of $CAL"; ok=0; fi
before=$(ls "$CALDIR/new" 2>/dev/null | wc -l)
printf 'Subject: group4 virtual mailbox test %s\n\nDelivery test of fixes/mail_virtual.sh.\n' "$(date '+%F %T')" | /usr/sbin/sendmail "$CAL"
i=0; while [ "$(ls "$CALDIR/new" 2>/dev/null | wc -l)" -le "$before" ] && [ $i -lt 15 ]; do sleep 1; i=$((i + 1)); done
if [ "$(ls "$CALDIR/new" 2>/dev/null | wc -l)" -gt "$before" ]; then
    echo "   OK   test mail delivered in $CALDIR/new (owner $(stat -c %U "$CALDIR/new"))"
else
    echo "   FAIL test mail not delivered: sudo journalctl -t postfix/virtual -n 5"; ok=0
fi
if [ $ok = 0 ]; then
    if ask "Some tests failed. Put back the previous configuration (recommended)?"; then restore; fi
else
    echo "All tests passed. Log in to the mail with the full address ($CAL) from now on."
fi

echo
echo "== Backups in $BK"
echo "== Running checks/full.sh (full regression test)"
sh "$REPO/checks/full.sh"
