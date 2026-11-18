#!/usr/bin/env python3
"""What went wrong with the mail on welcome (read-only test battery), 2026-11-18.
At 09:18 the mail worked (results/inventory-welcome); at 12:20 Dovecot did not start any more and Postfix
failed its MySQL lookups, after the New 4.3 was started by hand. This report collects, without changing
anything: who changed what today (sudo commands, packages, files, accounts, histories), the state of
Dovecot, Postfix and MariaDB, the mailboxes, live tests on 25 and 993, and a list of findings.
Passwords and hashes are masked; history lines that are not commands are hidden (a password typed by
mistake at the prompt would otherwise be printed).

Usage (through checks/mail_diag.sh): mail_diag.py <output file> <repo dir>
"""

import os
import re
import shutil
import smtplib
import socket
import ssl
import subprocess
import sys
import time

outfile, repo = sys.argv[1], sys.argv[2]
out, findings = [], []
TODAY = time.strftime("%Y-%m-%d")
CAL = "calogero@group4.umons"
BUILTINS = {"cd", "echo", "export", "exit", "history", "source", ".", "set", "unset", "alias", "for", "if", "while",
            "sudo", "su", "ls", "cat", "nano", "vi", "vim", "less", "cp", "mv", "rm", "mkdir", "chmod", "chown"}


def sh(cmd, timeout=40):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return (p.stdout + (("\n" + p.stderr) if p.stderr else "")).strip(), p.returncode
    except subprocess.TimeoutExpired:
        return "(timeout)", 124


def mask(text):
    text = text.replace("\\040", " ")
    text = re.sub(r"(?i)(identified\s+by\s+(password\s+)?)('[^']*'|\"[^\"]*\"|\S+)", r"\1<MASKED>", text)
    text = re.sub(r"(?i)(using\s+(password\s*\(\s*)?)'[^']*'", r"\1'<MASKED>'", text)
    text = re.sub(r"(?i)(password\s*\(\s*)'[^']*'", r"\1'<MASKED>'", text)
    text = re.sub(r"(?i)(password\s*[=:]\s*)\S+", r"\1<MASKED>", text)
    text = re.sub(r"(?i)(--password=|password=)\S+", r"\1<MASKED>", text)
    text = "\n".join(re.sub(r"(\s-p)(\S+)", r"\1<MASKED>", l) if re.search(r"mysql|mariadb", l) else l
                     for l in text.splitlines())
    text = re.sub(r"\{(SHA512-CRYPT|SHA256-CRYPT|BLF-CRYPT|ARGON2I?D?|PLAIN|CRYPT)\}\S+", r"{\1}<MASKED>", text)
    text = re.sub(r"\$[0-9a-z]{1,2}\$[^\s'\"]{20,}", "<MASKED-HASH>", text)
    text = re.sub(r"\*[0-9A-F]{40}", "*<MASKED-HASH>", text)
    return text


def sec(title):
    out.append(f"\n== {title}")


def show(label, cmd, limit=40, keep_rc=False):
    res, rc = sh(cmd)
    lines = mask(res).splitlines() or ["(nothing)"]
    out.append(f"-- {label}" + (f" (exit {rc})" if keep_rc else ""))
    out.extend(f"   {l[:170]}" for l in lines[-limit:])
    return res, rc


def history(label, path, n=50):
    out.append(f"-- {label}: last {n} lines of {path} (only lines that start with a command)")
    try:
        lines = open(path, errors="replace").read().splitlines()[-n:]
    except OSError:
        out.append("   (no file)")
        return
    for l in lines:
        l = l.replace("\\040", " ")
        first = l.strip().split(" ")[0] if l.strip() else ""
        if path.endswith(".mysql_history"):
            keep = re.match(r"(?i)(select|insert|update|delete|create|alter|drop|grant|revoke|use|show|flush|set|describe|desc|exit|quit)\b", l.strip())
        else:
            keep = first in BUILTINS or shutil.which(first) or first.startswith(("/", "./"))
        if keep or shutil.which(first) or first.startswith(("/", "./")):
            out.append(f"   {mask(l)[:170]}")
        else:
            out.append("   <line hidden: not a command>")


