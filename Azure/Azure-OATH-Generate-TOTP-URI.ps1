## Azure-OATH-Generate-TOTP-URI.ps1
#
# Takes an Azure OATH CSV file and generates a URI for easy importing into a TOTP generator of your choice.
# 
# TODO: Code clean-up, get rid of magic values.
#

$importCSV = '.\import.csv'
$outputTXT = '.\output.txt'
$otpLabel = 'Microsoft 365:'
$otpAlgorithm = 'SHA1'
$otpLength = '6'

try {
	$azureOATHs = @(Import-CSV -Path $importCSV -ErrorAction Stop)
} catch {
	Write-Host "Unable to import Azure OATH .csv file."
	Write-Error "$_" -ErrorAction Stop
}

if ( $azureOATHs.Count -lt 1 ) {
	Write-Host "No Azure OATH entries found."
	Write-Error "$_" -ErrorAction Stop
}

[String[]]$output = ""
foreach ($azureOATH in $azureOATHs) {
	[String[]]$output += [uri]::EscapeUriString('otpauth://totp/' + `
		$otpLabel + $azureOATH.'UPN' + `
		'?secret=' + $azureOATH.'Secret Key' + `
		'&issuer=' + $azureOATH.'Manufacturer' + `
		'&algorithm=' + $otpAlgorithm + `
		'&digits=' + $otpLength + `
		'&period=' + $azureOATH.'Time Interval')
}

$output > $outputTXT
