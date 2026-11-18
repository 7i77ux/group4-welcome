#!/bin/sh
# Mail accounts of the virtual mailboxes (after fixes/mail_virtual.sh). Accounts live in the database
# mailserver.virtual_users; only active accounts receive mail and log in (registration with approval).
#   sudo sh fixes/mail_users.sh list
#   sudo sh fixes/mail_users.sh add <name>         new active account <name>@group4.umons (password typed twice)
#   sudo sh fixes/mail_users.sh activate <name>    approve an account created by the registration form
#   sudo sh fixes/mail_users.sh disable <name>     no more login and no more mail (the mailbox stays)
#   sudo sh fixes/mail_users.sh passwd <name>      new password (typed twice)
# Manual steps: DOCUMENTATION.md 10.26.
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0 ..."; exit 1; }
{ [ "$(hostname)" = welcome ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.11/'; } || { echo "ERROR: run this script on welcome." >&2; exit 1; }
DOMAIN=group4.umons
MYCNF=""
trap '[ -n "$MYCNF" ] && rm -f "$MYCNF"' EXIT
myroot() {  # MariaDB as root: through the system account, else with the admin password (NOTES 1), asked once, not shown
    command mysql -e 'SELECT 1' >/dev/null 2>&1 && return 0
    echo "   MariaDB refuses root through the system account (mysql_secure_installation): type the MariaDB admin password (NOTES 1), not shown:"
    stty -echo 2>/dev/null; read -r p; stty echo 2>/dev/null; echo
    MYCNF=$(mktemp); chmod 600 "$MYCNF"
    printf '[client]\nuser=root\npassword="%s"\n' "$p" > "$MYCNF"; p=""
    command mysql --defaults-extra-file="$MYCNF" -e 'SELECT 1' >/dev/null 2>&1 || { echo "   ERROR: MariaDB refuses this password"; rm -f "$MYCNF"; MYCNF=""; exit 1; }
    echo "   MariaDB: logged in as root with the password (kept only in a temporary file, deleted at the end)"
}
mysql() { if [ -n "$MYCNF" ]; then command mysql --defaults-extra-file="$MYCNF" "$@"; else command mysql "$@"; fi; }
myroot
mysql -N mailserver -e 'SELECT 1 FROM virtual_users LIMIT 1' >/dev/null 2>&1 \
    || { echo "ERROR: no database of virtual mailboxes: run fixes/mail_virtual.sh first."; exit 1; }
sql() { mysql -N mailserver -e "$1"; }
addr() {  # name or name@group4.umons -> checked address (no other characters: safe inside SQL)
    case "$1" in *@*) a=$1 ;; *) a="$1@$DOMAIN" ;; esac
    echo "$a" | grep -qE "^[a-z0-9][a-z0-9._-]{0,63}@$DOMAIN\$" \
        || { echo "ERROR: '$1': use lowercase letters, digits, '.', '_' or '-' (address name@$DOMAIN)." >&2; exit 1; }
    echo "$a"
}
exists() { [ -n "$(sql "SELECT email FROM virtual_users WHERE email='$1'")" ]; }
newhash() {
    echo "Password for $1 (at least 12 characters; typed twice):" >&2
    h=$(openssl passwd -6) || { echo "ERROR: password not set" >&2; exit 1; }   # same scheme as doveadm pw -s SHA512-CRYPT
    case "$h" in '$6$'*) echo "{SHA512-CRYPT}$h" ;; *) echo "ERROR: unexpected hash" >&2; exit 1 ;; esac
}

cmd=${1:-}
case "$cmd" in
    list)
        mysql -t mailserver -e "SELECT email, IF(active, 'yes', 'no (waiting)') AS active, created FROM virtual_users ORDER BY created"
        mysql -t mailserver -e "SELECT source AS alias, destination FROM virtual_aliases ORDER BY source"
        ;;
    add)
        a=$(addr "${2:?usage: add <name>}") || exit 1
        exists "$a" && { echo "ERROR: $a already exists (activate or passwd)."; exit 1; }
        h=$(newhash "$a") || exit 1
        sql "INSERT INTO virtual_users (email, password, active) VALUES ('$a', '$h', 1)"
        echo "done: $(sql "SELECT CONCAT(email, ' active=', active) FROM virtual_users WHERE email='$a'")"
        echo "Its mailbox is created by the first mail it receives; it logs in with the full address $a."
        ;;
    activate|disable)
        a=$(addr "${2:?usage: $cmd <name>}") || exit 1
        exists "$a" || { echo "ERROR: $a does not exist."; exit 1; }
        v=1; [ "$cmd" = disable ] && v=0
        sql "UPDATE virtual_users SET active = $v WHERE email='$a'"
        echo "done: $(sql "SELECT CONCAT(email, ' active=', active) FROM virtual_users WHERE email='$a'")"
        ;;
    passwd)
        a=$(addr "${2:?usage: passwd <name>}") || exit 1
        exists "$a" || { echo "ERROR: $a does not exist."; exit 1; }
        h=$(newhash "$a") || exit 1
        sql "UPDATE virtual_users SET password = '$h' WHERE email='$a'"
        echo "done: new password for $a"
        ;;
    *)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
