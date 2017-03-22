#
# JN Standalone Post install script
# 
# Date : 06/12/2016
# Version : 0.1
#
# Auth : Joris DECOMBE
#


$ConfirmPreference = "none"
$ErrorActionPreference = "continue"

# Log Path
$logpath = $env:SystemRoot + "\Logs\000"
New-Item -Path $logpath -ItemType Directory -Force -Confirm:$false | Out-Null
$Script:ScriptLog = "$logpath\pi-" + (Get-Date -f yy.MM.dd-HH.mm.ss) + ".log"
Start-Transcript -Path $Script:ScriptLog

# SNMP
$SNMPAllowedIPCust = @("10.0.192.48","10.0.193.78","85.31.192.48","85.31.193.78","10.0.192.39")

# CheckVM Function
# Returns True if VM
# Returns False if not

Function CheckVM {
	$VM_Count = 0
	#Searching for specific VM processes
	Get-process | Where-Object { ($_.ProcessName -like "VBoxService") -or ($_.ProcessName -like "VBoxTray") -or ($_.ProcessName -like "VMwareTray") -or ($_.ProcessName -like "VMwareUser")}
	If ($process_list -ne $Null) {$VM_Count += 1}

	#Checking Bios Informations
	$Bios_info = Get-WmiObject Win32_BIOS
	If (($Bios_info.SMBIOSBIOSVersion -like "*virt*") -or ($Bios_info.Version -like "*Vbox*") -or ($Bios_info.Version -like "*Hyper-V*") -or ($Bios_info.Version -like "VRTUAL*")) {$VM_Count += 2}

	#Checking Baseboard
	$Baseboard_info = Get-WmiObject Win32_Baseboard
	If (($Baseboard_info.Product -like "*440BX Desktop Reference Platform*") -or ($Baseboard_info.Product -like "*Virtual Machine*") ) {$VM_Count += 1}
    
	#Checking HDD
	$HDD_info = Get-WmiObject Win32_DiskDrive
	If (($HDD_info.Model -like "*VBOX*") -or ($HDD_info.Model -like "*VMWARE VIRTUAL*")) {$VM_Count += 1}

	If ($VM_Count -ge 2) {
		Return $true
	}
	Else {
		Return $false
	}

}

# Init

Sleep -Seconds 2

#
# Getting OS Info and putting it in $OS array
#

$Win32_OS = Get-WmiObject Win32_OperatingSystem | Select Caption,BuildNumber,OSLanguage,Version

$OS = @{}
$OS.Name = $Win32_OS.Caption
$OS.Build = $Win32_OS.BuildNumber
$OS.Version = $Win32_OS.Version
$OS.LanguageNumber = $Win32_OS.OSLanguage

Switch ($OS.LanguageNumber) {
    1033 {$OS.Language = 'EN'; break}
    1036 {$OS.Language = 'FR'; break}
}

Switch ($OS.Version) {
    {$_ -like '6.0.*'} {$OS.CustomName = '2008'; break}
    {$_ -like '6.1.*'} {$OS.CustomName = '2008R2'; break}
    {$_ -like '6.2.*'} {$OS.CustomName = '2012'; break}
    {$_ -like '6.3.*'} {$OS.CustomName = '2012R2'; break}
    {$_ -like '10.0*'} {$OS.CustomName = '2016'; break}
    Default {$OS.CustomName = 'NotSupported' ; break}
}

If (CheckVM) {
    $OS.VM = $True
}
Else {
    $OS.VM = $False
}

$OS.VMHyperV = $False
If ($OS.VM) {
    $Bios_info = Get-WmiObject Win32_BIOS
    $Baseboard_info = Get-WmiObject Win32_Baseboard
    
    If ($Bios_info.Version -like "*Hyper-V*") { $OS.VMHyperV = $True }
    If ($Baseboard_info.Product -like "*Virtual Machine*" -and $Baseboard_info.Manufacturer -like "*Microsoft*" ) { $OS.VMHyperV = $True }
}

# Let's go
$separator = "-"*50

Write-Host -ForegroundColor White ($separator)
Write-Host
Write-Host -ForegroundColor Cyan ("JN Post Install Script")
Write-Host
Write-Host -ForegroundColor Cyan ("Computername : " + $env:COMPUTERNAME)
Write-Host
Write-Host -ForegroundColor White ($separator)
Write-Host
Write-Host ("OS Info")

