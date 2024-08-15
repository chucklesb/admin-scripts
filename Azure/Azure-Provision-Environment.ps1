@'
## Azure-Provision-Environment.ps1 - Create Azure resource group with vnet, gateway, VM, etc.
#
# This script will provision an Azure virtual environment. We'll start by
# gathering the client name and network address details. Work with your Network
# Engineer or Systems Administrator to plan network addressing.
#
'@


###########
## logging

# Suppress PowerShell console output, set log path, and formatting
function Out-Default {}
$logPath = $env:TEMP + '\Provision-Azure-Environment.log'

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


#############
## variables

# Define regex matching patterns
$patternNonalpha = '[^a-zA-Z]'
$patternIPV4 = '^((?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
$patternCIDR = '^((?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/(?:[0-9]|[1-2][0-9]|3[0-2])$'

# Get client's short name. Used when naming the Azure resources and certificates.
while ( [string]::IsNullOrWhitespace($clientName) ) {
    $clientName = Read-Host "`nEnter the client short name (e.g., ABC, Contoso)"
}
$clientname = $clientName -replace $patternNonalpha, ''

# Prompt for network address details
while ( $vnetAddressPrefix -notmatch $patternCIDR) {
    $vnetAddressPrefix = Read-Host "Enter the virtual network address space [10.1.0.0/16]"
    if ( -not $vnetAddressPrefix ) { $vnetAddressPrefix = '10.1.0.0/16' }
}
while ( $vmSubnetAddressPrefix -notmatch $patternCIDR) {
    $vmSubnetAddressPrefix = Read-Host "Enter the VM address space [10.1.0.0/24]"
    if ( -not $vmSubnetAddressPrefix ) { $vmSubnetAddressPrefix = '10.1.0.0/24' }
}
while ( $vpnSubnetAddressPrefix -notmatch $patternCIDR) {
    $vpnSubnetAddressPrefix = Read-Host "Enter the virtual gateway address space [10.1.255.0/24]"
    if ( -not $vpnSubnetAddressPrefix ) { $vpnSubnetAddressPrefix = '10.1.255.0/24' }
}
while ( $vpnClientAddressPool -notmatch $patternCIDR) {
    $vpnClientAddressPool = Read-Host "Enter the VPN client address space [172.16.201.0/24]"
    if ( -not $vpnClientAddressPool ) { $vpnClientAddressPool = '172.16.201.0/24' }
}
while ( $localNetworkGatewayIpAddress -notmatch $patternIPV4) {
    $localNetworkGatewayIpAddress = Read-Host "Enter the on-premise gateway IP"
}
$localNetworkGatewayAddressPrefix = @()
while ( $subnet -notmatch $patternCIDR ) { $subnet = Read-Host "Enter on-premise destination subnet" }
$localNetworkGatewayAddressPrefix += $subnet
do {
    $subnet = ( Read-Host "Enter additional on-premise destination subnet (optional)" )
    if ( -not [string]::IsNullOrWhitespace($subnet) ) { 
        if ( $subnet -match $patternCIDR ) { $localNetworkGatewayAddressPrefix += $subnet }
    }
} until ( [string]::IsNullOrWhitespace($subnet) )

# Naming conventions and Azure options
$resourceGroupName = $clientName + '-RG'
$resourceGroupLocation = 'West Central US'
$vnetName = $clientName + '-Azure'
$vmSubnetName = 'ResourceSubnet'
$vpnSubnetName = 'GatewaySubnet'
$vpnGatewayName = 'VPN-Gateway'
$vpnGatewayIPName = 'VPN-Gateway-IP'
$localNetworkGatewayName = 'Local-Gateway'
$vpnPublicIPName = 'VPN-Public-IP'
$vpnConnectionS2SName = 'S2S-Connection'
$rootCertName = $clientName + '-AzureP2SRootCert'
$clientCertName = $clientName + '-AzureP2SClientCert'
$clientCertDNSName = 'AzureP2SClientCert'

# Certificate options and password
$certExportLocation = $pwd.Path + '\private-key-export.pfx'
$certStoreName = 'cert:\currentuser\my'
$certValidMonths = 60
$certExportPassword = -join ((48..57) + (65..90) | Get-Random -Count 20 | % {[char]$_})

