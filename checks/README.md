# checks

Read-only test scripts: they change nothing on the VMs, they only print what they find.

Workflow:

1. A new script (or a new version) is pushed here.
2. On the VM: `cd ~/Desktop/group4-welcome && git pull && git log -1 --oneline` (check the commit id).
3. Run the script of that VM with sudo. The output is pushed to `results/<vm>/` (file with date and time + `latest.txt`).

One-time setup on each VM, so that it can push the results (as user, without sudo): `sh checks/setup-results.sh`. It creates an SSH key valid only for this repo, shows it, and waits until it is added on GitHub (Settings → Deploy keys → Add deploy key, tick "Allow write access"). Pull stays anonymous; only push uses the key. Until the setup is done, the checks still run and print their output, without pushing.

The results are public while they are here: they will be removed at the end of the session.

| VM | Command | Output saved in |
|---|---|---|
| welcome (10.4.255.11) | `sudo sh checks/welcome.sh` | `/tmp/check-welcome.txt` |
| ns1 (10.4.255.10) | `sudo sh checks/ns1.sh` | `/tmp/check-ns1.txt` |

Each line starts with `OK`, `WARN` (something to fix) or `INFO` (a value to read). The last line counts the warnings. To scroll the full output: `less /tmp/check-<vm>.txt`.
