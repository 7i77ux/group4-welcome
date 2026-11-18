# fixes

Scripts that CHANGE a VM, one fix at a time: current state, reason, confirmation (`y`), backup of the files they change in `/root/fixes-backup-<date>`, change, check (and restore of the backup if the check fails). Take a PVE snapshot of the VM first. Each script refuses to run on another VM; most end with `checks/full.sh`.

| VM | Command | What |
|---|---|---|
| welcome | `sudo sh fixes/fix_welcome.sh` | Fixes 1-10 of welcome: hostname; Postfix `myhostname`; leftover BIND removed; `mynetworks` local only; Maildir; account `calogero` + mail login only for `mailusers`; IMAP only on 993; Postfix protections; relay refused with 554 (W30); DNS of welcome = course resolver 10.4.255.254 (W34) |
| welcome | `sudo sh fixes/mail_virtual.sh` | Virtual mailboxes ("New 4.3" with the five fixes of its review: `docs/new-4.3.md`): MariaDB, user `vmail`, Dovecot login from the database, Postfix virtual domain, `postmaster` alias, migration of `calogero`, tests; the previous configuration is put back if a test fails |
| welcome | `sudo sh fixes/mail_users.sh` | Mail accounts of the virtual mailboxes: `list`, `add <name>`, `activate`, `disable`, `passwd` |
| welcome | `sudo sh fixes/cert.sh` | Course certificate. Part A: key and request checked (CN `welcome.group4.umons`, names welcome + mail), request put in `certs/group4.csr` for the teacher. Part B, once the signed certificate is in `certs/` (pushed from the laptop): checks (course CA, chain, our key, expiry, names), files in `/etc/ssl/group4`, Postfix 25, Dovecot 993, nginx 443 (new site `welcome-ssl`, 80 unchanged), TLS tests. The forward of 443 on pfSense is done by hand (printed at the end) |
| welcome | `sudo sh fixes/fix_suricata.sh` | Repair of Suricata (card of the default route, `HOME_NET`, rules folder, rules, `suricata -T`, start, test alert) |
| ns1 | `sudo sh fixes/fix_dns_serial.sh` | Raise the serial of `group4.umons` and `2.4.10.in-addr.arpa` |

Manual steps of every fix: DOCUMENTATION.md section 10.
