
<#PSScriptInfo

.VERSION 1.0.1

.GUID cb059a0e-09b6-4756-8df4-28e997b9d97f

.AUTHOR saw-friendship@yandex.ru

.COMPANYNAME 

.COPYRIGHT 

.TAGS 

.LICENSEURI 

.PROJECTURI https://sawfriendship.wordpress.com/

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES


#>

<# 

.DESCRIPTION 
 IP Calculator 

#> 


[CmdletBinding(DefaultParameterSetName="ParameterSet1")]
	param(
		[parameter(ParameterSetName="ParameterSet1",Position=0)][Alias("IP")][IPAddress]$IPAddress,
		[parameter(ParameterSetName="ParameterSet1",Position=1)][IPAddress]$Mask,
		[parameter(ParameterSetName="ParameterSet1",Position=1)][ValidateRange(0,32)][int]$PrefixLength,
		[parameter(ParameterSetName="ParameterSet1",Position=1)][Alias("Joker")][IPAddress]$WildCard,
		[Parameter(ParameterSetName="ParameterSet2",Position=2,ValueFromPipeline = $true)][string]$CIDR,
		[Parameter(Position=3)][switch]$CreateIParray,
		[Parameter(Position=4)][switch]$CreateIParrayPassThru
	)

	if($CIDR){
		[IPAddress]$IPAddress,[int]$PrefixLength = $CIDR -split '[^\d\.]' -match "\d"
	}
	if($PrefixLength){
		[IPAddress]$Mask = (([string]'1'*$PrefixLength + [string]'0'*(32-$PrefixLength)) -split "(\d{8})" -match "\d" | % {[convert]::ToInt32($_,2)}) -split "\D" -join "."
	}
	if($WildCard){
		$SplitWildCard = $WildCard -split "\." -match "\d"
		[IPAddress]$Mask = ($SplitWildCard | % {255 - $_}) -join "."
	}
	if($Mask){
		$SplitIPAddress = [int[]]@($IPAddress -split "\." -match "\d")
		$ToDecimal = ($SplitIPAddress | % -Begin {$i = 3} -Process {([Math]::Pow(256,$i))*$_; $i--} | measure -Sum).Sum
		$SplitMask = $Mask -split "\." -match "\d"
		$PrefixLength = 32 - ($SplitMask | % {256-$_} | % {[math]::Log($_,2)} | measure -Sum).Sum
		$IPBin = ($SplitIPAddress | % {[convert]::ToString($_,2).PadLeft(8,"0")}) -join "."
		$MaskBin = ($SplitMask | % {[convert]::ToString($_,2).PadLeft(8,"0")}) -join "."
		if((($MaskBin -replace "\.").TrimStart("1").Contains("1")) -and (!$WildCard)){
			Write-Warning "Mask Length error, you can try put WildCard"; break
		}
		$WildCard = ($SplitMask | % {255 - $_}) -join "."
		$Subnet = ((0..31 | % {@($IPBin -split "" -match "\d")[$_] -band @($MaskBin -split "" -match "\d")[$_]}) -join '' -split "(\d{8})" -match "\d" | % {[convert]::ToInt32($_,2)}) -join "."
		$SplitSubnet = [int[]]@($Subnet -split "\." -match "\d")
		$SubnetBin = ($SplitSubnet | % {[convert]::ToString($_,2).PadLeft(8,"0")}) -join "."
		$Broadcast = (0..3 | % {[int]$(@($Subnet -split "\." -match "\d")[$_]) + [int]$(@($WildCard -split "\." -match "\d")[$_])}) -join "."
		$SplitBroadcast = [int[]]@($Broadcast -split "\." -match "\d")
		$BroadcastBin = ($SplitBroadcast | % {[convert]::ToString($_,2).PadLeft(8,"0")}) -join "."
		$CIDR = $Subnet + '/' + $PrefixLength
		$IPcount = [math]::Pow(2,$(32 - $PrefixLength))
	}

	$Object = [ordered]@{
	'IP' = $IPAddress.IPAddressToString
	'Mask' = $Mask.IPAddressToString
	'PrefixLength' = $PrefixLength
	'WildCard' = $WildCard.IPAddressToString
	'IPcount' = $IPcount
	'Subnet' = $Subnet
	'Broadcast' = $Broadcast
	'CIDR' = $CIDR
	'ToDecimal' = $ToDecimal
	'IPBin' = $IPBin
	'MaskBin' = $MaskBin
	'SubnetBin' = $SubnetBin
	'BroadcastBin' = $BroadcastBin
	}
	
	if ($CreateIParray -or $CreateIParrayPassThru){
		$SplitSubnet = $Subnet -split "\." -match "\d"
		$SplitBroadcast = $Broadcast -split "\." -match "\d"
		$w,$x,$y,$z =  @($SplitSubnet[0]..$SplitBroadcast[0]),@($SplitSubnet[1]..$SplitBroadcast[1]),@($SplitSubnet[2]..$SplitBroadcast[2]),@($SplitSubnet[3]..$SplitBroadcast[3])
		$IParray = $w | % {$wi = $_; $x | % {$xi = $_; $y | % {$yi = $_; $z | % {$zi = $_; $wi,$xi,$yi,$zi -join '.'}}}}
		$Object.IParray = $IParray
	}
	
	
	if(!$CreateIParrayPassThru){[pscustomobject]$Object}else{$IParray}
