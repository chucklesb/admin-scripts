## Generate-VPN-Profile-Script-Shared.ps1
#
# Generate a VPN profile creation script. The generated script creates a shared VPN profile accessible to all users (requires elevation).
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
# Add VPN connection including pre-shared key
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
`$rasphoneConfiguration = `$env:ALLUSERSPROFILE + '\Microsoft\Network\Connections\Pbk\rasphone.pbk'
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
			Add-VpnConnection -AllUserConnection -SplitTunneling -Force `
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
			Add-VpnConnection -AllUserConnection -Force `
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

# SIG # Begin signature block
# MIIJAAYJKoZIhvcNAQcCoIII8TCCCO0CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBKntFn66S6t/W4
# +KLHiGqcRXo3V7ecdDMi1P4Gs78DkKCCBiwwggYoMIIFEKADAgECAhNSAAAAQuhS
# GCuOwrbKAAAAAABCMA0GCSqGSIb3DQEBCwUAMGExFTATBgoJkiaJk/IsZAEZFgVs
# b2NhbDETMBEGCgmSJomT8ixkARkWA3N3dDEzMDEGA1UEAxMqU3dlZXR3YXRlciBU
# ZWNobm9sb2d5IFNlcnZpY2VzIEludGVybmFsIENBMB4XDTIzMDUyNjE4MDgxNVoX
# DTI1MDUyNjE4MTgxNVowGjEYMBYGA1UEAxMPQ2hhcmxlcyBPZ2xlc2J5MIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2HtH2NJKydPo04oGc7DenmXk3eOG
# 487iYaBByu2ICayLcW832738t5jg5VyCf2YHW+IP5g/UAfgsgyg93dFHLbmPI4GW
# e9NQ7b9d12XGYbViluyszj9sog17r6LcWkc4iNitu4/78Vsa8RL16THd4DqinwB/
# yYpjj5n7QyCkHw+oZzw/QpszaunglOHGzt43zDWxB+fhvVLwuQvYEeTld4Cre+Lo
# iEo5cPTMMEVRcUyoUPGUlmHJqO5Fir1fbY3XPBe1MZI/CZGkQeLpy/g6bpwRAvfR
# fE5ezmzekRo9IPuDRfl20v7APL7jd/Pk/0vt4nwsGpnRGmIgoK26Pqyc8QIDAQAB
# o4IDHjCCAxowPAYJKwYBBAGCNxUHBC8wLQYlKwYBBAGCNxUIg6COboL9oAmGsZ0W
# g8ilf6n0HwCEqOVKhKn5AwIBZAIBBzATBgNVHSUEDDAKBggrBgEFBQcDAzAOBgNV
# HQ8BAf8EBAMCB4AwGwYJKwYBBAGCNxUKBA4wDDAKBggrBgEFBQcDAzAdBgNVHQ4E
# FgQUD/FwLGUyh/GVOINO7xhA74YCcEswHwYDVR0jBBgwFoAUudcI3zVuFfgInWv6
# PFjrnlZVWfcwgewGA1UdHwSB5DCB4TCB3qCB26CB2IaB1WxkYXA6Ly8vQ049U3dl
# ZXR3YXRlciUyMFRlY2hub2xvZ3klMjBTZXJ2aWNlcyUyMEludGVybmFsJTIwQ0Es
# Q049U1dUREMsQ049Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNl
# cnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9c3d0LERDPWxvY2FsP2NlcnRpZmlj
# YXRlUmV2b2NhdGlvbkxpc3Q/YmFzZT9vYmplY3RDbGFzcz1jUkxEaXN0cmlidXRp
# b25Qb2ludDCB4gYIKwYBBQUHAQEEgdUwgdIwgc8GCCsGAQUFBzAChoHCbGRhcDov
# Ly9DTj1Td2VldHdhdGVyJTIwVGVjaG5vbG9neSUyMFNlcnZpY2VzJTIwSW50ZXJu
# YWwlMjBDQSxDTj1BSUEsQ049UHVibGljJTIwS2V5JTIwU2VydmljZXMsQ049U2Vy
# dmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1zd3QsREM9bG9jYWw/Y0FDZXJ0aWZp
# Y2F0ZT9iYXNlP29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwNgYD
# VR0RBC8wLaArBgorBgEEAYI3FAIDoB0MG2NoYXJsZXNAc3dlZXR3YXRlci10ZWNo
# LmNvbTBMBgkrBgEEAYI3GQIEPzA9oDsGCisGAQQBgjcZAgGgLQQrUy0xLTUtMjEt
# MzE1NDQ4MjM4LTIxNTY1Mzc4MS0yODMyOTU4NzMtMjY4MTANBgkqhkiG9w0BAQsF
# AAOCAQEAviKMQTpYmm0yF6Qf4JeWMYUJpbhNYioN+Z+7dKH0kLr5okTsGY/H5lFs
# oPI/A2xqBY2/PsYmFEIXu1G2vve1Z4rNEmSAmYQJ7iE3J7Sfh8hGcSwxK5i2X8Gd
# GulEz5cEX7yjrSizEfMokm1oZjGBMKF7dilwLYTODkEXJSmmRyPUVXRrQ5Gz0iuR
# OCXiD6kXz3CfB4DhLZLly3ibKedV7bCeWxAFqhMSqDkNSm5e28JPJ52ZtI0wCoZU
# ue8aTonFB2VqjGgk1xFeKGK0Sfe8ZLgmXRF95DUQkxDd2UXTLketZRSVi3igkiR+
# Btp3AkGqlOpsega38Al6wPw5Yaw53DGCAiowggImAgEBMHgwYTEVMBMGCgmSJomT
# 8ixkARkWBWxvY2FsMRMwEQYKCZImiZPyLGQBGRYDc3d0MTMwMQYDVQQDEypTd2Vl
# dHdhdGVyIFRlY2hub2xvZ3kgU2VydmljZXMgSW50ZXJuYWwgQ0ECE1IAAABC6FIY
# K47CtsoAAAAAAEIwDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAig
# AoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgEL
# MQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg5k6FSK5XJI5TVzBPHAie
# EZ/McedbpFG6/XXIYja85JwwDQYJKoZIhvcNAQEBBQAEggEAnPtlG7cg3NoIES32
# Mr3u48X0Q8rU4p8jgoU07DNMABdBetA9AgSV4xCWj55NFYdXD+xIjnAGOjvAalG/
# BjHAe0VM6ME1U6Q8SHoPAEnztWnmBRASZLvvUA7QVdr+7I+EhD/BhKgty6ao5gGn
# PDYqKGg2fROs78zKaJx4c3L9XsGGosjP1aToMws4HgJPWwDlWnj6QYvHzNgXtOqg
# lyKZt9HmAaMsqjgFlBStomhi3nS/oLPJHgGk8ltDZCrmMhR7V/ZXAkeF5eUT/o5c
# 80jGLnE3JLADwM4R40iF+pyll9h0Z8lLGPYYmB/9wOMGzt8QirYkyMhD7S8BmGSa
# X+1Xrg==
# SIG # End signature block
