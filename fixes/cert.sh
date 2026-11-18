#!/bin/sh
# Certificate of welcome signed by the course CA (D09, D23, W11): the whole job, on welcome.
#   Part A, request: key and CSR checked (CN welcome.group4.umons, names welcome + mail, made from
#     the key); a new CSR on the SAME key only if something is wrong; the CSR (public, no secret)
#     goes to certs/group4.csr of this repo, to send it to the teacher from the laptop.
#     The key never leaves this VM.
#   Part B, install, once the signed certificate is in certs/ of this repo (pushed from the laptop):
#     checks of the certificate, files in /etc/ssl/group4, Postfix (25), Dovecot (993),
#     nginx (443), TLS tests. The forward of 443 on pfSense is printed at the end (pfSense web page).
# Each step: current state, reason, confirmation [y/N], backup in /root/fixes-backup-<date>, check,
# backup put back if the check fails. Take a PVE snapshot of welcome first.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh fixes/cert.sh [certificate file]
# Manual steps: DOCUMENTATION.md 10.27.
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
{ [ "$(hostname)" = welcome ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.11/'; } || { echo "ERROR: run this script on welcome." >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
D=/etc/ssl/group4
KEY=$D/group4.key; CSR=$D/group4.csr; CRT=$D/group4.crt; FULL=$D/group4-fullchain.pem
CHAIN=$REPO/certs/ca-chain-certificates.pem
SUBJ="/C=BE/ST=Hainaut/O=Group4/OU=CyberDefense/CN=welcome.group4.umons"
SAN="subjectAltName=DNS:welcome.group4.umons,DNS:mail.group4.umons"
DOVE=/etc/dovecot/conf.d/99-group4-tls.conf
SITE=/etc/nginx/sites-available/welcome-ssl
U=${SUDO_USER:-user}; [ "$U" = root ] && U=user
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
bk() { mkdir -p "$BK" && cp -a "$@" "$BK/"; }
gu() { sudo -H -u "$U" git -C "$REPO" "$@"; }                 # git as the owner of the clone (deploy key)
fp() { sha256sum | cut -c1-16; }                               # short fingerprint of a public key
keyfp() { openssl pkey -in "$KEY" -pubout 2>/dev/null | fp; }
names() { case "$1" in *DNS:welcome.group4.umons*) case "$1" in *DNS:mail.group4.umons*) return 0 ;; esac ;; esac; return 1; }
first() { sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/{p;/-----END CERTIFICATE-----/q}' "$1"; }
tlstest() {  # $1 label, $2 s_client options: issuer and result of the check against the course chain
    r=$(echo | timeout 8 openssl s_client $2 -CAfile "$CHAIN" 2>/dev/null)
    iss=$(printf '%s\n' "$r" | openssl x509 -noout -issuer 2>/dev/null | sed 's/.*CN *= *//; s/, *emailAddress.*//')
    v=$(printf '%s\n' "$r" | grep -m1 'Verify return code' | sed 's/^ *//')
    echo "   $1: issuer ${iss:-?}; ${v:-no TLS answer}"
    case "$v" in *"code: 0 "*) return 0 ;; esac; return 1
}
[ -s "$CHAIN" ] || { echo "ERROR: $CHAIN missing: git pull first."; exit 1; }

ask "Did you take a PVE snapshot of welcome?" || { echo "Take it first: PVE > welcome > Snapshots > Take Snapshot."; exit 1; }

echo
echo "######## Part A: request"
echo
echo "== A1. Private key $KEY"
if [ -e "$KEY" ]; then
    echo "   present: mode $(stat -c '%a, owner %U' "$KEY"), $(openssl pkey -in "$KEY" -noout -text 2>/dev/null | head -1)"
    if [ "$(stat -c '%a %U' "$KEY")" != "600 root" ]; then
        echo "   Why: only root may read the key (D09)."
        ask "   Set mode 600, owner root?" && chown root:root "$KEY" && chmod 600 "$KEY" && echo "   done: mode $(stat -c '%a, owner %U' "$KEY")"
    fi
else
    echo "   missing."
    echo "   Why a new one: the certificate is signed for the public half of this key (D09: RSA 3072);"
    echo "        the key is made here and never leaves welcome. A request already sent for a lost key"
    echo "        is useless: the new request must be sent again."
    ask "   Create the key and a new request?" || { echo "   Nothing else can be done without the key."; exit 1; }
    mkdir -p "$D"
    ( umask 077; openssl req -new -newkey rsa:3072 -nodes -keyout "$KEY" -out "$CSR" -subj "$SUBJ" -addext "$SAN" 2>/dev/null )
    chmod 600 "$KEY"; chmod 644 "$CSR"
    echo "   done: $KEY (mode $(stat -c '%a, owner %U' "$KEY")), $CSR"
