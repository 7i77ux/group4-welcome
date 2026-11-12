#!/usr/bin/env python3
"""Full regression test of the Group 4 VMs (read-only). Run it through checks/full.sh.

It checks every state recorded in the documentation (decisions Dxx, weaknesses Wxx, timeline
steps 10.x) on the VM where it runs, and the other VM as the other groups see it.
It changes nothing:
- no configuration is written;
- no login is attempted;
- no mail is sent (the SMTP tests stop before DATA);
- the account mother is only observed (D28).

Statuses:
  OK    as documented
  FAIL  differs from the documentation: something broke, or the documentation is wrong
  NEW   not in the documentation: to look at
  OPEN  known open point (weakness or task id), expected for now
  INFO  data
"""

import http.client
import imaplib
import ipaddress
import os
import re
import smtplib
import socket
import ssl
import subprocess
import sys
import time

WELCOME, NS1, GW = "10.4.255.11", "10.4.255.10", "10.4.255.254"
DOMAIN = "group4.umons"
COUNT = {"OK": 0, "INFO": 0}
LISTS = {"FAIL": [], "NEW": [], "OPEN": []}


# ---------- output ----------

def _out(tag, ref, text):
    print(f"{tag:<5} {'[' + ref + '] ' if ref else ''}{text}", flush=True)


def ok(ref, text):
    COUNT["OK"] += 1
    _out("OK", ref, text)


def fail(ref, text):
    LISTS["FAIL"].append(f"{'[' + ref + '] ' if ref else ''}{text}")
    _out("FAIL", ref, text)


def new(text):
    LISTS["NEW"].append(text)
    _out("NEW", "", text)


def opn(ref, text):
    LISTS["OPEN"].append(f"[{ref}] {text}")
    _out("OPEN", ref, text)


def info(text):
    COUNT["INFO"] += 1
    _out("INFO", "", text)


def sub(text):
    print(f"        {text}", flush=True)


def sec(title):
    print(f"\n== {title}", flush=True)


def check(cond, ref, good, bad):
    if cond:
        ok(ref, good)
    else:
        fail(ref, bad)


# ---------- commands ----------

def run(cmd, timeout=30):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return p.stdout.strip(), p.stderr.strip(), p.returncode
    except subprocess.TimeoutExpired:
        return "", "timeout", 124


def sh(cmd, timeout=30):
    return run(cmd, timeout)[0]


def has(cmd):
    return run(f"command -v {cmd}")[2] == 0


def installed(pkg):
    return sh(f"dpkg-query -W -f='${{Status}}' {pkg} 2>/dev/null") == "install ok installed"


def unit_state(unit):
    return sh(f"systemctl is-active {unit} 2>/dev/null"), sh(f"systemctl is-enabled {unit} 2>/dev/null")


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def dig(server, name, rtype="A", extra=""):
    out = sh(f"dig +short +time=2 +tries=1 {extra} @{server} {name} {rtype} 2>/dev/null")
    return [l for l in out.splitlines() if l and not l.startswith(";;")]


def port_open(host, port, timeout=2):
    s = socket.socket()
    s.settimeout(timeout)
    try:
        return s.connect_ex((host, port)) == 0
    finally:
        s.close()


def no_verify():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def cert_of(host, port, starttls=""):
    opt = f"-starttls {starttls} " if starttls else ""
    return sh(f"echo | timeout 6 openssl s_client {opt}-connect {host}:{port} 2>/dev/null"
              f" | openssl x509 -noout -subject -issuer 2>/dev/null").replace("\n", " | ")


# ---------- network probes (data only, no report) ----------

def smtp_session(host, port=25, timeout=6):
    """One SMTP session without DATA: greeting, MAIL before HELO, EHLO, VRFY, three RCPT tests."""
    r = {}
    s = smtplib.SMTP(timeout=timeout)
    code, msg = s.connect(host, port)
    r["greeting"] = (code, msg.decode(errors="replace"))
    c, m = s.docmd("MAIL FROM:<full-test@ns1.group4.umons>")
    r["nohelo"] = (c, m.decode(errors="replace"))
    s.docmd("RSET")
    s._host = host
    s.ehlo("full-test.group4.umons")
    r["starttls"] = bool(s.has_extn("starttls"))
    r["auth_plain_text"] = s.esmtp_features.get("auth", "")
    c, m = s.docmd("VRFY", "postmaster")
    r["vrfy"] = (c, m.decode(errors="replace"))

    def rcpt(to):
        s.rset()
        s.mail("full-test@ns1.group4.umons")
        c, m = s.rcpt(to)
        return c, m.decode(errors="replace")

    r["relay"] = rcpt("relay-test@example.org")
    r["postmaster"] = rcpt(f"postmaster@{DOMAIN}")
    r["unknown"] = rcpt(f"no-such-user-full-test@{DOMAIN}")
    s.rset()
    s.quit()
    return r


def http_get(host, path="/", host_header=None, timeout=6):
    c = http.client.HTTPConnection(host, 80, timeout=timeout)
    c.request("GET", path, headers={"Host": host_header or host, "User-Agent": "group4-full-test"})
    resp = c.getresponse()
    body = resp.read()
    c.close()
    return resp.status, resp.getheader("Server", ""), body


def imap_993(host, timeout=6):
    i = imaplib.IMAP4_SSL(host, 993, ssl_context=no_verify(), timeout=timeout)
    greeting = i.welcome.decode(errors="replace")
    caps = " ".join(i.capabilities)
    i.logout()
    return greeting, caps


# ---------- classification of the probes (tested on the laptop with fake servers) ----------

def report_smtp(r, where):
    c, m = r["greeting"]
    check(c == 220 and m.startswith("mail.group4.umons ESMTP") and "postfix" not in m.lower(), "D26",
          f"{where} greeting: {c} {m}", f"{where} greeting: {c} {m} (expected '220 mail.group4.umons ESMTP', no software name)")
    c, m = r["nohelo"]
    check(c == 503, "D26", f"{where} MAIL before HELO refused: {c}", f"{where} MAIL before HELO: {c} {m[:60]} (expected 503, HELO required)")
    check(r["starttls"], "M1", f"{where} STARTTLS offered", f"{where} STARTTLS not offered")
    if r["auth_plain_text"]:
        fail("M2", f"{where} AUTH offered before TLS: {r['auth_plain_text']} (passwords readable on the network)")
    c, m = r["vrfy"]
    check(c == 502, "D26", f"{where} VRFY disabled: {c}", f"{where} VRFY answered {c} {m[:60]} (user enumeration)")
    c, m = r["relay"]
    if c == 250:
        fail("W3", f"{where} OPEN RELAY: RCPT to an external address accepted ({c} {m[:60]})")
    elif c == 554 and "Relay access denied" in m:
        ok("W30", f"{where} relay refused with a permanent code: {c}")
    elif c == 454 and "Relay access denied" in m:
        opn("W30", f"{where} relay refused, but with the temporary code 454 (abusers retry)")
    elif 400 <= c < 500:
        fail("W26", f"{where} RCPT to an external address: temporary error {c} {m[:70]} (server problem)")
    else:
        info(f"{where} RCPT to an external address refused: {c} {m[:70]}")
    c, m = r["postmaster"]
    check(c == 250, "D21", f"{where} RCPT postmaster@{DOMAIN}: {c} (reception works)",
          f"{where} RCPT postmaster@{DOMAIN}: {c} {m[:70]} (reception broken, see I3)")
    c, m = r["unknown"]
    check(c == 550, "10.41", f"{where} RCPT to an unknown user refused: {c}",
          f"{where} RCPT to an unknown user: {c} {m[:70]} (expected 550)")


