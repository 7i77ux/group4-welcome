# checks

Read-only checks: they change nothing on the VMs. Exceptions, always asked first: the mail login test of `full.sh` (you type the passwords), the test mail of `mail_exchange.sh`, the test alert of `suricata.sh`; `save_volatile.sh` only writes into `/root/evidence/`. The output is pushed to `results/<name>/` (file with date and time + `latest.txt`) by `push-results.sh`, with a deploy key valid for this repo only.

| VM | Command | What |
|---|---|---|
| both | `sudo sh checks/full.sh` | Full test of everything documented, on this VM and on the other one as the other groups see it (section 1b: our names from the course resolver) |
| both | `sudo sh checks/inventory.sh` | Inventory of the structure (addresses, routes, names, zones, mail, web); passwords masked |
| both | `sh checks/public_dns.sh` | Our names as the other groups get them, time left and expiry time of an old answer |
| welcome | `sudo sh checks/suricata.sh` | Suricata step by step (DOCUMENTATION.md 10.17); optional test alert |
| welcome | `sudo sh checks/mail_diag.sh` | Mail diagnosis: who changed what today (sudo commands, packages, files, accounts, histories), Dovecot, Postfix, MariaDB, mailboxes, live tests on 25 and 993, findings; passwords masked, not pushed if something looks like a password |
| welcome | `sudo sh checks/mail_exchange.sh` | Mail exchange with the other providers; one test mail per group you choose |
| both | `sudo sh checks/ice_watch.sh` | What ice and mother do now compared with 2026-11-12 (SAME / CHANGED); secrets redacted |
| both | `sudo sh checks/evidence_ice.sh` | Code of ice with secrets redacted, orders of its servers (saved, never executed) |
| both | `sudo sh checks/save_volatile.sh` | Before a reboot: copies what a reboot destroys into `/root/evidence/` (root only) |

Statuses of `full.sh`: `OK` as documented, `FAIL` differs from the documentation, `NEW` not in the documentation, `OPEN` known open point (id), `INFO` data.

If a push fails because of a conflict, `push-results.sh` aborts the rebase and drops its own commit; the output stays in `/tmp/unpushed-<name>-<time>.txt`. A clone still stuck: `cd ~/Desktop/group4-welcome && git rebase --abort; git fetch origin && git reset --hard origin/main`.
