## bootstrap.ps1
#
# Build cwdeploy.ps1 script and configure deployment GPO
#


###########
## Privilege elevation

param(
	[Parameter(Mandatory=$false)]
	[switch]$shouldAssumeToBeElevated,

	[Parameter(Mandatory=$false)]
	[String]$workingDirOverride
)

# Get the current working directory
if(-not($PSBoundParameters.ContainsKey('workingDirOverride')))
{
	$workingDirOverride = (Get-Location).Path
}

# Check if we are already elevated
function Test-Admin {
	Write-Host "Checking for elevated privileges.`r`n"
	$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
	$currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Attempt to elevate
if ((Test-Admin) -eq $false)  {
	if ($shouldAssumeToBeElevated) {
		Write-Host "Unable to elevate privileges."
		Write-Error "$_" -ErrorAction Stop
	} else {
		Write-Host "Attempting elevation.`r`n"
		Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -shouldAssumeToBeElevated -workingDirOverride "{1}"' -f ($myinvocation.MyCommand.Definition, "$workingDirOverride"))
	}
	exit
}

# Set the correct working directory
Set-Location "$workingDirOverride"


###########
# Check that we are running on a domain controller
$OperatingSystem = Get-WmiObject -Class Win32_OperatingSystem
if ($OperatingSystem.ProductType -ne 2) {
#	Write-EventLog -LogName "Application" -Source "cwdeploy-bootstrap" -EventID 100 -EntryType Error -Message "This script must be run on a domain controller."
	Write-Host "This script must be run on a domain controller."
	Write-Host
	Write-Error "$_" -ErrorAction Stop
}


###########
## imports and methods
Write-Host "Importing required modules.`r`n"
try {
	Import-Module ActiveDirectory -ErrorAction Stop
	Import-Module GroupPolicy -ErrorAction Stop
} catch {
	Write-Host "Unable to import required PowerShell modules."
	Write-Error "$_" -ErrorAction Stop
}


###########
## variables
$sysvolPath = ((Get-SmbShare -Name 'SYSVOL').Path + '\' + $Env:userdnsdomain + '\scripts')
$scriptPath = $pwd.Path + '\res\cwdeploy.ps1'
$clientsPath = $pwd.Path + '\res\clients.csv'
$automatePath = $pwd.Path + '\res\automate.csv'
$scriptPathReplace = $sysvolPath + '\cwdeploy.ps1'
$gpoPath = $pwd.Path + '\res\gpo'
$gpoName = 'ConnectWise Automate Deployment'
$ADDistinguishedName = (Get-ADDomain).DistinguishedName


###########
## main

# Verify paths
Write-Host "Verifying paths and resources.`r`n"
$verifyPaths = @("$($sysvolPath)","$($clientsPath)","$($automatePath)","$($scriptPath)","$($gpoPath)")
foreach ($path in $verifyPaths) {
	try { 
		[void](Get-Item -Path $path -ErrorAction Stop)
	} catch { 
		Write-Host "Path not found: $($path)"
		Write-Error "$_" -ErrorAction Stop
	}
}

# Identify GPO backups by name and GUID
$gpoBackups = Get-ChildItem -Recurse -Include backup.xml $gpoPath
foreach ( $gpoBackup in $gpoBackups ) {
	$guid = $gpoBackup.Directory.Name
	$displayName = ([xml](Get-Content $gpoBackup)).GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.DisplayName.InnerText
	if ( $displayName -eq $gpoName ) {
		$gpoGUID = $guid
		break
	}
}
if ( $null -eq $gpoGUID ) {
	Write-Host "Error: Unable to locate GPO backup"
	Write-Host
	Write-Error "Unable to locate GPO backup" -ErrorAction Stop
}

# Import Automate servers
try {
	$automates = @(Import-CSV -Path $automatePath -ErrorAction Stop)
} catch {
	Write-Host "Unable to import Automate server configuration."
	Write-Error "$_" -ErrorAction Stop
}
if ( $automates.Count -lt 1 ) {
	Write-Host "No Automate servers found."
	Write-Error "$_" -ErrorAction Stop
}
if ( $automates.Count -eq 1 ) {
	$automate = $automates[0]
} else {
	while (-not ($selection -In 1..$automates.Count)) {
		Write-Host "`r`nSelect the Automate server:`r`n"
		foreach ($automate in $automates) { "$([string]($automates.IndexOf($automate)+1)). $($automate.ServerURL) ($($automate.InstallerToken), expires $($automate.ExpirationDate))" }
		[uint16]$selection = Read-Host -Prompt "Enter a selection [1..$($automates.Count)]"
	}
	$automate = $automates[$selection-1]
	Remove-Variable selection
}
if ( $null -eq $automate.ServerURL ) {
	Write-Host "Unable to get Automate server URL."
	Write-Error "$_" -ErrorAction Stop
}
if ( $null -eq $automate.InstallerToken ) {
	Write-Host "Unable to get Automate installer token."
	Write-Error "$_" -ErrorAction Stop
}
# Check expiration here

# Import clients
try {
	$clients = @(Import-CSV -Path $clientsPath -ErrorAction Stop)
} catch {
	Write-Host "Unable to import client list."
	Write-Error "$_" -ErrorAction Stop
}
if ( $clients.Count -lt 1 ) {
	Write-Host "No clients found."
	Write-Error "$_" -ErrorAction Stop
}
if ( $clients.Count -eq 1 ) {
	$client = $clients[0]
} else {
	while (-not ($selection -In 1..$clients.Count)) {
		Write-Host "`r`nSelect the client:`r`n"
		foreach ($client in $clients) { "$([string]($clients.IndexOf($client)+1)). $($client.Name)" }
		[uint16]$selection = Read-Host -Prompt "Enter a selection [1..$($clients.Count)]"
	}
	$client = $clients[$selection-1]
	Remove-Variable selection
}
if ( $null -eq $client.AutomateLocationID ) {
	Write-Host "Unable to get client's Automate location ID."
	Write-Error "$_" -ErrorAction Stop
}

# Define find and replace strings
$strFindAutomateServerURL = '^\$automateServerURL = .*'
$strReplaceAutomateServerURL = '$automateServerURL = "' + $automate.ServerURL + '"'
$strFindAutomateInstallerToken = '^\$automateInstallerToken = .*'
$strReplaceAutomateInstallerToken = '$automateInstallerToken = "' + $automate.InstallerToken + '"'
$strFindClientAutomateLocationID = '^\$automateLocationID = .*'
$strReplaceClientAutomateLocationID = '$automateLocationID = "' + $client.AutomateLocationID + '"'

# Find and replace strings and place the script in SYSVOL path
Write-Host "`r`nGenerating deployment script.`r`n"
try {
	((Get-Content -Path $scriptPath) `
	-Replace $strFindAutomateServerURL,$strReplaceAutomateServerURL `
	-Replace $strFindAutomateInstallerToken,$strReplaceAutomateInstallerToken `
	-Replace $strFindClientAutomateLocationID,$strReplaceClientAutomateLocationID) | `
	Set-Content -Path $scriptPathReplace -ErrorAction Stop
} catch {
	Write-Host "Error writing deployment script."
	Write-Error "$_" -ErrorAction Stop
}

# Create GPO
# Requirements for Import-GPO:
# Backup.xml
# 	 \temp\Level-Temp{920B8A43-A054-4C44-B126-1E057DFFBC4C}\Backup.xml
# bkupInfo.xml
# 	\temp\Level-Temp{920B8A43-A054-4C44-B126-1E057DFFBC4C}\bkupInfo.xml
# ScheduledTasks.xml
# 	\temp\Level-Temp{920B8A43-A054-4C44-B126-1E057DFFBC4C}\DomainSysvol\GPO\Machine\Preferences\ScheduledTasks\ScheduledTasks.xml
Write-Host "Creating group policy object.`r`n"
try {
	$gpoObject = Import-GPO -BackupId $gpoGUID -Path $gpoPath -TargetName "$gpoName" -CreateIfNeeded -ErrorAction Stop
} catch {
	Write-Host "Error creating group policy object."
	Write-Error "$_" -ErrorAction Stop
}

# Link GPO
$confirmLink = Read-Host -Prompt "Would you like to link the newly created GPO? [y/n]"
if ( $confirmLink -eq 'y' ) { 
	try {
		Write-Host "`r`nLinking group policy object.`r`n"
		$gpoObject | New-GPLink -Target $ADDistinguishedName -ErrorAction Stop
	} catch {
		Write-Host "Error linking group policy object."
		Write-Error "$_" -ErrorAction Stop
	}
}

Write-Host "`r`nScript completed successfully!`r`n"
