#!/usr/bin/env python3
"""What ice and mother do now, compared with what we saw on 2026-11-12 (read-only, attack detection).

Every item is compared with the known pattern (baseline below):
  SAME     as on 2026-11-12
  CHANGED  differs from 2026-11-12: the attacker (the teacher) changed something
  INFO     data
Nothing is changed and ice is never run. The orders of the two command servers (GET /next) are
saved in /root/ice-watch-next-<server>.txt and NOT executed. Secrets (the content of /tmp/.test,
'echo ... | sudo -S', passwords given to the expect scripts) are redacted before anything is
written or printed; the report is checked for them before it is saved.

Usage (through checks/ice_watch.sh): ice_watch.py <vm> <output file>
"""

import glob
import hashlib
import os
import re
import subprocess
import sys
import time

vm, outfile = sys.argv[1], sys.argv[2]

# ---- what we saw on 2026-11-12 (DOCUMENTATION 7.3, TIMELINE 12.6-12.7, 16.4)
KNOWN_HASH = {
    "c72cf5f54d8806ed90ba4d62de621a467da00ef716153ef2d4485ee5a1509048": "ice.py of 2026-11-10",
    "d18b295830034bc7311d4cc469e37c7a303ae5ecb1a1eb3f77fdf48b25acd34c": "ice2.py of 2026-11-04",
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855": "empty file (failed download)",
}
KNOWN_BIN = {"ice.py", "ice2.py"}
KNOWN_CRON = re.compile(r"^30 \* \* \* \* root python3 /usr/local/bin/ice2?\.py$")
KNOWN_SOURCES = {"10.4.255.10", "10.4.255.11", "10.4.255.41", "10.4.255.46", "10.4.255.47"}
KNOWN_SUDO = re.compile(
    r"COMMAND=(/usr/bin/ls|/bin/bash|/usr/bin/mv /tmp/ice2?\.py /usr/local/bin/ice2?\.py|/usr/bin/tee -a /etc/crontab"
    r"|/etc/init\.d/cron reload|/usr/sbin/service crond? reload|/usr/bin/python3 /usr/local/bin/ice2?\.py"
    r"|/usr/bin/chmod 755 /tmp/poiuytree?|/usr/bin/apt(-get)? (update|install -y (python3-scapy|expect))"
    r"|/usr/bin/dnf install -y (python3-scapy|expect))$")
KNOWN_PROC = re.compile(r"python3 /usr/local/bin/ice2?\.py|sh -c cat /tmp/\.test \| sudo -S python3 /usr/local/bin/ice2?\.py"
                        r"|^\[?poiuytree?\]?|/tmp/poiuytree?|ssh -o StrictHostKeyChecking no mother@|systemd --user|\(sd-pam\)"
                        r"|dbus-daemon --session|pipewire|wireplumber|^sudo -S python3")
KNOWN_ACCOUNTS = {"user", "mother", "calogero"}
C2 = ("https://safeupdate.umons/next", "https://10.222.0.86/next")

lines = []
changed = []


def say(tag, text):
    lines.append(f"{tag:<8}{text}")
    if tag == "CHANGED":
        changed.append(text)


def sub(text):
    lines.append(f"          {text}")


def sh(cmd, timeout=60):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except subprocess.TimeoutExpired:
        return ""


