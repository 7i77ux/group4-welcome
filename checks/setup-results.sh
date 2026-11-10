#!/bin/sh
# One-time setup on a VM, as user (WITHOUT sudo):
#   cd ~/Desktop/group4-welcome && git pull && sh checks/setup-results.sh
# The only credential is an SSH key valid for THIS repo only (GitHub deploy key).
# No GitHub login on the VM: the public key (not a secret) is shown and published
# at a short paste.rs address; it is added to the repo from the laptop, after
# checking that its fingerprint matches the one shown here.
# Then: push URL of this clone, first check of this VM, result pushed.
# To be deleted from the repo once both VMs are set up.
set -e
[ "$(id -u)" != 0 ] || { echo "Run it as user, without sudo: sh $0"; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
KEY="$HOME/.ssh/group4_welcome_push"
GITHUB_ED25519="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"   # published by GitHub

if ip -4 -o addr show | grep -q ' 10\.4\.255\.11/'; then VM=welcome
elif ip -4 -o addr show | grep -q ' 10\.4\.255\.10/'; then VM=ns1
else echo "ERROR: this is neither welcome (10.4.255.11) nor ns1 (10.4.255.10)." >&2; exit 1
fi
echo "== VM: $VM"

# 1. key used only for pushing to group4-welcome, SSH alias through port 443
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "group4-welcome push $VM" -f "$KEY"
if ! grep -q '^Host github-welcome$' "$HOME/.ssh/config" 2>/dev/null; then
    cat >> "$HOME/.ssh/config" <<EOF

Host github-welcome
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile $KEY
    IdentitiesOnly yes
EOF
fi
chmod 600 "$HOME/.ssh/config"
if ! ssh-keygen -F '[ssh.github.com]:443' >/dev/null 2>&1; then
    tmp=$(mktemp)
    ssh-keyscan -p 443 -t ed25519 ssh.github.com 2>/dev/null > "$tmp"
    fp=$(ssh-keygen -lf "$tmp" | awk '{print $2}')
    [ "$fp" = "$GITHUB_ED25519" ] || { echo "ERROR: unexpected GitHub host key ($fp). Stop." >&2; rm -f "$tmp"; exit 1; }
    cat "$tmp" >> "$HOME/.ssh/known_hosts"; rm -f "$tmp"
fi

# 2. the key must be added as a deploy key of group4-welcome (from the laptop)
if ! ssh -T github-welcome 2>&1 | grep -q 'successfully authenticated'; then
    fp=$(ssh-keygen -lf "$KEY.pub" | awk '{print $2}')
    url=$(curl -s --max-time 15 --data-binary @"$KEY.pub" https://paste.rs/ 2>/dev/null | tr -d '\r\n' || true)
    case "$url" in https://paste.rs/*) ;; *) url="";; esac
    echo
    echo "== Public key of $VM (public data, not a secret)"
    cat "$KEY.pub"
    echo "   Fingerprint: $fp"
    if [ -n "$url" ]; then
        echo "   Published at: $url"
        echo "   -> give this address, and the fingerprint, to whoever adds it from the laptop"
    else
        echo "   (publishing failed: send a screenshot of the key line above)"
    fi
    echo
    echo "   It must be added as a deploy key of 7i77ux/group4-welcome only, with write access."
    printf 'Press Enter when the key is added... '; read -r _
    ssh -T github-welcome 2>&1 | grep -q 'successfully authenticated' \
        || { echo "ERROR: GitHub does not accept the key yet. Run this script again." >&2; exit 1; }
fi
echo "== Push key accepted by GitHub (valid for group4-welcome only)"

# 3. this clone: pull over HTTPS as before, push with the key
git -C "$REPO" remote set-url --push origin github-welcome:7i77ux/group4-welcome.git
git -C "$REPO" config user.name "group4-$VM"
git -C "$REPO" config user.email "$VM@group4.umons"

# 4. first check of this VM, which pushes its result
echo "== Running checks/$VM.sh (sudo)"
sudo sh "$REPO/checks/$VM.sh"
