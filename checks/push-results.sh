#!/bin/sh
# Called at the end of each check: copies the output into results/<vm>/ of this
# repo (timestamped file + latest.txt), commits and pushes it.
# Usage: sh push-results.sh <vm> <output file>
VMDIR="$1"; OUTFILE="$2"
RES=$(cd "$(dirname "$0")/.." && pwd)
U="${SUDO_USER:-$(id -un)}"
[ "$U" = root ] && U=user
g() { git -c safe.directory='*' -C "$RES" "$@"; }

# A clone left in the middle of a rebase (a failed push) blocks every later pull: undo it first.
if [ -d "$RES/.git/rebase-merge" ] || [ -d "$RES/.git/rebase-apply" ]; then
    echo "The clone was stuck in an unfinished rebase: aborting it (git rebase --abort)."
    if [ "$(id -u)" = 0 ]; then sudo -H -u "$U" git -C "$RES" rebase --abort; else g rebase --abort; fi
fi

if [ -z "$(g config --get remote.origin.pushurl)" ]; then
    echo "Results not pushed: run once 'sh checks/setup-results.sh' (as user, without sudo)."
    exit 0
fi

TS=$(date '+%Y-%m-%d_%H%M')
mkdir -p "$RES/results/$VMDIR"
cp "$OUTFILE" "$RES/results/$VMDIR/$TS.txt"
cp "$OUTFILE" "$RES/results/$VMDIR/latest.txt"
[ "$(id -u)" = 0 ] && chown -R "$U" "$RES/results"

# git runs as the user, who owns the deploy key
# If the pull with rebase fails (conflict), abort it and drop this commit: the clone stays
# usable for the next 'git pull', and the output is kept in /tmp (see below).
cmd="cd '$RES' && git add 'results/$VMDIR' && git commit -q -m 'results: $VMDIR checks $TS' && { git pull -q --rebase || { git rebase --abort; git reset -q --hard HEAD~1; false; }; } && git push -q"
if [ "$(id -u)" = 0 ]; then sudo -H -u "$U" sh -c "$cmd"; else sh -c "$cmd"; fi
if [ $? -eq 0 ]; then
    echo "Pushed: results/$VMDIR/$TS.txt"
else
    cp "$OUTFILE" "/tmp/unpushed-$VMDIR-$TS.txt"
    echo "WARN: push failed. Output kept in /tmp/unpushed-$VMDIR-$TS.txt"
    echo "      If 'git pull' fails too, realign this clone: cd $RES && git rebase --abort; git fetch origin && git reset --hard origin/main"
fi
