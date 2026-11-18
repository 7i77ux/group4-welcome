#!/usr/bin/env python3
"""Inventory of the new structure (read-only): what is really configured on this VM after the changes of
2026-11-17 (pfSense with DMZ and NAT, NOTES chapter 8; virtual mailboxes with MariaDB, NOTES "New 4.3").
It only reads: addresses, routes, DNS answers, zones, Postfix/Dovecot/MariaDB settings, listening ports.
Passwords are masked; no password hash is printed. The checks are then updated from this report.

Usage (through checks/inventory.sh): inventory.py <vm> <output file>
"""

import os
import re
import socket
import subprocess
import sys
import time

vm, outfile = sys.argv[1], sys.argv[2]
out = []


def sh(cmd, timeout=40):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return (p.stdout + (("\n" + p.stderr) if p.returncode and p.stderr else "")).strip()
    except subprocess.TimeoutExpired:
        return "(timeout)"


def mask(text):
    text = re.sub(r"(?i)(password\s*[=:]\s*)\S+", r"\1<MASKED>", text)
    text = re.sub(r"(?i)(password=)\S+", r"\1<MASKED>", text)
    text = re.sub(r"\{(SHA512-CRYPT|SHA256-CRYPT|BLF-CRYPT|ARGON2I?D?)\}\S+", r"{\1}<MASKED>", text)
    text = re.sub(r"\$[0-9a-z]{1,2}\$[^\s'\"]{20,}", "<MASKED-HASH>", text)
    return text


def sec(title):
    out.append(f"\n== {title}")


def show(label, cmd, limit=40):
    res = mask(sh(cmd))
    lines = res.splitlines() or ["(nothing)"]
    out.append(f"-- {label}: {cmd}")
    out.extend(f"   {l[:160]}" for l in lines[:limit])
    if len(lines) > limit:
        out.append(f"   ... {len(lines) - limit} more lines")


def port(host, p, t=3):
    try:
        socket.create_connection((host, p), timeout=t).close()
        return "open"
    except OSError as e:
        return f"closed/filtered ({e.__class__.__name__})"


out.append(f"== Inventory of {vm} ({time.strftime('%Y-%m-%d %H:%M')}), read-only, passwords masked")

sec("1. Network of this VM")
show("addresses", "ip -br -4 addr")
show("routes", "ip -4 route")
show("NetworkManager profile of ens18",
     "c=$(nmcli -g GENERAL.CONNECTION device show ens18 2>/dev/null); echo \"profile: $c\"; "
     "nmcli -g ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns connection show \"$c\" 2>/dev/null")
show("/etc/network/interfaces (without comments)", "grep -vE '^\\s*(#|$)' /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null")
show("resolv.conf", "grep -E '^(nameserver|search)' /etc/resolv.conf")
gw = sh("ip -4 route show default | awk '{print $3; exit}'")
for h in sorted({gw, "10.4.2.1", "10.4.255.1", "10.4.255.254"} - {""}):
    out.append(f"   ping {h}: {'answers' if subprocess.run(['ping', '-c1', '-W2', h], capture_output=True).returncode == 0 else 'no answer'}")
out.append(f"   outgoing HTTPS (deb.debian.org): {sh('curl -s -o /dev/null -w %{http_code} --max-time 8 https://deb.debian.org/') or 'none'}")
out.append(f"   GitHub SSH (github.com:22, used to push the results): {port('github.com', 22)}")

sec("2. Our names as the other groups see them (resolver of the course 10.4.255.254) and through ns1")
for name, t in (("group4.umons", "MX"), ("group4.umons", "NS"), ("welcome.group4.umons", "A"), ("mail.group4.umons", "A"), ("ns1.group4.umons", "A")):
    out.append(f"   {name} {t}: course resolver -> {' '.join(sh(f'dig +short +time=2 +tries=1 @10.4.255.254 {name} {t}').split()) or 'nothing'}"
               f" | ns1 10.4.2.10 -> {' '.join(sh(f'dig +short +time=2 +tries=1 @10.4.2.10 {name} {t}').split()) or 'nothing'}"
               f" | ns1 10.4.255.10 -> {' '.join(sh(f'dig +short +time=2 +tries=1 @10.4.255.10 {name} {t}').split()) or 'nothing'}")
