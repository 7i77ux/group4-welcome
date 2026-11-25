---
title: How to join Group 4 Mail
subtitle: Step-by-step guide for new customers
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
    .step { background: #fff; border: 1px solid #dde2e7; border-radius: 8px; padding: .4em 1.2em .8em; margin: 1em 0; }
    .step h3 { color: #1d4c9c; margin: .6em 0 .4em; }
    .warn { border-left: 4px solid #c98a00; background: #fff8ec; padding: .5em 1em; margin: .8em 0; border-radius: 4px; }
    .see { border-left: 4px solid #2e7d32; background: #f1f8f2; padding: .5em 1em; margin: .8em 0; border-radius: 4px; }
    table { font-size: .92em; }
    th { text-align: left; }
  </style>
  ```
---

[← Back to the main page](index.html) · [Download this guide as PDF](Group4_How_to_join.pdf)

This guide explains, step by step, how to get a mail address `@group4.umons` and use it in **Thunderbird**. It takes about 15 minutes. Do the steps **in order**.

What you need: a computer on the umons network with **Firefox** and **Thunderbird** installed.

1. **Ask for your account** on our website.
2. **Trust the authority of the umons network** (only once per computer).
3. **Add your account** in Thunderbird.
4. **Check** that everything works.

::: {.step}
### Step 1 - Ask for your account (on our website)

1. Open **Firefox** and type in the address bar: **`http://welcome.group4.umons`** (with `http`, without `s`: your computer does not know our authority yet, it is step 2).
2. Click the blue button **Request an account**. You can also click it here:\
   [Request an account](mailto:calogero@group4.umons?subject=Account%20request&body=Company%3A%20%0AName%3A%20%0AWished%20address%3A%20____%40group4.umons){.button}
3. Your mail program opens a new message, already addressed to `calogero@group4.umons`, with the subject **Account request**.
4. Fill in the three lines:
    - **Company:** the name of your company;
    - **Name:** your first name and last name;
    - **Wished address:** the address you want, for example `anna.rossi@group4.umons`.
5. Click **Send**.

::: {.warn}
**Rules for the address:** only lowercase letters `a-z`, digits `0-9`, the dot `.`, the dash `-` and the underscore `_`. No spaces, no accents, no capital letters.
:::

::: {.warn}
**Nothing opened when you clicked the button?** Your computer has no mail program ready yet. Write a normal e-mail from any address you already have to **`calogero@group4.umons`**, subject **Account request**, with the same three lines. Or ask us in person.
:::

::: {.see}
**What happens next:** we create your account and give you your **password in person**. We never send passwords by e-mail.
:::
:::

::: {.step}
### Step 2 - Trust the authority of the umons network (only once)

Our servers prove who they are with a certificate signed by the authority of the umons network, called **Simply The Best**. Your computer must know this authority **once**: after that, no warning appears, for us and for the other providers of the umons network.

::: {.see}
**Already done for another provider of the umons network?** Then skip to step 3: it is the same authority.
:::

**2a. Download the authority**

1. In Firefox, on **`http://welcome.group4.umons`**, click **Download the course authority** in the box *Certificate*.
2. The file **`course-root-ca.pem`** is saved in your **Downloads** folder.

**2b. Add it to Thunderbird**

1. Open **Thunderbird**.
2. Click the menu **≡** (three lines, top right) → **Settings**.
3. On the left, click **Privacy & Security**.
4. Scroll down to **Certificates** and click **Manage Certificates…**
5. Click the tab **Authorities**, then **Import…**
6. Choose the file **`course-root-ca.pem`** in **Downloads** and click **Open**.
7. In the small window, **tick** the box **This certificate can identify websites**, then click **OK**.

**2c. Check that it is the right file**

1. Still in **Authorities**, find **UMONS** in the list and click **Simply The Best** under it.
2. Click **View…** and look at **SHA-256 Fingerprint**. It must be exactly:\
   [CD:B8:69:AE:E5:49:74:CB:28:C5:C9:A2:6B:13:29:D8:7D:B7:D2:41:DE:3C:2C:CB:6C:63:D3:A8:F9:32:8D:02]{.fp}
3. Close the windows with **OK**.

::: {.warn}
**The fingerprint is different?** Stop. Select the entry, click **Delete or Distrust…**, and contact us: someone may have changed the file.
:::

**2d. Add it to Firefox too** (to see our website with the padlock)

1. Firefox: menu **≡** → **Settings** → **Privacy & Security**.
2. Scroll down to **Certificates** → **View Certificates…** → tab **Authorities** → **Import…**
3. Choose **`course-root-ca.pem`**, tick **Trust this CA to identify websites**, click **OK**.
:::

::: {.step}
### Step 3 - Add your account in Thunderbird

1. In Thunderbird: menu **≡** → **Account Settings** → at the bottom left **Account Actions** → **Add Mail Account…**\
   (The first time you open Thunderbird, this window opens by itself.)
2. Fill in:

| Field | What to write |
|---|---|
| Your full name | your first name and last name (the name people see) |
| Email address | your full address, for example `anna.rossi@group4.umons` |
| Password | the password we gave you |
| Remember password | tick it if you do not want to type it each time |

3. Click **Configure manually** (do not use the automatic search).

**4. Incoming server** (to read your mail):

| Field | Value |
|---|---|
| Protocol | **IMAP** |
| Hostname | **`mail.group4.umons`** |
| Port | **993** |
| Connection security | **SSL/TLS** |
| Authentication method | **Normal password** |
| Username | your **full address**, for example `anna.rossi@group4.umons` |

**5. Outgoing server** (to send mail):

| Field | Value |
|---|---|
| Hostname | **`mail.group4.umons`** |
| Port | **587** |
| Connection security | **STARTTLS** |
| Authentication method | **Normal password** |
| Username | your **full address** |

6. Click **Re-test**: Thunderbird checks the settings.
7. Click **Done**.

::: {.warn}
**A window "Add Security Exception" appears?** Click **Cancel**, never "Confirm". It means that step 2 is missing, or that the hostname is not exactly `mail.group4.umons`.
:::
:::

::: {.step}
### Step 4 - Check that everything works

1. Click **Get Messages**: no warning must appear.
2. Under your account you see the folders **Inbox**, **Drafts**, **Sent**, **Trash** and **Junk**. We create them for you.
3. Write a message **to yourself** and click **Send**.

::: {.see}
**You should see:** the sending window closes by itself after a few seconds; the message arrives in **Inbox**, and a copy is in **Sent**. You can now write to anyone of the umons network.
:::
:::

## If something goes wrong

| Thunderbird says | What to do |
|---|---|
| *Peer's Certificate issuer is not recognized* | Step 2 is missing: add the authority to Thunderbird. |
| *The certificate for imap.group4.umons…* or *smtp.group4.umons…* | The hostname is wrong: write **`mail.group4.umons`** (Account Settings → Server Settings, and Outgoing Server (SMTP) → Edit). |
| *Must issue a STARTTLS command first* | Outgoing server → Edit → Connection security: **STARTTLS**. |
| *Login failed* | The username must be your **full address**; check the password (capital letters count). If it still fails, contact us: your account may not be active yet. |
| *Sender address rejected* | You can only send from **your own** address. |
| The sending window stays open | Account Settings → **Copies & Folders** → *Place a copy in* → **"Sent" Folder on** your account; restart Thunderbird. |

## Other programs and phones

The settings are the same as in step 3: **IMAP `mail.group4.umons` port 993 SSL/TLS**, **SMTP `mail.group4.umons` port 587 STARTTLS**, username = your full address. Install the file `course-root-ca.pem` once as a **trusted certificate authority (CA)** in the security settings of the device.

## Contact

Questions: **`calogero@group4.umons`**, or ask us in person.

::: {.footer}
Group 4 · `group4.umons` · [Main page](index.html) · Last update: 2026-11-25
:::
