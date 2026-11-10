# checks

Read-only test scripts: they change nothing on the VMs, they only print what they find. They never log in and never send mail (the relay test of `ns1.sh` stops before DATA).

Workflow:

1. A new script (or a new version) is pushed here.
2. On the VM: `cd ~/Desktop/group4-welcome && git pull && git log -1 --oneline` (check the commit id).
3. Run the script of that VM with sudo. The output is pushed to `results/<vm>/` (file with date and time + `latest.txt`).

One-time setup on each VM, so that it can push the results (as user, without sudo): `sh checks/setup-results.sh`. The only credential is an SSH key valid for this repo only (GitHub deploy key, write access); there is no GitHub login on the VM. The script shows the public key with its fingerprint and publishes it (public data) at a short paste.rs address; the key is added to this repo from the laptop after checking the fingerprint; then the script sets the push URL, runs the check of the VM and pushes the result. Pull stays anonymous. This script will be deleted once both VMs are set up.

The results are public while they are here: they will be removed at the end of the session.

| VM | Command | Output saved in |
|---|---|---|
| welcome (10.4.255.11) | `sudo sh checks/welcome.sh` | `/tmp/check-welcome.txt` |
| ns1 (10.4.255.10) | `sudo sh checks/ns1.sh` | `/tmp/check-ns1.txt` |
| welcome (10.4.255.11), mail service | `sudo sh checks/mail.sh` | `/tmp/check-mail.txt` |
| ns1, proof of reception (sends ONE test mail to our own server, after confirmation) | `sudo sh checks/mailtest_ns1.sh` | `/tmp/check-mailtest.txt` |

Each line starts with `OK`, `WARN` (something to fix) or `INFO` (a value to read). The last line counts the warnings. To scroll the full output: `less /tmp/check-<vm>.txt`.
