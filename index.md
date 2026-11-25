---
title: Group 4 Mail
subtitle: Email provider for the companies of the umons network
lang: en
maxwidth: 46em
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
    header { text-align: left; margin-bottom: 1.5em; padding-bottom: 1em; border-bottom: 3px solid #1d4c9c; }
    .subtitle { margin-top: 0; color: #5f6b78; }
    h2 { color: #1d4c9c; margin-top: 1.8em; }
    .badge { display: inline-block; font-size: .8em; color: #5f6b78; background: #fff; border: 1px solid #dde2e7; border-radius: 1em; padding: .1em .8em; }
    .wait::before { content: "\25CF\00A0"; color: #c98a00; }
    .badge::before { content: "\25CF\00A0"; color: #2e7d32; }
    .ok::before { content: "\25CF\00A0"; color: #2e7d32; }
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(13em, 1fr)); gap: 1em; margin: 1em 0; }
    .card { background: #fff; border: 1px solid #dde2e7; border-radius: 8px; padding: .9em 1.1em; }
    .card h3 { margin: 0 0 .6em; font-size: 1em; color: #1d2733; }
    .card p { font-size: .9em; margin: .4em 0; }
    .card dl { display: grid; grid-template-columns: auto 1fr; gap: .2em 1em; margin: 0; font-size: .9em; }
    .card dt { color: #5f6b78; font-weight: normal; }
    .card dd { margin: 0; }
    .note { border-left: 4px solid #1d4c9c; }
    .later { background: #f4f6f8; color: #5f6b78; }
    .footer { color: #5f6b78; font-size: .85em; border-top: 1px solid #dde2e7; margin-top: 2.5em; padding-top: .8em; }
    a.button { display: inline-block; background: #1d4c9c; color: #fff; text-decoration: none; border-radius: 6px; padding: .3em .9em; font-size: .9em; margin: .3em 0; }
    .fp { font-family: monospace; font-size: .8em; word-break: break-all; background: #eef1f5; padding: .1em .3em; }
  </style>
  ```
---

[Service online]{.badge}

Group 4 gives the companies of the umons network addresses **@group4.umons**. Mail sent from any provider of the network arrives in your mailbox, and you read it with your usual mail client (Thunderbird or any IMAP client).

## Configure your mail client

New customer? Follow the guide, step by step: [How to join Group 4 Mail](join.html){.button}

:::: {.cards}

::: {.card}
### Your account

Address
:   `name@group4.umons`

User name
:   your full address, `name@group4.umons`

Password
:   the one we gave you (normal password)
:::

::: {.card}
### Incoming server

Server
:   `mail.group4.umons`

Protocol
:   IMAP

Port
:   993

Security
:   SSL/TLS
:::

::: {.card}
### Outgoing server

Server
:   `mail.group4.umons`

Protocol
:   SMTP

Port
:   587

Security
:   STARTTLS
:::

::::

::: {.card .note}
### Certificate

Our website (HTTPS) and our mail server use a certificate signed by the certificate authority of the course (*Simply The Best*). Import this authority once in your mail client and in your browser:

[Download the course authority](course-root-ca.pem){.button}

After the import, check that its SHA-256 fingerprint is exactly:\
[CD:B8:69:AE:E5:49:74:CB:28:C5:C9:A2:6B:13:29:D8:7D:B7:D2:41:DE:3C:2C:CB:6C:63:D3:A8:F9:32:8D:02]{.fp}

Thunderbird: Settings → Privacy & Security → Manage Certificates → Authorities → Import, choose the file, tick "This certificate can identify websites", OK.\
Firefox: Settings → Privacy & Security → View Certificates → Authorities → Import, tick "Trust this CA to identify websites", OK.
:::

:::: {.cards}

::: {.card}
### Ask for an account

Accounts are created by our administrator. The button prepares the request in your mail client:

[Request an account](mailto:calogero@group4.umons?subject=Account%20request&body=Company%3A%20%0AName%3A%20%0AWished%20address%3A%20____%40group4.umons){.button}

We create the account and contact you. All the steps: [step-by-step guide](join.html).
:::

::: {.card}
### Service status

[Website (HTTP and HTTPS): online]{.ok}\
[Receiving mail from every provider (SMTP, port 25): online]{.ok}\
[Reading your mailbox (IMAP over TLS, port 993): online]{.ok}\
[Sending from your mail client (SMTP with login, port 587): online]{.ok}
:::

::::

::: {.footer}
Group 4 · `group4.umons` · Last update: 2026-11-25
:::
