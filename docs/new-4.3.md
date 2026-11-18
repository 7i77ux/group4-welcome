# New 4.3: virtual mailboxes on welcome

Copy of the team notes of 2026-11-18: the plan of Fabio (as he wrote it; passwords are placeholders) and its review. The scripts that apply it with the five fixes of the review are `fixes/mail_virtual.sh` and `fixes/mail_users.sh` (menu `m` and `u` of `action.sh`).

## 1. New 4.3 part (postfix + dovecom change to implement a mailbox architecture)
Change the mail system to a virtual mailbox architecture (one user in the welcome machine + db with the external user informations): Dovecom and Postfix will only be able to access to the db via a "puppet" admin user, allowing postfix to write mails and dovecom to check and read them. In the system, all the provoledges are given to a vmail user, that is only able to access and modify the /var/mail folders, lmiiting an attacker able to get the permission on the two servers. 
    - New user account -> he'll be the "global" user that will manage all the other mail accounts. It's a permissionless account that simply store the mails of the different accounts
        `sudo groupadd -g 5000 vmail
         sudo useradd -g vmail -u 5000 vmail -d /var/vmail -m`
    - Create the database that will store the user informations (name, psw, servers...). Install also the libraries that allow postfix and dovecot to talk to it
        `sudo apt update
        sudo apt install mariadb-server dovecot-mysql postfix-mysql`
    - Do the secure installation: -> root psw, delete anonymus + test, no root remote login 
        `sudo mysql_secure_installation`
    - Setup the database (create the table)
        `
        CREATE DATABASE mailserver;
        CREATE USER 'mailuser'@'127.0.0.1' IDENTIFIED BY 'your_secure_password';
        GRANT ALL PRIVILEGES ON mailserver.* TO 'mailuser'@'127.0.0.1';
        FLUSH PRIVILEGES;
        USE mailserver;
        ``
        CREATE TABLE virtual_users (
          id INT NOT NULL AUTO_INCREMENT,
          email VARCHAR(128) NOT NULL,
          password VARCHAR(150) NOT NULL,
          PRIMARY KEY (id),
          UNIQUE KEY email (email)
        );
        `
    
    - Setup dovecot and postfix. They talk to the just created mailuser SQL account. They'll be able to get user informations from there...
        - Dovecot -> need to be able to verify if a user has the permissions to check their mail box, when the user register itself to a service (es thunderbird) but doesn't have any /Maildir directory he's the one in charge of the creation 

            Modify the file to allow the GET of user and psw (to authenticate user)
                `sudo nano /etc/dovecot/dovecot-sql.conf.ext`
                `
                driver = mysql
                connect = host=127.0.0.1 dbname=mailserver user=mailuser password=your_secure_password
                default_pass_scheme = SHA512-CRYPT 
                password_query = SELECT email AS user, password FROM virtual_users WHERE email = '%u';
                user_query = SELECT 5000 AS uid, 5000 AS gid, '/var/vmail/%d/%n' AS home FROM virtual_users WHERE email = '%u';
                `
            Give the file permissions only to Dovecot
                `
                sudo chown root:root /etc/dovecot/dovecot-sql.conf.ext
                sudo chmod 600 /etc/dovecot/dovecot-sql.conf.ext
                `
            Set the normal authentication to the sql one
                `sudo nano /etc/dovecot/conf.d/10-auth.conf` -> comment `!include auth-system.conf.ext` and decomment `#!include auth-sql.conf.ext`
                `sudo systemctl restart dovecot`

    - Postfix -> when he has to send an email and the user doesn't have any /Maildir directory he's the one in charge of the creation 
        Give Postfix the credential to log in the sql db
            `sudo nano /etc/postfix/mysql-virtual-mailbox-maps.cf`
            `
            user = mailuser
            password = your_secure_password
            hosts = 127.0.0.1
            dbname = mailserver
            query = SELECT CONCAT(SUBSTRING_INDEX(email,'@',-1),'/',SUBSTRING_INDEX(email,'@',1),'/') FROM virtual_users WHERE email='%s'
            `
        Give the file permission only to postfix
            `
            sudo chown root:postfix /etc/postfix/mysql-virtual-mailbox-maps.cf
            sudo chmod 640 /etc/postfix/mysql-virtual-mailbox-maps.cf
            `
        Change the Postfix configuration in `sudo nano /etc/postfix/main.cf`
            - cancel the mydestination line and replace that with `mydestination = $myhostname, localhost.$mydomain, localhost`. This will allow the database user to receive the mail, not the actual VM user
            - enable virtual delivery by attaching those line at the end of the file
                `
                virtual_mailbox_domains = group4.umons
                virtual_mailbox_base = /var/vmail
                virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
                virtual_minimum_uid = 100
                virtual_uid_maps = static:5000
                virtual_gid_maps = static:5000
                `
        `sudo systemctl restart postfix`

        Check the configuration with the calogero user
            - `doveadm pw -s SHA512-CRYPT`
            - Then, log into MariaDB (sudo mysql -u root -p), select the database (USE mailserver;), and insert the user with the hash it just generated: `INSERT INTO virtual_users (email, password) VALUES ('calogero@group4.umons', 'PASTE_THE_LONG_HASH_HERE');`
            - `postmap -q "calogero@group4.umons" mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf`


    - Web application
        Need to implement a way to sign in users -> insert users into the table (send an insert query) and hash the psw (check the webapp code)


