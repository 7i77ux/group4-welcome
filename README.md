# group4-welcome

Source of the welcome page of Group 4: http://welcome.group4.umons

- `index.md`: the page, written in Markdown
- `deploy.sh`: publishes the page with nginx on the Welcome + mail VM and keeps it always on
- `make-csr.sh`: generates the private key and the certificate signing request (CSR) for the course CA
- `checks/`: read-only test scripts for the VMs (see `checks/README.md`)

`deploy.sh` and `make-csr.sh` refuse to run on a VM other than welcome (10.4.255.11).

## Deploy (on the Welcome + mail VM)

```
git clone https://github.com/7i77ux/group4-welcome
sudo sh group4-welcome/deploy.sh
```

## Update the page

Edit `index.md`, push, then on the VM:

```
cd group4-welcome && git pull && sudo sh deploy.sh
```

## TLS certificate request (on the Welcome + mail VM)

```
cd group4-welcome && git pull
sudo sh make-csr.sh
```

The key is created in `/etc/ssl/group4/group4.key` (root only) and never leaves the VM. Send only `~/group4.csr` to the teacher, and ask to keep the `subjectAltName` (`welcome.group4.umons`, `mail.group4.umons`). The script refuses to overwrite an existing key.