out.append(f"== Mail diagnosis of welcome ({time.strftime('%Y-%m-%d %H:%M')}), read-only, passwords masked")
out.append("   Reference: at 09:18 today (results/inventory-welcome) Dovecot and Postfix worked with the Linux accounts.")

sec("1. What changed today, and who")
show("sudo commands today (time, user, command)",
     "journalctl _COMM=sudo --since today --no-pager -o short-iso | grep 'COMMAND=' "
     "| sed -E 's/^([^ ]+) [^ ]+ sudo\\[[0-9]+\\]: +([^ ]+) : .*COMMAND=/\\1 \\2: /' | cut -c12-", limit=150)
show("packages installed or removed today (apt)",
     f"awk '/^Start-Date: {TODAY}/{{p=1}} /^End-Date/{{if(p)print; p=0}} p' /var/log/apt/history.log 2>/dev/null "
     "| grep -E 'Start-Date|Commandline|Install|Remove|Purge' | cut -c1-300", limit=40)
show("files changed today (mail, database, accounts, TLS, web)",
     "find /etc/dovecot /etc/postfix /etc/mysql /etc/group4-mail /etc/aliases /etc/aliases.db /etc/passwd /etc/group "
     "/etc/ssl/group4 /etc/nginx /var/vmail -xdev -maxdepth 4 -newermt 'today 00:00' "
     "-printf '%TH:%TM  %u:%g %m  %p\\n' 2>/dev/null | sort", limit=80)
show("accounts created or changed today", "journalctl --since today --no-pager -o short-iso "
     "| grep -E 'useradd|groupadd|usermod|userdel|chpasswd|passwd\\[' | cut -c12- | tail -20")
show("logins today (console and SSH)", "last -F -s today 2>/dev/null | head -15")
show("service starts and failures today", "journalctl --since today --no-pager -o short-iso "
     "| grep -E 'systemd\\[1\\]: (Started|Stopped|Starting|Failed|.*failed)' | grep -Ei 'dovecot|postfix|mariadb|nginx' | cut -c12- | tail -25")
history("shell history of root", "/root/.bash_history")
history("shell history of user", "/home/user/.bash_history")
history("MariaDB history of root", "/root/.mysql_history", 40)
history("MariaDB history of user", "/home/user/.mysql_history", 40)

sec("2. Dovecot")
show("version", "dovecot --version")
err, rc = sh("doveconf -n >/dev/null")
out.append(f"-- does the configuration load? doveconf -n -> exit {rc}")
out.extend(f"   {mask(l)}" for l in (err.splitlines() or ["(no error)"]))
if rc:
    findings.append(f"Dovecot configuration does not load: {mask(err.splitlines()[0]) if err else rc}")
m = re.search(r"Error in configuration file (\S+) line (\d+)", err)
if m:
    f, n = m.group(1), int(m.group(2))
    show(f"{f} around line {n} (the line of the error)", f"awk 'NR>={max(1, n - 10)} && NR<={n + 5} {{printf \"%4d  %s\\n\", NR, $0}}' {f}", limit=20)
    show(f"lines of {f} and when it changed", f"wc -l < {f}; stat -c '%y %U' {f}")
inc, _ = show("includes of 10-auth.conf (active = no # in front)", "grep -nE 'include auth-' /etc/dovecot/conf.d/10-auth.conf")
if re.search(r"^\d+:\s*!include auth-sql", inc, re.M):
    findings.append("10-auth.conf: '!include auth-sql.conf.ext' active (Dovecot 2.3 syntax in a 2.4 server: fix 1 of the review)")
if not re.search(r"^\d+:\s*!include auth-system", inc, re.M):
    findings.append("10-auth.conf: system login (PAM) switched off: the Linux accounts (calogero) cannot log in")