def report_http(status, server, body, where, expect_file_body=None):
    check(status == 200, "10.10", f"{where}: HTTP {status}", f"{where}: HTTP {status}")
    check(server.lower() == "nginx", "W20", f"{where}: Server header '{server}' (no version)",
          f"{where}: Server header '{server}' (expected 'nginx' without version)")
    t = re.search(rb"<title>([^<]*)</title>", body)
    check(bool(t), "10.10", f"{where}: title '{t.group(1).decode(errors='replace') if t else ''}'", f"{where}: no <title> in the page")
    if expect_file_body is not None:
        check(body == expect_file_body, "10.10", f"{where}: served page = /var/www/welcome/index.html",
              f"{where}: served page differs from /var/www/welcome/index.html")


# ---------- sections ----------

def identity_and_network(vm, ip, repo):
    commit = sh(f"git -c safe.directory='*' -C '{repo}' log -1 --format=%h 2>/dev/null")
    sec(f"1. Identity and network ({vm}, {time.strftime('%Y-%m-%d %H:%M')}, checks commit {commit or '?'})")
    h = sh("hostname")
    check(h == vm, "D08", f"hostname {h}", f"hostname '{h}', expected {vm}")
    hosts = read("/etc/hosts") or ""
    check(re.search(rf"^127\.0\.1\.1\s+{vm}(\s|$)", hosts, re.M), "10.11",
          f"/etc/hosts: 127.0.1.1 {vm}", f"/etc/hosts has no '127.0.1.1 {vm}' line (sudo prints 'unable to resolve host')")
    addrs = sh("ip -4 -o addr show dev ens18 2>/dev/null | awk '{print $4}'").split()
    check(f"{ip}/16" in addrs, "D02", f"{ip}/16 on ens18", f"ens18 has {' '.join(addrs) or 'no address'}, expected {ip}/16")
    extra = [a for a in addrs if a != f"{ip}/16"]
    if extra:
        new(f"other addresses on ens18: {' '.join(extra)} (DHCP leftover?)")
    conn = sh("nmcli -g GENERAL.CONNECTION device show ens18 2>/dev/null")
    if conn:
        def f(k):
            return sh(f"nmcli -g {k} connection show '{conn}' 2>/dev/null")
        m, a, g, d, ign = f("ipv4.method"), f("ipv4.addresses"), f("ipv4.gateway"), f("ipv4.dns"), f("ipv4.ignore-auto-dns")
        info(f"NetworkManager profile '{conn}': method={m} addresses={a} gateway={g} dns={d} ignore-auto-dns={ign}")
        check(m == "manual" and f"{ip}/16" in a, "10.28/10.34", "address saved in the profile (survives a reboot)",
              f"profile method '{m}', addresses '{a}': the address is lost at reboot")
        check(g == GW, "D02", f"gateway in the profile: {g}", f"gateway in the profile '{g}', expected {GW}")
        if vm == "ns1":
            check(d.replace(" ", "") == "127.0.0.1,10.4.255.254", "10.34", f"DNS in the profile: {d}", f"DNS in the profile '{d}', expected 127.0.0.1,10.4.255.254")
            check(ign == "yes", "10.34", "DHCP DNS ignored (ignore-auto-dns yes)", f"ignore-auto-dns '{ign}'")
        else:
            check(GW in d, "0.3", f"DNS in the profile: {d}", f"DNS in the profile '{d}', expected {GW}")
    else:
        fail("W7", "ens18 is not managed by NetworkManager")
    stanza = sh("grep -hE '^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+ens18' /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null")
    check(not stanza, "W7", "no ifupdown configuration for ens18 (one tool only)", f"ifupdown also configures ens18: {stanza}")
    ns = sh("systemctl is-active networking 2>/dev/null")
    check(ns != "failed", "W7", f"networking.service {ns or 'absent'} (not failed)", "networking.service failed")
    gw = sh("ip -4 route show default | awk '{print $3; exit}'")
    check(gw == GW, "D02", f"default route via {gw}", f"default route via {gw or 'none'}")
    resolv = " ".join(re.findall(r"^nameserver\s+(\S+)", read("/etc/resolv.conf") or "", re.M))
    info(f"resolv.conf: {resolv}")
    if vm == "ns1":
        check(resolv.startswith("127.0.0.1"), "10.34", "ns1 asks its own BIND first", f"resolv.conf '{resolv}': ns1 does not ask its own BIND first")
    r = sh(f"getent hosts welcome.{DOMAIN} | awk '{{print $1}}'")
    check(r == WELCOME, "10.4", f"welcome.{DOMAIN} -> {r} (system resolver)", f"welcome.{DOMAIN} -> {r or 'no answer'} (system resolver)")
    code = sh("curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://deb.debian.org/")
    check(code not in ("", "000"), "fn. 2", f"outgoing HTTPS to the Internet works (deb.debian.org -> {code})",
          "no outgoing HTTPS to the Internet (apt and git pull will fail)")
    info(f"running since {sh('uptime -s')} (last boot)")
    pushurl = sh(f"git -c safe.directory='*' -C '{repo}' config --get remote.origin.pushurl")
    info(f"results push: {pushurl or 'not configured (setup-results.sh)'}")


