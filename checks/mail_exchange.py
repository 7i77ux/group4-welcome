#!/usr/bin/env python3
"""Mail exchange with the other mail providers (project statement, case 1: "it MUST be possible to
exchange messages across multiple mail providers"). Run on welcome through checks/mail_exchange.sh.

1. Our side, as the other providers see it: MX, A and PTR through the gateway resolver, Postfix,
   port 25.
2. The other groups that have a mail server: MX record of groupX.umons (X = 1-20), and whether their
   port 25 answers (greeting only, no mail sent).
3. After confirmation: ONE test mail per chosen group (default postmaster@groupX.umons), sent by our
   Postfix like any real mail, asking for a reply to calogero@group4.umons.
4. Result of each delivery from the Postfix log: sent, deferred or bounced, with the reason.
5. Mails received by calogero from other domains (the replies): headers only.
Run it again later (answer with Enter at step 3) to see new replies.
"""

import email.parser
import os
import re
import socket
import subprocess
import time

GW, ME, DOMAIN = "10.4.255.254", "10.4.255.11", "group4.umons"
SENDER = f"calogero@{DOMAIN}"
MAILDIR = "/home/calogero/Maildir"
COUNT = {"OK": 0, "FAIL": 0, "INFO": 0}


def out(tag, text):
    COUNT[tag] = COUNT.get(tag, 0) + 1
    print(f"{tag:<5} {text}", flush=True)


def sh(cmd, timeout=30):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except subprocess.TimeoutExpired:
        return ""


def dig(name, rtype="A"):
    return [l for l in sh(f"dig +short +time=2 +tries=1 @{GW} {name} {rtype}").splitlines() if l and not l.startswith(";")]


def greeting(ip):
    try:
        s = socket.create_connection((ip, 25), timeout=5)
        s.settimeout(5)
        g = s.recv(300).decode(errors="replace").strip().splitlines()[0]
        s.sendall(b"QUIT\r\n")
        s.close()
        return g
    except (OSError, IndexError) as e:
        return f"no answer ({e.__class__.__name__})"


print(f"== Mail exchange with the other providers ({time.strftime('%Y-%m-%d %H:%M')}), run on welcome", flush=True)

print("\n== 1. Our side, as the other providers see it (resolver of the gateway 10.4.255.254)")
mx = dig(DOMAIN, "MX")
(out("OK", f"MX of {DOMAIN}: {' '.join(mx)}") if any("mail.group4.umons" in m for m in mx)
 else out("FAIL", f"MX of {DOMAIN}: {' '.join(mx) or 'none'} (expected 10 mail.group4.umons.)"))
a = dig(f"mail.{DOMAIN}")
out("OK", f"mail.{DOMAIN} -> {' '.join(a)}") if a == [ME] else out("FAIL", f"mail.{DOMAIN} -> {' '.join(a) or 'nothing'} (expected {ME})")
ptr = [l for l in sh(f"dig +short +time=2 +tries=1 @{GW} -x {ME}").splitlines() if l and not l.startswith(";")]
out("INFO", f"reverse name of {ME} through the gateway: {' '.join(ptr) or 'none'} (some servers check it)")
act = sh("systemctl is-active postfix")
out("OK", "Postfix active") if act == "active" else out("FAIL", f"Postfix {act}")
g = greeting(ME)
out("OK", f"our port 25: {g}") if g.startswith("220") else out("FAIL", f"our port 25: {g}")
out("INFO", f"myhostname {sh('postconf -h myhostname')}, TLS to other servers: smtp_tls_security_level={sh('postconf -h smtp_tls_security_level') or 'none'}")
q = sh("postqueue -p | tail -1")
out("INFO", f"mail queue: {q or '?'}")

print("\n== 2. The other groups with a mail server (MX of groupX.umons, port 25 greeting only)")
providers = []
for x in range(1, 21):
    if x == 4:
        continue
    dom = f"group{x}.umons"
    mxs = dig(dom, "MX")
    if not mxs:
        continue
    host = sorted(mxs, key=lambda m: int(m.split()[0]) if m.split()[0].isdigit() else 99)[0].split()[-1].rstrip(".")
    ips = dig(host)
    gr = greeting(ips[0]) if ips else "MX name does not resolve"
    up = gr.startswith("220")
    providers.append((dom, host, ips[0] if ips else "-", up))
    out("INFO", f"{dom}: MX {host} ({ips[0] if ips else '-'}), port 25: {gr[:80]}")
if not providers:
    out("INFO", "no other group publishes an MX record yet")

