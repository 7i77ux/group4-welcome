#!/bin/sh
# Read-only checks of the mail service on welcome (10.4.255.11). It changes nothing,
# it does not log in and it sends no mail.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/mail.sh
# Output saved in /tmp/check-mail.txt and pushed to results/mail/.

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
ip -4 -o addr show | grep -q ' 10\.4\.255\.11/' || { echo "ERROR: run this check on welcome (10.4.255.11)." >&2; exit 1; }
OUT=/tmp/check-mail.txt
REPO="$(dirname "$0")/.."

ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
info() { printf 'INFO  %s\n' "$*"; }
sec()  { printf '\n== %s\n' "$*"; }
d()    { dig +short +time=2 +tries=1 @10.4.255.10 "$@" 2>/dev/null | grep -v '^;;' | tr '\n' ' '; }
listening() { ss -Htln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$"; }
cert() { openssl x509 -noout -subject -issuer -enddate 2>/dev/null | sed 's/^/        /'; }

main() {
    sec "1. DNS for mail (asked to ns1, 10.4.255.10) ($(date '+%Y-%m-%d %H:%M'), checks commit $(git -c safe.directory='*' -C "$REPO" log -1 --format=%h 2>/dev/null))"
    r=$(d group4.umons MX);       if [ -n "$r" ]; then ok "MX: $r"; else warn "MX: none"; fi
    r=$(d mail.group4.umons A);   if echo "$r" | grep -q 10.4.255.11; then ok "mail.group4.umons -> $r"; else warn "mail.group4.umons -> ${r:-none}"; fi
    r=$(d -x 10.4.255.11);        if [ "$r" = "mail.group4.umons. " ]; then ok "PTR 10.4.255.11 -> $r"; else warn "PTR 10.4.255.11 -> ${r:-none} (expected only mail.group4.umons.)"; fi
    r=$(d group4.umons TXT | grep -o '"v=spf1[^"]*"'); if [ -n "$r" ]; then ok "SPF: $r"; else warn "SPF: no 'v=spf1' TXT record (M6)"; fi
    r=$(d _dmarc.group4.umons TXT); if echo "$r" | grep -q 'v=DMARC1'; then ok "DMARC: $r"; else warn "DMARC: no record (M6)"; fi

    sec "2. Postfix settings"
    info "version $(postconf -h mail_version 2>/dev/null)"
    for k in myhostname mydestination mynetworks inet_interfaces smtpd_banner smtpd_tls_cert_file smtpd_tls_key_file \
             smtpd_tls_security_level smtpd_tls_auth_only smtpd_sasl_auth_enable smtpd_sasl_type smtpd_sasl_path \
             smtpd_relay_restrictions smtpd_recipient_restrictions disable_vrfy_command smtpd_helo_required \
             smtpd_client_connection_rate_limit message_size_limit home_mailbox mailbox_command; do
        info "$k = $(postconf -h "$k" 2>/dev/null)"
    done
    info "services in master.cf listening on the network:"
    postconf -M 2>/dev/null | awk '$2 == "inet" {print "        " $1 " (" $2 ")" ($0 ~ /-o/ ? " with options" : "")}'
    postconf -P 2>/dev/null | grep -E '^submission/inet/' | sed 's/^/        /'

    sec "3. Dovecot"
    if command -v doveconf >/dev/null 2>&1; then
        info "version $(dovecot --version 2>/dev/null)"
        doveconf -n 2>/dev/null | grep -E '^(protocols|listen|ssl|ssl_cert|ssl_key|ssl_server_cert_file|ssl_server_key_file|ssl_min_protocol|auth_mechanisms|auth_allow_cleartext|disable_plaintext_auth|mail_location|mail_driver|mail_path|mail_inbox_path|first_valid_uid|dovecot_config_version)[[:space:]]*=' | sed 's/^/INFO  /'
        if [ -S /var/spool/postfix/private/auth ]; then ok "auth socket for Postfix: $(stat -c '%A %U %G' /var/spool/postfix/private/auth) /var/spool/postfix/private/auth"
        else info "no auth socket for Postfix (/var/spool/postfix/private/auth): needed for login on 587"; fi
        a=$(systemctl is-active dovecot 2>/dev/null); e=$(systemctl is-enabled dovecot 2>/dev/null)
        if [ "$a" = active ] && [ "$e" = enabled ]; then ok "dovecot: $a, $e at boot"; else warn "dovecot: $a, ${e:-?} at boot"; fi
    else
        warn "Dovecot not installed (M1)"
    fi

    sec "4. Live tests on 127.0.0.1 (no login, no mail sent)"
    python3 -I - <<'PY' 2>&1 | sed 's/^/      /'
import smtplib, imaplib, ssl
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
def smtp(port):
    try:
        s = smtplib.SMTP(timeout=5); code, greet = s.connect("127.0.0.1", port); s._host = "127.0.0.1"
        s.ehlo("check.group4.umons")
        tls = bool(s.has_extn("starttls")); auth_plain = s.esmtp_features.get("auth", "")
        line = f"SMTP {port}: {code} {greet.decode(errors='replace')} | STARTTLS {tls} | AUTH before TLS: {auth_plain or 'no'}"
        if tls:
            s.starttls(context=ctx); s.ehlo("check.group4.umons")
            line += f" | AUTH after TLS: {s.esmtp_features.get('auth', '') or 'no'}"
        vrfy = s.docmd("VRFY", "postmaster")[0]
        line += f" | VRFY answer {vrfy}"
        s.quit(); print(line)
    except Exception as e:
        print(f"SMTP {port}: test failed ({e.__class__.__name__}: {e})")
smtp(25); smtp(587)
try:
    i = imaplib.IMAP4_SSL("127.0.0.1", 993, ssl_context=ctx, timeout=5)
    print("IMAP 993 (TLS):", " ".join(i.capabilities)); i.logout()
except Exception as e:
    print(f"IMAP 993: not reachable ({e.__class__.__name__}: {e})")
try:
    i = imaplib.IMAP4("127.0.0.1", 143, timeout=5)
    print("IMAP 143 (no TLS):", " ".join(i.capabilities)); i.logout()
except Exception as e:
    print(f"IMAP 143: not reachable ({e.__class__.__name__})")
PY
    info "certificate on 993:"; echo | timeout 5 openssl s_client -connect 127.0.0.1:993 2>/dev/null | cert
    info "certificate on 25 (STARTTLS):"; echo | timeout 5 openssl s_client -starttls smtp -connect 127.0.0.1:25 2>/dev/null | cert

    sec "5. Addresses and mailboxes"
    info "aliases: $(grep -vE '^[[:space:]]*(#|$)' /etc/aliases 2>/dev/null | tr '\t' ' ' | tr -s ' ' | tr '\n' ';')"
    info "local accounts (uid >= 1000): $(awk -F: '$3 >= 1000 && $3 < 65534 {printf "%s ", $1}' /etc/passwd)"
    info "mailboxes in /var/mail: $(ls -1 /var/mail 2>/dev/null | tr '\n' ' ')"
    for md in /home/*/Maildir; do [ -d "$md" ] && info "Maildir $md: $(ls "$md/new" 2>/dev/null | wc -l) new, $(ls "$md/cur" 2>/dev/null | wc -l) read"; done
    q=$(postqueue -p 2>/dev/null | tail -1)
    case "$q" in *"is empty"*) ok "mail queue empty";; *) warn "mail queue: $q";; esac
    info "last mail errors in the logs (24 h):"
    journalctl --since -24h -o cat 2>/dev/null | grep -E 'postfix/|dovecot' | grep -iE 'reject|warning|fatal|error|failed' | tail -5 | cut -c1-150 | sed 's/^/        /'

    sec "6. Summary of the mail tasks"
    if command -v postconf >/dev/null 2>&1; then
        bad=$(postconf -h mynetworks | python3 -I -c 'import sys, ipaddress
bad = []
for e in sys.stdin.read().replace(",", " ").split():
    try: ipaddress.ip_network(e.strip("[]").replace("]/", "/"), strict=True)
    except ValueError: bad.append(e)
print(" ".join(bad))' 2>/dev/null)
        if [ -n "$bad" ]; then warn "W26 malformed mynetworks entries (host bits set): $bad -> remote senders get 451"; else ok "mynetworks entries well formed"; fi
        n=$(journalctl --since -24h -o cat 2>/dev/null | grep -c 'non-null host address bits')
        [ "$n" -gt 0 ] && warn "W26 log: $n 'non-null host address bits' warnings in 24 h"
    fi
    if listening 993; then ok "M1 IMAP over TLS on 993 listening"; else warn "M1 IMAP 993 not listening"; fi
    if listening 143; then warn "M1 IMAP 143 (without TLS) still open (W24)"; else ok "M1 port 143 closed"; fi
    if ! command -v postconf >/dev/null 2>&1; then
        warn "Postfix not installed: M2, M4, M5 not checked"
    else
        if listening 587; then ok "M2 port 587 listening"; else warn "M2 port 587 not listening (sending with login)"; fi
        if [ "$(postconf -h smtpd_tls_auth_only 2>/dev/null)" = yes ]; then ok "M2 login only over TLS"; else warn "M2 smtpd_tls_auth_only is not yes"; fi
        if postconf -h mynetworks 2>/dev/null | grep -Eq '10\.[0-9]+\.'; then warn "M4 open relay: mynetworks includes 10.x networks (W3)"; else ok "M4 mynetworks only local"; fi
        if [ "$(postconf -h disable_vrfy_command 2>/dev/null)" = yes ]; then ok "M5 VRFY disabled"; else warn "M5 VRFY enabled (user enumeration)"; fi
        if postconf -h smtpd_banner 2>/dev/null | grep -qi 'postfix\|debian\|mail_name'; then warn "M5 banner shows the software name"; else ok "M5 neutral banner"; fi
        if [ "$(postconf -h smtpd_helo_required 2>/dev/null)" = yes ]; then ok "M5 HELO required"; else warn "M5 smtpd_helo_required is not yes"; fi
    fi
}

main 2>&1 | tee "$OUT"
printf '\n%s warning(s). Full output: %s\n' "$(grep -c '^WARN' "$OUT")" "$OUT"
sh "$(dirname "$0")/push-results.sh" mail "$OUT"