for ip in ("10.4.255.1", "10.4.2.11", "10.4.255.11", "10.4.2.10"):
    out.append(f"   reverse {ip}: course resolver -> {sh(f'dig +short +time=2 +tries=1 @10.4.255.254 -x {ip}') or 'nothing'}"
               f" | ns1 10.4.2.10 -> {sh(f'dig +short +time=2 +tries=1 @10.4.2.10 -x {ip}') or 'nothing'}")
for host in ("10.4.255.1", "10.4.2.11", "10.4.2.10"):
    out.append("   " + host + ": " + ", ".join(f"{p} {port(host, p)}" for p in (53, 25, 80, 993, 22)))

sec("3. Listening services of this VM")
show("ss -tlnup", "ss -Htlnup | awk '{print $1, $5, $7}' | sed -E 's/users:\\(\\(\"([^\"]+)\".*/\\1/' | sort -u")
show("services", "for s in named bind9 nginx apache2 postfix dovecot mariadb mysql php8.4-fpm php8.3-fpm suricata ssh; do "
     "a=$(systemctl is-active $s 2>/dev/null); [ \"$a\" = inactive ] && continue; echo \"$s $a $(systemctl is-enabled $s 2>/dev/null)\"; done")

if vm == "ns1":
    sec("4. DNS server (ns1)")
    show("zones loaded", "named-checkconf -z 2>&1 | grep -E 'loaded serial|error|not loaded'")
    conf = sh("named-checkconf -p 2>/dev/null")
    out.append("-- options and zones (named-checkconf -p, selected lines)")
    for l in conf.splitlines():
        if re.search(r"zone |file |forward|recursion|allow-|listen-on|dnssec|version|type ", l):
            out.append(f"   {l.strip()[:150]}")
    for zone, f in re.findall(r'zone "([^"]+)"[^{]*\{[^}]*?file "([^"]+)"', conf, re.S):
        show(f"records of {zone}", f"named-checkzone -D -o - {zone} {f} 2>&1 | grep -vE '^;|^$'", limit=30)

if vm == "welcome":
    sec("4. Mail (welcome)")
    show("postconf -n", "postconf -n", limit=80)
    show("postfix check", "postfix check 2>&1 | head -5")
    show("doveconf -n (main lines)", "doveconf -n 2>&1 | grep -E 'passdb|userdb|driver|args|query|connect|mail_driver|mail_path|mail_home|mail_location|mail_uid|mail_gid|"
         "first_valid|auth_mechanisms|ssl_server|ssl_cert|listen|protocols|sql|mysql|error|Error|^ *}' | head -60", limit=60)
    show("dovecot status", "systemctl is-active dovecot; journalctl -u dovecot -p err --since -24h -o cat --no-pager | tail -5")
    show("account vmail", "getent passwd vmail; getent group vmail")
    show("/var/vmail (mailboxes: new / cur mails)", "for d in /var/vmail/*/*/; do [ -d \"$d\" ] && echo \"$d new $(ls \"$d/new\" 2>/dev/null | wc -l) cur $(ls \"$d/cur\" 2>/dev/null | wc -l)\"; done")
    show("old Maildir of calogero", "ls -d /home/calogero/Maildir 2>/dev/null && echo \"new $(ls /home/calogero/Maildir/new | wc -l) cur $(ls /home/calogero/Maildir/cur | wc -l)\"")
    show("MariaDB: virtual users (addresses only)", "mysql -N -e 'SELECT email FROM mailserver.virtual_users' 2>&1 | head -20")
    show("Postfix finds calogero in the database", "postmap -q calogero@group4.umons mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf 2>&1")
    show("files with the database password (owner, mode)", "ls -l /etc/postfix/mysql-*.cf /etc/dovecot/dovecot-sql.conf.ext 2>&1")
    show("PAM rule of D24 (mailusers)", "grep -n mailusers /etc/pam.d/dovecot 2>&1")
    show("aliases", "grep -vE '^\\s*(#|$)' /etc/aliases")
    sec("5. Web (welcome)")
    show("nginx sites", "for f in /etc/nginx/sites-enabled/*; do echo \"$f -> $(readlink -f $f)\"; grep -hE 'listen|server_name|root|fastcgi_pass' $f | sed 's/^ */      /'; done")
    show("/var/www", "ls -la /var/www")

report = "\n".join(out) + "\n"
open(outfile, "w", encoding="utf-8").write(report)
print(report)
