#!/bin/sh
# Removes from this VM the public repo group4-welcome and the connection to GitHub, one step at a time:
#   1. the clone folder (~/Desktop/group4-welcome) and any other clone of 7i77ux's repos on this VM;
#   2. the connection: push key ~/.ssh/group4_welcome_push (deploy key), the 'Host github-welcome' block
#      of ~/.ssh/config, the GitHub host keys in ~/.ssh/known_hosts, stored git credentials;
#   3. the files the scripts of the repo left outside the clone (outputs in /tmp, /home/user/group4.csr,
#      copies of deploy.sh / index.md / make-csr.sh in ~/Downloads).
# Kept on purpose: /root/evidence and /root/next-observed-* (evidence of ice), /root/fixes-backup-* (copies
# of the configuration before each fix), the published page /var/www/welcome, every service configuration,
# the git package. The deploy keys 'welcome' and 'ns1' must ALSO be removed on GitHub (repo Settings >
# Deploy keys): only that cuts the access of a key already copied (ice runs as root on both VMs).
# The repo stays public: a VM can still read it with git clone over HTTPS, but no longer write to it.
# Run on each VM:  sudo sh ~/Desktop/group4-welcome/fixes/cleanup_repo.sh
# Manual steps: DOCUMENTATION.md 10.29.
set -u
[ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo sh $0"; exit 1; }
if { [ "$(hostname)" = welcome ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.11/'; }; then VM=welcome
elif { [ "$(hostname)" = ns1 ] || ip -4 -o addr show | grep -qE ' 10\.4\.(255|2)\.10/'; }; then VM=ns1
else echo "ERROR: run it on welcome or ns1." >&2; exit 1
fi
# the script deletes its own folder: it runs from a temporary copy, removed at the end
case "$0" in
    /tmp/cleanup_repo.*) trap 'rm -f "$0"' EXIT ;;
    *) t=$(mktemp /tmp/cleanup_repo.XXXXXX) && cp "$0" "$t" && cd / && exec sh "$t" "$@" ;;
esac
U=${SUDO_USER:-user}; [ "$U" = root ] && U=user
H=$(getent passwd "$U" | cut -d: -f6); [ -n "$H" ] || H=/home/$U
BK=/root/fixes-backup-$(date +%Y%m%d-%H%M)
ask() { printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }

# what to remove
CLONES=$(find /home /root /opt /srv -maxdepth 5 -type d -name .git 2>/dev/null | while read -r d; do
    d=${d%/.git}
    case "$(git -c safe.directory='*' -C "$d" config --get remote.origin.url 2>/dev/null)" in *7i77ux/*) echo "$d" ;; esac
done)
KEYS=$(grep -lsF 'group4-welcome push' /home/*/.ssh/*.pub /root/.ssh/*.pub 2>/dev/null | while read -r p; do echo "${p%.pub} $p"; done)
CONFS=$(grep -lsE '^Host[[:space:]]+github-welcome([[:space:]]|$)' /home/*/.ssh/config /root/.ssh/config 2>/dev/null)
KNOWN=$(for f in /home/*/.ssh/known_hosts /root/.ssh/known_hosts; do
    [ -f "$f" ] || continue
    for h in '[ssh.github.com]:443' ssh.github.com github.com; do ssh-keygen -F "$h" -f "$f" >/dev/null 2>&1 && echo "$f $h"; done
done)
CREDS=$(ls /home/*/.git-credentials /root/.git-credentials 2>/dev/null)
OUTS=$(ls -d /tmp/check-full-* /tmp/check-mail-exchange.txt /tmp/check-suricata.txt /tmp/evidence-ice-* /tmp/full-doveadm.* \
    /tmp/ice-watch-* /tmp/inventory-* /tmp/mail-diag.txt /tmp/public-dns-* /tmp/save-volatile-* /tmp/unpushed-* \
    "$H/group4.csr" "$H/Downloads/deploy.sh" "$H/Downloads/index.md" "$H/Downloads/make-csr.sh" 2>/dev/null)

echo "== State of $VM (user $U)"
echo "   clones of 7i77ux's repos: $(echo $CLONES)"
for d in $CLONES; do
    echo "   - $d: $(du -sh "$d" 2>/dev/null | cut -f1), origin $(git -c safe.directory='*' -C "$d" config --get remote.origin.url),"
    echo "     push $(git -c safe.directory='*' -C "$d" config --get remote.origin.pushurl || echo none);" \
         "changed by hand: $(git -c safe.directory='*' -C "$d" status --porcelain 2>/dev/null | grep -vc '^?? results/')," \
         "stashes: $(git -c safe.directory='*' -C "$d" stash list 2>/dev/null | wc -l)," \
         "commits not pushed: $(git -c safe.directory='*' -C "$d" log --oneline '@{u}..' 2>/dev/null | wc -l)"
done
echo "   push keys: $(echo "$KEYS" | awk '{print $1}' | tr '\n' ' ')"
echo "   'Host github-welcome' in: $(echo $CONFS)"
echo "   GitHub host keys in: $(echo "$KNOWN" | tr '\n' ';')"
echo "   stored git credentials: ${CREDS:-none}"
echo "   files of the scripts outside the clone: $(echo "$OUTS" | wc -w)"
echo "   Why: the push key gives write access to the public repo, and ice runs as root on this VM: whoever"
echo "        controls it could change the scripts that we run with sudo. Without the clone and the key,"
echo "        nothing on this VM comes from the repo or can write to it."
ask "Did you take a PVE snapshot of $VM?" || { echo "Take it first: PVE > $VM > Snapshots > Take Snapshot."; exit 1; }

echo
echo "== Step 1/3: delete the clone folder(s)"
if [ -z "$CLONES" ]; then
    echo "   already done (no clone)"
else
    for d in $CLONES; do
        case "$d" in /home/*/*|/root/*|/opt/*|/srv/*) ;; *) echo "   SKIPPED $d (unexpected place)"; continue ;; esac
        [ -d "$d/.git" ] || { echo "   SKIPPED $d (not a git clone)"; continue; }
        n=$(git -c safe.directory='*' -C "$d" status --porcelain 2>/dev/null | grep -vc '^?? results/')
        s=$(git -c safe.directory='*' -C "$d" stash list 2>/dev/null | wc -l)
        [ "$n" -gt 0 ] || [ "$s" -gt 0 ] && echo "   WARN $d: $n file(s) changed by hand and $s stash(es) are lost with the folder:" \
            && git -c safe.directory='*' -C "$d" status --short 2>/dev/null | grep -v '^?? results/' | head -10 | sed 's/^/      /'
        if ask "   Delete $d?"; then
            rm -rf -- "$d"
            [ -e "$d" ] && echo "   ERROR: $d still there" || echo "   done: $d deleted"
        fi
    done
fi

echo
echo "== Step 2/3: connection to GitHub (push key, SSH alias, GitHub host keys, git credentials)"
if [ -z "$KEYS$CONFS$KNOWN$CREDS" ]; then
    echo "   already done"
elif ask "   Remove them? (copies of ~/.ssh/config and known_hosts in $BK; the private key is NOT copied)"; then
    mkdir -p "$BK"
    echo "$KEYS" | while read -r k p; do [ -n "$k" ] && rm -f -- "$k" "$p" && echo "   key removed: $k"; done
    for c in $CONFS; do
        cp -a "$c" "$BK/$(echo "$c" | tr / _)"
        awk '/^Host[[:space:]]/ {skip = ($2 == "github-welcome")} !skip' "$c" > "$c.new" && cat "$c.new" > "$c" && rm -f "$c.new"
        echo "   'Host github-welcome' removed from $c"
    done
    echo "$KNOWN" | while read -r f h; do
        [ -n "$f" ] || continue
        [ -e "$BK/$(echo "$f" | tr / _)" ] || cp -a "$f" "$BK/$(echo "$f" | tr / _)"
        o=$(stat -c %U "$f")
        sudo -u "$o" ssh-keygen -q -R "$h" -f "$f" >/dev/null 2>&1 && rm -f "$f.old" && echo "   GitHub host key $h removed from $f"
    done
    for c in $CREDS; do rm -f -- "$c" && echo "   stored git credentials removed: $c"; done
fi
# check
left=""
ls /home/*/.ssh/group4_welcome_push* /root/.ssh/group4_welcome_push* >/dev/null 2>&1 && left="$left push-key"
grep -qsE '^Host[[:space:]]+github-welcome' /home/*/.ssh/config /root/.ssh/config && left="$left ssh-alias"
for f in /home/*/.ssh/known_hosts /root/.ssh/known_hosts; do
    [ -f "$f" ] && ssh-keygen -F '[ssh.github.com]:443' -f "$f" >/dev/null 2>&1 && left="$left known_hosts"
done
[ -z "$left" ] && echo "   check: no push key, no SSH alias, no GitHub host key on this VM" || echo "   WARN still there:$left"

echo
echo "== Step 3/3: files of the scripts left outside the clone"
if [ -z "$OUTS" ]; then
    echo "   already done"
else
    echo "$OUTS" | sed 's/^/   /'
    echo "   (outputs of the checks: the pushed ones are in results/ of the repo; /tmp/unpushed-* were never pushed)"
    if ask "   Delete these $(echo "$OUTS" | wc -w) files?"; then
        echo "$OUTS" | while read -r f; do [ -n "$f" ] && rm -rf -- "$f"; done
        echo "   done"
    fi
fi

echo
echo "== Kept on purpose (not files of the repo):"
for p in /root/evidence /root/fixes-backup-* /root/next-observed-* /var/www/welcome; do
    [ -e "$p" ] && echo "   $p"
done
echo
echo "== Still to do on GitHub, from the laptop: remove the deploy key '$VM' of 7i77ux/group4-welcome"
echo "   (Settings > Deploy keys > Delete, or: gh repo deploy-key list -R 7i77ux/group4-welcome, then"
echo "   gh repo deploy-key delete <id> -R 7i77ux/group4-welcome). Only this cuts a key that was copied."
[ -n "$(ls -A "$BK" 2>/dev/null)" ] && echo "== Copies of the SSH files in $BK"
