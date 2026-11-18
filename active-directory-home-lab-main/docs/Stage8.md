# Stage 8 — Users & Groups

**Goal:** Populate the domain with user accounts and a least-privilege group structure — one user created by hand to learn the workflow, three provisioned in bulk with PowerShell, and an AGDLP group model wired up and ready for resource permissions.

**Environment:** DC01 (Windows Server 2025, 10.10.10.10) and CLIENT01 (Windows 11, domain-joined), domain `corp.lab`.

---

## What was built

| Item | Detail |
|---|---|
| GUI-created user | `jane.doe` in `OU=IT,OU=Users,OU=CORP` |
| Bulk-created users | `mark.lopez` (Sales), `amy.chen` (HR), `raj.patel` (IT) — provisioned from CSV via PowerShell |
| Global group | `SG-IT-Staff` — role group containing IT users |
| Domain Local group | `SG-Share-IT-RW` — resource group, contains `SG-IT-Staff` |
| Verified flow | First-login forced password change for a new domain user on CLIENT01 |

---

## Build walkthrough

### 1. Create a user in the GUI

In **Active Directory Users and Computers**, right-clicked `OU=IT` → **New → User**.

- First/Last name: Jane Doe
- User logon name: `jane.doe@corp.lab` — this is the **UPN**, the modern login format
- The pre-Windows 2000 field auto-filled `CORP\jane.doe` — the **sAMAccountName**, the legacy format. Both resolve to the same account at a login screen.

📸 `08-01-new-user-jane-doe.png`

On the password screen, set a temporary password and left only **User must change password at next logon** checked. This mirrors real onboarding: IT sets a temporary credential, the user replaces it on first login, and from that point only the user knows their password — which makes account activity attributable to the person (non-repudiation).

The other three checkboxes, for reference:

- *User cannot change password* — shared/kiosk-style accounts
- *Password never expires* — service accounts; a red flag on human accounts and a standard audit target (`Search-ADAccount -PasswordNeverExpires`)
- *Account is disabled* — pre-staging hires before their start date, and the first step of offboarding (disable, don't delete, to preserve the SID and audit trail)

📸 `08-02-jane-doe-created.png`

### 2. Verify onboarding end-to-end on the client

Logged into CLIENT01 as `CORP\jane.doe` with the temporary password. Windows immediately required a password change — the *change at next logon* flag working as designed, not an error.

📸 `08-03-jane-first-logon-password-change.png`

After setting a new password, Windows built Jane's local profile (`C:\Users\jane.doe`). Verified the session with `whoami` → `corp\jane.doe`.

📸 `08-04-jane-logged-in.png`

Two things worth knowing here:

- **Kerberos** authenticated this login — CLIENT01 requested a ticket from DC01 on Jane's behalf. This was the domain's first authentication of a regular user rather than an administrator.
- The domain holds the **identity**; the workstation holds the **profile**. Logging into a second machine would create a fresh local profile there (roaming profiles / folder redirection address this in production).

### 3. AGDLP group structure

Real environments assign permissions to groups, not people. The AGDLP pattern: **A**ccounts go into **G**lobal groups (by role), Global groups nest into **D**omain **L**ocal groups (by resource), and **P**ermissions are assigned to the Domain Local group.

Created in `OU=Groups`:

| Group | Scope | Answers the question |
|---|---|---|
| `SG-IT-Staff` | Global | *Who is this person?* (role/department) |
| `SG-Share-IT-RW` | Domain Local | *What does this resource allow?* (read/write on the IT share) |

Then the two memberships that make it AGDLP:

1. Added `jane.doe` to `SG-IT-Staff` (A → G)
2. Added `SG-IT-Staff` as a member of `SG-Share-IT-RW` (G → DL)

📸 `08-05-agdlp-groups-created.png`
📸 `08-06-group-nesting.png`

The P — actual NTFS permissions on a share — is deferred until a file server exists (planned follow-on build). The payoff of the structure: when a share is created, `SG-Share-IT-RW` gets Modify **once**, and every current and future member of `SG-IT-Staff` inherits access. Onboarding a new IT hire becomes a single group-membership change.

### 4. Bulk-provision users from CSV with PowerShell

Created `C:\Lab\Scripts` on DC01 with two files.

**`newusers.csv`:**

```csv
FirstName,LastName,SamAccountName,Department,OU
Mark,Lopez,mark.lopez,Sales,"OU=Sales,OU=Users,OU=CORP,DC=corp,DC=lab"
Amy,Chen,amy.chen,HR,"OU=HR,OU=Users,OU=CORP,DC=corp,DC=lab"
Raj,Patel,raj.patel,IT,"OU=IT,OU=Users,OU=CORP,DC=corp,DC=lab"
```

The OU column is a **distinguished name (DN)** — the object's full address in the directory, read right-to-left from the domain (`DC=corp,DC=lab`) down through each OU. It's the LDAP-native form of the path ADUC displays as `corp.lab/CORP/Users/Sales`. The quotes are required because DNs contain commas, which are also the CSV delimiter.

**`New-LabUsers.ps1`:**

```powershell
Import-Module ActiveDirectory
$users = Import-Csv .\newusers.csv

# Prompt once for the temporary password instead of hardcoding it — keeps the
# credential out of source control. Must meet the domain policy (14+ chars).
$tempPassword = Read-Host "Temporary password for new accounts" -AsSecureString

foreach ($u in $users) {
    $upn = "$($u.SamAccountName)@corp.lab"
    New-ADUser -Name "$($u.FirstName) $($u.LastName)" `
        -GivenName $u.FirstName -Surname $u.LastName `
        -SamAccountName $u.SamAccountName -UserPrincipalName $upn `
        -Department $u.Department -Path $u.OU `
        -AccountPassword $tempPassword `
        -ChangePasswordAtLogon $true -Enabled $true
    Write-Host "Created $($u.SamAccountName)"
}
```

> The temporary password is prompted for at runtime with `Read-Host -AsSecureString` rather than hardcoded as plaintext — the same credential-handling pattern used by the reset and offboard scripts, keeping secrets out of source control.

Every parameter maps to a field from the GUI wizard: `-Name` is Full name, `-SamAccountName` is the pre-Windows 2000 box, `-Path` is "Create in:", `-ChangePasswordAtLogon $true` is the onboarding checkbox. One non-obvious detail: `-Enabled $true` is required because **PowerShell creates AD accounts disabled by default** — the opposite of the GUI.

Ran from an elevated PowerShell session:

```powershell
cd C:\Lab\Scripts
.\New-LabUsers.ps1
```

Output: `Created mark.lopez`, `Created amy.chen`, `Created raj.patel` — clean run, no execution-policy intervention needed.

Verified with:

```powershell
Get-ADUser -Filter * -SearchBase "OU=Users,OU=CORP,DC=corp,DC=lab" -Properties Department |
    Select-Object Name,SamAccountName,Department |
    Format-Table
