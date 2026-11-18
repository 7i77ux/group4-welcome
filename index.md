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
    .badge::before, .wait::before { content: "\25CF\00A0"; color: #c98a00; }
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
  </style>
  ```
---

[Service being set up]{.badge}

Group 4 gives the companies of the umons network addresses **@group4.umons**. Mail sent from any provider of the network arrives in your mailbox, and you read it with your usual mail client (Thunderbird or any IMAP client).

## Configure your mail client

:::: {.cards}

::: {.card}
### Your account

Address
:   `name@group4.umons`

User name
:   your account name, without `@group4.umons`

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

::: {.card .later}
### Outgoing server

[Not available yet]{.wait}

Sending from your mail client opens together with our certificate from the course authority.
:::

::::

::: {.card .note}
### Certificate

Today the mail server uses a temporary certificate (`CN=debian`): the first time you connect, your mail client asks you to accept it.

We have asked the certificate authority of the course for our own certificate. Once it is installed, this page will tell you how to trust it, and the warning disappears.
:::

:::: {.cards}

::: {.card}
### Ask for an account

Accounts are created by our administrator. Write to `calogero@group4.umons`.
:::

::: {.card}
### Service status

[Website (HTTP): online]{.ok}\
[Receiving mail from every provider (SMTP, port 25): online]{.ok}\
[Reading your mailbox (IMAP over TLS, port 993): online]{.ok}\
[Sending from your mail client (port 587): not yet]{.wait}\
[Website over HTTPS: not yet]{.wait}
:::

::::

::: {.footer}
Group 4 · `group4.umons` · Last update: 2026-11-18
:::
