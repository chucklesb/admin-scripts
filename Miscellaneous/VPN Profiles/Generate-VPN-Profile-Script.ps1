## Generate-VPN-Profile-Script.ps1
#
# Generate a VPN profile creation script. The generated script creates a VPN profile under the current user.
#


# Prompt for client name and VPN location. Build VPN connection name based on these values.
while ( [string]::IsNullOrWhitespace($clientName) ) { $clientName = Read-Host "Enter the client's name" }
$vpnLocation = Read-Host "Enter the VPN site location (optional)"
if ( -not $vpnLocation ) {
	$name = $clientName
} else {
	$name = "$clientName ($vpnLocation)"
}

# Prompt for VPN server address
while ( [string]::IsNullOrWhitespace($serverAddress) ) { $serverAddress = Read-Host "Enter the VPN server address" }

# Prompt for pre-shared key. Generate a key if not provided.
$vpnPreSharedKey = Read-Host "Enter the VPN pre-shared key (optional)"
if ( -not $vpnPreSharedKey ) { $vpnPreSharedKey = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 20 | % {[char]$_}) }

# Base64 encode PSK
$b64PSK = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($vpnPreSharedKey))

# Prompt for DNS suffix
while ( [string]::IsNullOrWhitespace($dnsSuffix) ) { $dnsSuffix = Read-Host "Enter the domain DNS suffix" }

# Prompt for split or full tunnel
$splitTunneling = Read-Host "Would you like to enable split-tunneling? [y/N]"
if ($splitTunneling -eq 'y') {
	$splitTunneling = $True

	# Prompt for destination subnets
	$destinationPrefixes = @()
	while ( [string]::IsNullOrWhitespace($subnet) ) { $subnet = Read-Host "Enter remote destination subnet in CIDR notation" }
	$destinationPrefixes += $subnet
	do {
		$subnet = ( Read-Host "Enter additional remote destination subnet in CIDR notation (optional)" )
		if ( -not [string]::IsNullOrWhitespace($subnet) ) { $destinationPrefixes += $subnet }
	} until ( [string]::IsNullOrWhitespace($subnet) )
	
} else {
	$splitTunneling = $False
}


# Write resulting script
$scriptOutputFile = $pwd.Path + '\Add-VpnConnection.' + $name.Replace(' ', '.') + '.ps1'

@'
## Add-VpnConnection.ps1
#
# Add user VPN connection including pre-shared key
#


'@ + @"
###########
## variables
`$name = "$name"
`$serverAddress = "$serverAddress"
`$tunnelType = "L2tp"
`$splitTunneling = `$$splitTunneling
`$encryptionLevel = "Optional"
`$l2tpPsk = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String("$b64PSK"))
`$dnsSuffix = "$dnsSuffix"
`$authenticationMethod = "Pap"
`$rememberCredential = `$True
`$strDestinationPrefixes = "$destinationPrefixes"
`$rasphoneConfiguration = `$env:APPDATA + '\Microsoft\Network\Connections\Pbk\rasphone.pbk'
`$logPath = `$env:TEMP + '\Add-VpnConnection.log'
"@ + @'


###########
## logging

function printAndLog([string]$message) {
	$timestamp = Get-Date -f 'yyyy-MM-dd HH:mm:ss - '
	$message = '[INFO]  ' + $timestamp + $message
	Add-Content $logPath $message
	Write-Host $message
}

function printAndLogError([string]$message) {
	$timestamp = Get-Date -f 'yyyy-MM-dd HH:mm:ss - '
	$message = '[ERROR] ' + $timestamp + $message + ": $_"
	Add-Content $logPath $message
	Write-Host $message
	Write-Error "$_" -ErrorAction Stop
}

###########
## main

$m = "Script initialized. Logging to $logPath."
printAndLog($m)