def listeners(vm):
    sec("2. Listening services (non-local addresses), compared with the documentation")
    rows = set()
    local = set()
    for line in sh("ss -Htulpn 2>/dev/null").splitlines():
        p = line.split()
        if len(p) < 5:
            continue
        addr, _, port = p[4].rpartition(":")
        addr = addr.split("%")[0].strip("[]")
        proc = re.search(r'\(\("([^"]+)"', line)
        proc = proc.group(1) if proc else "?"
        if not port.isdigit():
            continue
        item = (p[0], int(port), proc)
        if addr.startswith("127.") or addr == "::1":
            local.add(item)
        else:
            rows.add(item)
    info("local only: " + ", ".join(sorted(f"{x[0]}/{x[1]} {x[2]}" for x in local)))
    if vm == "welcome":
        must = {("tcp", 25): "SMTP (Postfix)", ("tcp", 80): "web (nginx)", ("tcp", 993): "IMAP over TLS (Dovecot)"}
    else:
        must = {("tcp", 53): "DNS (BIND)", ("udp", 53): "DNS (BIND)"}
    seen = {(x[0], x[1]) for x in rows}
    for k, what in must.items():
        check(k in seen, "0.3", f"{k[0]}/{k[1]} listening: {what}", f"{k[0]}/{k[1]} NOT listening: {what}")
    for proto, port, proc in sorted(rows):
        key = (proto, port)
        if key in must:
            continue
        if port == 22:
            opn("W9", f"{proto}/22 {proc}: SSH open to every group (D19)")
        elif proc.startswith("firefox"):
            info(f"{proto}/{port} {proc}: browser client socket (not a service)")
        elif proc.startswith("avahi"):
            info(f"{proto}/{port} {proc} (mDNS, kept: D18)")
        elif port == 5355:
            opn("W14", f"{proto}/5355 {proc}: LLMNR open on the network")
        elif port == 143:
            fail("D25", f"{proto}/143 {proc}: IMAP without TLS is open again")
        elif port == 587:
            c = cert_of("127.0.0.1", 587, "smtp")
            check("Simply The Best" in c, "D23", f"587 open with the course certificate: {c}", f"587 open WITHOUT the course certificate: {c}")
        elif port == 443:
            info(f"{proto}/443 {proc} open (HTTPS): certificate {cert_of('127.0.0.1', 443)}")
        else:
            new(f"{proto}/{port} {proc} listening on the network: not in the documentation")


def accounts(vm):
    sec("3. Accounts")
    pw = [l.split(":") for l in (read("/etc/passwd") or "").splitlines() if l.count(":") >= 6]
    for u in pw:
        if u[2] == "0" and u[0] != "root":
            fail("", f"account {u[0]} has uid 0 (a second root)")
    humans = [u for u in pw if 1000 <= int(u[2]) < 65534]
    names = {u[0] for u in humans}
    expected = {"user", "mother", "calogero"} if vm == "welcome" else {"user", "mother"}
    info(f"accounts with uid >= 1000: {' '.join(sorted(names))}")
    for n in sorted(names - expected):
        new(f"account '{n}' is not in the documentation (when was it created? see the logs below)")
    for n in sorted(expected - names):
        fail("D24" if n == "calogero" else "", f"account '{n}' missing")
    for u in humans:
        st = sh(f"passwd -S {u[0]} 2>/dev/null").split()
        if len(st) > 1 and st[1] == "NP":
            fail("", f"account {u[0]} has NO password")
    groups = {n: sh(f"id -nG {n} 2>/dev/null").split() for n in names}
    if "sudo" in groups.get("user", []):
        opn("W1", "user/user (template password) is an administrator (D12)")
    if "mother" in names:
        opn("W29", f"account mother: administrator ({' '.join(groups['mother'])}), not touched for now (D28)")
    if vm == "welcome" and "calogero" in names:
        ent = next(u for u in humans if u[0] == "calogero")
        check(ent[6] in ("/usr/sbin/nologin", "/sbin/nologin"), "D24", "calogero: shell nologin (mail only)", f"calogero: shell {ent[6]} (can log in to the VM)")
        check("mailusers" in groups["calogero"], "D24", "calogero in group mailusers", "calogero not in group mailusers: no mail login")
        md = f"{ent[5]}/Maildir"
        check(all(os.path.isdir(f"{md}/{d}") for d in ("cur", "new", "tmp")), "D20", f"{md} exists (cur, new, tmp)", f"{md} missing or incomplete")
    created = sh("journalctl --no-pager -o short-iso 2>/dev/null | grep -E 'useradd.*new user: name=' | sed -E 's/^([^ ]+) .*new user: name=([^,]+).*/\\1 \\2/'")
    if created:
        info("accounts created (useradd in the logs):")
        for l in created.splitlines()[-10:]:
            sub(l)


def investigation():
    sec("4. Account mother: read-only observation (D28, nothing is changed)")
    if not sh("getent passwd mother"):
        info("no account mother on this VM")
        return
    info(f"password status: {sh('passwd -S mother 2>/dev/null')}")
    procs = sh("ps -o pid=,ppid=,lstart=,args= -u mother 2>/dev/null")
    if procs:
        info(f"processes of mother: {len(procs.splitlines())}")
        for l in procs.splitlines()[:15]:
            sub(l[:150])
        ppids = sorted({l.split()[1] for l in procs.splitlines()})
        parents = sh(f"ps -o pid=,user=,args= -p {','.join(ppids)} 2>/dev/null")
        if parents:
            info("their parent processes (who started them):")
            for l in parents.splitlines()[:8]:
                sub(l[:150])
    else:
        info("processes of mother: none now")
    info(f"systemd linger (user services kept running without login): {sh('loginctl show-user mother -p Linger --value 2>/dev/null') or 'no session'}")
    logins = sh("journalctl -o short-iso --no-pager 2>/dev/null | grep -E 'sshd.*(Accepted|Failed) [a-z-]+ for mother from'")
    if logins:
        lines = logins.splitlines()
        methods = sorted({re.search(r"(Accepted|Failed) ([a-z-]+)", l).group(0) for l in lines})
        info(f"SSH logins of mother in the whole journal: {len(lines)}; methods: {', '.join(methods)}")
        per = {}
        for l in lines:
            src, when = re.search(r"from (\S+)", l).group(1), l.split()[0][:16]
            per.setdefault(src, []).append(when)
        for src, w in sorted(per.items(), key=lambda x: x[1][0]):
            sub(f"from {src}: {len(w)} logins, first {w[0]}, last {w[-1]}")
    else:
        info("SSH logins of mother: none in the journal")
    sudo_cmds = sh("journalctl -o short-iso --no-pager _COMM=sudo 2>/dev/null | grep -E 'sudo\\[[0-9]+\\]: +mother :'")
    if sudo_cmds:
        lines = sudo_cmds.splitlines()
        info(f"commands run with sudo by mother (whole journal): {len(lines)}; first 5 and last 5:")
        for l in (lines[:5] + ["..."] + lines[-5:]) if len(lines) > 10 else lines:
            sub(l if l == "..." else f"{l.split()[0][:16]} " + re.sub(r".*COMMAND=", "COMMAND=", l)[:130])
    else:
        info("commands run with sudo by mother: none in the journal")
    info("files of ice (metadata only, contents not printed):")
    for l in sh("ls -la --time-style=+%Y-%m-%dT%H:%M /usr/local/bin/ /tmp/.test /tmp/ice* 2>&1 | grep -vE '^total|^$'").splitlines():
        sub(l[:150])
    for l in sh("sha256sum /usr/local/bin/ice*.py 2>/dev/null").splitlines():
        sub(l[:150])
    n = sh("grep -c 'ice' /etc/crontab 2>/dev/null")
    info(f"lines of /etc/crontab that run ice: {n or 0}")
    procs_ice = sh("ps -eo pid,ppid,user,lstart,args 2>/dev/null | grep -E 'ice[0-9]*\\.py|sudo -S' | grep -v grep")
    info("processes running ice now: " + ("" if procs_ice else "none"))
    for l in procs_ice.splitlines():
        sub(l[:150])
    net = sh("ss -Htunap 2>/dev/null | grep -i python")
    info("network sockets of python processes: " + ("" if net else "none"))
    for l in net.splitlines():
        sub(" ".join(l.split())[:150])
    refs = sh("grep -rlI mother /etc/cron* /var/spool/cron /etc/systemd /etc/sudoers /etc/sudoers.d /etc/ssh /etc/profile.d 2>/dev/null")
    info(f"configuration files that mention mother: {' '.join(refs.split()) or 'none'}")
    outgoing = sh("ss -Htnp state established '( dport = :22 )' 2>/dev/null")
    info(f"outgoing SSH connections now: {outgoing.replace(chr(10), ' | ') or 'none'}")