```

All four users present, each in the correct department OU.

📸 `08-07-bulk-users-complete.png`

---

## Observations & fixes

### Attribute drift on the manually-created account

The verification table surfaced an inconsistency: the three scripted users all had a `Department` value, but `jane.doe` — created through the GUI — did not. The New User wizard never asks for Department, while the script sets it explicitly on every account.

Remediated with a one-liner:

```powershell
Set-ADUser -Identity jane.doe -Department IT
```

Re-ran the verification; all four accounts now consistent.

📸 `08-09-jane-dept-fixed.png`

**Takeaway:** this is the case for scripted provisioning in miniature. Hand-created accounts drift in small ways that nobody notices until a report depends on the missing attribute; scripted accounts are identical by construction. Auditing for and correcting attribute gaps is exactly the kind of hygiene work that separates tidy directories from messy ones.

### Guest Additions missing on DC01 (clipboard failure)

**Symptom:** Host-to-VM copy/paste silently failed on DC01, blocking the transfer of the CSV and script content. Setting *Shared Clipboard → Bidirectional* in VM Settings had no effect.

**Root cause:** VirtualBox Guest Additions had been installed on CLIENT01 but never on DC01. The Guest Additions ISO was *mounted* (visible on SATA Port 1 in the VM's storage settings) but the installer had never been run inside the guest — and the shared clipboard requires the in-guest service, not just the host-side setting.

**Fix:** Inside DC01, opened the mounted CD drive, ran `VBoxWindowsAdditions.exe` (the architecture-detecting launcher), accepted defaults, rebooted. Bidirectional clipboard worked immediately afterward.

**Lesson:** "ISO attached" ≠ "Guest Additions installed." The host-side clipboard setting and the in-guest service are two halves of one feature; either alone does nothing.

### The `.csv.txt` trap (avoided)

Notepad's Save As dialog defaults to *Text Documents (\*.txt)*, which silently appends `.txt` to the filename — producing `newusers.csv.txt` that *looks* correct because Windows hides extensions by default. Avoided by setting **Save as type: All Files** before saving, and verified afterward via the Type column in Explorer (`CSV File` / `Windows PowerShell`). Enabling *View → Show → File name extensions* on any administered server makes this class of error visible.

---

## Skills demonstrated

- Created and verified domain user accounts via both ADUC and PowerShell (`New-ADUser`, `Set-ADUser`, `Get-ADUser`)
- Implemented a least-privilege AGDLP group model with correct Global / Domain Local scoping
- Automated bulk account provisioning from CSV, including DN-based OU targeting
- Validated the full onboarding flow from the end-user side, including forced password change at first logon
- Diagnosed and resolved a VirtualBox Guest Additions / shared clipboard issue via root-cause analysis
- Identified and remediated attribute inconsistency between manual and scripted provisioning

## Security+ concepts in play

| Concept | Where it showed up |
|---|---|
| Least privilege | AGDLP — permissions flow through groups, never to individuals |
| Non-repudiation | Forced password change means only the user knows their credential |
| Identity lifecycle | Temporary password → forced change; disable-don't-delete offboarding pattern |
| Account auditing | `Password never expires` as an audit flag; attribute consistency checks |

---

**Snapshot taken:** `05a-users-groups-done` (both DC01 and CLIENT01, powered off).

Position in the snapshot lineage:

```
01-server-installed
└─ 02-dc-promoted
   └─ 03-dns-dhcp-done
      └─ 04-client-joined
         └─ 04b-ou-structure          (Stage 7)
            └─ 05a-users-groups-done   (Stage 8 — current)
               └─ Current State
```

This is an interim snapshot. The guide's `05-baseline` milestone is reserved for after Stage 9 (Group Policy), so `05a-` keeps the sequence ordered and honest without claiming the baseline is complete.

**Next:** Stage 9 — Group Policy (password/lockout policy, logon banner, drive mapping, restrictions).
