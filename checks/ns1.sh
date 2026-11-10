#!/bin/sh
# Read-only checks for the ns1 VM (10.4.255.10). It changes nothing.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/ns1.sh
# Output saved in /tmp/check-ns1.txt (scroll with: less /tmp/check-ns1.txt)

[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
IF=ens18
IP=10.4.255.10
OUT=/tmp/check-ns1.txt
REPO="$(dirname "$0")/.."

ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
info() { printf 'INFO  %s\n' "$*"; }
sec()  { printf '\n== %s\n' "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }
q()    { dig +short +time=2 +tries=1 @127.0.0.1 "$@" 2>/dev/null | grep -v '^;;' | tr '\n' ' '; }

main() {
    sec "1. Identity ($(date '+%Y-%m-%d %H:%M'), checks commit $(git -c safe.directory='*' -C "$REPO" log -1 --format=%h 2>/dev/null))"
    h=$(hostname)
    if [ "$h" = ns1 ]; then ok "hostname: $h"; else warn "hostname: $h (expected ns1)"; fi
    if grep -Eq "^127\.0\.1\.1[[:space:]]+$h([[:space:]]|$)" /etc/hosts; then ok "/etc/hosts: 127.0.1.1 $h"; else warn "/etc/hosts: no '127.0.1.1 $h' line"; fi
    addrs=$(ip -4 -o addr show dev "$IF" 2>/dev/null | awk '{f=""; for (i=5; i<=NF; i++) if ($i=="dynamic" || $i=="noprefixroute") f=f" "$i; print $4 f}')
    echo "$addrs" | while read -r l; do [ -n "$l" ] && info "address on $IF: $l"; done
    if echo "$addrs" | grep -q "^$IP/"; then ok "$IP present"; else warn "$IP missing"; fi

    sec "2. Who configures $IF (must be one tool only)"
    tools=""
    if has nmcli && nmcli -t -f RUNNING general 2>/dev/null | grep -q running; then
        st=$(nmcli -g GENERAL.STATE device show "$IF" 2>/dev/null)
        conn=$(nmcli -g GENERAL.CONNECTION device show "$IF" 2>/dev/null)
        info "NetworkManager: $IF '$st', profile '${conn:-none}'"
        if [ -n "$conn" ]; then
            info "NM profile: method=$(nmcli -g ipv4.method connection show "$conn" 2>/dev/null) addresses=$(nmcli -g ipv4.addresses connection show "$conn" 2>/dev/null) gateway=$(nmcli -g ipv4.gateway connection show "$conn" 2>/dev/null) dns=$(nmcli -g ipv4.dns connection show "$conn" 2>/dev/null)"
            tools="NetworkManager"
        fi
    else
        info "NetworkManager: not running"
    fi
    if grep -hqE "^[[:space:]]*iface[[:space:]]+$IF[[:space:]]" /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null; then
        tools="${tools:+$tools + }ifupdown"
        grep -hE "^[[:space:]]*(iface|address|gateway|dns-nameservers)[[:space:]]" /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null | grep -v '[[:space:]]lo[[:space:]]' | sed 's/^[[:space:]]*/INFO  interfaces: /'
    fi
    ns=$(systemctl is-active networking 2>/dev/null); if [ "$ns" = failed ]; then warn "networking.service: failed"; else ok "networking.service: $ns (not failed)"; fi
    case "$tools" in
        *" + "*) warn "$IF configured by $tools: keep only one";;
        "")      warn "$IP is in no configuration: lost at reboot";;
        *)       ok "$IF configured by $tools only";;
    esac

    sec "3. Route and resolver"
    gw=$(ip -4 route show default | awk '{print $3; exit}')
    if [ "$gw" = 10.4.255.254 ]; then ok "default gateway: $gw"; else warn "default gateway: ${gw:-none} (expected 10.4.255.254)"; fi
    ns=$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    info "resolv.conf: $ns"
    case "$ns" in 127.0.0.1*|10.4.255.10*) ok "ns1 asks its own BIND first";; *) warn "ns1 does not ask its own BIND first";; esac

    sec "4. BIND"
    a=$(systemctl is-active named 2>/dev/null); e=$(systemctl is-enabled named 2>/dev/null)
    if [ "$a" = active ] && [ "$e" = enabled ]; then ok "named: $a, $e at boot"; else warn "named: $a, ${e:-?} at boot"; fi
    if named-checkconf >/dev/null 2>&1; then ok "named-checkconf: no errors"; else warn "named-checkconf: $(named-checkconf 2>&1 | head -1)"; fi
    named-checkconf -z 2>&1 | grep -E 'group4|4\.10\.in-addr|error|not loaded' | sed 's/^/INFO  /'
    sed 's://.*$::; s:#.*$::' /etc/bind/named.conf.options 2>/dev/null | tr '\n' ' ' | tr -s ' ' \
        | grep -oE '(forwarders|allow-query|allow-recursion|allow-transfer|recursion|dnssec-validation|listen-on[^{;]*)[^;{]*(\{[^}]*\})?' \
        | sed 's/^/INFO  options: /'

    sec "5. Answers of ns1 (dig @127.0.0.1)"
    for n in welcome mail ns1; do
        r=$(q "$n.group4.umons" A)
        if [ -n "$r" ]; then ok "$n.group4.umons -> $r"; else warn "$n.group4.umons -> no answer"; fi
    done
    r=$(q group4.umons MX); if [ -n "$r" ]; then ok "MX -> $r"; else warn "MX -> no answer"; fi
    r=$(q group4.umons NS); if [ -n "$r" ]; then ok "NS -> $r"; else warn "NS -> no answer"; fi
    info "SOA -> $(q group4.umons SOA)"
    if dig +time=2 +tries=1 @127.0.0.1 group4.umons SOA 2>/dev/null | grep -q 'flags:.* aa'; then ok "authoritative (flag aa)"; else warn "no aa flag: zone not loaded"; fi
    for i in 10 11; do info "PTR 10.4.255.$i -> $(q -x 10.4.255.$i)"; done
    r=$(q deb.debian.org A); if [ -n "$r" ]; then ok "external name via forwarder -> $r"; else warn "external name via forwarder: no answer"; fi
    n=$(dig +time=2 +tries=1 @127.0.0.1 group4.umons AXFR 2>/dev/null | grep -c 'IN')
    info "zone transfer (AXFR) from this host: $n records (check allow-transfer for the others)"

    sec "6. Listening ports (proto, address:port, process)"
    ss -Htulpn 2>/dev/null | awk '{split($7, p, "\""); printf "      %-4s %-26s %s\n", $1, $5, p[2]}' | sort -u

    sec "7. Leftovers and services that should not be here"
    for p in apache2 nginx pandoc; do
        if dpkg -l "$p" 2>/dev/null | grep -q '^ii'; then warn "$p installed on ns1"; else ok "$p not installed"; fi
    done
    if [ -e /var/www/welcome ]; then warn "/var/www/welcome exists"; else ok "/var/www/welcome absent"; fi

    if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ]; then ok "clock synchronized (NTP)"; else warn "clock not synchronized (NTP)"; fi

    sec "8. welcome seen from another VM (as the other groups see it; no mail is sent)"
    python3 -I - <<'PY' 2>&1 | sed 's/^/      /'
