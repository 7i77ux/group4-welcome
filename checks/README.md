# checks

Read-only test scripts: they change nothing on the VMs, they only print what they find.

Workflow:

1. A new script (or a new version) is pushed here.
2. On the VM: `cd ~/Desktop/group4-welcome && git pull && git log -1 --oneline` (check the commit id).
3. Run the script of that VM with sudo. The output is pushed to `results/<vm>/` (file with date and time + `latest.txt`).

One-time setup on each VM, so that it can push the results (as user, without sudo): `sh checks/setup-results.sh`. It creates an SSH key valid only for this repo, adds it as a deploy key through a temporary login of the GitHub CLI (you only type an 8-character code at https://github.com/login/device, from any browser), removes the login right after (also on error), uninstalls `gh`, then runs the check of the VM and pushes the result. Pull stays anonymous; only push uses the key. This script will be deleted once both VMs are set up.

The results are public while they are here: they will be removed at the end of the session.

| VM | Command | Output saved in |
|---|---|---|
| welcome (10.4.255.11) | `sudo sh checks/welcome.sh` | `/tmp/check-welcome.txt` |
| ns1 (10.4.255.10) | `sudo sh checks/ns1.sh` | `/tmp/check-ns1.txt` |

Each line starts with `OK`, `WARN` (something to fix) or `INFO` (a value to read). The last line counts the warnings. To scroll the full output: `less /tmp/check-<vm>.txt`.
