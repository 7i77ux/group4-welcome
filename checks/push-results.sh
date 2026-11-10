#!/bin/sh
# Called at the end of each check: copies the output into results/<vm>/ of this
# repo (timestamped file + latest.txt), commits and pushes it.
# Usage: sh push-results.sh <vm> <output file>
VMDIR="$1"; OUTFILE="$2"
RES=$(cd "$(dirname "$0")/.." && pwd)
U="${SUDO_USER:-$(id -un)}"
[ "$U" = root ] && U=user
g() { git -c safe.directory='*' -C "$RES" "$@"; }

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
cmd="cd '$RES' && git add 'results/$VMDIR' && git commit -q -m 'results: $VMDIR checks $TS' && git pull -q --rebase && git push -q"
if [ "$(id -u)" = 0 ]; then sudo -H -u "$U" sh -c "$cmd"; else sh -c "$cmd"; fi
if [ $? -eq 0 ]; then
    echo "Pushed: results/$VMDIR/$TS.txt"
else
    echo "WARN: push failed (the file is kept in $RES/results/$VMDIR)"
fi