# Check for existing VPN profile
$vpnObjectsCurrentUser = Get-VpnConnection -ErrorAction SilentlyContinue
$vpnObjectsAllUsers = Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue
$vpnConnectionExists = $False
foreach ( $vpnObjectCurrentUser in $vpnObjectsCurrentUser ) {
	if ( $vpnObjectCurrentUser.ServerAddress -eq $serverAddress ) {
		$vpnConnectionExists = $True
	}
}

foreach ( $vpnObjectAllUsers in $vpnObjectsAllUsers ) {
	if ( $vpnObjectAllUsers.ServerAddress -eq $serverAddress ) {
		$vpnConnectionExists = $True
	}
}

if ( -not $vpnConnectionExists ) {
	$m = 'Creating VPN profile.'
	printAndLog($m)

	if ( $splitTunneling ) {
		try {
			Add-VpnConnection -SplitTunneling -Force `
				-Name "$name" `
				-ServerAddress "$serverAddress" `
				-TunnelType "$tunnelType" `
				-EncryptionLevel "$encryptionLevel" `
				-L2tpPsk "$l2tpPsk" `
				-DnsSuffix "$dnsSuffix" `
				-AuthenticationMethod "$authenticationMethod" `
				-RememberCredential:$rememberCredential `
				-WarningAction SilentlyContinue -ErrorAction Stop
		} catch {
			$m = 'Unable to create VPN profile'
			printAndLogError($m)
		}
		$destinationPrefixes = $strDestinationPrefixes -split ' '
		foreach ( $destinationPrefix in $destinationPrefixes ) {
			try {
				Add-VpnConnectionRoute -ConnectionName "$name" -DestinationPrefix $destinationPrefix -WarningAction SilentlyContinue -ErrorAction Stop
			} catch {
				$m = 'Unable to add VPN destination prefix route'
				printAndLogError($m)
			}
		}
	} else {
		try {
			Add-VpnConnection -Force `
				-Name "$name" `
				-ServerAddress "$serverAddress" `
				-TunnelType "$tunnelType" `
				-EncryptionLevel "$encryptionLevel" `
				-L2tpPsk "$l2tpPsk" `
				-DnsSuffix "$dnsSuffix" `
				-AuthenticationMethod "$authenticationMethod" `
				-RememberCredential:$rememberCredential `
				-WarningAction SilentlyContinue -ErrorAction Stop
		} catch {
			$m = 'Unable to create VPN profile'
			printAndLogError($m)
		}
	}

	# Set EncryptionLevel to Forced
	try {
		((Get-Content -Path "$rasphoneConfiguration" -WarningAction SilentlyContinue -ErrorAction Stop) -replace 'DataEncryption=8','DataEncryption=256') | `
			Set-Content -Path "$rasphoneConfiguration" -WarningAction SilentlyContinue -ErrorAction Stop
	} catch {
		$m = 'Unable to configure VPN encryption settings'
		printAndLogError($m)
	}

	# Skip credential prompt
	try {
		((Get-Content -Path "$rasphoneConfiguration" -WarningAction SilentlyContinue -ErrorAction Stop) -replace 'PreviewUserPw=1','PreviewUserPw=0') | `
			Set-Content -Path "$rasphoneConfiguration" -WarningAction SilentlyContinue -ErrorAction Stop
	} catch {
		$m = 'Unable to configure VPN credential settings'
		printAndLogError($m)
	}

	$m = "VPN profile $name created successfully"
	printAndLog($m)

} else {
	$m = 'VPN profile already exists'
	printAndLog($m)
}
'@ > $scriptOutputFile

try {
	[void](Get-Item -Path $scriptOutputFile -ErrorAction Stop)
	Write-Host "`r`nScript written to $($scriptOutputFile)`r`n"
	Start-Process -FilePath "C:\Windows\explorer.exe" -ArgumentList "/select, $($scriptOutputFile)"
	Read-Host "Press enter to exit"
} catch {
	Write-Host "Output file not found."
	Write-Error "$_" -ErrorAction Stop
}