# Generate a preshared key for site-to-site VPN connection
$vpnPreSharedKey = -join ((48..57) + (65..90) | Get-Random -Count 20 | % {[char]$_})


########
## main

# Create VPN root certificate
Write-Host
$m = 'Creating VPN root certificate.'
printAndLog($m)

$argsRootCertificate = @{
    Type = 'Custom'
    KeySpec = 'Signature'
    Subject = "CN=$rootCertName"
    KeyExportPolicy = 'Exportable'
    HashAlgorithm = 'sha256'
    KeyLength = 2048
    CertStoreLocation = $certStoreName
    KeyUsageProperty = 'Sign'
    KeyUsage = 'CertSign'
    NotAfter = (Get-Date).AddMonths($certValidMonths)
}
try {
    $rootCertificate = New-SelfSignedCertificate @argsRootCertificate `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to create root certificate'
    printAndLogError($m)
}

# Create VPN client certificate
$m = 'Creating VPN client certificate.'
printAndLog($m)

$argsClientCertificate = @{
    Type = 'Custom'
    DnsName = $clientCertDNSName
    KeySpec = 'Signature'
    Subject = "CN=$clientCertName"
    KeyExportPolicy = 'Exportable'
    HashAlgorithm = 'sha256'
    KeyLength = 2048
    CertStoreLocation = $certStoreName
    Signer = $rootCertificate
    TextExtension = @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")
    NotAfter = (Get-Date).AddMonths($certValidMonths)
}
try {
    $clientCertificate = New-SelfSignedCertificate @argsClientCertificate `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to create client certificate'
    printAndLogError($m)
}

# Export the root certificate keys
$m = 'Exporting root certificate keys.'
printAndLog($m)

$rootCertificate | Export-PfxCertificate -FilePath $certExportLocation -Password ($certExportPassword | ConvertTo-SecureString -AsPlainText -Force)
$rootCertificateB64 = [Convert]::ToBase64String($rootCertificate.Export('Cert'))

# Connect to Azure PowerShell
Write-Host
Write-Host
$m = 'Connecting to Azure PowerShell. Sign in as the client''s Azure subscription owner.'
printAndLog($m)

try {
    Connect-AzAccount `
        -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
} catch {
    $m = 'Unable to connect to Azure PowerShell'
    printAndLogError($m)
}

# Create resource group
$m = 'Creating the Azure resource group.'
printAndLog($m)

$resourceGroup = @{
    Name = $resourceGroupName
    Location = $resourceGroupLocation
}
try {
    New-AzResourceGroup @resourceGroup `
        -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
} catch {
    $m = 'Unable to create the Azure resource group'
    printAndLogError($m)
}

# Create VM subnet
$m = 'Creating the Azure VM resource subnet.'
printAndLog($m)

$subnet = @{
    Name = $vmSubnetName
    AddressPrefix = $vmSubnetAddressPrefix
}
try {
    $vmSubnetConfig = New-AzVirtualNetworkSubnetConfig @subnet `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to create the Azure VM resource subnet'
    printAndLogError($m)
}

# Create VPN subnet
$m = 'Creating the Azure VPN subnet.'
printAndLog($m)

$subnet = @{
    Name = $vpnSubnetName
    AddressPrefix = $vpnSubnetAddressPrefix
}
try {
    $vpnSubnetConfig = New-AzVirtualNetworkSubnetConfig @subnet `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to create the Azure VPN subnet'
    printAndLogError($m)
}

# Create virtual network
$m = 'Creating the Azure virtual network.'
printAndLog($m)

$vnet = @{
    Name = $vnetName
    ResourceGroupName = $resourceGroupName
    Location = $resourceGroupLocation
    AddressPrefix = $vnetAddressPrefix
    Subnet = $vmSubnetConfig, $vpnSubnetConfig
}
try {
    $virtualNetwork = New-AzVirtualNetwork @vnet `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to create the Azure virtual network'
    printAndLogError($m)
}

# Create the local network gateway
$m = 'Creating the Azure local network gateway.'
printAndLog($m)

$argsLocalNetworkGateway = @{
    Name = $localNetworkGatewayName
    ResourceGroupName = $resourceGroupName
    Location = $resourceGroupLocation
    GatewayIpAddress = $localNetworkGatewayIpAddress
    AddressPrefix = $localNetworkGatewayAddressPrefix
}
try {
    $localNetworkGateway = New-AzLocalNetworkGateway @argsLocalNetworkGateway `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to create the Azure local network gateway'
    printAndLogError($m)
}

