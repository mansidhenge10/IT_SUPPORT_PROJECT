# Get-LabUserReport.ps1
# Two quick inventory reports: all enabled users exported to CSV.
# and a check for accounts that have never logged on.

Import-Module ActiveDirectory

# Report 1: every enabled user, with department and last logon, to CSV
Get-ADUser -Filter 'Enabled -eq $true' -Properties Department,LastLogonDate |
    Select-Object Name,SamAccountName,Department,LastLogonDate |
    Export-Csv "$HOME\Documents\user_report.csv" -NoTypeInformation

Write-Host "Enabled-user report written to Documents\user_report.csv" -ForegroundColor Green

# Report 2: accounts that have never logged on (potential stake/unused accounts)
Write-Host "`nAccounts that have never logged on:" -ForegroundColor Cyan
Search-ADAccount -AccountInactive -UsersOnly |
    Select-Object Name,LastLogonDate