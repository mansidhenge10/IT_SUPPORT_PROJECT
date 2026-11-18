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