def hardening(vm):
    sec("5. Hardening and open weaknesses")
    t = sh("sshd -T 2>/dev/null")
    pa = re.search(r"^passwordauthentication (\S+)", t, re.M)
    pr = re.search(r"^permitrootlogin (\S+)", t, re.M)
    if pa and pa.group(1) == "yes":
        opn("W9", "SSH accepts password logins (D19)")
    elif pa:
        ok("W9", f"SSH password login: {pa.group(1)}")
    if pr:
        check(pr.group(1) != "yes", "", f"SSH root login: {pr.group(1)}", "SSH root login with password allowed (PermitRootLogin yes)")
    if sh("timedatectl show -p NTPSynchronized --value 2>/dev/null") == "yes":
        ok("W28", "clock synchronized (NTP)")
    else:
        opn("W28", f"clock not synchronized (NTP); timesync: {sh('timedatectl show-timesync -p ServerName --value 2>/dev/null') or '?'}")
    if not installed("unattended-upgrades"):
        opn("W12", "no automatic security updates (unattended-upgrades not installed)")
    if not installed("fail2ban"):
        opn("W10", "no fail2ban (no automatic blocking)")
    rules = sh("nft list ruleset 2>/dev/null | grep -c 'hook input'")
    if rules in ("", "0"):
        opn("W2", "no host firewall rules (nftables empty)")
    else:
        info(f"nftables: {rules} input chain(s)")
    up = sh("apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep -c '^Inst'")
    info(f"packages with an update available (apt cache): {up or '?'}")
    if os.path.exists("/var/run/reboot-required"):
        info("a reboot is required by installed updates")


def health():
    sec("6. Health")
    failed = sh("systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}'")
    if failed:
        for u in failed.split():
            new(f"systemd unit failed: {u}")
    else:
        ok("", "no failed systemd unit")
    use = sh("df --output=pcent / | tail -1").strip().rstrip("%")
    if use.isdigit():
        check(int(use) < 85, "", f"disk / used {use}%", f"disk / used {use}% (above 85%)")
    info(f"RAM: {sh('free -m | awk \"/^Mem:/{print \\$2\\\" MB, used \\\"\\$3\\\" MB\\\"}\"')}")
    errs = sh("journalctl -p err --since -24h -o cat --no-pager 2>/dev/null | cut -c1-110 | sort | uniq -c | sort -rn | head -5")
    if errs:
        info("most frequent errors in the logs (24 h):")
        for l in errs.splitlines():
            sub(l.strip())


# ---------- welcome ----------

def web():
    sec("7. Web (nginx)")
    a, e = unit_state("nginx")
    check(a == "active" and e == "enabled", "10.10", f"nginx {a}, {e} at boot", f"nginx {a}, {e or '?'} at boot")
    rs = sh("systemctl show nginx -p Restart --value 2>/dev/null")
    rsu = sh("systemctl show nginx -p RestartUSec --value 2>/dev/null")
    check(rs == "on-failure", "10.10", f"nginx restarts after a crash (Restart={rs}, after {rsu})", f"nginx Restart={rs or '?'}")
    _, err, rc = run("nginx -t")
    check(rc == 0, "10.10", "nginx -t: configuration valid", f"nginx -t: {err.splitlines()[-1] if err else rc}")
    sites = sorted(os.listdir("/etc/nginx/sites-enabled")) if os.path.isdir("/etc/nginx/sites-enabled") else []
    check(sites == ["welcome"], "10.10", "sites enabled: welcome only", f"sites enabled: {' '.join(sites) or 'none'} (expected welcome only)")
    conf = read("/etc/nginx/sites-enabled/welcome") or ""
    for pat, what in ((r"listen\s+80\s+default_server", "listen 80 default_server"),
                      (rf"server_name\s+welcome\.{DOMAIN}", f"server_name welcome.{DOMAIN}"),
                      (r"root\s+/var/www/welcome", "root /var/www/welcome"),
                      (r"server_tokens\s+off", "server_tokens off")):
        check(re.search(pat, conf), "10.10", f"site: {what}", f"site: '{what}' missing")
    page = None
    try:
        with open("/var/www/welcome/index.html", "rb") as f:
            page = f.read()
        ok("10.10", f"/var/www/welcome/index.html present ({len(page)} bytes)")
    except OSError:
        fail("10.10", "/var/www/welcome/index.html missing")
    try:
        st, srv, body = http_get("127.0.0.1", host_header=f"welcome.{DOMAIN}")
        report_http(st, srv, body, "http://welcome (local)", page)
        if b"abuse@" in body:
            fail("W22", "the page publishes abuse@ again")
        if re.search(rb"send and receive.*?Online", body, re.S) and not port_open("127.0.0.1", 587):
            opn("D15", "the page says 'send and receive: Online' but customers cannot send (no 587)")
        st, _, _ = http_get("127.0.0.1", "/no-such-page-full-test", f"welcome.{DOMAIN}")
        check(st == 404, "10.10", "unknown path -> 404", f"unknown path -> {st}")
    except OSError as ex:
        fail("10.10", f"local web test failed: {ex}")
    try:
        st, srv, body = http_get(f"welcome.{DOMAIN}")
        check(st == 200, "10.10", f"http://welcome.{DOMAIN}/ (by name) -> {st}", f"http://welcome.{DOMAIN}/ (by name) -> {st}")
    except OSError as ex:
        fail("10.10", f"http://welcome.{DOMAIN}/ by name: {ex}")
    check(not installed("apache2"), "10.10", "apache2 not installed", "apache2 installed")
    if not port_open("127.0.0.1", 443):
        opn("W11", "no HTTPS (443) yet: waits for the course certificate")


