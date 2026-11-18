Import-Module ActiveDirectory
$users = Import-Csv .\newusers.csv

# Prompt once for the temporary password instead of hardcoding it — keeps the
# credential out of source control. Must meet the domain policy (14+ chars,
# complexity enabled) or New-ADUser will reject it at account creation.
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