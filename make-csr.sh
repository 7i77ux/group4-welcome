#!/bin/sh
# Generate the private key and the certificate signing request (CSR) of Group 4,
# to be signed by the course CA. Run on the Welcome + mail VM (10.4.255.11):
#   sudo sh make-csr.sh
# Send ONLY the .csr to the teacher. The .key never leaves the VM.
set -e

# run only on welcome (10.4.255.11): on 2026-11-10 deploy.sh was run on ns1 by mistake
ip -4 -o addr show | grep -q ' 10\.4\.255\.11/' || { echo "ERROR: run this script on welcome (10.4.255.11), not on $(hostname)." >&2; exit 1; }
DIR="${DIR:-/etc/ssl/group4}"
KEY="$DIR/group4.key"
CSR="$DIR/group4.csr"
SUBJ="/C=BE/ST=Hainaut/O=Group4/OU=CyberDefense/CN=welcome.group4.umons"
SAN="subjectAltName=DNS:welcome.group4.umons,DNS:mail.group4.umons"
OWNER="${SUDO_USER:-user}"
OUT="${OUT:-/home/$OWNER/group4.csr}"

mkdir -p "$DIR"

# never overwrite an existing key: a certificate may already have been signed for it
if [ -e "$KEY" ]; then
    echo "ERROR: a key already exists: $KEY (not overwritten)." >&2
    echo "To start over: sudo rm $KEY $CSR, then run this script again." >&2
    exit 1
fi

# 1. key (RSA 3072, readable only by root) + CSR with both names in subjectAltName
umask 077
openssl req -new -newkey rsa:3072 -nodes -keyout "$KEY" -out "$CSR" -subj "$SUBJ" -addext "$SAN"
chmod 600 "$KEY"
chmod 644 "$CSR"

# 2. checks
openssl req -in "$CSR" -noout -verify
openssl req -in "$CSR" -noout -subject
openssl req -in "$CSR" -noout -text | grep -A1 'Subject Alternative Name'

# 3. copy of the CSR to send to the teacher
cp "$CSR" "$OUT"
chmod 644 "$OUT"
chown "$OWNER" "$OUT" 2>/dev/null || true
echo "OK. Send this file to the teacher: $OUT"
echo "Do NOT send $KEY: it stays on this VM."
