#!/usr/bin/env python3
"""Check of Suricata on welcome after an installation by hand (DOCUMENTATION.md 10.17), read-only.

It checks the steps one by one and, for every problem, names the step to redo. Nothing is changed:
the configuration test (suricata -T) writes its logs in a temporary folder that is then removed.
With --test-alert it also downloads http://testmynids.org/uid/index.html (a harmless page made to
trigger the ET Open rule 2100498) and waits for the alert.

Usage (through checks/suricata.sh): suricata.py [--test-alert] [root prefix, only for tests]
Statuses: OK as expected; FAIL to fix (step of 10.17 given); WARN to look at; INFO data.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

args = [a for a in sys.argv[1:] if a != "--test-alert"]
TEST_ALERT = "--test-alert" in sys.argv[1:]
ROOT = args[0] if args else ""


def P(path):
    return ROOT + path


Y = P("/etc/suricata/suricata.yaml")
ORIG = P("/root/suricata.yaml.orig")
RULES = "/var/lib/suricata/rules"
LOG = P("/var/log/suricata")
IFACE, NET = "ens18", "[10.4.0.0/16]"
TEST_SID = "2100498"
COUNT = {"OK": 0, "INFO": 0}
LISTS = {"FAIL": [], "WARN": []}


def out(tag, text):
    print(f"{tag:<5} {text}")
    if tag in LISTS:
        LISTS[tag].append(text)
    else:
        COUNT[tag] = COUNT.get(tag, 0) + 1


def ok(t): out("OK", t)
def fail(t): out("FAIL", t)
def warn(t): out("WARN", t)
def info(t): out("INFO", t)
def sub(t): print(f"        {t}")
def sec(t): print(f"\n== {t}")


def check(cond, good, bad, level=fail):
    if cond:
        ok(good)
    else:
        level(bad)
    return bool(cond)


def run(cmd, timeout=30):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return p.stdout.strip(), p.stderr.strip(), p.returncode
    except subprocess.TimeoutExpired:
        return "", "timeout", 124


def sh(cmd, timeout=30):
    return run(cmd, timeout)[0]


def read(path, tail_bytes=None):
    try:
        with open(path, "rb") as f:
            if tail_bytes:
                f.seek(0, 2)
                f.seek(max(0, f.tell() - tail_bytes))
            return f.read().decode("utf-8", "replace")
    except OSError:
        return None


def pkg(name):
    st = sh(f"dpkg-query -W -f='${{Status}} ${{Version}}' {name} 2>/dev/null")
    return st.split()[-1] if st.startswith("install ok installed") else None


def block(text, key):
    """Lines of a top-level YAML key, up to the next top-level key (comments at column 0 skipped)."""
    m = re.search(rf"^{re.escape(key)}:[^\n]*\n(.*?)(?=^[^\s#]|\Z)", text, re.M | re.S)
    return m.group(1) if m else ""


# ---------------------------------------------------------------------------
print(f"Suricata check on welcome ({time.strftime('%Y-%m-%d %H:%M')}), read-only. Steps = DOCUMENTATION.md 10.17.")

sec("0. Resources")
mem = dict(re.findall(r"^(\w+):\s+(\d+) kB", read(P("/proc/meminfo")) or "", re.M))
if mem:
    tot, av = int(mem.get("MemTotal", 0)) // 1024, int(mem.get("MemAvailable", 0)) // 1024
    info(f"RAM {tot} MB, available {av} MB")
    if av < 300:
        warn(f"only {av} MB of RAM available: Suricata or the mail service may be killed (give welcome 3 GB)")

sec("1. Installation (step 1)")
ver = pkg("suricata")
if not check(ver, f"package suricata {ver}", "package suricata not installed: step 1"):
    print("\nSuricata is not installed: the other steps cannot be checked.")
    sys.exit(0)
check(pkg("suricata-update"), f"package suricata-update {pkg('suricata-update')}",
      "package suricata-update not installed: step 1 (sudo apt install -y suricata-update)")
check(pkg("jq"), "jq installed (to read eve.json)", "jq not installed: step 1 (sudo apt install -y jq)", warn)
info(f"{sh('suricata -V 2>/dev/null') or 'suricata -V: no answer'}")

sec("2. Basic setup (step 2): /etc/suricata/suricata.yaml")
text = read(Y)
if text is None:
    fail("/etc/suricata/suricata.yaml not readable")
    text = ""
check(os.path.exists(ORIG), "copy of the original configuration in /root/suricata.yaml.orig",
      "no copy in /root/suricata.yaml.orig: make it before editing (step 2), to be able to undo", warn)
if os.path.exists(ORIG) and text:
    diff = [l for l in sh(f"diff '{ORIG}' '{Y}' 2>/dev/null").splitlines() if l[:1] in "<>"]
    info(f"lines changed compared with the original: {len(diff)}")
    for l in diff[:12]:
        sub(l[:120])
hn = re.search(r'^\s*HOME_NET:\s*"?([^"\n]*?)"?\s*$', text, re.M)
hn = hn.group(1) if hn else None
if hn == NET:
    ok(f'HOME_NET "{hn}" (our network)')
elif hn and "10.0.0.0/8" in hn:
    fail(f'HOME_NET "{hn}" is still the default: the other groups (10.X) count as ours, use "{NET}" (step 2)')
else:
    fail(f'HOME_NET "{hn}": expected "{NET}" (step 2)')
en = re.search(r'^\s*EXTERNAL_NET:\s*"?([^"\n]*?)"?\s*$', text, re.M)
check(en and en.group(1) == "!$HOME_NET", 'EXTERNAL_NET "!$HOME_NET" (everything that is not ours)',
      f'EXTERNAL_NET "{en.group(1) if en else None}": expected "!$HOME_NET"', warn)
afp = block(text, "af-packet")
ifs = re.findall(r"^\s*-\s*interface:\s*(\S+)", afp, re.M)
real = [i for i in ifs if i != "default"]
if not afp:
    fail("no af-packet section in the configuration (step 2)")
elif real and real[0] == IFACE:
    ok(f"af-packet listens on {IFACE} (interfaces in the section: {' '.join(ifs)})")
else:
    fail(f"af-packet interfaces: {' '.join(ifs) or 'none'}; the first one must be {IFACE} (step 2)")
first = re.split(r"^\s*-\s*interface:", afp, flags=re.M)
cm = re.search(r"^\s*copy-mode:\s*(\S+)", first[1], re.M) if len(first) > 1 else None
if cm and cm.group(1).strip("'\"") in ("ips", "tap"):
    warn(f"af-packet copy-mode {cm.group(1)}: Suricata forwards and can block (IPS); planned is IDS only (D10)")
else:
    ok("af-packet without copy-mode: alerts only, nothing is blocked (IDS, D10)")
dflt = read(P("/etc/default/suricata")) or ""
m = re.search(r"^IFACE=(\S+)", dflt, re.M)
if m:
    check(m.group(1).strip("'\"") == IFACE, f"/etc/default/suricata IFACE={IFACE}",
          f"/etc/default/suricata IFACE={m.group(1)}: set IFACE={IFACE} (step 2)")
rp = re.search(r"^default-rule-path:\s*(\S+)", text, re.M)
rp = rp.group(1).strip("'\"") if rp else None
check(rp == RULES, f"default-rule-path {rp}", f"default-rule-path {rp}: expected {RULES} (step 2)")
rf = re.findall(r"^\s*-\s*(\S+)", block(text, "rule-files"), re.M)
check("suricata.rules" in rf, f"rule-files: {' '.join(rf)}",
      f"rule-files: {' '.join(rf) or 'none'}; 'suricata.rules' must be there (step 2)")

sec("3. Signatures (step 3)")
rfile = P(RULES + "/suricata.rules")
rtext = read(rfile)
if rtext is None:
    fail(f"{RULES}/suricata.rules missing: run sudo suricata-update (step 3)")
else:
    n = len(re.findall(r"^alert ", rtext, re.M))
    age = (time.time() - os.path.getmtime(rfile)) / 86400
    check(n > 1000, f"{n} active rules in {RULES}/suricata.rules",
          f"only {n} active rules in {RULES}/suricata.rules: run sudo suricata-update (step 3)")
    info(f"rules updated on {time.strftime('%Y-%m-%d %H:%M', time.localtime(os.path.getmtime(rfile)))}")
    if age > 7:
        warn(f"rules older than {int(age)} days: update them with sudo suricata-update")
    check(TEST_SID in rtext, f"test rule {TEST_SID} present", f"test rule {TEST_SID} not in the rules", warn)
if not ROOT:
    tmp = tempfile.mkdtemp(prefix="suricata-check-")
    o, e, rc = run(f"suricata -T -v -c {Y} -l {tmp}", timeout=240)
    shutil.rmtree(tmp, ignore_errors=True)
    both = o + "\n" + e
    loaded = re.search(r"(\d+) rules successfully loaded, (\d+) rules failed", both)
    if loaded:
        info(f"configuration test: {loaded.group(1)} rules loaded, {loaded.group(2)} failed")
    if "successfully loaded. Exiting" in both:
        ok("suricata -T: configuration valid")
    else:
        fail("suricata -T: configuration NOT valid (fix the setting named below, step 2-3):")
        for l in [l for l in both.splitlines() if re.search(r"<E>|<Error>|\bError\b|error", l)][:5]:
            sub(l.strip()[:150])

sec("4. Running Suricata (step 4)")
act = sh("systemctl is-active suricata 2>/dev/null")
ena = sh("systemctl is-enabled suricata 2>/dev/null")
check(act == "active", "service active", f"service {act or '?'}: sudo systemctl enable --now suricata (step 4)")
check(ena == "enabled", "service enabled at boot", f"service {ena or '?'} at boot: sudo systemctl enable suricata (step 4)")
info(f"started: {sh('systemctl show -p ActiveEnterTimestamp --value suricata 2>/dev/null') or '?'}")
pid = sh("pgrep -o -f '/usr/bin/suricata' 2>/dev/null")
if pid:
    info(f"process {pid}: {sh(f'ps -o args= -p {pid}')[:150]}")
    rss = sh(f"ps -o rss= -p {pid}")
    if rss.isdigit():
        info(f"memory used by Suricata: {int(rss) // 1024} MB")
slog = read(LOG + "/suricata.log", tail_bytes=400_000)
if slog is None:
    fail("/var/log/suricata/suricata.log missing: Suricata never started (step 4)")
else:
    i = slog.rfind("This is Suricata version")
    last = slog[i:] if i >= 0 else slog
    check(re.search(r"engine started", last, re.I), "suricata.log: engine started (last start)",
          "suricata.log: no 'engine started' after the last start (rules still loading, or an error below)")
    errs = [l for l in last.splitlines() if re.search(r"<Error>|<E>|\] [\d: -]+ Error:|^\S.* - Error", l)]
    if errs:
        warn(f"{len(errs)} error line(s) in suricata.log since the last start:")
        for l in errs[-3:]:
            sub(l.strip()[:150])
    if IFACE in last:
        ok(f"suricata.log names {IFACE}")
stats = read(LOG + "/stats.log", tail_bytes=300_000) or ""
kp = re.findall(r"^capture\.kernel_packets\s*\|\s*\S+\s*\|\s*(\d+)", stats, re.M)
kd = re.findall(r"^capture\.kernel_drops\s*\|\s*\S+\s*\|\s*(\d+)", stats, re.M)
if kp:
    p, d = int(kp[-1]), int(kd[-1]) if kd else 0
    check(p > 0, f"packets captured: {p} (stats.log)", "0 packets captured: Suricata listens on the wrong card? (step 2)")
    if p and d / p > 0.05:
        warn(f"{d} packets dropped ({100 * d / p:.1f} %): Suricata cannot keep up (CPU or RAM)")
else:
    info("stats.log: no capture counters yet (it is written every 8 seconds)")

sec("5. Alerting (step 5)")
fast = read(LOG + "/fast.log", tail_bytes=2_000_000)
if TEST_ALERT and not ROOT:
    before = (fast or "").count(f"[1:{TEST_SID}:")
    run("curl -s -o /dev/null --max-time 10 http://testmynids.org/uid/index.html", timeout=15)
    for _ in range(8):
        time.sleep(2)
        fast = read(LOG + "/fast.log", tail_bytes=2_000_000)
        if (fast or "").count(f"[1:{TEST_SID}:") > before:
            break
    check((fast or "").count(f"[1:{TEST_SID}:") > before, "test alert raised just now (curl testmynids.org)",
          "no test alert after curl testmynids.org: engine still loading, no outgoing HTTP, or wrong card")
if fast is None:
    fail("/var/log/suricata/fast.log missing (step 4-5)")
else:
    lines = [l for l in fast.splitlines() if l.strip()]
    tests = [l for l in lines if f"[1:{TEST_SID}:" in l]
    if tests:
        ok(f"test alert {TEST_SID} seen {len(tests)} time(s), last: {tests[-1][:26].strip()}")
    elif not TEST_ALERT:
        warn(f"test alert {TEST_SID} never seen: do step 5 (curl http://testmynids.org/uid/index.html)")
    info(f"alerts in fast.log: {len(lines)}; most frequent:")
    sigs = {}
    for l in lines:
        m = re.search(r"\[\*\*\] (\[\d+:\d+:\d+\] .*?) \[\*\*\]", l)
        if m:
            sigs[m.group(1)] = sigs.get(m.group(1), 0) + 1
    for s, c in sorted(sigs.items(), key=lambda x: -x[1])[:5]:
        sub(f"{c:>5}  {s[:130]}")

sec("6. EVE JSON (step 6)")
evp = LOG + "/eve.json"
if not os.path.exists(evp):
    fail("/var/log/suricata/eve.json missing (step 4)")
else:
    age = time.time() - os.path.getmtime(evp)
    info(f"eve.json: {os.path.getsize(evp) // 1024} KB, last write {int(age)} s ago")
    check(age < 120, "eve.json is being written", f"eve.json not written for {int(age)} s: is Suricata running?", warn)
    types = {}
    for l in (read(evp, tail_bytes=1_000_000) or "").splitlines()[1:]:
        try:
            t = json.loads(l).get("event_type", "?")
        except ValueError:
            continue
        types[t] = types.get(t, 0) + 1
    if types:
        info("event types in the last part of eve.json: " + ", ".join(f"{k} {v}" for k, v in sorted(types.items(), key=lambda x: -x[1])))

sec("7. Housekeeping")
check(os.path.exists(P("/etc/logrotate.d/suricata")), "logrotate rule for the Suricata logs",
      "no /etc/logrotate.d/suricata: the logs can fill the disk", warn)
du = sh(f"du -sh {LOG} 2>/dev/null | cut -f1")
info(f"size of /var/log/suricata: {du or '?'}; disk / used {sh('df --output=pcent / | tail -1').strip() or '?'}")

sec("Summary")
print(f"{COUNT['OK']} OK, {len(LISTS['FAIL'])} FAIL, {len(LISTS['WARN'])} WARN, {COUNT['INFO']} INFO")
for k in ("FAIL", "WARN"):
    for line in LISTS[k]:
        print(f"{k:<5} {line}")
if not LISTS["FAIL"]:
    print("Suricata is installed and configured as in DOCUMENTATION.md 10.17.")
