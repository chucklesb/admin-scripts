## cwdeploy.ps1
#
# Deploy ConnectWise Automate
#


###########
## tls settings
IF([Net.SecurityProtocolType]::Tls) {[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls}
IF([Net.SecurityProtocolType]::Tls11) {[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls11}
IF([Net.SecurityProtocolType]::Tls12) {[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12}


###########
## variables
$tempPath = [System.Environment]::GetEnvironmentVariable('TEMP','Machine')
$logPath = $tempPath + '\cwdeploy.log'
$automateServerURL = ''
$automateInstallerToken = ''
$automateLocationID = ''


###########
## functions
function printAndLog([string]$message) {
    $timestamp = Get-Date -f 'yyyy-MM-dd HH:mm:ss - '
    $message = $timestamp + $message
    Write-Host $message
    Add-Content $logPath $message
}


###########
## main
$m = 'Starting cwdeploy.'
printAndLog($m)

## Install Automate agent

$WarningPreference='SilentlyContinue'
(New-Object Net.WebClient).DownloadString('http://bit.ly/LTPoSh') | iex

$LTServiceInfo = Get-LTServiceInfo
$isAutomateServerURLPresent = $false

foreach ( $automateServer in $LTServiceInfo.Server ) {
	if ( $automateServer -eq $automateServerURL ) {
		$isAutomateServerURLPresent = $true
	}
}
if ($false -eq $isAutomateServerURLPresent) {
    $m = 'Reinstalling Automate agent.'
    printAndLog($m)
    Reinstall-LTService -SkipDotNet -Server $automateServerURL -LocationID $automateLocationID -InstallerToken $automateInstallerToken
}

$m = 'cwdeploy finished.'
printAndLog($m)