fi
KFP=$(keyfp)
[ -n "$KFP" ] || { echo "ERROR: $KEY cannot be read as a private key."; exit 1; }

csr_ok() {  # prints the state of the request; true if signature, CN, names and key are right
    [ -s "$CSR" ] || { echo "   missing"; return 1; }
    t=$(openssl req -in "$CSR" -noout -text 2>/dev/null)
    s=$(openssl req -in "$CSR" -noout -subject 2>/dev/null)
    n=$(printf '%s\n' "$t" | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//')
    echo "   $s"
    echo "   names: ${n:-none}"
    bad=0
    openssl req -in "$CSR" -noout -verify 2>&1 | grep -q 'verify OK' || { echo "   signature of the request: NOT valid"; bad=1; }
    case "$s" in *"CN = welcome.group4.umons"*|*"CN=welcome.group4.umons"*) ;; *) echo "   CN is not welcome.group4.umons"; bad=1 ;; esac
    names "$t" || { echo "   names welcome + mail: missing"; bad=1; }
    [ "$(openssl req -in "$CSR" -noout -pubkey 2>/dev/null | fp)" = "$KFP" ] || { echo "   made from ANOTHER key"; bad=1; }
    return $bad
}
echo
echo "== A2. Request $CSR"
if csr_ok; then
    echo "   OK: signature valid, CN and both names present, made from our key"
else
    echo "   Why a new request: the teacher signs exactly what is in it; without the two names browsers and"
    echo "        mail clients reject the certificate (D09). The new request uses the SAME key."
    if ask "   Make a new request?"; then
        [ -e "$CSR" ] && bk "$CSR"
        openssl req -new -key "$KEY" -out "$CSR" -subj "$SUBJ" -addext "$SAN" && chmod 644 "$CSR"
        if csr_ok; then echo "   done"; else echo "   ERROR: the new request is still wrong (see above)."; exit 1; fi
    fi
fi

echo
echo "== A3. Request in the public repo: certs/group4.csr (to send it to the teacher from the laptop)"
gu fetch -q origin 2>/dev/null
if [ "$(gu show origin/main:certs/group4.csr 2>/dev/null | fp)" = "$(fp < "$CSR")" ]; then
    echo "   already on GitHub, same as $CSR"
else
    echo "   Why: the request holds only public data; from GitHub it is downloaded on the laptop and mailed"
    echo "        to the teacher. The key is not copied."
    if [ -z "$(gu config --get remote.origin.pushurl)" ]; then
        echo "   No push URL in this clone: copy the request by hand (cat $CSR)."
    elif ask "   Copy it to certs/group4.csr and push?"; then
        cp "$CSR" "$REPO/certs/group4.csr"; chown "$U" "$REPO/certs/group4.csr"; chmod 644 "$REPO/certs/group4.csr"
        if gu add certs/group4.csr && gu commit -q -m "certs/group4.csr: certificate request of welcome (public; the key stays on the VM)" \
           && { gu pull -q --rebase || { gu rebase --abort; gu reset -q --hard HEAD~1; false; }; } && gu push -q; then
            echo "   done: https://github.com/7i77ux/group4-welcome/blob/main/certs/group4.csr"
        else
            echo "   ERROR: push failed; copy the request by hand (cat $CSR)."
        fi
    fi
fi

