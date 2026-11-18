# Stage 9 — Group Policy

**Goal:** Move the domain from "exists" to "managed." Build four Group Policy Objects that enforce a domain-wide password and lockout baseline, present a legal logon banner, map a department drive only to the staff who should have it, and restrict a setting for a scoped test group — then verify every one of them on the client and read the resultant policy back to prove it.

**Environment:** DC01 (Windows Server 2025, 10.10.10.10) and CLIENT01 (Windows 11, domain-joined), domain `corp.lab`.

---

## What was built

| GPO | Linked to | Scope / targeting | Purpose | Security+ concept |
|---|---|---|---|---|
| Default Domain Policy (edited) | Domain root `corp.lab` | All domain accounts | Password length/age + account lockout | Authentication hardening, brute-force mitigation |
| `Logon-Banner` | `OU=CORP` | All computers beneath CORP | Legal authorized-use banner at logon | Deterrent / administrative control |
| `Drive-Map-IT` | `OU=Users` | Item-level targeted to `SG-IT-Staff` | Maps `S:` → `\\DC01\IT-Share` for IT staff only | Least privilege (access by role) |
| `Restrict-ControlPanel` | `OU=Test` | `test.user` only | Blocks Control Panel + PC Settings | Least privilege / attack surface reduction |

Supporting infrastructure created this stage: an SMB file share (`C:\Shares\IT-Share` → `\\DC01\IT-Share`) wired to the Stage 8 AGDLP groups, plus `OU=Test` and a throwaway `test.user` account for safely testing the restriction.

---

## Build walkthrough

### 1. Domain password & lockout policy (Default Domain Policy)

Edited the **Default Domain Policy** rather than creating a new GPO. This is deliberate and worth stating plainly: for **domain accounts**, account policies (password, lockout, Kerberos) are only honored when set at the **domain root**. A password policy linked to an OU does nothing for domain logons. Microsoft's guidance is to use Default Domain Policy for account policies *and nothing else* — everything else gets its own GPO. That is exactly the pattern followed here.

Captured the **before** state first — the out-of-the-box Windows defaults, which are interview trivia in their own right:

| Policy | Default (before) | Set to (after) |
|---|---|---|
| Minimum password length | 7 characters | **14** |
| Maximum password age | 42 days | **90** |
| Password complexity | Enabled | Enabled (verified, not changed) |
| Password history | 24 remembered | 24 (left as-is) |
| Store passwords w/ reversible encryption | Disabled | Disabled (left — never enable) |
| Account lockout threshold | **0 (never lock out)** | **5** invalid attempts |
| Account lockout duration | Not Defined | **15** minutes |
| Reset lockout counter after | Not Defined | **15** minutes |
| Allow Administrator account lockout | Not Defined | **Enabled** |

📸 `09-02-password-policy-defaults.png`, `09-03-lockout-policy-defaults.png` (before)
📸 `09-04-password-policy-configured.png`, `09-05-lockout-policy-configured.png` (after)

Two details worth knowing:

- The default lockout threshold of **0 means accounts never lock out** — out of the box, a domain will accept unlimited password guesses. Setting it to 5 is the single biggest brute-force improvement on this list.
- Setting the threshold triggered a **Suggested Value Changes** dialog that auto-populated duration and reset-counter (Server 2025 suggests 10 minutes; older Windows suggested 30 — even "the defaults" drift over time, which is why the configured values are documented rather than assumed). Accepted and then adjusted duration/reset to 15.
- **Allow Administrator account lockout = Enabled** locks the built-in Administrator out of *network* logons after the threshold, but **console logon always remains available** — so it cannot brick the domain. In this lab the DC01 VirtualBox window *is* the console, so the recovery path is guaranteed.

**Security+ framing:** threshold 5 + duration 15 is brute-force mitigation — an online guessing attack gets 5 tries per 15 minutes instead of unlimited. The tradeoff is a denial-of-service angle (an attacker can deliberately lock a user out), which is exactly why the duration is a self-clearing 15 minutes rather than "until an admin unlocks."

### 2. Logon banner (`Logon-Banner`, linked to OU=CORP)

Created a new GPO via **right-click OU=CORP → "Create a GPO in this domain, and Link it here…"** — one action that creates both the GPO *object* (stored in the Group Policy Objects container) and the *link* to the OU.

