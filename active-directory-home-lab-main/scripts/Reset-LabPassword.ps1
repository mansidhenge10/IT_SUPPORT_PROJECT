# Reset-LabPassword.ps1
# Resets a domain user's password, forces a change at next logon, and unlocks the account.
Import-Module ActiveDirectory

$user = Read-Host "SamAccountName to reset (e.g. jane.doe)"
$pwd = Read-Host "New temporary password" -AsSecureString

try {
    Set-ADAccountPassword -Identity $user -Reset -NewPassword $pwd -ErrorAction Stop
    Set-ADUser -Identity $user -ChangePasswordAtLogon $true
    Unlock-ADAccount -Identity $user
    Write-Host "Reset complete for $user" -ForegroundColor Green
    }
catch {
    Write-Host "Reset FAILED for $user : $($_.Exception.Message)" -ForegroundColor Red
    }