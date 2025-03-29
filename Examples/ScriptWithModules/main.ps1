#requires -Module IPNetwork

[CmdletBinding()]
param(
	#The IP prefixed address to get the subnet for. Example: 10.2.1.5/24
	[string]$IP = '199.255.26.15/21'
)

$IPInfo = Get-IPNetwork $IP

return "The Network ID of $IP is $($IPInfo.Network)"