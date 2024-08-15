## AD-Get-Active-Users-Computers.ps1
#
# Export list of AD Users and Computers and print stats
#

#### START ELEVATE TO ADMIN #####
param(
    [Parameter(Mandatory=$false)]
    [switch]$shouldAssumeToBeElevated,

    [Parameter(Mandatory=$false)]
    [String]$workingDirOverride
)

if(-not($PSBoundParameters.ContainsKey('workingDirOverride')))
{
    $workingDirOverride = (Get-Location).Path
}

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# If we are in a non-admin execution. Execute this script as admin
if ((Test-Admin) -eq $false)  {
    if ($shouldAssumeToBeElevated) {
        Write-Output "Unable to elevate to administrator privileges."

    } else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -shouldAssumeToBeElevated -workingDirOverride "{1}"' -f ($myinvocation.MyCommand.Definition, "$workingDirOverride"))
    }
    exit
}

Set-Location "$workingDirOverride"
#### END ELEVATE TO ADMIN #####

###########
## imports and methods
Import-Module ActiveDirectory
Import-Module Microsoft.PowerShell.Archive

###########
## variables
$tempPath = [System.Environment]::GetEnvironmentVariable('TEMP','Machine')
$outputPath = $tempPath + '\ad-export'

###########
## main

# Get AD users
$allUsers = Get-ADUser -Filter * -Properties LastLogonDate,CanonicalName,MemberOf
$enabledUsers = $allUsers | Where-Object {$_.Enabled -eq $true}
$disabledUsers = $allUsers | Where-Object {$_.Enabled -eq $false}
$activeUsers = $enabledUsers | Where-Object {$_.LastLogonDate -gt (Get-Date).AddDays(-30)}
$inactiveUsers = $enabledUsers | Where-Object {$_.LastLogonDate -lt (Get-Date).AddDays(-30)}

# Get AD computers
$allComputers = Get-ADComputer -Filter * -Properties LastLogonDate,CanonicalName,PrimaryGroup,MemberOf
$enabledComputers = $allComputers | Where-Object {$_.Enabled -eq $true}
$disabledComputers = $allComputers | Where-Object {$_.Enabled -eq $false}
$activeComputers = $enabledComputers | Where-Object {$_.LastLogonDate -gt (Get-Date).AddDays(-30)}
$inactiveComputers = $enabledComputers | Where-Object {$_.LastLogonDate -lt (Get-Date).AddDays(-30)}

# Print user stats
Write-Output "`n"
Write-Output "Number of users: $($allUsers.Count)"
Write-Output "Number of enabled users: $($enabledUsers.Count)"
Write-Output "Number of disabled users: $($disabledUsers.Count)"
Write-Output "Number of active users: $($activeUsers.Count)"
Write-Output "Number of inactive users: $($inactiveUsers.Count)"
Write-Output "`n"

# Print computer stats
Write-Output "Number of computers: $($allComputers.Count)"
Write-Output "Number of enabled computers: $($enabledComputers.Count)"
Write-Output "Number of disabled computers: $($disabledComputers.Count)"
Write-Output "Number of active computers: $($activeComputers.Count)"
Write-Output "Number of inactive computers: $($inactiveComputers.Count)"
Write-Output "`n"

# Export data as CSV
if (-Not (Test-Path $outputPath)) { New-Item $outputPath -ItemType Directory }
$allUsers | Select-Object Name,SamAccountName,CanonicalName,Enabled,LastLogonDate,@{n='MemberOf'; e= { ( $_.memberof | % { (Get-ADObject $_).Name }) -join ", " }} | Export-CSV -NoTypeInformation $outputPath\All-Users.csv
$inactiveUsers | Select-Object Name,SamAccountName,CanonicalName,Enabled,LastLogonDate,@{n='MemberOf'; e= { ( $_.memberof | % { (Get-ADObject $_).Name }) -join ", " }} | Export-CSV -NoTypeInformation $outputPath\Inactive-Users.csv
$allComputers | Select-Object Name,CanonicalName,Enabled,LastLogonDate,PrimaryGroup,@{n='MemberOf'; e= { ( $_.memberof | % { (Get-ADObject $_).Name }) -join ", " }} | Export-CSV -NoTypeInformation $outputPath\All-Computers.csv
$inactiveComputers | Select-Object Name,CanonicalName,Enabled,LastLogonDate,PrimaryGroup,@{n='MemberOf'; e= { ( $_.memberof | % { (Get-ADObject $_).Name }) -join ", " }} | Export-CSV -NoTypeInformation $outputPath\Inactive-Computers.csv

# Compress to archive
Compress-Archive -Path $outputPath\* -DestinationPath $tempPath\ad-export.zip -Force | Out-Null
Write-Output "Data exported to $($tempPath)\ad-export.zip`n"