echo
echo "######## Part B: signed certificate"
cert=""
for f in "${1:-}" "$REPO"/certs/*; do
    [ -f "$f" ] || continue
    case "$f" in "$CHAIN"|*.csr) continue ;; esac
    grep -q 'BEGIN CERTIFICATE' "$f" 2>/dev/null || continue
    if [ "$(openssl x509 -in "$f" -noout -pubkey 2>/dev/null | fp)" = "$KFP" ]; then cert=$f; break; fi
    echo "   $f: not for our key ($(openssl x509 -in "$f" -noout -subject 2>/dev/null))"
done
if [ -z "$cert" ]; then
    echo "   Not received yet: no certificate for our key in certs/. Next:"
    echo "   1. Laptop: download https://github.com/7i77ux/group4-welcome/blob/main/certs/group4.csr (Raw)"
    echo "      and mail it to the teacher: \"Could you sign our CSR for welcome.group4.umons? Please keep its"
    echo "      subjectAltName (welcome.group4.umons and mail.group4.umons): with OpenSSL 3 this is"
    echo "      'openssl x509 -req ... -copy_extensions copy'.\""
    echo "   2. Laptop: put the certificate in certs/ of the public repo, then git add, commit, push."
    echo "   3. Here: git pull && sudo sh fixes/cert.sh   (it goes on with the installation)"
    exit 0
fi

echo
echo "== B1. Checks of $cert"
openssl x509 -in "$cert" -noout -subject -issuer -dates | sed 's/^/   /'
t=$(openssl x509 -in "$cert" -noout -text)
stop=0
openssl x509 -in "$cert" -noout -issuer | grep -q 'Simply The Best, Really' \
    && echo "   1. OK  issued by the course intermediate CA" || { echo "   1. FAIL not issued by the course CA"; stop=1; }
v=$(openssl verify -CAfile "$CHAIN" "$cert" 2>&1 | tr '\n' ' ')
case "$v" in *": OK"*) echo "   2. OK  chain up to the course root: $v" ;; *) echo "   2. FAIL chain: $v"; stop=1 ;; esac
echo "   3. OK  made for our key (same public key as $KEY)"
openssl x509 -in "$cert" -noout -checkend 0 >/dev/null && echo "   4. OK  not expired" || { echo "   4. FAIL expired"; stop=1; }
nosan=0
if names "$t"; then echo "   5. OK  names welcome.group4.umons and mail.group4.umons"
else
    nosan=1
    n=$(printf '%s\n' "$t" | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//')
    echo "   5. WARN names welcome + mail missing (names in it: ${n:-none})"
    echo "      Browsers and mail clients reject it for mail.group4.umons (and browsers also for welcome)."
    echo "      Ask the teacher to sign again with 'openssl x509 -req ... -copy_extensions copy'."
fi
[ "$stop" = 0 ] || { echo "   STOP: certificate not installed."; exit 1; }
if [ "$nosan" = 1 ]; then ask "   Install it anyway (until the corrected one arrives)?" || exit 1; fi

# certificate alone, and certificate + intermediate CA (what the services send to the clients)
first "$cert" > "$TMP/crt"
first "$CHAIN" > "$TMP/inter"
if openssl x509 -in "$TMP/inter" -noout -subject | grep -q 'Simply The Best, Really'; then
    cat "$TMP/crt" "$TMP/inter" > "$TMP/full"
else
    cat "$TMP/crt" "$CHAIN" > "$TMP/full"
fi

echo
echo "== B2. Files $CRT and $FULL (certificate + intermediate CA of the course)"
echo "   Why: the services send the certificate with the intermediate CA, so a client that knows only"
echo "        the course root can check it."
if cmp -s "$TMP/crt" "$CRT" && cmp -s "$TMP/full" "$FULL"; then
    echo "   already done"
elif ask "   Apply?"; then
    for f in "$CRT" "$FULL"; do [ -e "$f" ] && bk "$f"; done
    cp "$TMP/crt" "$CRT"; cp "$TMP/full" "$FULL"; chmod 644 "$CRT" "$FULL"
    if openssl verify -CAfile "$CHAIN" "$CRT" >/dev/null 2>&1 && [ "$(openssl x509 -in "$FULL" -noout -pubkey | fp)" = "$KFP" ]; then
        echo "   done: $(stat -c '%a %U %n' "$CRT" "$FULL" | paste -sd ';' | sed 's/;/; /')"
    else
        echo "   ERROR: the copied files do not check; nothing else is changed."; exit 1
    fi
fi
[ -s "$FULL" ] || { echo "   The next steps need $FULL: stop."; exit 1; }

echo
cf=$(postconf -h smtpd_tls_cert_file); ck=$(postconf -h smtpd_tls_key_file); cc=$(postconf -h smtpd_tls_chain_files)
echo "== B3. Postfix, port 25 STARTTLS (now: cert $cf, key $ck${cc:+, chain_files $cc}, security level $(postconf -h smtpd_tls_security_level))"
echo "   Why: the other providers and the customers get the course certificate instead of the Debian one (D23)."
if [ "$cf" = "$FULL" ] && [ "$ck" = "$KEY" ] && [ -z "$cc" ]; then
    echo "   already done"
elif ask "   Apply?"; then
    bk /etc/postfix/main.cf
    postconf -e "smtpd_tls_cert_file = $FULL" "smtpd_tls_key_file = $KEY"
    [ -n "$cc" ] && postconf -X smtpd_tls_chain_files
    if postfix check && systemctl reload postfix && sleep 2 && tlstest "25 STARTTLS" "-starttls smtp -connect 127.0.0.1:25"; then
        echo "   done"
    else
        cp -a "$BK/main.cf" /etc/postfix/main.cf; systemctl reload postfix
        echo "   ERROR: check failed, main.cf put back"
    fi
fi

echo
ver=$(dovecot --version 2>/dev/null | cut -d' ' -f1)
case "$ver" in
    2.3*) cur=$(doveconf -h ssl_cert 2>/dev/null); want=$(printf 'ssl_cert = <%s\nssl_key = <%s' "$FULL" "$KEY") ;;
    *)    cur=$(doveconf -h ssl_server_cert_file 2>/dev/null); want=$(printf 'ssl_server_cert_file = %s\nssl_server_key_file = %s' "$FULL" "$KEY") ;;
esac
echo "== B4. Dovecot $ver, port 993 (now: ${cur:-?})"
echo "   Why: the customers read their mail on 993; today they get the Debian certificate (D29: only the"
echo "        certificate and key paths change)."
if [ "$cur" = "$FULL" ] || [ "$cur" = "<$FULL" ]; then
    echo "   already done"
elif ask "   Apply? (file $DOVE)"; then
    had=0; [ -e "$DOVE" ] && { bk "$DOVE"; had=1; }
    printf '# Course certificate (fixes/cert.sh, DOCUMENTATION 10.27)\n%s\n' "$want" > "$DOVE"
    if err=$(doveconf -n 2>&1 >/dev/null) && systemctl restart dovecot && sleep 2 && tlstest "993" "-connect 127.0.0.1:993"; then
        echo "   done"
    else
        [ -n "${err:-}" ] && echo "$err" | head -5 | sed 's/^/   /'
        if [ "$had" = 1 ]; then cp -a "$BK/$(basename "$DOVE")" "$DOVE"; else rm -f "$DOVE"; fi
        systemctl restart dovecot
        echo "   ERROR: check failed, Dovecot back to the previous configuration"
    fi
fi

echo
cat > "$TMP/site" <<EOF
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name welcome.group4.umons;
    ssl_certificate     $FULL;
    ssl_certificate_key $KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/welcome;
    index index.html;
    server_tokens off;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
on443=$(grep -lsE '^[^#]*listen[^;]*443' /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf 2>/dev/null)
other=$(printf '%s\n' "$on443" | grep -v '/welcome-ssl$' | grep .)
echo "== B5. nginx, port 443 HTTPS (now: $(echo ${on443:-no site on 443}))"
echo "   Why: the welcome page over HTTPS with the course certificate (W11); port 80 stays as it is."
if [ -n "$other" ]; then
    echo "   SKIPPED: 443 already used by $other (not changed by this script)."
elif cmp -s "$TMP/site" "$SITE" && [ -L /etc/nginx/sites-enabled/welcome-ssl ]; then
    echo "   already done"
elif ask "   Apply? (site $SITE)"; then
    had=0; [ -e "$SITE" ] && { bk "$SITE"; had=1; }
    cp "$TMP/site" "$SITE"; ln -sf "$SITE" /etc/nginx/sites-enabled/welcome-ssl
    if nginx -t 2>"$TMP/ngx" && systemctl reload nginx && sleep 2 \
       && tlstest "443" "-connect 127.0.0.1:443 -servername welcome.group4.umons" \
       && curl -s --cacert "$CHAIN" --resolve welcome.group4.umons:443:127.0.0.1 https://welcome.group4.umons/ | cmp -s - /var/www/welcome/index.html; then
        echo "   done: https://welcome.group4.umons serves /var/www/welcome/index.html"
    else
        sed 's/^/   /' "$TMP/ngx"
        rm -f /etc/nginx/sites-enabled/welcome-ssl
        if [ "$had" = 1 ]; then cp -a "$BK/welcome-ssl" "$SITE"; else rm -f "$SITE"; fi
        nginx -t 2>/dev/null && systemctl reload nginx
        echo "   ERROR: check failed, site removed"
    fi
fi

echo
echo "== B6. Tests against the course chain (Verify return code must be 0)"
tlstest "25 STARTTLS" "-starttls smtp -connect 127.0.0.1:25"
tlstest "993" "-connect 127.0.0.1:993"
tlstest "443" "-connect 127.0.0.1:443 -servername welcome.group4.umons"
echo
echo "== By hand on pfSense (web page, from the LAN): Firewall > NAT > Port Forward > Add"
echo "   Interface WAN, Protocol TCP, Destination WAN address, port 443,"
echo "   Redirect target IP 10.4.2.11, port 443, Filter rule association: Add associated filter rule;"
echo "   Save, Apply Changes. Then from a machine on the WAN side: https://welcome.group4.umons"
echo
echo "== Backups in $BK"
echo "== Running checks/full.sh (full regression test)"
sh "$REPO/checks/full.sh"
