## Sync-AD-and-Azure.ps1
#
# Forces inter-site AD replication and triggers an Azure AD delta sync. Make sure to edit the $ADConnectServer variable to reflect your environment.
# 
# TODO: Dynamically get $ADConnectServer value
#

# Variables
$ADConnectServer = 'AD-CONNECT'

# Force inter-site AD replication
Write-Host "`nSynchronizing all domain controllers with their replication partners.`n"
(Get-ADDomainController -Filter *).Name | Foreach-Object { repadmin /syncall $_ (Get-ADDomain).DistinguishedName /AdeP }

# Wait for replication to finish
Write-Host "`nWaiting 10 seconds before continuing...`n"
Start-Sleep -Seconds 10

# Trigger Azure AD delta sync
Write-Host "`nRunning an Azure AD Connect delta synchronization.`n"
Invoke-Command -ComputerName $ADConnectServer -ScriptBlock { Start-ADSyncSyncCycle -PolicyType Delta }
