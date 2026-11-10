# fixes

Scripts that CHANGE a VM, one fix at a time. For each fix they show the current state and the reason, ask for confirmation (`y`), back up the files they change in `/root/fixes-backup-<date>`, apply and check. At the end they run the check of the VM, which pushes the result to `results/`.

Before running one: take a PVE snapshot of the VM.

| VM | Command | Fixes |
|---|---|---|
| welcome (10.4.255.11) | `sudo sh fixes/fix_welcome.sh` | hostname `welcome`; Postfix `myhostname = mail.group4.umons`; remove the leftover BIND; `mynetworks` only local (closes the relay, repairs incoming mail); Maildir; account `calogero` + mail login only for group `mailusers`; IMAP only on 993; Postfix protections |
| ns1 (10.4.255.10) | `sudo sh fixes/fix_ns1.sh` | one tool for the network (NetworkManager, gateway and DNS 127.0.0.1 in the profile, ens18 removed from `/etc/network/interfaces`); one PTR for 10.4.255.11 (`mail.group4.umons.`), serial raised |

Each script refuses to run on another VM.
