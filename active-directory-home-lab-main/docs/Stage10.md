# Stage 10 — PowerShell Automation

> **Goal of this stage:** Prove the day-to-day help desk tasks can be done *efficiently* and *repeatably*, not just clicked through one at a time. Everything before Stage 10 proved the domain works. Stage 10 proves I can operate it like someone who's trending past tier-1.

This stage produced three scripts, each committed to the repo:

| Script | What it does | Lifecycle stage |
|---|---|---|
| `Reset-LabPassword.ps1` | Reset a password, force change at next logon, unlock the account | Maintain |
| `Disable-LabUser.ps1` | Disable a departed user, stamp the date, move to a holding OU | Deprovision |
| `Get-LabUserReport.ps1` | Export enabled users to CSV; flag accounts that never logged on | Audit / report |

Together with the Stage 8 bulk-provisioning script (`New-LabUsers.ps1` + `newusers.csv`), the `scripts\` folder now tells a complete **identity lifecycle** story: **provision → maintain → deprovision → audit.**

---

## Part 1 — Build Walkthrough

### 10.0 — Environment setup

Authored everything in **Windows PowerShell ISE** on DC01 (pre-installed on Server 2025; script pane on top, live console below — author and test in one window). Ran ISE as Administrator, since these cmdlets modify directory objects.

Two checks before writing a line:

```powershell
Get-ExecutionPolicy -List
```

The `LocalMachine` scope was already `RemoteSigned` — Server 2025's out-of-the-box default — so **no change was needed**. Local scripts run; unsigned scripts pulled from elsewhere are blocked.

> **Note for interviews:** Execution policy is a guardrail against *accidents*, not a security boundary. It's trivially bypassed (e.g. `-ExecutionPolicy Bypass`), so it should never be described as "securing PowerShell." The scopes are a precedence stack evaluated top-down (MachinePolicy → UserPolicy → Process → CurrentUser → LocalMachine); the effective policy is the first non-`Undefined` one — the same precedence shape as GPO LSDOU from Stage 9.

```powershell
Import-Module ActiveDirectory
Get-Command -Module ActiveDirectory | Measure-Object
```

Returned **151 cmdlets** — the same RSAT ActiveDirectory module that lit up when the DC was promoted. Every script below depends on it.

### 10.1 — Reset-LabPassword.ps1

The single most common help desk task — reset, force change, unlock — in one script.

```powershell
# Reset-LabPassword.ps1
# Resets a domain user's password, forces a change at next logon, and unlocks the account.

Import-Module ActiveDirectory

$user = Read-Host "SamAccountName to reset (e.g. jane.doe)"
$pwd  = Read-Host "New temporary password" -AsSecureString

try {
    Set-ADAccountPassword -Identity $user -Reset -NewPassword $pwd -ErrorAction Stop
    Set-ADUser            -Identity $user -ChangePasswordAtLogon $true
    Unlock-ADAccount      -Identity $user
    Write-Host "Reset complete for $user" -ForegroundColor Green
}
catch {
    Write-Host "Reset FAILED for $user : $($_.Exception.Message)" -ForegroundColor Red
}
```

**Cmdlet → GUI mapping** (so I can explain it cold):

| Cmdlet | ADUC equivalent |
|---|---|
| `Set-ADAccountPassword -Reset` | Right-click user → Reset Password |
| `Set-ADUser -ChangePasswordAtLogon $true` | "User must change password at next logon" checkbox |
| `Unlock-ADAccount` | "Unlock account" box on the Account tab |

**Two deliberate design choices:**

- **`Read-Host -AsSecureString`** instead of the guide's hardcoded plaintext password. A plaintext credential committed to a public repo is a real-world security smell; prompting at runtime keeps secrets out of source control. (Security+: credential handling.)
- **`-ChangePasswordAtLogon $true`** means even the admin doesn't know the user's permanent password — the user sets it themselves at first login. (Security+: least privilege, supports non-repudiation.)

**End-to-end verification** — a green line on the DC only proves the *cmdlet didn't error*. The real test was on CLIENT01: logged in as `CORP\jane.doe` with the temp password and got the **"The user's password must be changed before signing in"** prompt, confirming the whole chain — authentication via Kerberos, plus `-ChangePasswordAtLogon` — actually fired on a separate machine. 📸 `10-02-forced-password-change-client01.png`

### 10.2 — Disable-LabUser.ps1 (offboarding)

The mirror of onboarding. First created the holding OU — via PowerShell, fittingly for an automation stage, and the first OU built scripted rather than in ADUC:

```powershell
New-ADOrganizationalUnit -Name "Disabled" -Path "OU=CORP,DC=corp,DC=lab" -ProtectedFromAccidentalDeletion $true
```

Confirmed it landed before targeting it (never trust a silent `New-AD*` cmdlet):

```powershell
Get-ADOrganizationalUnit -Filter 'Name -eq "Disabled"' | Select-Object Name,DistinguishedName
# -> OU=Disabled,OU=CORP,DC=corp,DC=lab
```

📸 `10-04-disabled-ou-created.png`

The offboarding script:

```powershell
# Disable-LabUser.ps1
# Offboards a departed employee: disables the account, timestamps why, and
# moves it to the Disabled OU so it's out of the active tree but auditable.

