## AD-Get-FSMO-Role-Holders.ps1
#
# Print list of AD FSMO role holders
#

Get-ADDomain | Select-Object InfrastructureMaster, RIDMaster, PDCEmulator
Get-ADForest | Select-Object DomainNamingMaster, SchemaMaster
Get-ADDomainController -Filter * | `
    Select-Object Name, Domain, Forest, OperationMasterRoles | `
    Where-Object {$_.OperationMasterRoles} | `
    Format-Table -AutoSize