show("configuration files (date, owner, mode)", "ls -l --time-style=+%m-%d_%H:%M /etc/dovecot/*.conf /etc/dovecot/*.ext /etc/dovecot/conf.d/ 2>&1")
show("dovecot-sql.conf.ext (New 4.3 written for Dovecot 2.3)", "grep -vE '^\\s*(#|$)' /etc/dovecot/dovecot-sql.conf.ext 2>&1")
show("files of the scripts (99-group4-*.conf)", "for f in /etc/dovecot/conf.d/99-group4-*.conf; do echo \"# $f\"; grep -vE '^\\s*(#|$)' \"$f\"; done 2>&1")
st, _ = show("service", "systemctl is-active dovecot; systemctl is-enabled dovecot")
if not st.startswith("active"):
    findings.append(f"dovecot is {st.splitlines()[0]}: nobody can read mail (993)")
show("errors of dovecot today", "journalctl -u dovecot --since today -p warning --no-pager -o short-iso | cut -c12- | tail -15")

sec("3. Postfix")
pc, _ = show("settings for the delivery", "postconf mydestination virtual_mailbox_domains virtual_mailbox_base virtual_mailbox_maps "
             "virtual_alias_maps virtual_minimum_uid virtual_uid_maps virtual_gid_maps alias_maps home_mailbox smtpd_tls_cert_file")
vdom = re.search(r"^virtual_mailbox_domains = (.*)$", pc, re.M)
vam = re.search(r"^virtual_alias_maps = (.*)$", pc, re.M)
if vdom and "group4.umons" in vdom.group(1):
    findings.append("Postfix: group4.umons is a VIRTUAL domain: every mail for @group4.umons is looked up in MariaDB")
    if not (vam and vam.group(1).strip()):
        findings.append("Postfix: no virtual_alias_maps: postmaster@group4.umons is refused (fix 4 of the review)")
show("postfix check", "postfix check 2>&1", keep_rc=True)
show("MySQL map files (owner, mode, content)", "for f in /etc/postfix/mysql-*.cf; do ls -l \"$f\"; grep -vE '^\\s*(#|$)' \"$f\"; done 2>&1")
mp, _ = sh("grep -h '^user' /etc/postfix/mysql-virtual-mailbox-maps.cf 2>/dev/null")
if "mailuser" in mp:
    findings.append("Postfix map uses the database user 'mailuser' (ALL PRIVILEGES in the New 4.3: fix 3 of the review)")
q, _ = sh("grep -h '^query' /etc/postfix/mysql-virtual-mailbox-maps.cf 2>/dev/null")
if q and "Maildir" not in q:
    findings.append("Postfix map writes to /var/vmail/<domain>/<user>/ while Dovecot reads .../Maildir (fix 2 of the review)")
lk, rc = show(f"lookup of {CAL} in the mailbox map", f"postmap -q {CAL} mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf 2>&1", keep_rc=True)
if rc:
    findings.append(f"Postfix cannot look up {CAL} in MariaDB: {mask(lk.splitlines()[-1]) if lk else rc}")
show("errors and deliveries of Postfix today", "journalctl --since today --no-pager -o short-iso | grep 'postfix/' "
     "| grep -Ei 'fatal|error|warning|status=' | cut -c12- | tail -25")
show("queue", "postqueue -p 2>&1 | tail -4")

sec("4. MariaDB")
show("service and port", "systemctl is-active mariadb; mariadb --version 2>/dev/null | cut -c1-80; ss -Htln | awk '$4 ~ /:3306$/ {print \"listening on\", $4}'")
who, rc = show("root through the system account (unix socket)", "mysql -N -e 'SELECT CURRENT_USER()' 2>&1", keep_rc=True)
if rc:
    findings.append("MariaDB: root cannot log in through the system account (mysql_secure_installation?): the scripts need it")