$OS | Format-Table -AutoSize -HideTableHeaders

Write-Host
Write-Host -ForegroundColor White ($separator)
Write-Host

#
# Set Culture and Keyboard to FR-fr
#

Write-Host "Set Culture and Keyboard to FR-fr"
Set-Culture 1036
Set-WinUserLanguageList -LanguageList FR-FR -Confirm:$false
Set-WinDefaultInputMethodOverride -InputTip "040C:0000040C"

#
# Enable ICMP Firewall rules
#

Write-Host "Enabling ICMP Firewall rules"
Get-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" | Set-NetFirewallRule -Enabled true
Get-NetFirewallRule -Name "FPS-ICMP6-ERQ-In" | Set-NetFirewallRule -Enabled true

#
# Enable RemoteDesktop
#

$Str = "Enable RemoteDesktop"
Write-Host -ForegroundColor Cyan $Str
(Get-WmiObject Win32_TerminalServiceSetting -Namespace root\cimv2\TerminalServices).SetAllowTsConnections(1,1) | Out-Null
(Get-WmiObject -Class "Win32_TSGeneralSetting" -Namespace root\cimv2\TerminalServices -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(0) | Out-Null
Get-NetFirewallRule -Group "@FirewallAPI.dll,-28752" | Set-NetFirewallRule -Enabled true

If ($?) {
    Write-Host -ForegroundColor Green ($Str + ": OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + ": Error")
    Write-Host -ForegroundColor Red $error[0]
}

#
# Enable WinRM (PSRemoting)
#

$Str = "Setting up WinRM"
Write-Host -ForegroundColor Cyan $Str
#Set-NetFirewallRule -Name WINRM-HTTP-In-TCP-PUBLIC -RemoteAddress Any
Enable-WSManCredSSP -Force -Role Server
Enable-PSRemoting -Force -SkipNetworkProfileCheck

If ($?) {
    Write-Host -ForegroundColor Green ($Str + ": OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + ": Error")
    Write-Host -ForegroundColor Red $error[0]
}


#
# Setting up accounts to never expire
#

$Str = "Setting up admin accounts (Password never expires)"
Write-Host -ForegroundColor Cyan ($Str)

$AdminGroup = 'Administrators'

If ($OS.Language -eq 'FR') {
    $AdminGroup = 'Administrateurs'
}

$Group = [ADSI]"WinNT://./$AdminGroup,group"
$Members = @($Group.psbase.Invoke("Members"))
$Members | ForEach-Object {
                $UserName = $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
                $User = [adsi]"WinNT://./$UserName"
                $User.UserFlags.value = $User.UserFlags.value -bor 0x10000
                $User.CommitChanges()
                $Str = "Setting up " + $UserName
                If ($?) {
                    Write-Host -ForegroundColor Green ($Str + ": OK")
                }
                Else {
                    Write-Host -ForegroundColor Red ($Str + ": Error")
                    Write-Host -ForegroundColor Red $error[0]
                }
        }

$Str = "Setting up user accounts (Password never expires)"
Write-Host -ForegroundColor Cyan ($Str)

$AdminGroup = 'Users'

If ($OS.Language -eq 'FR') {
    $AdminGroup = 'Utilisateurs'
}

$Group = [ADSI]"WinNT://./$AdminGroup,group"
$Members = @($Group.psbase.Invoke("Members"))
$Members | ForEach-Object {
                $UserName = $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
                $Continue = $True
                If ($OS.Language -eq 'FR') {
                    If ($UserName -like "INTERACTIF") {
                        $Continue = $False
                    }
                    If ($UserName -like "Utilisateurs Authentifiés") {
                        $Continue = $False
                    }
                }
                ElseIf ($OS.Language -eq 'EN') {
                    If ($UserName -like "INTERACTIVE") {
                        $Continue = $False
                    }
                    If ($UserName -like "Authenticated Users") {
                        $Continue = $False
                    }
                }
                If ($Continue) {
                    $User = [adsi]"WinNT://./$UserName"
                    $User.UserFlags.value = $User.UserFlags.value -bor 0x10000
                    $User.CommitChanges()
                    $Str = "Setting up " + $UserName
                    If ($?) {
                        Write-Host -ForegroundColor Green ($Str + ": OK")
                    }
                    Else {
                        Write-Host -ForegroundColor Red ($Str + ": Error")
                        Write-Host -ForegroundColor Red $error[0]
                    }
                }
        }


#
# Setting up power management to "High Performance"'
#

$Str = 'Setting up power management to "High Performance"'

Write-Host -ForegroundColor Cyan ($Str)

Start-Process 'PowerCfg.exe' -ArgumentList '/s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'-Wait
If ($?) {
    Write-Host -ForegroundColor Green ($Str + ": OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + ": Error")
    Write-Host -ForegroundColor Red $error[0]
}

#
# Disable power management on physical network interfaces
#

$Str = 'Disabling power mgmt on physical network interfaces'
Write-Host -ForegroundColor Cyan ($Str)

$PhysicalAdapters = Get-NetAdapter -Physical

$ParentKeyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}'

$InstanceIDs = @()
$PhysicalAdapters | %{ $InstanceIDs += $_.InstanceID }

$KeyToChange = @()
Get-ChildItem -Path $ParentKeyPath -Recurse -ErrorAction SilentlyContinue  `
| %{ Get-ItemProperty -Path $_.PSPath } | Where NetCfgInstanceId | %{ If ($_.NetCfgInstanceId -In $InstanceIDs) { $KeyToChange +=  $_.PSPath } }

$KeyToChange | %{  New-ItemProperty -Path $_ -Name PnPCapabilities -PropertyType DWord -Value 24 -Force } | Out-Null

#
# Networking - Sorting NICs
#

Import-Module NetAdapter

Write-Host "Sorting and renaming NICs"
$prefix = "NIC"
$netAdapters = Get-NetAdapterHardwareInfo | Sort-Object Bus,Function
$i = 0

ForEach ($netAdapter in $netAdapters) {

    $interface = $netadapter | Get-NetAdapter
    $old = $interface.Name
    $newName = "TEMP" + $old
    $interface | Rename-NetAdapter -NewName $newName
    $i++
}

$i = 0

ForEach ($netAdapter in $netAdapters) {

    $interface = $netadapter | Get-NetAdapter
    $old = $interface.Name -replace "TEMP",""
    $newName = $prefix + $i
    $interface | Rename-NetAdapter -NewName $newName
    $i++
    Write-Host "Renaming" $old "to:" $newName

}

#
# Disable Ipv6
#
If ($Os.Build -ge 9200) {

    $Str = "Disabling adapters ipv6"
    Write-Host -ForegroundColor Cyan ($Str)
    Get-NetAdapter | Disable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$False -ErrorAction SilentlyContinue

}

#
# Disable all adapters LLDP (Network discovery) and adding fw rules
#

If ($Os.Build -ge 9200) {

    $Str = "Disabling adapters ms_rspndr"
    Write-Host -ForegroundColor Cyan ($Str)
    $Disabler = Get-NetAdapter | Disable-NetAdapterBinding -ComponentID ms_rspndr -Confirm:$False -ErrorAction SilentlyContinue

    $Str = "Disabling adapters ms_lltdio"
    Write-Host -ForegroundColor Cyan ($Str)
    $Disabler = Get-NetAdapter | Disable-NetAdapterBinding -ComponentID ms_lltdio -Confirm:$False -ErrorAction SilentlyContinue

}

$Str = "Disabling network discovery rules"
Write-Host -ForegroundColor Cyan ($Str)
$Disabler = Start-Process 'netsh.exe' -Verb runAs -ArgumentList 'advfirewall firewall set rule group="network discovery" new enable=no' -Wait -PassThru


#
# Firewall Rules
#

$Str = "Adding Firewall rules"
Write-Host -ForegroundColor Cyan ($Str)

$RemoteIps = @("78.153.253.11","78.153.253.12","78.153.253.130") 

If ($Os.Build -ge 9200) {
    # JIB Windows 2012 R2
    New-NetFirewallRule -DisplayName "Allow JIB" -Direction Inbound -LocalPort Any -RemoteAddress $RemoteIps -Protocol TCP -Action Allow -Enabled True -Group "JN" | Out-Null
    # Core Networking
    Get-NetFirewallRule -Group "@FirewallAPI.dll,-25000" | Enable-NetFirewallRule
}
Else {
    # Windows 2008 R2
    Start-Process 'netsh' -Verb runAs -ArgumentList ('advfirewall add rule name="Allow JIB" dir=in action=allow enable=yes remoteip=' +($RemoteIps -join ",")+ ' group="JN" protocol=tcp localport=any') -Wait
}

If ($?) {
    Write-Host -ForegroundColor Green ($Str + ": OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + ": Error")
    Write-Host -ForegroundColor Red $error[0]
}

#
# Disabling Hibernation
#

$HiberStatus = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -name HibernateEnabled).HibernateEnabled

If ($HiberStatus -ne 0) {
    $Str = "Disabling Hibernation"
    Write-Host -ForegroundColor Cyan ($Str)

    Start-Process 'powercfg.exe' -Verb runAs -ArgumentList '/h off' -Wait

    If ($?) {
        Write-Host -ForegroundColor Green ($Str + ": OK")
    }
    Else {
        Write-Host -ForegroundColor Red ($Str + ": Error")
        Write-Host -ForegroundColor Red $error[0]
    }
}
Else {Write-Host -ForegroundColor Green ("Hibernation is already disabled")}

#
# Uninstalling VMTools if not virtual
#

If (!$OS.VM) {
    $Str = "Uninstalling VMTools"
    Write-Host -ForegroundColor Cyan ($Str)
    $VMTools = Get-WmiObject -Class Win32_Product | Where-Object -FilterScript {$_.Name -like "VMWare Tools"}
    If ($VMTools) {
        $Uninstall = $VMTools.uninstall()
        If ($?) {
            Write-Host -ForegroundColor Green ($Str + ": OK")
        }
        Else {
            Write-Host -ForegroundColor Red ($Str + ": Error")
            Write-Host -ForegroundColor Red $error[0]
        }
    }
    Else {
        Write-Host -ForegroundColor Yellow ($Str + ": Not Found")
    }
}

#
# Setting Windows Update parameters
#


$Str = "Enabling Windows Update"
$Notif = 3

$WUSettings = (New-Object -com "Microsoft.Update.AutoUpdate").Settings

# NotificationLevel  :
# 0 = Not configured;
# 1 = Disabled;
# 2 = Notify before download;
# 3 = Notify before installation;
# 4 = Scheduled installation;

$WUSettings.NotificationLevel = $Notif
$WUSettings.Save()

If ($?) {
    Write-Host -ForegroundColor Green ($Str + ": OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + ": Error")
    Write-Host -ForegroundColor Red $error[0]
}

#
# Cleaining up Scheduled tasks
#

$TaskPath = "\JN\"

$Str = "Cleaning up Scheduled tasks"

If (Get-ScheduledTask | Where TaskPath -EQ $TaskPath) {
    Write-Host -ForegroundColor Cyan ($Str)
    Unregister-ScheduledTask -TaskPath $TaskPath -Confirm:$false

    If ($?) {
        Write-Host -ForegroundColor Green ($Str + ": OK")
    }
    Else {
        Write-Host -ForegroundColor Red ($Str + ": Error")
        Write-Host -ForegroundColor Red $error[0]
    }
}

#
# Setting up NTP
#

$Str = "Setting up NTP"
Write-Host -ForegroundColor Cyan ($Str)

$NtpStr = "ntp.as30781.net"
$SyncStr = "manual"

$Command = "w32tm"
$Arg = "/config /manualpeerlist/" + $NtpStr + "/syncfromflags:" + $SyncStr
$SetupExec = Start-Process $Command -ArgumentList $Arg -Wait -PassThru

If ($?) {
    Write-Host -ForegroundColor Green ($Str + ": OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + ": Error")
    Write-Host -ForegroundColor Red $error[0]
}

#
# Setting up SNMP
#

$Str = "Setting up Snmp"
Write-Host -ForegroundColor Cyan ($Str)
$Check = Get-WindowsFeature | Where {$_.Name -like "SNMP-Service"}
If (!$Check.Installed) {
    Write-Host -ForegroundColor Yellow ($Str + " - Not found - Installing feature")
    Install-WindowsFeature SNMP-Service -IncludeManagementTools | Out-Null
    If ($?) {
    Write-Host -ForegroundColor Green ($Str + " - Installing feature : OK")
    }
    Else {
        Write-Host -ForegroundColor Red ($Str + " - Installing feature : Error")
        Write-Host -ForegroundColor Red $error[0]
    }
}

$Str = "Setting up Snmp RSAT"
Write-Host -ForegroundColor Cyan ($Str)
$Check = Get-WindowsFeature | Where {$_.Name -like "RSAT-SNMP"}
If (!$Check.Installed) {
    Write-Host -ForegroundColor Yellow ($Str + " - Not found - Installing feature")
    Install-WindowsFeature RSAT-SNMP | Out-Null
    If ($?) {
    Write-Host -ForegroundColor Green ($Str + " - Installing feature : OK")
    }
    Else {
        Write-Host -ForegroundColor Red ($Str + " - Installing feature : Error")
        Write-Host -ForegroundColor Red $error[0]
    }
}

$Str = "Setting up Snmp - Communities"
Write-Host -ForegroundColor Cyan ($Str)
Reg Add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\ValidCommunities" /v Ef4Twyff /t REG_DWORD /d 4 /f | Out-Null
If ($?) {
    Write-Host -ForegroundColor Green ($Str + " : OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + " : Error")
    Write-Host -ForegroundColor Red $error[0]
}

$Str = "Setting up Snmp - location"
Write-Host -ForegroundColor Cyan ($Str)
Reg Add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\RFC1156Agent" /v "sysLocation" /t REG_SZ /d MRS01 /f | Out-Null
If ($?) {
    Write-Host -ForegroundColor Green ($Str + " : OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + " : Error")
    Write-Host -ForegroundColor Red $error[0]
}

$Str = "Setting up Snmp - Syscontact"
Write-Host -ForegroundColor Cyan ($Str)
Reg Add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\RFC1156Agent" /v "sysContact" /t REG_SZ /d "noc@as30781.net" /f | Out-Null
If ($?) {
    Write-Host -ForegroundColor Green ($Str + " : OK")
}
Else {
    Write-Host -ForegroundColor Red ($Str + " : Error")
    Write-Host -ForegroundColor Red $error[0]
}

$Str = "Setting up Snmp - Allowed IP"
Write-Host -ForegroundColor Cyan ($Str)

$i = 1;
$SNMPAllowedIPCust | %{ 
    $Str = "Setting up Snmp - Add $i : $_";
    Write-Host -ForegroundColor Cyan ($Str);
    Reg Add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\PermittedManagers" /v $i /t REG_SZ /d $_ /f | Out-Null ;
    If ($?) {
        Write-Host -ForegroundColor Green ($Str + " : OK");
    }
    Else {
        Write-Host -ForegroundColor Red ($Str + " : Error");
        Write-Host -ForegroundColor Red $error[0];
    }
    $i++ ;
}


# Règles FW

$SNMPFWRules = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -LocalOnlyMapping $False -Group "@snmp.exe,-3"

$suffix = "_JN_CUSTOM_SNMP"

$SNMPFWRules | %{ Copy-NetFirewallRule $_.Name -NewName ($_.Name + $suffix) }

$NewRules = Get-NetFirewallRule -Direction Inbound -Action Allow | Where Name -Like "*$suffix"
$NewRules | %{ Set-NetFirewallRule $_.Name -NewDisplayName ($_.DisplayName + $suffix) }

$NewRules | %{ Set-NetFirewallRule $_.Name -RemoteAddress $SNMPAllowedIPCust }

New-NetFirewallRule -DisplayName "Allow JIB" -Direction Inbound -LocalPort Any -RemoteAddress $RemoteIps -Protocol TCP -Action Allow -Enabled True -Group "JN" | Out-Null

Get-Service -Name SNMP | Restart-Service -Force -Confirm:$False | Out-Null

# Clear event logs

Get-Eventlog -list | % {Clear-Eventlog -log $_.Log -Confirm:$False}

# Cleaning temp directories

Write-Host "Cleaning Temp directories..."
@(
    "$env:localappdata\Nuget",
    "$env:localappdata\temp\*",
    "$env:windir\logs",
    "$env:windir\panther",
    "$env:windir\Temp\*",
    "$env:windir\winsxs\manifestcache",
    "$env:windir\Prefetch\*",
    "$env:TEMP\*",
    "C:\Documents and Settings\*\Local Settings\temp\*",
    "C:\Users\*\Appdata\Local\Temp\*"
) | % {
        if(Test-Path $_) {
            Write-Host "Removing $_"
            Takeown /d Y /R /f $_  2>&1 | Out-Null
            Icacls $_ /GRANT:r administrators:F /T /c /q  2>&1 | Out-Null
            Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$False | Out-Null
        }
    }


Stop-Transcript