Edited **Computer Configuration → Policies → Windows Settings → Security Settings → Local Policies → Security Options** and defined the two **Interactive logon** entries:

- **Message title:** `Authorized Access Only`
- **Message text:** a notice covering the three legal elements — authorized use only, monitoring, and consent by continuing.

📸 `09-06-logon-banner-gpo-settings.png`

Confirmed on the **Scope** tab: Link = CORP, Link Enabled = Yes, Enforced = No, Security Filtering = Authenticated Users (universal, which is correct for a banner). Scoped to OU=CORP rather than the domain root as a precision habit — policy goes where it is needed.

📸 `09-01-gpmc-tree.png` (GPMC tree), scope verified on the GPO's Scope tab

**Security+ framing:** a banner is a deterrent and administrative control. It stops nothing technically, but it removes the "I didn't know I wasn't allowed" defense and establishes monitoring consent.

### 3. Mapped department drive (`Drive-Map-IT`) — the AGDLP payoff

This is where the Stage 8 group work becomes concrete. Three layers:

**3a. The share.** Created `C:\Shares\IT-Share` and shared it as `IT-Share`. At the **share permission** layer, removed `Everyone` and granted `Authenticated Users` Full Control. At the **NTFS** layer, added the domain-local group `SG-Share-IT-RW` with **Modify** (read/write/delete, but not permission-change or ownership). This is the standard pattern: share permissions wide, NTFS does the real enforcement, most-restrictive-wins when both apply.

📸 `09-07-share-permissions.png`, `09-08-ntfs-permissions.png`

**3b. The GPO.** Linked `Drive-Map-IT` to `OU=Users` (a *user* setting must reach user accounts). Under **User Configuration → Preferences → Windows Settings → Drive Maps**, created a New Mapped Drive: Action **Create**, Location `\\DC01\IT-Share`, Reconnect **on**, Label `IT Share`, Drive letter **S:**. Used a *Preference* (not a Policy) because mapping a drive is a convenience, not a lockdown — the user can modify it afterward.

**3c. Item-level targeting.** On the **Common** tab, enabled Item-level targeting → condition "the user is a member of the security group **CORP\SG-IT-Staff**." The condition resolves against the group's immutable **SID**, so it survives a rename. This is what lets one GPO serve many departments: each drive item is targeted at its own role group.

📸 `09-09-drive-map-targeting.png`

**The full AGDLP chain, end to end:**

```
jane.doe
  └─ member of SG-IT-Staff (Global, "who are the IT people")
        └─ nested in SG-Share-IT-RW (Domain Local, "who can write to the IT share")
              └─ holds NTFS Modify on C:\Shares\IT-Share
                    └─ shared as \\DC01\IT-Share
                          └─ mapped to S: by Group Policy Preferences (targeted at SG-IT-Staff)
```

A new IT hire gets a working, writable IT drive by being added to **one** group. That is the entire reason the AGDLP model exists.

### 4. Restrict a setting (`Restrict-ControlPanel`, scoped to a test OU)

To demonstrate a *restriction* (the contrast to the convenience features above) without affecting the accounts used for verification, created a dedicated `OU=Test` under CORP and a throwaway `test.user` inside it. This isolates policy experiments from production OUs — the way a real shop tests a GPO before rolling it out.

Creating `test.user` produced a useful side-effect: the first password attempt was **rejected** by the new 14-character policy from step 1 — live proof the password baseline works. A compliant password was then accepted.

📸 `09-10-test-ou-and-user.png`

Linked `Restrict-ControlPanel` to OU=Test and enabled **User Configuration → Policies → Administrative Templates → Control Panel → "Prohibit access to Control Panel and PC settings."** A *Policy* (enforced) and a *User* setting (follows the user) — the opposite half of the GPO from the password policy, which was a Computer setting.

📸 `09-11-control-panel-restriction.png`

---

## Verification (on CLIENT01)

Every GPO was verified by its actual behavior on the client, not just by its presence on the DC.

