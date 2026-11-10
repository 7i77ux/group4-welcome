#!/bin/sh
# One-time setup on a VM, as user (WITHOUT sudo), almost all automatic:
#   cd ~/Desktop/group4-welcome && git pull && sh checks/setup-results.sh
# 1. SSH key valid only for this repo (GitHub deploy key) + SSH alias on port 443
# 2. adds the key to the repo through a TEMPORARY login of the GitHub CLI:
#    you only type an 8-character code at https://github.com/login/device
#    (from any browser, e.g. your laptop). The login is removed right after,
#    also on error, and gh is uninstalled.
# 3. push URL of this clone, then runs the check of this VM and pushes the result.
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

# never leave a GitHub login on the VM, whatever happens
cleanup() {
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        u=$(gh api user --jq .login 2>/dev/null || true)
        gh auth logout --hostname github.com ${u:+--user "$u"} >/dev/null 2>&1 || rm -f "$HOME/.config/gh/hosts.yml"
        echo "== GitHub login removed from this VM"
    fi
}
trap cleanup EXIT INT TERM

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

# 2. add the key to the repo (only if GitHub does not accept it yet)
if ! ssh -T github-welcome 2>&1 | grep -q 'successfully authenticated'; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "== Installing the GitHub CLI (temporary, sudo password may be asked)"
        sudo apt-get install -y -q gh >/dev/null
    fi
    echo
    echo "== Temporary GitHub login"
    echo "   1. If asked 'Authenticate Git with your GitHub credentials?' answer: n"
    echo "   2. Copy the one-time code, press Enter"
    echo "   3. On any browser (e.g. your laptop) open https://github.com/login/device,"
    echo "      type the code and click Authorize"
    echo
    gh auth login --hostname github.com --git-protocol https --web
    gh repo deploy-key add "$KEY.pub" --repo 7i77ux/group4-welcome --allow-write --title "$VM"
    cleanup
    sleep 3
    ssh -T github-welcome 2>&1 | grep -q 'successfully authenticated' \
        || { echo "ERROR: GitHub does not accept the key. Run this script again." >&2; exit 1; }
fi
echo "== Push key accepted by GitHub"
if dpkg -l gh 2>/dev/null | grep -q '^ii'; then
    sudo apt-get purge -y -q gh >/dev/null && echo "== gh uninstalled"
fi

# 3. this clone: pull over HTTPS as before, push with the key
git -C "$REPO" remote set-url --push origin github-welcome:7i77ux/group4-welcome.git
git -C "$REPO" config user.name "group4-$VM"
git -C "$REPO" config user.email "$VM@group4.umons"

# 4. first check of this VM, which pushes its result
echo "== Running checks/$VM.sh (sudo)"
sudo sh "$REPO/checks/$VM.sh"
