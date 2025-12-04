Here is a "preview" of what your terminal will look like when you run these scripts. This way, you can recognize if things are going right (or wrong) and you won't be surprised by long pauses.

### Part 1: The Repo Setup (`setup_1_repo.sh`)

This script is fast (usually under 1 minute). The output will look roughly like this:

```text
>>> [1/4] Installing OSTree dependencies...
Reading package lists... Done
Building dependency tree... Done
The following NEW packages will be installed:
  ostree libostree-dev gnupg
... (lots of text lines from apt) ...

>>> [2/4] Generating GPG Key...
gpg: key 3AA5C34371567BD2 marked as ultimately trusted
gpg: directory '/root/.gnupg' created
   Key ID: 3AA5C34371567BD2

>>> [3/4] Initializing OSTree Repository...
   Repo initialized at /srv/flatpak-repo

>>> [4/4] Exporting Public Key...

=== PART 1 COMPLETE ===
Repo Path: /srv/flatpak-repo
GPG Key ID: 3AA5C34371567BD2
(Save this Key ID, you will need it for Part 2!)
```

**🔴 CRITICAL STEP:**
See that line `GPG Key ID: 3AA5C34371567BD2`?
You **must copy that code** (yours will be different) and paste it into the second script before you run it.

-----

### Part 2: The Manager Setup (`setup_2_manager.sh`)

This script takes much longer (5–15 minutes) because it has to compile code.

**1. The Start (Fast)**
It installs the database and basic tools.

```text
>>> [1/5] Installing Dependencies (Postgres & Rust)...
Reading package lists... Done
... (apt output) ...
info: downloading installer
info: installing component 'cargo'
info: default toolchain set to 'stable-x86_64-unknown-linux-gnu'

>>> [2/5] Setting up Database...
CREATE ROLE
CREATE DATABASE
```

**2. The Long Wait (Slow\!)**
This is where most people panic. It will say "Compiling" for a long time. **This is normal.**

```text
>>> [3/5] Compiling Flat-manager (Takes time)...
    Updating git repository `https://github.com/flatpak/flat-manager`
  Downloaded serde v1.0.130
  Downloaded tokio v1.14.0
  ... (hundreds of "Downloaded" lines) ...
   Compiling libc v0.2.108
   Compiling proc-macro2 v1.0.32
   ... (lots of "Compiling" lines) ...
   Compiling flat-manager v0.1.0 (/root/.cargo/git/checkouts/flat-manager...)
    Finished release [optimized] target(s) in 8m 42s
  Installing /usr/local/bin/flat-manager
  Installing /usr/local/bin/flat-manager-client
```

**3. The Finish (Fast)**
It configures the system service and gives you your password.

```text
>>> [4/5] Creating Configuration...
>>> [5/5] Creating Systemd Service...
Created symlink /etc/systemd/system/multi-user.target.wants/flat-manager.service → /etc/systemd/system/flat-manager.service.

=== PART 2 COMPLETE ===
Server is running at: http://192.168.1.50:8080
Your Admin Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbl9tYW51YWwiLCJzY29wZSI6WyJzdGFibGUiXSwiaWF0IjoxNj...
```

**🔴 CRITICAL STEP:**
That long string starting with `eyJ...` is your **Admin Token**.

  * It is your password.
  * It allows you to upload apps.
  * **Save it immediately** (e.g., in a password manager or a text file on your laptop). If you lose it, you have to SSH into the server to generate a new one.

### Summary Checklist

1.  **Run Part 1.**
2.  **Copy** the `GPG Key ID` from the output.
3.  **Edit Part 2** and **Paste** the ID into the top of the script.
4.  **Run Part 2** and wait for the compilation (don't cancel it\!).
5.  **Copy** the `Admin Token` at the end.