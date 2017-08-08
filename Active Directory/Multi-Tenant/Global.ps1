#
# Global.ps1
# Multi Tenant Active Directory Global Variables and Functions
#
# Auth : Joris DECOMBE
#

#
# Modules
#

Import-Module ActiveDirectory

#
# Variables 
#

$xmlFileName = "Objects.xml"

$ComputerDomainOU = "OU=Tenants,DC=computerauth,DC=corp,DC=com"
$UserDomainOU = "OU=Tenants,DC=userauth,DC=corp,DC=com"
$Suffix = "corp.com"
$RootDomain = "corp"
$ComputerDomain = "computerauth"
$UserDomain = "userauth"
$RootDomainFQDN = "$RootDomain.$Suffix"
$ComputerDomainFQDN = "$ComputerDomain.$RootDomainFQDN" 
$UserDomainFQDN = "$UserDomain.$RootDomainFQDN" 

# Getting InfrastructureMaster for each domain
$RootDomainDC = (Get-ADDomain $RootDomainFQDN).InfrastructureMaster
$ComputerDomainDC = (Get-ADDomain $ComputerDomainFQDN).InfrastructureMaster
$UserDomainDC = (Get-ADDomain $UserDomainFQDN).InfrastructureMaster

$DefaultDelegationGroups = @()
$DefaultDelegationGroups += "CN=N3-Admins,OU=Delegation Groups,OU=Admins,DC=corp,DC=com"
$DefaultDelegationGroups += "CN=N2-Admins,OU=Delegation Groups,OU=Admins,DC=corp,DC=com"

$DefaultDelegationGroups_DD = @()
$DefaultDelegationGroups_DD += "CN=DD-N3-Admins,OU=Delegation Groups,OU=Admins,DC=corp,DC=com"

$NTPServer = "ntp.corp.com"

$AD_ReadAccount_User = "$RootDomain\ad-read-account"
$AD_ReadAccount_Password = "kAs9vynBvjKi3DAW"
$AD_ReadAccount_SS = ConvertTo-SecureString -String $AD_ReadAccount_Password -AsPlainText -Force

$AD_DNS = "1000:101:666:1::101","1000:101:666:1::102"

$AD_JoinDomain_User = "$ComputerDomain\domain-join-account"
$AD_JoinDomain_Password = "nUnNSBtEtb742BvP"
$AD_ComputerDomain_DNS = "1000:101:666:1::1001","1000:101:666:1::1002"

# Automation PostInstall Script Template :

$Automation_Script_Template = @'

Sleep -Seconds 10
Get-NetAdapter | Enable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$False -ErrorAction SilentlyContinue
Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred -PrefixOrigin Manual | Get-NetAdapter | Disable-NetAdapterBinding -ComponentID ms_tcpip6

Sleep -Seconds 30
$DNS = ("%DNS_IP%")
$NetAdapter = (Get-NetIPAddress -AddressFamily IPv6 -AddressState Preferred | Where IPAddress -like "1000:101:666:1:*" | Select -First 1)

$NetAdapter | Get-Netadapter | Disable-NetAdapterBinding -ComponentID ms_tcpip

Set-DnsClientServerAddress -InterfaceIndex $NetAdapter.InterfaceIndex -ResetServerAddresses
Set-DnsClientServerAddress -InterfaceIndex $NetAdapter.InterfaceIndex -ServerAddresses $DNS

$domain = "%TARGETDOMAIN%"
Set-DnsClient -InterfaceIndex $NetAdapter.InterfaceIndex -ConnectionSpecificSuffix $domain

$password = "%JD_ACCOUNT_PASSWORD%" | ConvertTo-SecureString -asPlainText -Force
$username = "%JD_ACCOUND_USERNAME%"
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
Add-Computer -DomainName $domain -Credential $credential -OUPath "%TARGETOU%" -Restart

'@

#
# Hypervisor Variables
#

$Hypervisors = @()
$Hypervisors += "hv01"
$Hypervisors += "hv02"

$vSwitchName = "vSwitch-Multitenant-AD"
$ADC_PFS_VLAN = 1001

#
# Dedicated Domains Variables
#

# Dedicated Domain - Path
$DD_HV_Path = "H:\Hyper-V"
$DD_Template_Path = $DD_HV_Path + "\Templates"
$DD_VHD_Path = $DD_HV_Path + "\Vhdx"
$DD_VM_Path = $DD_HV_Path + "\VMs"

# Dedicated Domain - Network
$DD_GW = "1000:101:666:1::1"
$DD_DNS = "1000:101:666:1::101","1000:101:666:1::102"
$DD_IP_Prefix = "1000:101:666:1:"

# Dedicated Domain
$DD_DomainPrefix = "dedicated"
$DD_DomainSuffix = ".local"
$DD_DefaultSiteName = "MRS-PFS-CAS-DD"

# Dedicated Domain - Credentials
$DD_TemplateAdmin_User = "Administrator"
$DD_TemplateAdmin_SS = ConvertTo-SecureString -String "LNUUR2jC35WJGCaq" -AsPlainText -Force
$DD_TemplateAdmin_Creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DD_TemplateAdmin_User,$DD_TemplateAdmin_SS
$DD_Template_core = $DD_Template_Path + "\w2016-template-core.vhdx"

$DD_DomainJoin_User = "domain-join-account"
$DD_DomainJoin_Pwd = "PVvvgdMRm06nPVzA"
$DD_DomainJoin_SS = ConvertTo-SecureString -String $DD_DomainJoin_Pwd -AsPlainText -Force