Import-Module ActiveDirectory

$user = Read-Host "SamAccountName to offboard (e.g. mark.lopez)"

try {
    $account = Get-ADUser -Identity $user -ErrorAction Stop

    Disable-ADAccount -Identity $user
    Set-ADUser -Identity $user -Description "Disabled $(Get-Date -Format yyyy-MM-dd) - offboarded"
    Move-ADObject -Identity $account.DistinguishedName -TargetPath "OU=Disabled,OU=CORP,DC=corp,DC=lab"

    Write-Host "Offboarded $user - disabled, stamped, moved to Disabled OU" -ForegroundColor Green
}
catch {
    Write-Host "Offboard FAILED for $user : $($_.Exception.Message)" -ForegroundColor Red
}
```

**The principle that matters most: disable, don't delete.** Disabling kills the login but keeps the object — its SID, group memberships, and file-ownership history stay intact, which preserves the audit trail and lets you answer "what did this person have access to?" later. Deletion (if ever) happens weeks later after review, never as step one.

Three actions, in order:
1. **Disable** (`Disable-ADAccount`) — revoke access immediately.
2. **Stamp** (`Set-ADUser -Description` with `Get-Date -Format yyyy-MM-dd`) — dated note so anyone in ADUC later knows when and why. Documentation as a detective aid.
3. **Move** (`Move-ADObject`, operating on the `DistinguishedName`) — park it in `OU=Disabled` to keep active OUs clean and give review/cleanup a single target.

The leading `Get-ADUser ... -ErrorAction Stop` does double duty: fetches the DN needed for the move, and fails fast on a typo'd username so you can't half-offboard a nonexistent account.

**Tested on `mark.lopez`** (a Stage 8 CSV-provisioned Sales user). Verification:

```powershell
Get-ADUser mark.lopez -Properties Enabled,Description | Select-Object Name,Enabled,Description,DistinguishedName
```

Returned `Enabled : False`, the dated `Disabled 2026-06-15 - offboarded` description, and a DN now reading `...OU=Disabled,OU=CORP,...` — all three actions confirmed. 📸 `10-05-offboard-mark-lopez.png`

### 10.3 — Get-LabUserReport.ps1 (reporting)

```powershell
# Get-LabUserReport.ps1
# Two inventory reports: all enabled users to CSV, and accounts that never logged on.

Import-Module ActiveDirectory

# Report 1: every enabled user, with department and last logon, to CSV
Get-ADUser -Filter 'Enabled -eq $true' -Properties Department,LastLogonDate |
    Select-Object Name,SamAccountName,Department,LastLogonDate |
    Export-Csv "$HOME\Documents\user_report.csv" -NoTypeInformation

Write-Host "Enabled-user report written to Documents\user_report.csv" -ForegroundColor Green

# Report 2: accounts that have never logged on (potential stale/unused accounts)
Write-Host "`nAccounts that have never logged on:" -ForegroundColor Cyan
Search-ADAccount -AccountInactive -UsersOnly |
    Select-Object Name,LastLogonDate