def postfix():
    sec("8. Mail: Postfix")
    if not has("postconf"):
        fail("D05", "Postfix not installed")
        return
    a, e = unit_state("postfix")
    check(a == "active" and e == "enabled", "D05", f"postfix {a}, {e} at boot", f"postfix {a}, {e or '?'} at boot")

    def pc(k):
        return sh(f"postconf -h {k} 2>/dev/null")
    o, er, rc = run("postfix check")
    if rc != 0:
        fail("10.41", f"postfix check failed: {(o or er).splitlines()[0] if (o or er) else rc}")
    elif o or er:
        for l in (o + "\n" + er).strip().splitlines():
            new(f"postfix check warning: {l[:120]}")
    else:
        ok("10.41", "postfix check: no warnings")
    info(f"version {pc('mail_version')}")
    check(pc("myhostname") == f"mail.{DOMAIN}", "W21", f"myhostname = {pc('myhostname')}", f"myhostname = {pc('myhostname')} (expected mail.{DOMAIN})")
    check(DOMAIN in re.split(r"[\s,]+", pc("mydestination")), "10.13", f"mydestination includes {DOMAIN}", f"mydestination = {pc('mydestination')}")
    mailname = (read("/etc/mailname") or "").strip()
    check(mailname == DOMAIN, "10.13", f"/etc/mailname = {mailname}", f"/etc/mailname = '{mailname}'")
    mn = " ".join(re.split(r"[\s,]+", pc("mynetworks").strip()))
    check(mn == "127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128", "D21", f"mynetworks only local: {mn}", f"mynetworks = {mn} (expected only local: relay or reception at risk)")
    bad = []
    for x in mn.split():
        try:
            ipaddress.ip_network(x.replace("[", "").replace("]", ""), strict=True)
        except ValueError:
            bad.append(x)
    check(not bad, "W26", "mynetworks entries well formed", f"malformed mynetworks entries: {' '.join(bad)} (remote senders get 451)")
    n = sh("journalctl --since -24h -o cat --no-pager 2>/dev/null | grep -c 'non-null host address bits'")
    check(n in ("", "0"), "W26", "no 'non-null host address bits' warning in 24 h", f"{n} 'non-null host address bits' warnings in 24 h")
    check(pc("home_mailbox") == "Maildir/", "D20", "home_mailbox = Maildir/", f"home_mailbox = '{pc('home_mailbox')}'")
    check(pc("mailbox_command") == "", "D20", "mailbox_command empty", f"mailbox_command = '{pc('mailbox_command')}' (Maildir ignored)")
    for k, v in (("disable_vrfy_command", "yes"), ("smtpd_helo_required", "yes"),
                 ("smtpd_banner", "$myhostname ESMTP"), ("smtpd_client_connection_rate_limit", "30")):
        check(pc(k) == v, "D26", f"{k} = {v}", f"{k} = '{pc(k)}' (expected {v})")
    rr = pc("smtpd_relay_restrictions")
    if "reject_unauth_destination" in rr:
        ok("W30", f"smtpd_relay_restrictions = {rr}")
    elif "defer_unauth_destination" in rr:
        opn("W30", f"smtpd_relay_restrictions = {rr} (refusal with 454)")
    else:
        fail("W3", f"smtpd_relay_restrictions = '{rr}': no unauth_destination rule (relay control?)")
    if pc("smtpd_tls_auth_only") != "yes" or not port_open("127.0.0.1", 587):
        opn("M2", "sending with login on 587 not ready (waits for the course certificate, D23)")
    am = pc("alias_maps").split(",")[0].strip()
    aliases = read("/etc/aliases") or ""
    names = re.findall(r"^([A-Za-z0-9._-]+):", aliases, re.M)
    check("postmaster" in names, "W18", "alias postmaster present", "alias postmaster missing (required by the mail standards)")
    info(f"aliases: {' '.join(names)}")
    db = None
    if ":" in am:
        kind, path = am.split(":", 1)
        db = {"hash": path + ".db", "lmdb": path + ".lmdb", "cdb": path + ".cdb"}.get(kind)
    if am:
        wrong = []
        for name, val in re.findall(r"^([A-Za-z0-9._-]+):\s*(.+?)\s*$", aliases, re.M):
            got = sh(f"postalias -q {name} {am} 2>/dev/null")
            if " ".join(got.replace(",", " ").split()) != " ".join(val.replace(",", " ").split()):
                wrong.append(f"{name} (file: {val}, database: {got or 'missing'})")
        check(not wrong, "10.13", f"aliases database answers like /etc/aliases ({am})",
              "aliases database differs from /etc/aliases, run 'sudo newaliases': " + "; ".join(wrong))
        if db and os.path.exists(db) and os.path.getmtime(db) < os.path.getmtime("/etc/aliases"):
            info("/etc/aliases is newer than its database (same content: only the date changed)" if not wrong else "/etc/aliases is newer than its database")
    q = sh("postqueue -p 2>/dev/null | tail -1")
    if "is empty" in q:
        ok("", "mail queue empty")
    else:
        info(f"mail queue: {q}")
    info(f"certificate on 25 (STARTTLS): {cert_of('127.0.0.1', 25, 'smtp')}")
    try:
        r = smtp_session("127.0.0.1")
        c, m = r["greeting"]
        check(c == 220 and m.startswith("mail.group4.umons ESMTP") and "postfix" not in m.lower(), "D26",
              f"local greeting: {c} {m}", f"local greeting: {c} {m}")
        check(r["vrfy"][0] == 502, "D26", f"local VRFY: {r['vrfy'][0]}", f"local VRFY: {r['vrfy'][0]} {r['vrfy'][1][:50]}")
        check(r["nohelo"][0] == 503, "D26", f"local MAIL before HELO: {r['nohelo'][0]}", f"local MAIL before HELO: {r['nohelo'][0]}")
    except (OSError, smtplib.SMTPException) as ex:
        fail("D05", f"local SMTP test failed: {ex}")
    errs = sh("journalctl --since -24h -o cat --no-pager 2>/dev/null | grep -E 'postfix/' | grep -iE 'fatal|panic|error' | tail -3")
    for l in errs.splitlines():
        new(f"Postfix error in 24 h: {l[:130]}")