import socket, smtplib
W = "10.4.255.11"
res = []
for p in (22, 25, 53, 80, 143, 443, 587, 993):
    s = socket.socket(); s.settimeout(2)
    res.append(f"{p}:{'open' if s.connect_ex((W, p)) == 0 else 'closed'}"); s.close()
print("ports of welcome:", " ".join(res))
try:
    s = smtplib.SMTP(W, 25, timeout=5); s.ehlo("ns1.group4.umons")
    def rcpt(to):
        s.rset(); s.mail("check@ns1.group4.umons"); return s.rcpt(to)
    def show(label, c, m, good):
        txt = m.decode(errors="replace")[:70]
        if 400 <= c < 500: tag = "WARN  temporary failure (server problem): "
        else: tag = "OK    " if good(c) else "WARN  "
        print(f"{tag}{label} -> {c} {txt}")
    c, m = rcpt("relay-test@example.org"); show("RCPT to an external address (relay)", c, m, lambda c: c >= 500)
    if c == 250: print("WARN  open relay from this network")
    c, m = rcpt("postmaster@group4.umons"); show("RCPT postmaster@group4.umons", c, m, lambda c: c == 250)
    c, m = rcpt("no-such-user-check@group4.umons"); show("RCPT to an unknown local user", c, m, lambda c: c >= 500)
    s.rset(); s.quit()
except Exception as e:
    print(f"SMTP test failed: {e}")
try:
    import imaplib
    i = imaplib.IMAP4(W, 143, timeout=5)
    caps = " ".join(i.capabilities); i.logout()
    print(("OK    " if "LOGINDISABLED" in caps else "WARN  password login allowed without TLS: ") + f"IMAP 143 seen from ns1: {caps}")
except Exception as e:
    print(f"IMAP 143 from ns1: not reachable ({e.__class__.__name__})")
PY

    sec "Accounts (uid >= 1000): who they are, when they were created (read-only)"
    for u in $(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd); do
        ent=$(getent passwd "$u")
        info "$u: uid $(echo "$ent" | cut -d: -f3), home $(echo "$ent" | cut -d: -f6), shell $(echo "$ent" | cut -d: -f7), groups: $(id -nG "$u" 2>/dev/null)"
        info "   password status / last change: $(passwd -S "$u" 2>/dev/null | awk '{print $2, $3}')"
        if id -nG "$u" 2>/dev/null | grep -qwE 'sudo|wheel|root'; then warn "   $u has administrator rights (sudo)"; fi
        last3=$( (wtmpdb last -n 3 "$u" 2>/dev/null || last -n 3 -F "$u" 2>/dev/null) | grep -v '^$' | grep -vE '^(wtmp|wtmpdb) ' | head -3 | tr -s ' ' | tr '\n' ';')
        info "   last logins: ${last3:-none recorded}"
        h=$(echo "$ent" | cut -d: -f6)
        info "   home modified $(stat -c '%y' "$h" 2>/dev/null | cut -d. -f1), files $(find "$h" -xdev -type f 2>/dev/null | wc -l), ssh keys: $([ -s "$h/.ssh/authorized_keys" ] && echo YES || echo no), crontab: $(crontab -l -u "$u" >/dev/null 2>&1 && echo YES || echo no), processes: $(pgrep -u "$u" 2>/dev/null | wc -l)"
    done
    info "account creations in the logs (useradd):"
    journalctl --no-pager -o short-iso 2>/dev/null | grep -E 'useradd.*new user: name=' | sed -E 's/^([^ ]+) [^ ]+ ([^:]+):.*new user: /\1 \2: /' | cut -c1-140 | sed 's/^/        /'

    sec "9. Resources"
    info "vCPU $(nproc) | RAM $(free -m | awk '/^Mem:/{print $2" MB, used "$3" MB"}') | disk / $(df -h / | awk 'NR==2{print $2", used "$3}')"
}

main 2>&1 | tee "$OUT"
printf '\n%s warning(s). Full output: %s\n' "$(grep -c '^WARN' "$OUT")" "$OUT"
sh "$(dirname "$0")/push-results.sh" ns1 "$OUT"
