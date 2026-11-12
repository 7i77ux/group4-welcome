#!/usr/bin/env python3
"""Evidence of the ice scripts (read-only, D28): copies their text into one report with the
secrets redacted, plus metadata, for the analysis. Nothing on the VM is changed; ice is never run.

Usage (through checks/evidence_ice.sh): evidence_ice.py <vm> <output file> [root prefix for tests]

Redacted before anything is written:
- every line of /tmp/.test (it is piped into 'sudo -S': almost certainly the password of mother);
- values of password/passwd/pwd/pass/secret/token assignments;
- arguments of 'sshpass -p', 'echo <x> | sudo -S';
- private key blocks.
"""

import glob
import hashlib
import os
import re
import subprocess
import sys
import time

vm, out = sys.argv[1], sys.argv[2]
root = sys.argv[3] if len(sys.argv) > 3 else ""
P = lambda p: root + p  # noqa: E731


def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30).stdout.strip()
    except subprocess.TimeoutExpired:
        return ""


secrets = []
try:
    with open(P("/tmp/.test"), encoding="utf-8", errors="replace") as f:
        secrets = sorted({l.strip() for l in f if len(l.strip()) >= 3}, key=len, reverse=True)
except OSError:
    pass

PATTERNS = [
    (re.compile(r"(?i)\b(\w*(?:password|passwd|pwd|pass|secret|token|apikey|api_key)\w*['\"]?\s*[=:]\s*)(['\"])(.*?)\2"), r"\1\2<REDACTED>\2"),
    (re.compile(r"(sshpass\s+-p\s*)(['\"]?)[^\s'\"]+\2"), r"\1<REDACTED>"),
    (re.compile(r"(echo\s+(?:-e\s+|-n\s+)?)(['\"]?)[^|'\"]+?\2(\s*\|\s*sudo\s+-S)"), r"\1<REDACTED>\3"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.S), "<REDACTED PRIVATE KEY>"),
]


def redact(text):
    n = 0
    for i, s in enumerate(secrets, 1):
        text, k = re.subn(rf"(?<![A-Za-z0-9_]){re.escape(s)}(?![A-Za-z0-9_])", f"<REDACTED-SECRET-{i}>", text)
        n += k
    for rx, rep in PATTERNS:
        text, k = rx.subn(rep, text)
        n += k
    return text, n


lines = [f"== Evidence of ice on {vm} ({time.strftime('%Y-%m-%d %H:%M')}): read-only, secrets redacted, ice not executed",
         f"INFO  /tmp/.test: {'present, ' + str(len(secrets)) + ' line(s) used as secrets to redact (never printed)' if secrets else 'absent or empty'}"]
files = sorted(set(glob.glob(P("/usr/local/bin/ice*")) + glob.glob(P("/tmp/ice*")) + glob.glob(P("/root/ice*"))
                   + glob.glob(P("/tmp/next*")) + glob.glob(P("/tmp/poiuytre*"))))
lines.append("\n== Metadata")
for f in files:
    st = os.stat(f)
    with open(f, "rb") as fh:
        h = hashlib.sha256(fh.read()).hexdigest()
    lines.append(f"INFO  {f[len(root):]}: {st.st_size} bytes, owner uid {st.st_uid}, mode {oct(st.st_mode & 0o7777)}, "
                 f"modified {time.strftime('%Y-%m-%d %H:%M', time.localtime(st.st_mtime))}, sha256 {h}")
if not files:
    lines.append("INFO  no ice file found in /usr/local/bin, /tmp, /root")
lines.append(f"INFO  /etc/crontab lines running ice: {sh('grep -c ice ' + P('/etc/crontab') + ' 2>/dev/null') or 0}")
for l in sh(f"grep -n ice {P('/etc/crontab')} 2>/dev/null | sort -t: -k2 -u").splitlines():
    lines.append(f"        {l}")
if not root:
    for l in sh("ps -eo pid,ppid,user,lstart,args | grep -E '/usr/local/bin/ice|/tmp/next|sudo -S' | grep -v grep").splitlines():
        lines.append(f"INFO  process: {' '.join(l.split())}")
if not root:
    lines.append("\n== Orders: what ice started and what the command servers answer now (nothing is executed)")
    ice_pids = sh("pgrep -f '/usr/local/bin/ice2?\\.py' | tr '\\n' ','").strip(",")
    if ice_pids:
        kids = sh(f"ps -o pid,ppid,user,lstart,args --ppid {ice_pids} 2>/dev/null | tail -n +2")
        lines.append("INFO  processes started by ice now: " + ("" if kids else "none"))
        lines += [f"        {' '.join(k.split())[:150]}" for k in kids.splitlines()]
    hits = sh("journalctl -o short-iso --no-pager 2>/dev/null | grep -E 'next\\.py|poiuytre|safeupdate|10\\.222\\.0\\.86' | tail -10")
    lines.append("INFO  journal lines about next.py, poiuytre or the command servers: " + ("" if hits else "none"))
    lines += [f"        {h[:150]}" for h in hits.splitlines()]
    lines.append(f"INFO  safeupdate.umons resolves to: {sh('getent hosts safeupdate.umons') or 'nothing'}")
    lines.append("INFO  files in /tmp (name, size, date):")
    lines += [f"        {l[:150]}" for l in sh("ls -la --time-style=+%Y-%m-%dT%H:%M /tmp 2>/dev/null | tail -n +2").splitlines()]
    for url in ("https://safeupdate.umons/next", "https://10.222.0.86/next"):
        tmp = "/root/next-observed-" + url.split("/")[2] + ".txt"
        st = sh(f"curl -sk --max-time 10 -o {tmp} -w '%{{http_code}} %{{size_download}}' {url}")
        lines.append(f"INFO  GET {url} (saved to {tmp}, NOT executed): HTTP status and bytes: {st or 'no answer'}")
        if st.startswith("200") and os.path.exists(tmp):
            files.append(tmp)
for f in files:
    try:
        with open(f, encoding="utf-8", errors="replace") as fh:
            text = fh.read(300_000)
    except OSError as e:
        lines.append(f"\n== {f[len(root):]}: not readable ({e})")
        continue
    text, n = redact(text)
    lines.append(f"\n== Content of {f[len(root):]} ({n} value(s) redacted)")
    lines.append(text.rstrip("\n"))
    lines.append(f"== End of {f[len(root):]}")

report = "\n".join(lines) + "\n"
for s in secrets:  # last safety net: never write a secret
    assert s not in report, "a secret survived the redaction: nothing written"
with open(out, "w", encoding="utf-8") as fh:
    fh.write(report)
print(report)