# Dedicated Domain - Groups
$DD_AdminGroup = "Admins"
$DD_TenantAdminGroup = "Tenant-Admins"
$DD_TenantUserGroup = "Tenant-Users"

# Dedicated Domain - VMs

$DD_VMPrefix = "dedicatedDC"
$DD_MemoryStartupBytes = 2GB
$DD_MemoryMinimumBytes = 256MB
$DD_MemoryMaximumBytes = 2GB
$DD_ProcessorCount = 1

# Automation PostInstall Script Template :

$DD_Automation_Script_Template = @'

Sleep -Seconds 10
Get-NetAdapter | Enable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$False -ErrorAction SilentlyContinue
Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred -PrefixOrigin Manual | Get-NetAdapter | Disable-NetAdapterBinding -ComponentID ms_tcpip6

Sleep -Seconds 30
$DNS = ("%DNS_IP%")
$NetAdapter = (Get-NetIPAddress -AddressFamily IPv6 -AddressState Preferred | Where IPAddress -like "1000:101:666:1:*" | Select -First 1)

$NetAdapter | Get-Netadapter | Disable-NetAdapterBinding -ComponentID ms_tcpip

Set-DnsClientServerAddress -InterfaceIndex $NetAdapter.InterfaceIndex -ResetServerAddresses
Set-DnsClientServerAddress -InterfaceIndex $NetAdapter.InterfaceIndex -ServerAddresses $DNS

$domain = "%TARGETDOMAIN%"
Set-DnsClient -InterfaceIndex $NetAdapter.InterfaceIndex -ConnectionSpecificSuffix $domain

$password = "%JD_ACCOUNT_PASSWORD%" | ConvertTo-SecureString -asPlainText -Force
$username = "%JD_ACCOUND_USERNAME%"
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
Add-Computer -DomainName $domain -Credential $credential -OUPath "%TARGETOU%" -Restart

'@

#
# Functions 
#

Function ReplicateNow() {
    Import-Module ActiveDirectory
    $Todo = @()
    Get-ADDomain | %{$DN=$_.DistinguishedName ; $_.ReplicaDirectoryServers | %{ $Todo += [pscustomobject]@{DN= $DN;DC=$_ } } }
    (Get-ADDomain).ChildDomains | Get-ADDomain | %{$DN = $_.DistinguishedName ; $_.ReplicaDirectoryServers | %{ $Todo += [pscustomobject]@{DN= $DN;DC=$_ } } }

    $Todo | %{$1=$_ ; ($Todo | Where {$1.DC -ne $_.DC} | Where {$1.DN -eq $_.DN} | %{ &repadmin /replicate $_.DC $1.DC $_.DN | Out-Null}) }
}

Function Generate-Password() {

    # Generate password
    $Chars = @([Char[]]'abcdefghijkmnopqrstuvwxyz',[Char[]]'ABCEFGHJKLMNPQRSTUVWXYZ',[Char[]]'23456789')
    
    $str = @()
    $Chars | %{$str += $_ | Get-Random -count 6}

    $pwdarr = @()
    For ($i=1;$i -le 12;$i++) {
        
        Do {
            $key = Get-Random -Minimum 0 -Maximum $str.Length
        }  While ($pwdarr.Contains($str.GetValue($key)))

        $pwdarr += $str.GetValue($key)
    }

    $TempPwd = $pwdarr -join ""
    Return $TempPwd
}

Function Generate-Strong-Password() {

    # Generate password
    $Chars = @([Char[]]'abcdefghijkmnopqrstuvwxyz',[Char[]]'ABCEFGHJKLMNPQRSTUVWXYZ',[Char[]]'23456789',[Char[]]'!?():;-_%$&@=+')
    
    $str = @()
    $Chars | %{$str += $_ | Get-Random -count 6}

    $pwdarr = @()
    For ($i=1;$i -le 16;$i++) {
        
        Do {
            $key = Get-Random -Minimum 0 -Maximum $str.Length
        }  While ($pwdarr.Contains($str.GetValue($key)))

        $pwdarr += $str.GetValue($key)
    }

    $TempPwd = $pwdarr -join ""
    Return $TempPwd
}


Function Get-IniContent ($filePath)
{
    $ini = @{}
    switch -regex -file $FilePath
    {
        "^\[(.+)\]" # Section
        {
            $section = $matches[1]
            $ini[$section] = @{}
            $CommentCount = 0
        }
        "^(;.*)$" # Comment
        {
            $value = $matches[1]
            $CommentCount = $CommentCount + 1
            $name = "Comment" + $CommentCount
            $ini[$section][$name] = $value
        } 
        "(.+?)\s*=(.*)" # Key
        {
            $name,$value = $matches[1..2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

Function Out-IniFile($InputObject, $FilePath)
{
    $outFile = New-Item -ItemType file -Path $Filepath
    foreach ($i in $InputObject.keys)
    {
        if (!($($InputObject[$i].GetType().Name) -eq "Hashtable"))
        {
            #No Sections
            Add-Content -Path $outFile -Value "$i=$($InputObject[$i])"
        } else {
            #Sections
            Add-Content -Path $outFile -Value "[$i]"
            Foreach ($j in ($InputObject[$i].keys | Sort-Object))
            {
                if ($j -match "^Comment[\d]+") {
                    Add-Content -Path $outFile -Value "$($InputObject[$i][$j])"
                } else {
                    Add-Content -Path $outFile -Value "$j=$($InputObject[$i][$j])"
                }

            }
            Add-Content -Path $outFile -Value ""
        }
    }
}