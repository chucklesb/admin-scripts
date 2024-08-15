## AD-Get-DNS-Servers.ps1
#
# Print list of AD nameservers
#

(Get-ADDomain).DNSRoot | `
	Resolve-DnsName -type ns | `
	? {$_.type -eq "A"} `
	| select name, IP4Address
