#!/usr/bin/env python3
"""How often ice attacks (read-only, D28): timing of the SSH logins of mother and of the rounds of ice.

From the journal of this VM:
- incoming SSH logins of mother, per source address: count, first, last, intervals (min, median,
  max), logins per day, minute of the hour, gaps longer than 3 hours;
- rounds of the local copies: every round runs 'sudo chmod 755 /tmp/poiuytre' (ice.py) or
  '/tmp/poiuytree' (ice2.py), so these lines give the exact time of each round;
- installations (sudo mv /tmp/ice*.py /usr/local/bin/...).
Then who is on the temporary DHCP addresses 10.4.255.41-.50 now (one ping each, MAC from the
neighbour table), to identify the unknown sources. Nothing is changed.

Usage (through checks/ice_timing.sh): ice_timing.py <vm> [journal file, only for tests]
"""

import re
import statistics
import subprocess
import sys
import time
from datetime import datetime

vm = sys.argv[1] if len(sys.argv) > 1 else "?"
OURS = {"10.4.255.10": "ns1", "10.4.255.11": "welcome", "10.4.255.254": "gateway"}


def sh(cmd, timeout=60):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout).stdout
    except subprocess.TimeoutExpired:
        return ""


if len(sys.argv) > 2:
    journal = open(sys.argv[2], encoding="utf-8", errors="replace").read()
else:
    journal = sh("journalctl -o short-iso --no-pager 2>/dev/null | grep -E "
                 "'for mother from|user mother|COMMAND=.*(poiuytre|/tmp/ice)'", timeout=300)

TS = r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)"


def when(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%S")


def series(title, times):
    """Print the timing of one series of events."""
    times = sorted(times)
    print(f"\n-- {title}: {len(times)}")
    if not times:
        return
    print(f"   first {times[0]:%Y-%m-%d %H:%M}, last {times[-1]:%Y-%m-%d %H:%M}")
    gaps = [(a, b) for a, b in zip(times, times[1:]) if (b - a).total_seconds() > 3 * 3600]
    iv = [(b - a).total_seconds() / 60 for a, b in zip(times, times[1:]) if (b - a).total_seconds() <= 3 * 3600]
    if iv:
        print(f"   interval (minutes, gaps over 3 h excluded): min {min(iv):.1f}, median {statistics.median(iv):.1f}, "
              f"mean {statistics.mean(iv):.1f}, max {max(iv):.1f} ({len(iv)} intervals)")
    per_day = {}
    for t in times:
        per_day[t.date()] = per_day.get(t.date(), 0) + 1
    print("   per day: " + ", ".join(f"{d:%m-%d} {n}" for d, n in sorted(per_day.items())))
    mins = sorted(t.minute for t in times)
    print(f"   minute of the hour: from :{mins[0]:02d} to :{mins[-1]:02d}, median :{int(statistics.median(mins)):02d}")
    if gaps:
        print(f"   gaps over 3 hours ({len(gaps)}): " + "; ".join(
            f"{a:%m-%d %H:%M} -> {b:%m-%d %H:%M} ({(b - a).total_seconds() / 3600:.0f} h)" for a, b in gaps[:8])
            + (" ..." if len(gaps) > 8 else ""))


print(f"== How often ice attacks, seen from {vm} ({time.strftime('%Y-%m-%d %H:%M')}), read-only")
print("Design (code of ice): one round every 3400 s + random 0-400 s = 56.7-63.3 minutes, plus the time of the round.")

logins = {}
fails = []
for m in re.finditer(TS + r".*Accepted (\w+) for mother from (\S+)", journal, re.M):
    logins.setdefault(m.group(3), []).append(when(m.group(1)))
for m in re.finditer(TS + r".*(Failed \w+ for (?:invalid user )?mother from \S+|Invalid user mother from \S+)", journal, re.M):
    fails.append(f"{m.group(1)} {m.group(2)}")

print("\n== 1. Incoming SSH logins of mother on this VM, per source")
if not logins:
    print("   none in the journal")
for ip in sorted(logins, key=lambda i: -len(logins[i])):
    series(f"from {ip} ({OURS.get(ip, 'UNKNOWN host')})", logins[ip])
alltimes = [t for ts in logins.values() for t in ts]
if alltimes:
    series("all sources together", alltimes)
print(f"\n   failed logins or invalid user for mother: {len(fails)}")
for f in fails[-5:]:
    print(f"   {f}")

print("\n== 2. Rounds of the copies of ice running on this VM (sudo chmod 755 of the expect script)")
for prog, script in (("ice.py", "/tmp/poiuytre"), ("ice2.py", "/tmp/poiuytree")):
    rounds = [when(m.group(1)) for m in re.finditer(TS + rf".*COMMAND=\S*chmod 755 {re.escape(script)}$", journal, re.M)]
    series(f"rounds of {prog} ({script})", rounds)

print("\n== 3. Installations on this VM (sudo mv of ice to /usr/local/bin)")
inst = re.findall(TS + r".*COMMAND=\S*mv (/tmp/ice2?\.py) (\S+)", journal, re.M)
for t, src, dst in inst[:20]:
    print(f"   {t.replace('T', ' ')}  {src} -> {dst}")
if len(inst) > 20:
    print(f"   ... {len(inst)} in total, last {inst[-1][0].replace('T', ' ')}")
if not inst:
    print("   none in the journal")

if len(sys.argv) <= 2:
    print("\n== 4. Who is on the temporary DHCP addresses now (one ping each, MAC from the neighbour table)")
    print("   Proxmox VMs have MAC addresses starting with BC:24:11: compare with PVE > VM > Hardware > Network Device.")
    unknown = sorted(ip for ip in logins if ip not in OURS)
    for i in range(41, 51):
        ip = f"10.4.255.{i}"
        alive = subprocess.run(["ping", "-c", "1", "-W", "1", ip], capture_output=True).returncode == 0
        neigh = sh(f"ip neigh show {ip}").strip()
        mac = re.search(r"lladdr (\S+)", neigh)
        mark = " <- logged in as mother" if ip in unknown else ""
        if alive or mac or mark:
            print(f"   {ip}: {'answers' if alive else 'no answer'}, MAC {mac.group(1) if mac else '?'}{mark}")
    print(f"   our VMs: ns1 BC:24:11:78:D3:A6, welcome BC:24:11:59:B9:3A")
