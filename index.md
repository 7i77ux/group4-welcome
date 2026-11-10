---
title: Group 4 Mail
subtitle: Email provider for the companies of the umons network
lang: en
maxwidth: 44em
mainfont: system-ui, sans-serif
fontsize: 17px
linestretch: 1.6
fontcolor: "#1d2733"
backgroundcolor: "#fbfcfd"
linkcolor: "#1d4c9c"
monobackgroundcolor: "#eef1f5"
header-includes: |
  ```{=html}
  <style>
    header { text-align: left; margin-bottom: 2em; padding-bottom: 1em; border-bottom: 3px solid #1d4c9c; }
    .subtitle { margin-top: 0; color: #5f6b78; }
    h2 { color: #1d4c9c; }
    tbody, th { border-color: #dde2e7; }
    td { border-bottom: 1px solid #dde2e7; }
    blockquote { border-left-color: #1d4c9c; color: inherit; background: #eef1f5; padding: 0.6em 1em; margin-left: 0; }
    hr { background-color: #dde2e7; margin-top: 2.5em; }
  </style>
  ```
---

> **SMTP is online. IMAP (reading mail) is coming soon.** Updates are posted on this page.

We are **Group 4**, the mail provider of the `group4.umons` domain. We give email addresses to our own staff and to the companies that choose us as their provider. Our mail works with every other provider in the network: you can write to and receive from any `groupX.umons` address.

## Services

| Service | Address | Status |
|---|---|---|
| Website | `welcome.group4.umons` | Online |
| Email: send and receive (SMTP) | `mail.group4.umons` | Online |
| Email: read your mailbox (IMAP) | `mail.group4.umons` | Coming soon |
| Webmail (read and write mail from the browser) | `mail.group4.umons` | Coming soon |
| Instant messaging | | Not offered yet |

<!-- Activate when the webmail is online:
- [Open webmail](http://mail.group4.umons)
- [Write a new email](http://mail.group4.umons/?_task=mail&_action=compose)
- [Read received emails](http://mail.group4.umons/?_task=mail&_mbox=INBOX)
-->

## Become a customer

1. Write to [postmaster@group4.umons](mailto:postmaster@group4.umons?subject=Account%20request) with your group number and the list of users who need an address.
2. We create one address per user, in the form `name@group4.umons`.
3. Each user receives a temporary password and must change it at the first login.

## Mail client settings

Use these values in Thunderbird or any other mail client. Your username is your full email address.

| Use | Server | Port | Security |
|---|---|---|---|
| Incoming mail (IMAP) | `mail.group4.umons` | 993 | SSL/TLS |
| Outgoing mail (SMTP) | `mail.group4.umons` | 587 | STARTTLS, login required |
| Other mail servers (MX) | `mail.group4.umons` | 25 | STARTTLS when available |

## Notices

Maintenance and new services are announced on this page and by email to our customers.

- **2026-11-10**: our SMTP server is online.
- **2026-11-06**: this website is online.

## Security

- We will never ask for your password by email.
- Connections between your mail client and our server are encrypted (ports 587 and 993).
- Report spam, phishing or security problems to [abuse@group4.umons](mailto:abuse@group4.umons).

## Contacts

| Address | For |
|---|---|
| [postmaster@group4.umons](mailto:postmaster@group4.umons) | New accounts, configuration, delivery problems |
| [abuse@group4.umons](mailto:abuse@group4.umons) | Spam, phishing, security incidents |

---

Group 4 · `group4.umons` · Last update: 2026-11-10