## 2. Review of the New 4.3 (2026-11-18)

**Which architecture is better.** The virtual mailboxes (B, Fabio) are better than the Linux accounts with PAM (A, today) because we want users to register from a web page:

| | A: Linux accounts + PAM (today) | B: virtual users in MariaDB (New 4.3) |
|---|---|---|
| Create a user | needs root (`adduser`): a web form would need root rights, which is dangerous | one `INSERT` in a table: the web form needs no root |
| What a stolen password gives | an account of the system (even with `nologin`) | one mailbox only, no account on the server |
| Mailboxes | in each `/home/<user>` | all under `/var/vmail`, owned by one user without rights (`vmail`) |
| Complexity | low, already tested | higher: one more service (MariaDB) to secure, back up and watch; if it stops, nobody can log in |

Without self-registration A would be enough; with it, B.

**Five fixes before applying the New 4.3** (as written, it would break the mail):

1. Dovecot syntax: the notes use the 2.3 syntax (`dovecot-sql.conf.ext` with `driver`/`connect`, `%u`). Debian 13 has Dovecot 2.4: `sql_driver = mysql`, a `mysql 127.0.0.1 { ... }` block, `passdb sql { query = ... }`, variables `%{user}`.
2. Mailbox folder: Postfix would write to `/var/vmail/<domain>/<user>/` while Dovecot reads `<home>/Maildir` (the same mistake as W27). Chosen in the script: the same folder for both, `/var/vmail/<domain>/<user>/Maildir/` (Postfix query ends with `/Maildir/`, Dovecot `mail_home` = `/var/vmail/<domain>/<user>`). Handing the mail to Dovecot through LMTP would also work, but needs more new settings.
3. Database rights: `mailuser` has `ALL PRIVILEGES`. Three users instead: Postfix and Dovecot read only (`SELECT`), the registration form `INSERT` only. A hacked form then cannot read or delete the other users.
4. `postmaster@group4.umons` must exist, as an alias in the database (table `virtual_aliases`): every mail server must accept it.
5. Registration with approval: whoever registers can also send through 587, so an attacker could create accounts to send spam in our name. The form creates the user disabled (`active = 0`); an administrator enables it (`active = 1`); Dovecot accepts only active users.

**Target architecture**

```
 browser --HTTPS 443--> pfSense --> welcome 10.4.2.11  nginx :443
                                      |-- /            welcome page (static)
                                      |-- /mail        Roundcube (webmail, PHP)
                                      `-- /register    registration form (PHP) --INSERT, active=0--+
                                                                                                   v
 other providers --25--> pfSense --> Postfix :25 --------------------> /var/vmail/group4.umons/<u>/Maildir   MariaDB 127.0.0.1
 customers --993--> pfSense --> Dovecot :993 (login checked in MariaDB, active users only) --SELECT--> virtual_users
 customers --587--> pfSense --> Postfix :587 (login through Dovecot)                                   virtual_aliases
 Roundcube --IMAP / SMTP on localhost--> Dovecot / Postfix
 database users: dovecot (SELECT), postfix (SELECT), register (INSERT only)
 administrator: enables the new users (active = 1)
```

**Where: on welcome, for now.** nginx, Postfix, Dovecot and the database are already there and talk on localhost; a separate VM would isolate the web part better but needs the database open on the network and more work before 2026-11-25. If the PHP part is hacked the attacker is on the machine of the mailboxes (W13, accepted in D13). Welcome has 2 GB: with Suricata, MariaDB and PHP, give it 3-4 GB.

**Conditions and order**

- HTTPS first: without the course certificate, passwords and mails would travel in clear text. The login pages go online only on 443.
- Order: (1) B with the five fixes, then the mail tests (reception from ns1, login of `calogero`, `user` refused); (2) sending on 587; (3) Roundcube; (4) registration with approval.
- Migration of `calogero`: account in the database, its `Maildir` moved to `/var/vmail/group4.umons/calogero/`, owner `vmail`; the PAM rule of D24 and the group `mailusers` are no longer used. A way back if something fails: the copies of the configuration and a PVE snapshot.
- The project statement asks for sending, receiving and the exchange between providers, not for a webmail or self-registration: they are extras, to document as such.

**Scripts (public repo, 2026-11-18), on welcome:**

- `sudo sh fixes/mail_virtual.sh` (menu `m`): steps 1-7 of B with the five fixes: packages, user `vmail`, database `mailserver` (tables `virtual_users` with `active`, `virtual_aliases` with `postmaster`), three database users (passwords in `/etc/group4-mail/`, root only), account `calogero@group4.umons` (password typed twice, old mailbox copied), Dovecot 2.4 login from the database, Postfix virtual domain, tests. If a test fails it puts back the previous Postfix and Dovecot configuration. PVE snapshot first.
- `sudo sh fixes/mail_users.sh list | add <name> | activate <name> | disable <name> | passwd <name>` (menu `u`): mail accounts.
- After the change the login of the mail is the full address (`calogero@group4.umons`); the welcome page must say it.
- Manual steps: `DOCUMENTATION.md` 10.25 and 10.26. Webmail and registration form: after the course certificate (HTTPS).