def dovecot():
    sec("9. Mail: Dovecot and mailboxes")
    if not has("doveconf"):
        fail("M1", "Dovecot not installed")
        return
    a, e = unit_state("dovecot")
    check(a == "active" and e == "enabled", "M1", f"dovecot {a}, {e} at boot", f"dovecot {a}, {e or '?'} at boot")
    o, er, rc = run("doveconf -n")
    check(rc == 0, "10.41", "doveconf -n: configuration valid", f"doveconf -n: {er.splitlines()[-1] if er else rc}")
    info(f"version {sh('dovecot --version')}")

    def dc(k):
        return sh(f"doveconf -h {k} 2>/dev/null")
    check(dc("mail_driver") == "maildir", "D20", "mail_driver = maildir", f"mail_driver = '{dc('mail_driver')}'")
    check(dc("mail_path") == "%{home}/Maildir", "D20", "mail_path = %{home}/Maildir", f"mail_path = '{dc('mail_path')}'")
    mip = dc("mail_inbox_path")
    check("/var/mail" not in mip, "D20", f"mail_inbox_path not /var/mail ('{mip}')", f"mail_inbox_path = '{mip}' (INBOX outside Maildir)")
    g4 = read("/etc/dovecot/conf.d/99-group4.conf") or ""
    check(re.search(r"port\s*=\s*0", g4), "D25", "99-group4.conf closes 143 (port = 0)", "99-group4.conf: no 'port = 0' for imap")
    check(not port_open("127.0.0.1", 143), "D25", "143 closed", "143 open: IMAP without TLS")
    pam = [re.sub(r"\s+", " ", l.strip()) for l in (read("/etc/pam.d/dovecot") or "").splitlines()
           if l.strip() and not l.strip().startswith("#")]
    rule = "auth required pam_succeed_if.so user ingroup mailusers quiet"
    if pam and pam[0] == rule:
        ok("D24", "PAM: mail login only for the group mailusers (first rule)")
    elif rule in pam:
        fail("D24", "PAM rule for mailusers present but not first: earlier rules may decide before it")
    else:
        fail("D24", "no PAM rule: every Linux account can log in to the mail (also user/user)")
    members = sh("getent group mailusers | cut -d: -f4")
    check(members.split(",") == ["calogero"], "D24", f"group mailusers: {members}",
          f"group mailusers: '{members}' (expected calogero only; user must not be there)")
    if os.path.exists("/var/spool/postfix/private/auth"):
        info("auth socket for Postfix present (login on 587)")
    else:
        opn("M2", "no auth socket for Postfix yet (needed for login on 587)")
    try:
        greet, caps = imap_993("127.0.0.1")
        check(greet.startswith("* OK"), "M1", f"IMAP 993 over TLS: {greet[:60]}", f"IMAP 993 greeting: {greet[:60]}")
        info(f"IMAP 993 capabilities: {caps}")
    except (OSError, imaplib.IMAP4.error) as ex:
        fail("M1", f"IMAP 993 over TLS: {ex}")
    c = cert_of("127.0.0.1", 993)
    if "Simply The Best" in c:
        ok("D23", f"course certificate on 993: {c}")
    else:
        opn("D23", f"993 still uses the Debian certificate: {c}")
    for md in sorted(p for p in (f"/home/{h}/Maildir" for h in os.listdir("/home")) if os.path.isdir(p)):
        n_new = len(os.listdir(f"{md}/new")) if os.path.isdir(f"{md}/new") else 0
        n_cur = len(os.listdir(f"{md}/cur")) if os.path.isdir(f"{md}/cur") else 0
        info(f"{md}: {n_new} new, {n_cur} read")
    proof = sh("grep -rls 'delivery-test@ns1.group4.umons' /home/calogero/Maildir/new /home/calogero/Maildir/cur 2>/dev/null | head -1")
    if proof:
        ok("D27", f"proof of reception from ns1 found in the mailbox of calogero ({os.path.basename(proof)[:40]})")
    else:
        opn("D27", "no test mail from ns1 in the mailbox of calogero yet (checks/mailtest_ns1.sh)")
    mbox = sh("find /var/mail -type f -size +0 2>/dev/null")
    if mbox:
        info(f"old mailboxes in /var/mail (before Maildir): {' '.join(mbox.split())}")
    info("login test with a password: by hand, 'sudo doveadm auth test calogero' (succeeded) and '... user' (failed)")


def tls():
    sec("10. TLS key, request and certificate")
    key, csr = "/etc/ssl/group4/group4.key", "/etc/ssl/group4/group4.csr"
    if not os.path.exists(key):
        fail("D09", f"{key} missing")
        return
    st = os.stat(key)
    check(st.st_mode & 0o777 == 0o600 and st.st_uid == 0, "D09", "key: mode 600, owner root",
          f"key: mode {oct(st.st_mode & 0o777)}, owner uid {st.st_uid} (expected 600 root)")
    if not os.path.exists(csr):
        fail("D09", f"{csr} missing")
        return
    o, er, rc = run(f"openssl req -in {csr} -noout -verify")
    check("verify OK" in (o + er), "D09", "request: signature valid", f"request: {o or er}")
    subj = sh(f"openssl req -in {csr} -noout -subject")
    check(f"CN = welcome.{DOMAIN}" in subj or f"CN=welcome.{DOMAIN}" in subj, "D09", f"request {subj}", f"request {subj} (expected CN welcome.{DOMAIN})")
    txt = sh(f"openssl req -in {csr} -noout -text")
    check(f"DNS:welcome.{DOMAIN}" in txt and f"DNS:mail.{DOMAIN}" in txt, "D09", "request: SAN welcome + mail", "request: SAN incomplete")
    k1 = sh(f"openssl req -in {csr} -noout -pubkey | sha256sum")
    k2 = sh(f"openssl pkey -in {key} -pubout 2>/dev/null | sha256sum")
    check(k1 and k1 == k2, "D09", "request and key match", "request and key do NOT match")
    if os.path.exists("/home/user/group4.csr"):
        check(read("/home/user/group4.csr") == read(csr), "10.15", "copy for the teacher identical (/home/user/group4.csr)", "/home/user/group4.csr differs from the request")
    certs = [f for f in os.listdir("/etc/ssl/group4") if f not in ("group4.key", "group4.csr")]
    if not certs:
        opn("D23", "signed certificate from the teacher not received yet")
    for f in certs:
        p = f"/etc/ssl/group4/{f}"
        iss = sh(f"openssl x509 -in {p} -noout -issuer 2>/dev/null")
        if not iss:
            info(f"other file: {p}")
            continue
        k3 = sh(f"openssl x509 -in {p} -noout -pubkey | sha256sum")
        check("Simply The Best" in iss and k3 == k2, "D23", f"{p}: course CA, matches our key", f"{p}: {iss} (not the course CA, or not our key)")