else:
    show("database users (user, host, method)", "mysql -N -e \"SELECT user, host, plugin FROM mysql.user ORDER BY user\" 2>&1")
    show("rights of the mail users", "for u in mailuser postfix dovecot register; do for h in 127.0.0.1 localhost; do "
         "mysql -N -e \"SHOW GRANTS FOR '$u'@'$h'\" 2>/dev/null; done; done")
    g, _ = sh("mysql -N -e \"SHOW GRANTS FOR 'mailuser'@'127.0.0.1'\" 2>/dev/null")
    if "ALL PRIVILEGES" in g:
        findings.append("MariaDB: 'mailuser' has ALL PRIVILEGES on mailserver (fix 3 of the review)")
    show("databases", "mysql -N -e 'SHOW DATABASES' 2>&1")
    cols, _ = show("columns of virtual_users", "mysql -N -e 'SHOW COLUMNS FROM mailserver.virtual_users' 2>&1")
    if "virtual_users" not in cols and "Unknown" not in cols and not re.search(r"^active\s", cols, re.M):
        findings.append("MariaDB: virtual_users has no 'active' column (fix 5 of the review)")
    show("addresses in virtual_users (only scheme and length of each password)",
         "mysql -N -e 'SELECT email, LEFT(password, 14), LENGTH(password) FROM mailserver.virtual_users' 2>&1")
    show("aliases", "mysql -N -e 'SELECT source, destination FROM mailserver.virtual_aliases' 2>&1")
show("errors of mariadb today", "journalctl -u mariadb --since today -p warning --no-pager -o short-iso | cut -c12- | tail -10")

sec("5. Accounts and mailboxes")
show("accounts", "getent passwd vmail calogero; getent group vmail mailusers")
show("/var/vmail (owner, folders)", "find /var/vmail -maxdepth 4 -printf '%M %u:%g %p\\n' 2>&1 | head -30")
show("mails in the mailboxes", "for d in /home/calogero/Maildir /var/vmail/group4.umons/calogero /var/vmail/group4.umons/calogero/Maildir; do "
     "[ -d \"$d/new\" ] && echo \"$d: new $(ls $d/new | wc -l), cur $(ls $d/cur | wc -l)\"; done")
show("/etc/group4-mail (passwords of the database users, names only)", "ls -la /etc/group4-mail 2>&1")

sec("6. Live tests")
show("listening ports", "ss -Htln | awk '{print $4}' | grep -E ':(25|80|443|587|993|3306)$' | sort -u")
try:
    s = smtplib.SMTP("127.0.0.1", 25, timeout=15)
    c1 = s.ehlo("diag.group4.umons")[0]
    c2 = s.mail("diag@ns1.group4.umons")[0]
    code, msg = s.rcpt(CAL)
    s.rset(); s.quit()
    out.append(f"-- SMTP 25: EHLO {c1}, MAIL {c2}, RCPT TO {CAL}: {code} {msg.decode(errors='replace')[:100]} (no mail sent)")
    if code >= 400:
        findings.append(f"SMTP 25 refuses mail for {CAL}: {code} (mails from the other providers do not arrive)")
except (OSError, smtplib.SMTPException) as e:
    out.append(f"-- SMTP 25: {e.__class__.__name__}: {e}")
    findings.append(f"SMTP 25 does not answer properly: {e} (mails from the other providers do not arrive)")
try:
    ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 993), timeout=8) as raw, ctx.wrap_socket(raw) as t:
        out.append(f"-- IMAP 993: {t.recv(120).decode(errors='replace').strip()[:100]}")
except OSError as e:
    out.append(f"-- IMAP 993: {e.__class__.__name__}: {e}")
show("Dovecot user lookup (needs Dovecot running)", f"doveadm user {CAL} 2>&1 | head -6; doveadm user calogero 2>&1 | head -4")

sec("7. Clone of the scripts on welcome")
show("files changed by hand, stashes, last commits",
     f"git -c safe.directory='*' -C {repo} status --short; git -c safe.directory='*' -C {repo} stash list; "
     f"git -c safe.directory='*' -C {repo} log --oneline -3")

sec("Findings")
out.extend(f"   - {f}" for f in findings) if findings else out.append("   none: the mail configuration looks consistent")

text = mask("\n".join(out)) + "\n"
with open(outfile, "w") as f:
    f.write(text)