```

**Things worth understanding here:**

- **`-Filter 'Enabled -eq $true'`** filters *server-side* — AD only returns matching accounts rather than dumping everyone for local filtering. On a real domain of thousands of users that's a major efficiency difference. Single quotes because the filter is evaluated by AD, not PowerShell.
- **`-Properties Department,LastLogonDate`** is mandatory to get those columns — `Get-ADUser` returns only a small default attribute set, so anything else must be requested explicitly or it comes back blank. (Common gotcha.)
- **`Search-ADAccount -AccountInactive`** is purpose-built for stale-account hunting.

**The skill is interpreting the output, not just running it.** The "never logged on" list included `krbtgt` and `Guest`. Those are **expected built-ins, not findings** — `krbtgt` is the Kerberos service account that never logs in interactively by design (its hash signs every ticket in the domain), and `Guest` is disabled by default. In a real audit you'd recognize and exclude them. The genuine signal is dormant *user* accounts: `mark.lopez`, `amy.chen`, `raj.patel` showed as never-logged-on, which weeks after creation would be a legitimate "are these still needed?" question. (Security+: dormant accounts are attack surface.)

The two reports cross-checked cleanly — `mark.lopez` appeared in the stale list but was **absent** from the enabled-users CSV, because he'd just been disabled by the offboarding script. Consistent data, not staged. 📸 `10-06-user-inventory-report.png`

All three scripts plus the Stage 8 artifacts now live in `D:\AD Lab\active-directory-home-lab\scripts\`.

---

## Part 2 — Troubleshooting Case Study: "The Script That Lied"

> A standalone root-cause walkthrough. This is the most valuable thing I learned in Stage 10, and it's a genuine production-grade lesson, not a lab artifact.

### Symptom

The very first run of `Reset-LabPassword.ps1` produced **contradictory output**: a red error from `Set-ADAccountPassword` saying the password *"does not meet the length, complexity, or history requirement of the domain,"* immediately followed by a **green "Reset complete for jane.doe."** The script claimed success on an operation that had just failed. 📸 `10-01-reset-password-script-error-handling.png` (before/after)

### Root cause — two layers

**Layer 1 (working as designed):** The temporary password I entered was too weak — under 14 characters — and was correctly rejected by the **domain password policy I built in Stage 9** (14-char minimum, complexity enabled). This part was the lab working *correctly*: the policy did its job.

**Layer 2 (the actual bug):** By default, a failed cmdlet like this throws a **non-terminating** error — it complains but the script keeps executing. So after line 1 failed, the script ran right on through `Unlock-ADAccount` and the final `Write-Host`, printing false success. **The script reported a result that never happened.** The password was never changed, but the output said it was. In production that's worse than a crash, because it hides a failure behind a green light.

### Fix

Promote the error to **terminating** with `-ErrorAction Stop`, and wrap the operations in **`try/catch`** so a failure is caught and reported honestly:

```powershell
try {
    Set-ADAccountPassword -Identity $user -Reset -NewPassword $pwd -ErrorAction Stop
    ...
    Write-Host "Reset complete for $user" -ForegroundColor Green
}
catch {
    Write-Host "Reset FAILED for $user : $($_.Exception.Message)" -ForegroundColor Red
}
```

After the fix, two clean runs proved the behavior: a weak password produced **only** a red, honest failure (no false green); a policy-compliant password (14+ chars, full complexity) produced **only** green success. The script now fails loudly or succeeds cleanly — never both.

### Lesson

**Fail loudly, not silently.** A script that lies about its own success will eventually corrupt state quietly and cost hours to trace. Defaulting to `-ErrorAction Stop` + `try/catch` for any state-changing operation is the difference between a script you'd trust in production and one you wouldn't. (Security+ framing: integrity of operations and reliable logging — a control is worthless if it reports success while doing nothing.)

---

## Stage 10 Checklist

- [x] Execution policy verified (`RemoteSigned`, no change needed)
- [x] ActiveDirectory module confirmed (151 cmdlets)
- [x] `Reset-LabPassword.ps1` — built, error-handled, verified end-to-end on CLIENT01
- [x] `OU=Disabled` created via PowerShell and confirmed
- [x] `Disable-LabUser.ps1` — built and verified (disabled, stamped, moved)
- [x] `Get-LabUserReport.ps1` — built; CSV + stale-account report verified and interpreted
- [x] All scripts committed to repo `scripts\` folder
- [ ] Snapshot both VMs as `06a-stage10-automation-done`

---

*Stage 10 complete. The lab build is finished; remaining work is documentation (README, hardening checklist) and the companion teaching document.*
