# checks

Read-only test scripts: they change nothing on the VMs, they only print what they find. They never log in (except the optional mail login test of `full.sh`) and never send mail (the relay test of `ns1.sh` stops before DATA; `mailtest_ns1.sh` sends one test mail after confirmation). `save_volatile.sh` only writes into `/root/evidence/`.

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
| welcome or ns1: evidence of the ice scripts (their text with secrets redacted, metadata; read-only, ice never run) | `sudo sh checks/evidence_ice.sh` | `/tmp/evidence-ice-<vm>.txt`, pushed to `results/evidence-<vm>/` |
| welcome or ns1: full regression test of everything documented (this VM + the other VM seen from here). On welcome it first offers the mail login test (`doveadm auth test`: calogero must succeed, user must be refused); the passwords are typed by hand and never stored | `sudo sh checks/full.sh` | `/tmp/check-full-<vm>.txt`, pushed to `results/full-<vm>/` |
| welcome, Suricata after the installation by hand (DOCUMENTATION.md 10.17): packages, settings, rules, `suricata -T`, service, capture, alerts; each FAIL names the step to redo; optional test alert (asked first) | `sudo sh checks/suricata.sh` | `/tmp/check-suricata.txt`, pushed to `results/suricata/` |
| welcome: mail exchange with the other providers (statement, case 1): our MX/A/PTR as the others see them, the other groups with a mail server (MX + port 25 greeting), ONE test mail per group you choose (reply asked to calogero), delivery result, replies received | `sudo sh checks/mail_exchange.sh` | `/tmp/check-mail-exchange.txt`, pushed to `results/mail-exchange/` |
| welcome or ns1: what ice and mother do now compared with 2026-11-12 (programs and hashes, cron and timers, processes, SSH logins of mother, sudo commands, accounts and keys, orders of the servers saved and not executed, connections); every line SAME or CHANGED; secrets redacted | `sudo sh checks/ice_watch.sh` | `/tmp/ice-watch-<vm>.txt`, pushed to `results/ice-watch-<vm>/` |
| welcome or ns1: inventory of the new structure after 2026-11-17 (addresses, routes, our names as the other groups see them, zones on ns1, Postfix/Dovecot/MariaDB virtual mailboxes and web on welcome); passwords masked, no hash printed | `sudo sh checks/inventory.sh` | `/tmp/inventory-<vm>.txt`, pushed to `results/inventory-<vm>/` |
| welcome or ns1: how often ice attacks (read-only): intervals between the SSH logins of mother per source, rounds of the local copies, installations, who is on the DHCP addresses .41-.50 now | `sudo sh checks/ice_timing.sh` | `/tmp/ice-timing-<vm>.txt`, pushed to `results/ice-timing-<vm>/` |
| welcome or ns1, before a reboot: saves what a reboot destroys (files of ice in /tmp, processes, sockets, journal of this boot) into `/root/evidence/<vm>-<time>/` (root only); only the list of files with sizes and hashes is pushed. Writes only there; mother and ice are not touched (D28) | `sudo sh checks/save_volatile.sh` | `/tmp/save-volatile-<vm>.txt`, pushed to `results/volatile-<vm>/` |

Each line starts with `OK`, `WARN` (something to fix) or `INFO` (a value to read). The last line counts the warnings. To scroll the full output: `less /tmp/check-<vm>.txt`.

`full.sh` (with `full.py`) uses other statuses: `OK` as documented, `FAIL` differs from the documentation (something broke, or the documentation is wrong), `NEW` not in the documentation (to look at), `OPEN` known open point with its id (expected for now), `INFO` data. The summary at the end lists every FAIL and NEW line and the OPEN ids. It observes the account `mother` without changing it (D28). Since 2026-11-12 it also checks the clock (one NTP time request to the gateway and to the configured servers, offset against the HTTPS Date of deb.debian.org; W28) and, on ns1, whether the names of the other groups (`.umons`) resolve through ns1 with and without DNSSEC validation.

If a push fails because of a conflict, `push-results.sh` now aborts the rebase and drops its own commit, so the clone stays usable; the output is kept in `/tmp/unpushed-<vm>-<time>.txt`. A clone that is still stuck from before: `cd ~/Desktop/group4-welcome && git rebase --abort; git fetch origin && git reset --hard origin/main`.
