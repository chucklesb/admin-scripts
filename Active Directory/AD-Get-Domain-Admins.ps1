## AD-Get-Domain-Admins.ps1
#
# Print list of AD domain admins
#

Import-Module ActiveDirectory

$tempPath = $ENV:temp
$logPath = $tempPath + "\AD-Active-Domain-Admins.log"

# Old query; only enumerates the Domain Admins group
# Get-ADGroupMember -Identity 'Domain Admins' -Recursive | Where {$_.objectClass -eq 'user'} | Get-ADUser | Where {$_.Enabled} | Select Name,SamAccountName | Out-File $logPath

# New query; enumerates all domain admin groups
Get-ADGroup -Filter {(Name -eq "Domain Admins" -or Name -eq "Enterprise Admins" -or Name -eq "Administrators" -or Name -eq "Schema Admins")} | 
	Get-ADGroupMember -Recursive | 
	Where-Object { $_.objectClass -eq "User" } | 
	Get-ADUser -Properties * | 
	Where-Object { $_.enabled -eq $True } | 
	Select-Object SamAccountName,MemberOf -Unique |
	Out-File $logPath

type $logPath