def welcome_leftovers():
    sec("11. Leftovers on welcome")
    check(not installed("bind9") and not sh("pgrep -x named"), "W23", "no BIND on welcome (removed 10.31)", "BIND installed or running on welcome again")
    bk = sh("ls -d /root/fixes-backup-* 2>/dev/null")
    info(f"backups of the fixes: {' '.join(bk.split()) or 'none'}")


def ns1_from_welcome():
    sec("12. ns1 seen from welcome (DNS as the other groups ask it)")
    if not has("dig"):
        fail("", "dig not installed: DNS tests skipped")
        return
    dns_answers(NS1, "from welcome")
    ax = sh(f"dig +time=3 +tries=1 @{NS1} {DOMAIN} AXFR 2>&1")
    if re.search(r"\sIN\s+SOA\s", ax):
        fail("W8", "zone transfer (AXFR) ALLOWED to welcome: the whole zone is readable")
    elif "Transfer failed" in ax or "REFUSED" in ax:
        ok("W8", "zone transfer (AXFR) refused to welcome")
    else:
        fail("W8", f"zone transfer test: no answer from ns1 ({ax.splitlines()[-1][:60] if ax else 'empty'})")
    v = sh(f"dig +time=2 +tries=1 -c CH @{NS1} version.bind TXT 2>&1")
    if "status:" not in v:
        fail("W8", "version test: no answer from ns1")
    elif re.search(r'version\.bind\.\s.*TXT\s+"[^"]*\d', v):
        opn("W8", "BIND shows its version: " + re.search(r'TXT\s+("[^"]*")', v).group(1))
    else:
        ok("W8", "BIND version hidden")
    ext = dig(NS1, "deb.debian.org")
    info(f"ns1 resolves Internet names for welcome (recursion): {'yes' if ext else 'no'}")
    ports = {p: port_open(NS1, p) for p in (22, 25, 53, 80, 443, 993)}
    if not ports[53]:
        fail("D03", "ns1 53/tcp not reachable: ns1 down or DNS stopped; port tests skipped")
        return
    ok("D03", "ns1 53/tcp reachable")
    if ports[22]:
        opn("W9", "ns1 22/tcp reachable (SSH)")
    for p in (25, 80, 443, 993):
        if ports[p]:
            new(f"ns1 {p}/tcp open: not in the documentation")
    for g in ("group7", "group8"):
        r = sh(f"getent hosts welcome.{g}.umons | awk '{{print $1}}'")
        info(f"provider welcome.{g}.umons -> {r or 'no answer'}")


# ---------- ns1 ----------

EXPECTED_ZONE = {
    (f"{DOMAIN}.", "NS", "ns1.group4.umons."),
    (f"{DOMAIN}.", "MX", "10 mail.group4.umons."),
    ("ns1.group4.umons.", "A", NS1),
    ("welcome.group4.umons.", "A", WELCOME),
    ("mail.group4.umons.", "A", WELCOME),
    ("imap.group4.umons.", "CNAME", "mail.group4.umons."),
    ("smtp.group4.umons.", "CNAME", "mail.group4.umons."),
}
EXPECTED_REVERSE = {
    ("255.4.10.in-addr.arpa.", "NS", "ns1.group4.umons."),
    ("10.255.4.10.in-addr.arpa.", "PTR", "ns1.group4.umons."),
    ("11.255.4.10.in-addr.arpa.", "PTR", "mail.group4.umons."),
}


def dns_answers(server, where):
    for (name, rtype, value) in sorted(EXPECTED_ZONE):
        got = dig(server, name, rtype)
        check(got == [value], "10.4", f"{where}: {name} {rtype} {value}", f"{where}: {name} {rtype} -> {' '.join(got) or 'no answer'} (expected {value})")
    for ip, name in ((NS1, "ns1.group4.umons."), (WELCOME, "mail.group4.umons.")):
        got = [l for l in sh(f"dig +short +time=2 +tries=1 @{server} -x {ip} 2>/dev/null").splitlines() if l and not l.startswith(";;")]
        check(got == [name], "W25", f"{where}: PTR {ip} -> {name}", f"{where}: PTR {ip} -> {' '.join(got) or 'no answer'} (expected only {name})")
    flags = sh(f"dig +time=2 +tries=1 @{server} {DOMAIN} SOA 2>/dev/null | grep -o 'flags:[^;]*'")
    check(" aa" in flags, "10.4", f"{where}: authoritative answer (aa)", f"{where}: no aa flag ({flags}): zone not loaded?")
    for name in (DOMAIN, f"_dmarc.{DOMAIN}"):
        if any("v=spf1" in t or "v=DMARC1" in t for t in dig(server, name, "TXT")):
            info(f"{where}: TXT record on {name} (SPF/DMARC were not planned, D22)")


def zone_records(zone, path):
    out, err, rc = run(f"named-checkzone -D -o - {zone} {path}")
    recs, soa = set(), None
    for l in out.splitlines():
        p = l.split(None, 4)
        if len(p) == 5 and p[2] == "IN":
            if p[3] == "SOA":
                soa = (int(p[1]), p[4].split())
            else:
                recs.add((p[0], p[3], " ".join(p[4].split())))
    return recs, soa, rc


