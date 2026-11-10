#!/bin/sh
# Read-only checks for the welcome VM (10.4.255.11). It changes nothing.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/welcome.sh
# Output also saved in /tmp/check-welcome.txt (scroll with: less /tmp/check-welcome.txt)

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
IF=ens18
IP=10.4.255.11
OUT=/tmp/check-welcome.txt
REPO="$(dirname "$0")/.."

ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
info() { printf 'INFO  %s\n' "$*"; }
sec()  { printf '\n== %s\n' "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

main() {
    sec "1. Identity ($(date '+%Y-%m-%d %H:%M'), checks commit $(git -C "$REPO" log -1 --format=%h 2>/dev/null))"
    h=$(hostname)
    if [ "$h" = welcome ]; then ok "hostname: $h"; else warn "hostname: $h (expected welcome)"; fi
    if grep -Eq "^127\.0\.1\.1[[:space:]]+$h([[:space:]]|$)" /etc/hosts; then ok "/etc/hosts: 127.0.1.1 $h"; else warn "/etc/hosts: no '127.0.1.1 $h' line"; fi
    addrs=$(ip -4 -o addr show dev "$IF" 2>/dev/null | awk '{f=""; for (i=5; i<=NF; i++) if ($i=="dynamic" || $i=="noprefixroute") f=f" "$i; print $4 f}')
    [ -n "$addrs" ] || warn "no IPv4 address on $IF"
    echo "$addrs" | while read -r l; do [ -n "$l" ] && info "address on $IF: $l"; done
    if echo "$addrs" | grep -q "^$IP/"; then ok "$IP present"; else warn "$IP missing"; fi

    sec "2. Does $IP survive a reboot?"
    pers=""
    if has nmcli && nmcli -t -f RUNNING general 2>/dev/null | grep -q running; then
        st=$(nmcli -g GENERAL.STATE device show "$IF" 2>/dev/null)
        conn=$(nmcli -g GENERAL.CONNECTION device show "$IF" 2>/dev/null)
        info "NetworkManager: $IF '$st', profile '${conn:-none}'"
        if [ -n "$conn" ]; then
            m=$(nmcli -g ipv4.method connection show "$conn" 2>/dev/null)
            a=$(nmcli -g ipv4.addresses connection show "$conn" 2>/dev/null)
            g=$(nmcli -g ipv4.gateway connection show "$conn" 2>/dev/null)
            d=$(nmcli -g ipv4.dns connection show "$conn" 2>/dev/null)
            info "NM profile: method=$m addresses=${a:-none} gateway=${g:-none} dns=${d:-none}"
            case "$m:$a" in manual:*"$IP/"*) pers="NetworkManager";; esac
        fi
    else
        info "NetworkManager: not running"
    fi
    stanza=$(grep -hE "^[[:space:]]*iface[[:space:]]+$IF[[:space:]]" /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null)
    if [ -n "$stanza" ]; then
        info "ifupdown: $stanza"
        grep -hqE "^[[:space:]]*address[[:space:]]+$IP(/|[[:space:]]|$)" /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null && pers="${pers:+$pers + }ifupdown"
    else
        info "ifupdown: no stanza for $IF in /etc/network/interfaces"
    fi
    grep -lq "$IP" /etc/systemd/network/*.network 2>/dev/null && pers="${pers:+$pers + }systemd-networkd"
    if [ -z "$pers" ]; then
        warn "$IP is in NO configuration: it was added by hand and will be LOST at reboot"
    else
        ok "persistent via: $pers"
        case "$pers" in *" + "*) warn "configured in two places: keep only one";; esac
    fi

    sec "3. Route and DNS"
    gw=$(ip -4 route show default | awk '{print $3; exit}')
    if [ "$gw" = 10.4.255.254 ]; then ok "default gateway: $gw"; else warn "default gateway: ${gw:-none} (expected 10.4.255.254)"; fi
    has resolvectl && info "resolver DNS ($IF): $(resolvectl dns "$IF" 2>/dev/null | sed 's/^[^:]*: *//')"
    info "resolv.conf: $(grep '^nameserver' /etc/resolv.conf | tr '\n' ' ')"
    r=$(getent hosts welcome.group4.umons | awk '{print $1}')
    if [ "$r" = "$IP" ]; then ok "welcome.group4.umons -> $r"; else warn "welcome.group4.umons -> ${r:-no answer}"; fi
    if has dig; then
        mx=$(dig +short +time=2 +tries=1 group4.umons MX 2>/dev/null | grep -v '^;;')
        if [ -n "$mx" ]; then ok "MX group4.umons: $mx"; else warn "MX group4.umons: no answer"; fi
    fi

    sec "4. Services"
    for s in nginx postfix; do
        a=$(systemctl is-active "$s" 2>/dev/null); e=$(systemctl is-enabled "$s" 2>/dev/null)
        if [ "$a" = active ] && [ "$e" = enabled ]; then ok "$s: $a, $e at boot"; else warn "$s: $a, ${e:-?} at boot"; fi
    done
    rs=$(systemctl show nginx -p Restart --value 2>/dev/null)
    if [ "$rs" = on-failure ]; then ok "nginx restarts after a crash (Restart=$rs)"; else warn "nginx Restart=${rs:-?}"; fi
    if dpkg -l apache2 2>/dev/null | grep -q '^ii'; then warn "apache2 installed"; else ok "apache2 not installed"; fi
    if dpkg -l dovecot-core 2>/dev/null | grep -q '^ii'; then info "dovecot installed"; else info "dovecot not installed yet"; fi

    sec "5. Listening ports (proto, address:port, process)"
    ss -Htulpn 2>/dev/null | awk '{split($7, p, "\""); printf "      %-4s %-26s %s\n", $1, $5, p[2]}' | sort -u

    sec "6. Web page"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1/)
    if [ "$code" = 200 ]; then ok "http://127.0.0.1/ -> $code"; else warn "http://127.0.0.1/ -> $code"; fi
    t=$(curl -s --max-time 5 http://welcome.group4.umons/ | grep -o '<title>[^<]*</title>')
    if [ -n "$t" ]; then ok "http://welcome.group4.umons/ -> $t"; else warn "http://welcome.group4.umons/ -> no page"; fi
    if curl -s --max-time 5 -H 'Host: welcome.group4.umons' http://127.0.0.1/ | cmp -s - /var/www/welcome/index.html; then
        ok "served page = /var/www/welcome/index.html"
    else
        warn "served page differs from /var/www/welcome/index.html"
    fi
    info "$(curl -sI --max-time 5 http://127.0.0.1/ | grep -i '^server:' | tr -d '\r')"

    sec "7. Postfix"
    for k in myhostname mydestination myorigin mynetworks inet_interfaces smtpd_tls_security_level; do
        info "$k = $(postconf -h "$k" 2>/dev/null)"
    done
    if postconf -h mynetworks 2>/dev/null | grep -Eq '10\.[1-35-9]\.'; then
        warn "mynetworks includes other groups' networks: they can relay mail through us without login"
    fi
    info "/etc/mailname = $(cat /etc/mailname 2>/dev/null)"
    al=$(grep -E '^(postmaster|abuse|root):' /etc/aliases 2>/dev/null | tr '\n' ' ')
    info "aliases: ${al:-none}"
    python3 -I - <<'PY' 2>&1 | sed 's/^/      /'
import smtplib
try:
    s = smtplib.SMTP(timeout=5)
    code, greeting = s.connect("127.0.0.1", 25)
    print("greeting:", code, greeting.decode(errors="replace"))
    s.ehlo("check.group4.umons")
    print("STARTTLS offered:", bool(s.has_extn("starttls")), "| AUTH offered:", bool(s.has_extn("auth")))
    s.quit()
except Exception as e:
    print("SMTP test failed:", e)
PY

    sec "8. TLS key and CSR"
    if [ -f /etc/ssl/group4/group4.key ]; then
        p=$(stat -c '%a %U' /etc/ssl/group4/group4.key)
        if [ "$p" = "600 root" ]; then ok "key /etc/ssl/group4/group4.key ($p)"; else warn "key permissions: $p (expected 600 root)"; fi
    else
        warn "no key in /etc/ssl/group4"
    fi
    [ -f /etc/ssl/group4/group4.csr ] && info "CSR $(openssl req -in /etc/ssl/group4/group4.csr -noout -subject 2>/dev/null)"
    ls /etc/ssl/group4/ 2>/dev/null | grep -vE '^group4\.(key|csr)$' | sed 's/^/INFO  other file in \/etc\/ssl\/group4: /'

    sec "9. Resources"
    info "vCPU $(nproc) | RAM $(free -m | awk '/^Mem:/{print $2" MB, used "$3" MB"}') | disk / $(df -h / | awk 'NR==2{print $2", used "$3}')"
}

main 2>&1 | tee "$OUT"
printf '\n%s warning(s). Full output: %s\n' "$(grep -c '^WARN' "$OUT")" "$OUT"
