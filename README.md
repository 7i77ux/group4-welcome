# group4-welcome

Source of the welcome page of Group 4 (http://welcome.group4.umons) and the scripts used on our VMs.

- `index.md`: the page, written in Markdown
- `deploy.sh`: publishes the page with nginx on welcome and keeps it always on
- `action.sh`: menu of the activities of the VM where it runs
- `checks/`: read-only checks (see `checks/README.md`)
- `fixes/`: scripts that change a VM, one fix at a time, with confirmation (see `fixes/README.md`)

The scripts recognise the VM by its host name (`welcome`, `ns1`) or by its address (DMZ 10.4.2.x since 2026-11-17) and refuse to run on the wrong one. Scripts removed on 2026-11-18 because done or replaced (still in the git history): `make-csr.sh`, `checks/welcome.sh`, `checks/ns1.sh`, `checks/mail.sh`, `checks/setup-results.sh`, `checks/mailtest_ns1.sh`, `checks/ice_timing.*`, `fixes/fix_ns1.sh`, `fixes/suricata_welcome.sh`.

## On a VM

```
cd ~/Desktop/group4-welcome && sh action.sh
```

It lists the activities of that VM with the date of the last result of each check, runs the one you choose (asking the sudo password), and `r` runs the recommended order, asking before each step.

## Update the page

Edit `index.md`, push, then on welcome: `cd ~/Desktop/group4-welcome && git pull && sudo sh deploy.sh` (menu 7).