print("\n== 3. Test mails (one per chosen group, sent by our Postfix)")
ready = [p for p in providers if p[3]]
for i, p in enumerate(ready, 1):
    print(f"   {i}. {p[0]}", flush=True)
sent = []
if ready:
    try:
        choice = input("   Send ONE test mail to which groups? Numbers separated by spaces, Enter = none: ").split()
    except EOFError:
        choice = []
    for c in choice:
        if not c.isdigit() or not 1 <= int(c) <= len(ready):
            continue
        dom = ready[int(c) - 1][0]
        try:
            to = input(f"   Address at {dom} (Enter = postmaster@{dom}): ").strip() or f"postmaster@{dom}"
        except EOFError:
            to = f"postmaster@{dom}"
        mid = f"<g4-exchange-{time.strftime('%Y%m%d%H%M%S')}-{dom}@{DOMAIN}>"
        body = (f"From: Group 4 <{SENDER}>\nTo: {to}\nSubject: Group 4 mail exchange test {time.strftime('%Y-%m-%d %H:%M')}\n"
                f"Message-ID: {mid}\n\nHello from Group 4 (group4.umons).\nThis is a test of the mail exchange between providers, "
                f"required by the project statement.\nPlease reply to {SENDER}, so we can check both directions. Thank you.\n")
        r = subprocess.run(["/usr/sbin/sendmail", "-f", SENDER, to], input=body, text=True, capture_output=True)
        if r.returncode == 0:
            sent.append((to, mid))
            out("INFO", f"handed to Postfix: {to}")
        else:
            out("FAIL", f"sendmail refused {to}: {r.stderr.strip()[:100]}")
else:
    out("INFO", "no other provider answers on port 25: nothing to send")

print("\n== 4. Delivery results (Postfix log)")
if sent:
    print("   waiting up to 60 s for the deliveries...", flush=True)
for to, mid in sent:
    status = ""
    for _ in range(12):
        log = sh("journalctl -o short-iso --no-pager --since -15min -t postfix/cleanup -t postfix/smtp -t postfix/bounce -t postfix/qmgr")
        m = re.search(rf"(\w+): message-id={re.escape(mid)}", log)
        if m:
            st = re.findall(rf"{m.group(1)}: to=<{re.escape(to)}>.*?status=(\w+) (.*)", log)
            if st:
                status = st[-1]
                if status[0] in ("sent", "bounced"):
                    break
        time.sleep(5)
    if not status:
        out("FAIL", f"{to}: no delivery line in the log yet (look later: sudo journalctl -t postfix/smtp -n 20)")
    elif status[0] == "sent":
        out("OK", f"{to}: delivered, {status[1][:110]}")
    else:
        out("FAIL", f"{to}: {status[0]}, {status[1][:110]}")
if not sent:
    out("INFO", "no test mail sent in this run")
last = sh("journalctl -o short-iso --no-pager -t postfix/smtp | grep -v 'group4.umons>' | grep 'status=' | tail -5")
if last:
    out("INFO", "last deliveries to other domains in the log:")
    for l in last.splitlines():
        print(f"        {l[:160]}")

print("\n== 5. Mails received by calogero from other domains (replies), headers only")
received = []
for sub in ("new", "cur"):
    d = os.path.join(MAILDIR, sub)
    for f in os.listdir(d) if os.path.isdir(d) else []:
        try:
            with open(os.path.join(d, f), encoding="utf-8", errors="replace") as fh:
                h = email.parser.Parser().parse(fh, headersonly=True)
        except OSError:
            continue
        frm = h.get("From", "")
        if "@" in frm and not re.search(r"@(\w+\.)?group4\.umons", frm):
            received.append((os.path.getmtime(os.path.join(d, f)), frm, h.get("Subject", ""), sub))
for t, frm, subj, sub in sorted(received, reverse=True)[:10]:
    out("OK", f"{time.strftime('%Y-%m-%d %H:%M', time.localtime(t))} from {frm[:60]}: {subj[:60]} ({sub})")
if not received:
    out("INFO", "no mail from another provider yet (run this check again later)")

print("\n== Summary")
print(f"{COUNT['OK']} OK, {COUNT['FAIL']} FAIL, {COUNT['INFO']} INFO; other providers found: {len(providers)} "
      f"(port 25 answering: {len(ready)}); test mails sent now: {len(sent)}; mails received from other providers: {len(received)}")
print("Requirement met when at least one mail was delivered to another provider (step 4: delivered) "
      "and at least one mail from another provider arrived (step 5).")