| What | Result | Evidence |
|---|---|---|
| Logon banner | Appeared at the lock screen on first boot, full title + text | 📸 `09-12-logon-banner-client.png` |
| Mapped drive (jane.doe) | `S:` present, labeled "IT Share", pointing at `\\DC01\IT-Share` | 📸 `09-13-mapped-drive-client.png` |
| Drive write access (jane.doe) | Created a test file inside `S:` — no access-denied, proving Modify (NTFS) is real | 📸 `09-13b-drive-write-test.png` |
| Control Panel block (test.user) | "This operation has been cancelled due to restrictions in effect on this computer." | 📸 `09-14-control-panel-blocked.png` |
| Mapped drive (test.user) | **No `S:` drive** — correct, she is not in SG-IT-Staff (negative test) | 📸 `09-16-no-drive-test-user.png` |
| Resultant policy | `gpresult` confirms applied vs. filtered GPOs per user | 📸 `09-15-gpresult.png`, `gpo/gpresult-testuser.html` |

The pairing of `09-13` (jane.doe **has** S:) against `09-16` (test.user does **not**) is the strongest single piece of evidence in the stage: it proves item-level targeting works in **both** directions — granting access to the authorized role and withholding it from everyone else. Same machine, same share on the network, different access based purely on group membership. Least privilege, made measurable.

The HTML resultant-set-of-policy report (`gpresult /h`) is filed under `gpo/` as a clean documentation artifact: it shows CLIENT01 in `corp.lab/CORP/Workstations`, Default Domain Policy + Logon-Banner applied to the computer, Restrict-ControlPanel applied to test.user, all components processed with "Success," and no errors.

---

## Troubleshooting case study — `gpresult` reported the wrong user

**Symptom.** Logged in to CLIENT01 as `test.user` to capture the resultant policy. Because Settings was now blocked, opened an **elevated** Command Prompt (which required entering `CORP\Administrator` credentials to elevate) and ran `gpresult /r`. The command returned:

```
INFO: The user "CORP\Administrator" does not have RSoP data.
```

**Why it happened.** Elevating the prompt with the Administrator credential meant the prompt was now running **as CORP\Administrator**, not as test.user. `gpresult /r` reports on **whoever the command prompt is running as — not whoever is logged into the desktop.** Administrator had never logged into CLIENT01 interactively, so there was no Resultant Set of Policy (RSoP) data for that account on that machine. The command was working correctly; it was simply looking at the wrong user.

**Root cause.** A context mismatch between the *interactive desktop session* (test.user) and the *process security context* of the elevated prompt (Administrator). The "run as a different user with elevation" UAC pattern — useful for borrowing admin rights without logging out — silently switches the identity that subsequent commands see.

**Fix.** Two valid options:

- `gpresult /r /user:test.user` — the `/user:` switch reports on a named user regardless of the prompt's identity; the elevated Administrator context has the rights to read another user's RSoP. *(Used this.)*
- Or run a plain, non-elevated `gpresult /r` while logged in as test.user — a user can always read their own RSoP without elevation.

**Lesson / interview takeaway.** `gpresult` (and many policy tools) operate in the security context of the running process. When you elevate as a different user, you change that context. If a policy report ever comes back empty or "wrong," check *who the prompt is actually running as* before assuming the policy failed.

---

## Notes for the rest of the project

- The temp password originally used for Stage 8 bulk provisioning was only **12 characters** — below the new 14-char minimum. Any future runs of `New-LabUsers.ps1` (which now prompts for the password at runtime) must supply a 14+ character value or account creation will fail (this is the same mechanism that rejected the first `test.user` password — the policy working as intended).
- Host↔guest file transfer was set up this stage via a **VirtualBox Shared Folder** (`D:\AD Lab\VM-Transfer` ↔ `\\VBOXSVR\VM-Transfer`), used to pull the `gpresult` HTML report onto the host. This will be the mechanism for moving any guest-generated artifacts into the repo. 📸 `09-17-shared-folder-config.png`
- The IT share doubled as a working transfer bridge during this stage (the report was copied through `\\DC01\IT-Share`), incidentally confirming the share functions for real multi-user file access, not just as a policy target.

---

## Snapshot

Both VMs snapshotted powered-off as **`05-baseline`** — child of `05a-users-groups-done` — representing "users, OUs, groups, shares, and GPOs all in place and verified."

**Stage 9 complete.** Next: Stage 10 — PowerShell automation.
