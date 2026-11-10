#!/bin/sh
# Proof of reception (D27): from ns1 (another host, like another mail provider) deliver
# ONE test mail to calogero@group4.umons through welcome:25. It sends exactly one mail,
# to our own server, after confirmation. Needs fix 4 (mynetworks) and fix 6 (account) on welcome.
# Run:  cd ~/Desktop/group4-welcome && git pull && sudo sh checks/mailtest_ns1.sh
# Then on welcome: sudo sh checks/mail.sh (section 5 counts the new mails of calogero).
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
ip -4 -o addr show | grep -q ' 10\.4\.255\.10/' || { echo "ERROR: run this test on ns1 (10.4.255.10)." >&2; exit 1; }
OUT=/tmp/check-mailtest.txt
TO="${1:-calogero@group4.umons}"
printf 'Send ONE test mail from ns1 to %s through welcome (10.4.255.11:25)? [y/N] ' "$TO"; read -r a
[ "$a" = y ] || [ "$a" = Y ] || { echo "Nothing sent."; exit 0; }
python3 -I - "$TO" <<'PY' 2>&1 | tee "$OUT"
import smtplib, sys, datetime
from email.message import EmailMessage
to = sys.argv[1]
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
m = EmailMessage()
m["From"] = "delivery-test@ns1.group4.umons"; m["To"] = to
m["Subject"] = f"group4 delivery test from ns1 {now}"
m.set_content(f"Proof of reception (D27): sent from ns1 to welcome:25 at {now}.")
print(f"== Delivery test {now}: ns1 -> welcome:25 -> {to}")
try:
    s = smtplib.SMTP("10.4.255.11", 25, timeout=10)
    s.set_debuglevel(0)
    print("greeting / EHLO:", s.ehlo("ns1.group4.umons")[0])
    refused = s.send_message(m)
    print("OK    accepted by welcome" if not refused else f"WARN  refused: {refused}")
    s.quit()
except smtplib.SMTPRecipientsRefused as e:
    print("WARN  recipient refused:", e.recipients)
except Exception as e:
    print(f"WARN  delivery failed: {e.__class__.__name__}: {e}")
PY
sh "$(dirname "$0")/push-results.sh" mailtest "$OUT"
