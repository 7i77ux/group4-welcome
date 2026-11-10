# fixes

Scripts that CHANGE a VM, one fix at a time. For each fix they show the current state and the reason, ask for confirmation (`y`), back up the files they change in `/root/fixes-backup-<date>`, apply and check. At the end they run the check of the VM, which pushes the result to `results/`.

Before running one: take a PVE snapshot of the VM.

| VM | Command | Fixes |
|---|---|---|
| welcome (10.4.255.11) | `sudo sh fixes/welcome.sh` | hostname `welcome`; Postfix `myhostname = mail.group4.umons`; remove the leftover BIND |

Each script refuses to run on another VM.
