#!/bin/sh
# One-time setup on a VM, as user (WITHOUT sudo): lets the checks push their
# results to this repo (folder results/), with an SSH key valid only for this
# repo (GitHub "deploy key"). Pull stays anonymous over HTTPS; only push uses the key.
#   cd ~/Desktop/group4-welcome && sh checks/setup-results.sh
set -e
[ "$(id -u)" != 0 ] || { echo "Run it as user, without sudo: sh $0"; exit 1; }
VM=$(hostname)
REPO=$(cd "$(dirname "$0")/.." && pwd)
KEY="$HOME/.ssh/group4_welcome_push"
GITHUB_ED25519="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"   # published by GitHub

# 1. key used only for pushing to group4-welcome
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "group4-welcome push $VM" -f "$KEY"

# 2. SSH alias through port 443 (port 22 may be blocked)
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

# 3. GitHub host key, accepted only if it matches the published fingerprint
if ! ssh-keygen -F '[ssh.github.com]:443' >/dev/null 2>&1; then
    tmp=$(mktemp)
    ssh-keyscan -p 443 -t ed25519 ssh.github.com 2>/dev/null > "$tmp"
    fp=$(ssh-keygen -lf "$tmp" | awk '{print $2}')
    if [ "$fp" != "$GITHUB_ED25519" ]; then
        echo "ERROR: unexpected GitHub host key ($fp). Stop." >&2; rm -f "$tmp"; exit 1
    fi
    cat "$tmp" >> "$HOME/.ssh/known_hosts"; rm -f "$tmp"
fi

# 4. the key must be added on GitHub
if ! ssh -T github-welcome 2>&1 | grep -q 'successfully authenticated'; then
    echo
    echo "Add this key on GitHub (from this VM's Firefox, private window):"
    echo "  https://github.com/7i77ux/group4-welcome/settings/keys/new"
    echo "  Title: $VM   Key: the line below   Tick 'Allow write access'"
    echo
    cat "$KEY.pub"
    echo
    printf 'Press Enter when the key is added... '; read -r _
    ssh -T github-welcome 2>&1 | grep -q 'successfully authenticated' \
        || { echo "ERROR: GitHub does not accept the key yet. Run this script again." >&2; exit 1; }
fi

# 5. this clone: pull over HTTPS as before, push with the key
git -C "$REPO" remote set-url --push origin github-welcome:7i77ux/group4-welcome.git
git -C "$REPO" config user.name "group4-$VM"
git -C "$REPO" config user.email "$VM@group4.umons"
echo "OK: the checks of $VM will push their results to results/$VM/ in $REPO"
