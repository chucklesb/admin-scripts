## Get-Installed-Roles.ps1
#
# Print installed server roles
# 

Get-WindowsFeature | Where-Object {$_.Installed -and $_.FeatureType -eq 'Role'}
