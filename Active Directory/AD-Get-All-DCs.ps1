## AD-Get-All-DCs.ps1
#
# Print list of AD domain controllers
#

Get-ADDomainController -filter * | Select-Object name