def sha(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return "unreadable"


secrets = []
try:
    with open("/tmp/.test", encoding="utf-8", errors="replace") as f:
        secrets = sorted({l.strip() for l in f if len(l.strip()) >= 3}, key=len, reverse=True)
except OSError:
    pass
for f in glob.glob("/usr/local/bin/ice*.py"):  # the password written in the code
    try:
        m = re.search(r"PASSWD\s*=\s*['\"](.+?)['\"]", open(f, encoding="utf-8", errors="replace").read())
        if m and m.group(1) not in secrets and len(m.group(1)) >= 3:
            secrets.append(m.group(1))
    except OSError:
        pass


def redact(text):
    for s in secrets:
        text = re.sub(rf"(?<![A-Za-z0-9_]){re.escape(s)}(?![A-Za-z0-9_])", "<REDACTED>", text)
    text = re.sub(r"(echo\s+(?:-e\s+|-n\s+)?)(['\"]?)[^|'\"]+?\2(\s*\|\s*sudo\s+-S)", r"\1<REDACTED>\3", text)
    text = re.sub(r"(-f /tmp/poiuytree?\s+)\S+", r"\1<REDACTED>", text)  # expect scripts get the password as 1st argument
    return text


say("INFO", f"ice and mother on {vm}, {time.strftime('%Y-%m-%d %H:%M')}; compared with 2026-11-12 (SAME / CHANGED)")

# 1. programs
lines.append("\n== 1. Programs in /usr/local/bin and /tmp")
for f in sorted(glob.glob("/usr/local/bin/*") + glob.glob("/tmp/ice*") + glob.glob("/tmp/*.py") + glob.glob("/tmp/next*")):
    if not os.path.isfile(f):
        continue
    h = sha(f)
    st = os.stat(f)
    desc = f"{f}: {st.st_size} bytes, modified {time.strftime('%Y-%m-%d %H:%M', time.localtime(st.st_mtime))}, sha256 {h[:16]}…"
    if h in KNOWN_HASH:
        say("SAME", f"{desc} = {KNOWN_HASH[h]}")
    elif os.path.basename(f) in KNOWN_BIN or f.startswith("/tmp"):
        say("CHANGED", f"{desc}: NEW VERSION / new file")
    else:
        say("INFO", f"{desc} (not ice)")

# 2. scheduled jobs
lines.append("\n== 2. Scheduled jobs (cron, systemd timers)")
cron = [l.strip() for l in (open("/etc/crontab").read().splitlines() if os.path.exists("/etc/crontab") else [])
        if l.strip() and not l.strip().startswith("#") and ("/usr/local/bin/ice" in l or "mother" in l or "/tmp/" in l)]
known = [l for l in cron if KNOWN_CRON.match(l)]
other = [l for l in cron if not KNOWN_CRON.match(l)]
say("SAME" if known else "CHANGED", f"/etc/crontab: {len(known)} known ice line(s) ({len(set(known))} different)" if known
    else "/etc/crontab: no ice line any more")
for l in sorted(set(other)):
    say("CHANGED", f"/etc/crontab, new line: {redact(l)[:140]}")
for f in sorted(glob.glob("/etc/cron.d/*") + glob.glob("/var/spool/cron/crontabs/*")):
    if os.path.basename(f) in (".placeholder", "e2scrub_all", "popularity-contest"):
        continue
    say("CHANGED" if os.path.getmtime(f) > time.mktime((2026, 11, 4, 0, 0, 0, 0, 0, -1)) else "INFO",
        f"{f} (modified {time.strftime('%Y-%m-%d %H:%M', time.localtime(os.path.getmtime(f)))})")
for l in sh("systemctl list-timers --all --no-legend --plain 2>/dev/null | awk '{print $NF\" \"$(NF-1)}'").splitlines():
    if not re.search(r"(apt-daily|dpkg-db|e2scrub|fstrim|logrotate|man-db|systemd-tmpfiles|anacron|fwupd|phpsessionclean|motd|update-notifier|exim|certbot|sysstat|plocate|apt-listbugs|cron)", l):
        say("CHANGED", f"systemd timer not of Debian: {l}")

# 3. processes
lines.append("\n== 3. Processes of mother and of ice")
ps = sh("ps -eo pid,user,lstart,args --no-headers")
rows = [l for l in ps.splitlines() if re.search(r"\bmother\b|/usr/local/bin/ice|poiuytre|/tmp/next|sudo -S", l)]
for l in rows:
    cmd = " ".join(l.split()[7:])
    tag = "SAME" if KNOWN_PROC.search(cmd) else "CHANGED"
    say(tag, redact(" ".join(l.split()[:2] + [" ".join(l.split()[2:7])] + [cmd]))[:160])
if not rows:
    say("CHANGED", "no process of mother or ice running now")

# 4. SSH logins of mother
lines.append("\n== 4. SSH logins of mother (last 24 hours)")
j = sh("journalctl -o short-iso --no-pager --since -24h 2>/dev/null | grep -E 'for mother from|user mother'", timeout=180)
src = {}
for m in re.finditer(r"^(\S+) .*Accepted (\w+) for mother from (\S+)", j, re.M):
    src.setdefault(m.group(3), []).append((m.group(1)[:16], m.group(2)))
for ip, ev in sorted(src.items(), key=lambda x: -len(x[1])):
    methods = sorted({e[1] for e in ev})
    tag = "SAME" if ip in KNOWN_SOURCES and methods == ["password"] else "CHANGED"
    say(tag, f"from {ip}: {len(ev)} login(s), method {' '.join(methods)}, last {ev[-1][0].replace('T', ' ')}")
if not src:
    say("CHANGED", "no SSH login of mother in the last 24 hours")
fails = re.findall(r"^\S+ .*(?:Failed \w+ for (?:invalid user )?mother|Invalid user mother) from \S+", j, re.M)
if fails:
    say("CHANGED", f"{len(fails)} failed login(s) for mother")

# 5. what mother runs with sudo
lines.append("\n== 5. Commands run with sudo by mother or by root through ice (last 7 days)")
sj = sh("journalctl -o short-iso --no-pager --since -7d _COMM=sudo 2>/dev/null | grep 'COMMAND='", timeout=180)
seen = {}
for l in sj.splitlines():
    if " mother :" not in l and "/tmp/" not in l:
        continue
    cmd = "COMMAND=" + l.split("COMMAND=", 1)[1].strip()
    seen.setdefault(cmd, []).append(l[:16])
for cmd, ts in sorted(seen.items(), key=lambda x: x[1][-1]):
    tag = "SAME" if KNOWN_SUDO.search(cmd) else "CHANGED"
    say(tag, f"{redact(cmd)[:110]}  x{len(ts)}, last {ts[-1].replace('T', ' ')}")
if not seen:
    say("INFO", "no such sudo command in the last 7 days")

# 6. accounts and keys (new ways in)
lines.append("\n== 6. Accounts, SSH keys, sudo rules")
acc = [l.split(":") for l in open("/etc/passwd").read().splitlines()]
users = {a[0] for a in acc if a[2].isdigit() and 1000 <= int(a[2]) < 65000}
for u in sorted(users - KNOWN_ACCOUNTS):
    say("CHANGED", f"new account: {u}")
say("SAME" if "mother" in users else "CHANGED", f"account mother {'present' if 'mother' in users else 'GONE'}; "
    f"password status: {' '.join(sh('passwd -S mother 2>/dev/null').split()[1:3])}")
for home in ["/root"] + [f"/home/{u}" for u in sorted(users)]:
    k = os.path.join(home, ".ssh/authorized_keys")
    if os.path.exists(k):
        n = len([l for l in open(k, errors="replace") if l.strip() and not l.startswith("#")])
        say("CHANGED", f"{k}: {n} key(s), modified {time.strftime('%Y-%m-%d %H:%M', time.localtime(os.path.getmtime(k)))}")
for f in sorted(glob.glob("/etc/sudoers.d/*")):
    if os.path.basename(f) != "README":
        say("CHANGED", f"sudo rule file {f}")

# 7. orders of the command servers (saved, not executed)
lines.append("\n== 7. Orders of the command servers (GET /next, saved, NOT executed)")
for url in C2:
    host = url.split("/")[2]
    tmp = f"/root/ice-watch-next-{host}.txt"
    st = sh(f"curl -sk --max-time 10 -o {tmp} -w '%{{http_code}} %{{size_download}}' {url}")
    code = st.split()[0] if st else "no answer"
    if code == "404":
        say("SAME", f"{url}: 404 (no order)")
    else:
        say("CHANGED", f"{url}: {st or 'no answer'} (saved in {tmp}, not executed)")
        if code == "200" and os.path.exists(tmp):
            for l in open(tmp, errors="replace").read().splitlines()[:15]:
                sub(redact(l)[:140])
say("SAME" if not os.path.exists("/tmp/next.py") else "CHANGED",
    "/tmp/next.py " + ("absent: no order executed" if not os.path.exists("/tmp/next.py") else "PRESENT: an order was executed"))

# 8. network
lines.append("\n== 8. Connections of the ice processes now")
conns = sh("ss -tunp 2>/dev/null | grep -E 'python3|expect|ssh' | grep -v ':22 .*sshd'")
for l in conns.splitlines()[:10]:
    peer = l.split()[5] if len(l.split()) > 5 else l
    tag = "SAME" if re.search(r"10\.222\.0\.86:443|10\.4\.255\.\d+:22", peer) else "CHANGED"
    say(tag, " ".join(l.split()[:6])[:140])
if not conns:
    say("INFO", "no connection open right now (ice sleeps about 1 hour between rounds)")

lines.append("\n== Summary")
lines.append(f"{len(changed)} CHANGED compared with 2026-11-12" + (":" if changed else ": same pattern as before."))
for c in changed:
    lines.append(f"CHANGED {c[:150]}")

report = redact("\n".join(lines)) + "\n"
for s in secrets:
    assert s not in report, "a secret survived the redaction: nothing written"
with open(outfile, "w", encoding="utf-8") as fh:
    fh.write(report)
print(report)