# Request an Azure public IP address
$m = 'Requesting an Azure public IP address.'
printAndLog($m)

$ip = @{
    Name = $vpnPublicIPName
    ResourceGroupName = $resourceGroupName
    Location = $resourceGroupLocation
    Sku = 'Basic'
    AllocationMethod = 'Dynamic'
    IpAddressVersion = 'IPv4'
}
try {
    $vpnPublicIP = New-AzPublicIpAddress @ip `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to obtain an Azure public IP address'
    printAndLogError($m)
}

# Set the Azure gateway IP configuration
$m = 'Setting the Azure gateway IP configuration.'
printAndLog($m)

$vpnSubnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $vpnSubnetName -VirtualNetwork $virtualNetwork
$vpnGatewayIP = @{
    Name = $vpnGatewayIPName
    Subnet = $vpnSubnetConfig
    PublicIpAddress = $vpnPublicIP
}
try {
    $vpnGatewayIPConfig = New-AzVirtualNetworkGatewayIpConfig @vpnGatewayIP `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to set the Azure gateway IP configuration'
    printAndLogError($m)
}

# Create the Azure VPN gateway
$m = 'Creating the Azure VPN gateway. This can take several minutes.'
printAndLog($m)

$argsVPNGateway = @{
    Name = $vpnGatewayName
    ResourceGroupName = $resourceGroupName
    Location = $resourceGroupLocation
    IpConfigurations = $vpnGatewayIPConfig
    GatewayType = 'Vpn'
    VpnType = 'RouteBased'
    GatewaySku = 'Basic'
    VpnGatewayGeneration = 'Generation1'
    VpnClientProtocol = 'SSTP'
}
try {
    $vpnGateway = New-AzVirtualNetworkGateway @argsVPNGateway `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to create the Azure VPN gateway'
    printAndLogError($m)
}

# Create the Azure S2S connection
$m = 'Creating the Azure S2S connection. This can take several minutes.'
printAndLog($m)

$argsVPNConnectionS2S = @{
    Name = $vpnConnectionS2SName
    ResourceGroupName = $resourceGroupName
    Location = $resourceGroupLocation
    VirtualNetworkGateway1 = $vpnGateway
    LocalNetworkGateway2 = $localNetworkGateway
    ConnectionType = 'IPsec'
    SharedKey = $vpnPreSharedKey
}
try {
    $vpnConnectionS2S = New-AzVirtualNetworkGatewayConnection @argsVPNConnectionS2S `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to create the Azure S2S connection'
    printAndLogError($m)
}

# Configure the Azure VPN client address pool
$m = 'Configuring the Azure VPN client address pool. This can take several minutes.'
printAndLog($m)

$argsVPNClientAddressPool = @{
    VirtualNetworkGateway = $vpnGateway
    VpnClientAddressPool = $vpnClientAddressPool
}
try {
    Set-AzVirtualNetworkGateway @argsVPNClientAddressPool `
        -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
} catch {
    $m = 'Unable to configure the Azure VPN client address pool'
    printAndLogError($m)
}

# Configure the Azure VPN P2s root certificate
$m = 'Configuring the Azure VPN P2S root certificate. This can take several minutes.'
printAndLog($m)

$argsVPNClientRootCertificate = @{
    VpnClientRootCertificateName = $rootCertName
    VirtualNetworkGatewayname = $vpnGatewayName
    ResourceGroupName = $resourceGroupName
    PublicCertData = $rootCertificateB64
}
try {
    $vpnClientRootCertificate = Add-AzVpnClientRootCertificate @argsVPNClientRootCertificate `
        -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    $m = 'Unable to configure the Azure VPN P2S root certificate'
    printAndLogError($m)
}

# Configure the Azure VPN P2s root certificate
$m = 'Azure environment successfully provisioned!'
printAndLog($m)

Write-Host
Write-Host
Read-Host "Press Enter to exit."
Remove-Item -Path Function:\Out-Default