def bind():
    sec("7. DNS: BIND")
    a, e = unit_state("named")
    check(a == "active" and e == "enabled", "D03", f"named {a}, {e} at boot", f"named {a}, {e or '?'} at boot")
    o, er, rc = run("named-checkconf")
    check(rc == 0 and not (o or er), "10.4", "named-checkconf: no errors", f"named-checkconf: {(o or er)[:120]}")
    o, er, rc = run("named-checkconf -z")
    for z in (DOMAIN, "255.4.10.in-addr.arpa"):
        m = re.search(rf"zone {re.escape(z)}/IN: loaded serial (\d+)", o + er)
        check(bool(m), "10.4", f"zone {z} loads (serial {m.group(1) if m else '?'})", f"zone {z} does NOT load: {(o + er)[:150]}")
    rs = sh("rndc status 2>/dev/null")
    check("server is up and running" in rs, "D03", "rndc: server is up and running", f"rndc status: {rs[:80] or 'no answer'}")
    conf = sh("named-checkconf -p 2>/dev/null")
    files = dict(re.findall(r'zone "([^"]+)"[^{]*\{[^}]*?file "([^"]+)"', conf, re.S))
    for zone, expected in ((DOMAIN, EXPECTED_ZONE), ("255.4.10.in-addr.arpa", EXPECTED_REVERSE)):
        path = files.get(zone)
        if not path:
            fail("10.4", f"zone {zone} not declared in the configuration")
            continue
        recs, soa, rc = zone_records(zone, path)
        info(f"zone {zone}: file {path}, {len(recs)} records besides the SOA")
        for r in sorted(expected - recs):
            fail("10.4", f"{zone}: record missing in the file: {' '.join(r)}")
        for r in sorted(recs - expected):
            new(f"{zone}: record not in the documentation: {' '.join(r)}")
        if not (expected - recs) and not (recs - expected):
            ok("10.4", f"{zone}: records exactly as documented")
        if soa:
            ttl, f = soa
            served = sh(f"dig +short +time=2 +tries=1 @127.0.0.1 {zone} SOA").split()
            check(len(served) > 2 and served[2] == f[2], "10.4", f"{zone}: serial {f[2]} in the file = serial served",
                  f"{zone}: serial {f[2]} in the file, {served[2] if len(served) > 2 else '?'} served (reload forgotten?)")
            if zone == DOMAIN:
                got = (ttl, f[3], f[4], f[5], f[6])
                check(got == (172800, "43200", "900", "345600", "7200"), "D06",
                      "time fields unchanged: TTL 2d, refresh 12h, retry 15m, expire 4d, minimum 2h",
                      f"time fields changed: TTL {ttl}, refresh {f[3]}, retry {f[4]}, expire {f[5]}, minimum {f[6]} (D06 says unchanged)")
            else:
                info(f"{zone}: SOA TTL {ttl}, refresh {f[3]}, retry {f[4]}, expire {f[5]}, minimum {f[6]}")
    fw = re.search(r"forwarders\s*\{([^}]*)\}", conf)
    check(fw and GW in fw.group(1), "10.4", f"forwarder {GW}", f"forwarders: {fw.group(1).strip() if fw else 'none'}")
    for opt in ("allow-recursion", "allow-transfer", "version"):
        if not re.search(rf"^\s*{opt}\s", conf, re.M):
            opn("W8", f"option '{opt}' not written explicitly (defaults apply)")
    dv = re.search(r"dnssec-validation\s+(\S+);", conf)
    info(f"dnssec-validation {dv.group(1) if dv else 'default'}")
    dns_answers("127.0.0.1", "local")
    check(bool(dig("127.0.0.1", "deb.debian.org")), "10.4", "Internet names through the forwarder", "Internet names do not resolve (forwarder)")


def ns1_leftovers():
    sec("8. Leftovers on ns1")
    for p in ("apache2", "nginx", "pandoc"):
        check(not installed(p), "10.11", f"{p} not installed", f"{p} installed on ns1")
    check(not os.path.exists("/var/www/welcome"), "10.11", "/var/www/welcome absent", "/var/www/welcome exists on ns1")
    if installed("postfix"):
        st = "/".join(unit_state("postfix"))
        new(f"Postfix installed on ns1 ({st}): not in the documentation; needed?")


def welcome_from_ns1():
    sec("9. welcome seen from ns1 (as the other groups see it; no mail is sent, no login)")
    ports = {p: port_open(WELCOME, p) for p in (22, 25, 53, 80, 143, 443, 587, 993)}
    info("ports of welcome: " + " ".join(f"{p}:{'open' if v else 'closed'}" for p, v in ports.items()))
    if not (ports[25] or ports[80] or ports[993]):
        fail("D05", "welcome does not answer on 25, 80 or 993: VM down or unreachable; tests from ns1 skipped")
        return
    for p, ref, what in ((25, "D05", "SMTP"), (80, "10.10", "web"), (993, "M1", "IMAP over TLS")):
        check(ports[p], ref, f"{p} open ({what})", f"{p} closed ({what})")
    check(not ports[53], "W23", "53 closed (no DNS on welcome)", "53 open on welcome (leftover DNS)")
    check(not ports[143], "D25", "143 closed", "143 open: IMAP without TLS")
    if ports[22]:
        opn("W9", "22 open on welcome (SSH)")
    if not ports[587]:
        opn("M2", "587 closed: customers cannot send yet")
    if not ports[443]:
        opn("W11", "443 closed: no HTTPS yet")
    try:
        report_smtp(smtp_session(WELCOME), "SMTP from ns1:")
    except (OSError, smtplib.SMTPException) as ex:
        fail("D05", f"SMTP session from ns1 failed: {ex}")
    try:
        greet, caps = imap_993(WELCOME)
        check(greet.startswith("* OK"), "M1", f"IMAP 993 from ns1: {greet[:50]}", f"IMAP 993 from ns1: {greet[:50]}")
        check("LOGINDISABLED" not in caps, "M1", "IMAP 993: login possible over TLS", "IMAP 993: LOGINDISABLED even over TLS")
    except (OSError, imaplib.IMAP4.error) as ex:
        fail("M1", f"IMAP 993 from ns1: {ex}")
    for host, label in ((WELCOME, "http://10.4.255.11/ (by address)"), (f"welcome.{DOMAIN}", f"http://welcome.{DOMAIN}/ from ns1")):
        try:
            st, srv, body = http_get(WELCOME, host_header=host)
            report_http(st, srv, body, label)
        except OSError as ex:
            fail("10.10", f"{label}: {ex}")


# ---------- main ----------

def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("welcome", "ns1"):
        sys.exit("usage: full.py welcome|ns1 [repo]")
    vm = sys.argv[1]
    repo = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ip = WELCOME if vm == "welcome" else NS1
    print("Full regression test (read-only). OK = as documented; FAIL = differs from the documentation;")
    print("NEW = not in the documentation; OPEN = known open point (id); INFO = data.")
    identity_and_network(vm, ip, repo)
    listeners(vm)
    accounts(vm)
    investigation()
    hardening(vm)
    health()
    if vm == "welcome":
        web()
        postfix()
        dovecot()
        tls()
        welcome_leftovers()
        ns1_from_welcome()
    else:
        bind()
        ns1_leftovers()
        welcome_from_ns1()
    sec("Summary")
    print(f"{COUNT['OK']} OK, {len(LISTS['FAIL'])} FAIL, {len(LISTS['NEW'])} NEW, {len(LISTS['OPEN'])} OPEN, {COUNT['INFO']} INFO")
    for k in ("FAIL", "NEW"):
        for line in LISTS[k]:
            print(f"{k:<5} {line}")
    ids = sorted({re.match(r"\[([^\]]+)\]", l).group(1) for l in LISTS["OPEN"]})
    print(f"OPEN ids: {' '.join(ids)}")


if __name__ == "__main__":
    main()
