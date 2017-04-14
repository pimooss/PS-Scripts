#
# HYPER-V Deployment Script
# Phase 2 -> 
#   .vSwitch configuration
#   .iSCSI Advanced Configuration
#   .Netapp MPIO Advanced Configuration
#
# Date : 14/04/2016
# Version : 0.1
# Auth : Joris DECOMBE
#

Param
(
    [Parameter(Mandatory=$false,Position=0)]
    [String]$Path = (Get-Location),
    [Parameter(Mandatory=$false)]
	[Switch]$EnableLogging = $true
)

# Enable logging
If ($EnableLogging)
{
	#$Script:Path = Get-Location
	$Script:ScriptLog = "$path\02_Configure-" + (Get-Date -f yy.MM.dd-HH.mm.ss) + ".log"
	Start-Transcript -Path $Script:ScriptLog
}

$StartDate = Get-Date

# Elevate
$StartDate=Get-Date ; Write-Host "Deployment started at: $StartDate"
Write-Host "Checking for elevation... " -NoNewline
$CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
if (($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) -eq $false)  {
    $ArgumentList = "-noprofile -noexit -file `"{0}`" -Path `"$Path`""
    If ($Setup) {$ArgumentList = $ArgumentList + " -Setup $Setup"}
    If ($Mode) {$ArgumentList = $ArgumentList + " -Mode $Mode"}
    Write-Host "elevating"
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($ArgumentList -f ($myinvocation.MyCommand.Definition))
    Exit
}

# Set Background to black
$Host.UI.RawUI.BackgroundColor = "Black"; Clear-Host
$Validate = $true

# Check OS version
If ((Get-WmiObject -Class Win32_OperatingSystem).Version.Split(".")[2] -lt 9200) {
    $Validate = $false
    Write-Host "Deployment should be run from Windows Server 2012 or later" -ForegroundColor Red
}

# Change to path
If (Test-Path $Path -PathType Container) {
    Set-Location $Path
} Else {
    $Validate = $false
    Write-Host "Invalid path" -ForegroundColor Red
}

# Validate variable.xml
Write-Host "Looking for Variable.xml"
If (Test-Path ".\Variable.xml") {
    try {$Variable = [XML] (Get-Content ".\Variable.xml")} catch {$Validate = $false;Write-Host "Invalid Variable.xml" -ForegroundColor Red}
} Else {
    $Validate = $false
    Write-Host "Missing Variable.xml" -ForegroundColor Red
}

# Validating sources
If ($Validate) {
    $NetAppMPIO = $Path + "\" + ($Variable.Installer.Variable | Where-Object {$_.Name -eq "NetAppMPIO"}).Value
    $AfterRebootScript = $Path + "\03_finalize.ps1"
    $AfterRebootScriptCMD = "c:\WINDOWS\system32\WindowsPowerShell\v1.0\powershell.exe -noexit -ExecutionPolicy Bypass -File $AfterRebootScript -Path $Path"
    
    $InstallerUsername = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "InstallerAccount"}).Value
    $InstallerPassword = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "InstallerAccountPassword"}).Value
    
    $DeploymentHost = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "DeploymentHost"}).Value
    $FormatiSCSIDisk = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "DeploymentHostFormatiSCSIDisk"}).Value
    
    If ($DeploymentHost -like $env:COMPUTERNAME) {
        Write-Host "Deployment Host is current host "
    } 
    
    If (!(Test-Path $AfterRebootScript)) {
        $Validate = $false
        Write-Host "Missing $AfterRebootScript" -ForegroundColor Red
    }
}

If ($Validate) {
    
    # Unattended Install of Netapp MPIO MSI
    
    $msipath = $NetAppMPIO
    Write-Host "Installing Netapp MPIO $msipath"
    
    If (Test-Path $msipath) {
        Write-Host "Starting Installer"
        Start-Process 'msiexec.exe' -ArgumentList "/i $msipath /quiet HYPERVUTIL=1 USESYSTEMACCOUNT=1 LICENSECODE=NOEQSCYNQDDCMA /norestart" -Wait
        Sleep -Seconds 10
    }
    
    # vSwitch & LACP Configuration
    $vSwitchName = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "vSwitchName"}).Value
    $LACPName = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "DefaultLACPName"}).Value
    
    If ($DeploymentHost -like $env:COMPUTERNAME) {
       Write-Host "vSwitch Configuration"
    
        If (!(Get-VMSwitch -Name $vSwitchName -ErrorAction SilentlyContinue)) {
            Write-Host "Creating vSwitch" $vSwitchName
            New-VMSwitch -Name $vSwitchName -NetAdapterName $LACPName -AllowManagementOS 0
        }
        Else {
            Write-Host "VSwitch" $vSwitchName "already exists -> no change"
        }
    
        Get-NetLbfoTeamNic -Team $LACPName | Where Primary -eq $false  | Get-NetIPInterface | Where DHCP -eq Disabled | %{
            $IfConfig = Get-NetIPConfiguration $_.InterfaceAlias      
            $VLAN = ($_ | Get-NetAdapter).VlanID
            $IP = ($IfConfig.IPv4Address).IPAddress
            $PLength = ($IfConfig.IPv4Address).PrefixLength
            $GW = ($IfConfig.IPv4DefaultGateway).NextHop
            $DNS = ($IfConfig.DNSServer).ServerAddresses
            
            $VLAN_Name = "VLAN"+$VLAN
            If (!(Get-VMNetworkAdapter -SwitchName "vSwitch" -ManagementOS -Name $VLAN_Name -ErrorAction SilentlyContinue)) {
                Write-Host "Deleting NetLbfoTeamNic with vlan" $VLAN
                Get-NetLbfoTeamNic -Team $LACPName | Where Primary -eq $false | Where {$_.VlanID -eq $VLAN} | Remove-NetLbfoTeamNic -Confirm:$False
                
                Write-Host "Adding VMNetworkAdapter" $VLAN_Name
                Add-VMNetworkAdapter -SwitchName "vSwitch" -ManagementOS -Name $VLAN_Name
                
                Write-Host "Setting up vlan of" $VLAN_Name "to" $VLAN
                Set-VMNetworkAdapterVlan –ManagementOS –VMNetWorkAdapterName $VLAN_Name -Access –VlanId $VLAN
                
                Write-Host "Setting up IP of" $VLAN_Name "to" $IP"/"$PLength "gw:"$GW
                If ($GW) {
                    New-NetIPAddress -InterfaceAlias "vEthernet ($VLAN_Name)" -IPAddress $IP -PrefixLength $PLength -DefaultGateway $GW
                }
                Else {
                    New-NetIPAddress -InterfaceAlias "vEthernet ($VLAN_Name)" -IPAddress $IP -PrefixLength $PLength
                }
                Write-Host "Setting up DNS of" $VLAN_Name "to" $DNS
                Set-DnsClientServerAddress -InterfaceAlias "vEthernet ($VLAN_Name)" -ServerAddresses $DNS
                
                Write-Host "Disabling IPV6"
                Disable-NetAdapterBinding -InterfaceAlias "vEthernet ($VLAN_Name)" -ComponentID ms_tcpip6 -Confirm:$False
            
            }
            Else {
                Write-Host "VM NetAdapter" $VLAN_Name "already exists -> no change"
            }
        }
    } 
    
    
    #
    # iSCSI Customization
    #
    
    Write-Host "iSCSI Configuration"
    
    # Setting up MPIO Settings
    
    Write-Host "MPIO Settings"
    
    Set-MPIOSetting -NewPathVerificationPeriod 5 -NewPathVerificationState Enabled -NewPDORemovePeriod 130 -NewRetryCount 6 -NewDiskTimeout 60 -CustomPathRecovery Enabled -NewPathRecoveryInterval 40

    Set-MSDSMGlobalDefaultLoadBalancePolicy LQD
    
    Enable-MSDSMAutomaticClaim -BusType iSCSI
    
    # Getting iSCSI Interface (Name your interface with "iSCSI" string in it)
    
    Write-Host "Getting iSCSI Interface"
    
    $InitiatorAdapter = Get-NetAdapter | Where Name -like "*iSCSI*"
    $InitiatorAddresses = ($InitiatorAdapter | Get-NetIPAddress -AddressFamily IPv4).IPAddress
    
    Write-Host "iSCSI Interfaces : "
    $InitiatorAdapter | %{ Write-Host $_.Name }
    Write-Host "iSCSI Addresses : "
    $InitiatorAddresses | %{ Write-Host $_ }
    
    # Disable all protocols and services expect IPV4
    
    Write-Host "Disabling unnecessary protocols"
    
    $InitiatorAdapter | Disable-NetAdapterBinding -ComponentID ms_rspndr -Confirm:$False
    $InitiatorAdapter | Disable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$False
    $InitiatorAdapter | Disable-NetAdapterBinding -ComponentID ms_server -Confirm:$False
    $InitiatorAdapter | Disable-NetAdapterBinding -ComponentID ms_lltdio -Confirm:$False
    $InitiatorAdapter | Disable-NetAdapterBinding -ComponentID ms_msclient -Confirm:$False
    
    # Disable DNS registration for iSCSI Adapters
    
    Write-Host "Disabling DNS Registration"
    
    $InitiatorAdapter | Set-DnsClient -RegisterThisConnectionsAddress:$False -Verbose

    # Disable power mgmt on adapters
    
    Write-Host "Disabling Power Management"
    
    $InitiatorAdapter | Disable-NetAdapterPowerManagement

    # Disable Netbios on iSCSI Adapters
    
    Write-Host "Disabling Netbios"
    
    $wmiadapters = @()
    $InitiatorAdapter | %{ $IfName = $_.Name ; $wmiadapters += (gwmi -query "select * from win32_networkadapter where netconnectionid='$IfName'").deviceid }
    $wmiadapters | %{ ([wmi]"\\.\root\cimv2:Win32_NetworkAdapterConfiguration.Index=$_").SetTcpipNetbios(2) }
    
    
    If ((($Variable.Installer.Variable | Where-Object {$_.Name -eq "ActivateJumboPacket"}).Value) -Like "True") {
        
        Write-Host "Enabling Jumbo Frame"
        
        # Enable Jumbo MTU if specified
    
        $InitiatorAdapter | Where ifDesc -like "*Broadcom*" | Set-NetAdapterAdvancedProperty -DisplayName "Jumbo Mtu" -DisplayValue "9000"

        $InitiatorAdapter | Where ifDesc -like "*Intel*I350*" | Set-NetAdapterAdvancedProperty -DisplayName "Jumbo Packet" -DisplayValue "9014 Bytes"

        $InitiatorAdapter | Where ifDesc -like "*Qlogic*5709*" | Set-NetAdapterAdvancedProperty -DisplayName "Jumbo Packet" -DisplayValue "9014"
    
    }
    
    # Disable NetFlow on Broadcom
    Write-Host "Disabling Netflow on buggy Broadcom"
    
    $InitiatorAdapter | Where ifDesc -like "*Broadcom*"  | Set-NetAdapterAdvancedProperty -DisplayName "Flow Control" -DisplayValue "Disabled"
    
    # Enable Large Send Offload
    
    Write-Host "Enabling Large Send Offload"
    
    $InitiatorAdapter | Set-NetAdapterAdvancedProperty -DisplayName "Large Send Offload V2 (IPv4)" -DisplayValue "Enabled"

    $InitiatorAdapter | Set-NetAdapterAdvancedProperty -DisplayName "Large Send Offload V2 (IPv6)" -DisplayValue "Enabled"
    
    # Set the Receive Buffers to maximum
    
    Write-Host "Setting up Receive Buffers"
    
    $InitiatorAdapter | Where ifDesc -like "*Broadcom*" | Set-NetAdapterAdvancedProperty -DisplayName "Receive Buffers" -DisplayValue "Maximum"

    $InitiatorAdapter | Where ifDesc -like "*Intel*I350*" | Set-NetAdapterAdvancedProperty -DisplayName "Receive Buffers" -DisplayValue "2048"

    $InitiatorAdapter | Where ifDesc -like "*Qlogic*5709*" | Set-NetAdapterAdvancedProperty -DisplayName "Receive Buffers (0=Auto)" -DisplayValue "3000"
    
    # Set the Transmit Buffer to max
    
    Write-Host "Setting up Transmit Buffers"
    
    $InitiatorAdapter | Where ifDesc -like "*Broadcom*" | Set-NetAdapterAdvancedProperty -DisplayName "Transmit Buffers" -DisplayValue "600"

    $InitiatorAdapter | Where ifDesc -like "*Intel*I350*" | Set-NetAdapterAdvancedProperty -DisplayName "Transmit Buffers" -DisplayValue "2048"

    $InitiatorAdapter | Where ifDesc -like "*Qlogic*5709*" | Set-NetAdapterAdvancedProperty -DisplayName "Transmit Buffers (0=Auto)" -DisplayValue "5000"

    # Setting up RSS queues
    
    Write-Host "Setting up RSS Queues"
    
    $InitiatorAdapter | Where ifDesc -like "*Broadcom*" | Set-NetAdapterAdvancedProperty -DisplayName "Maximum Number of RSS Queues" -DisplayValue "RSS 4 Queues"

    $InitiatorAdapter | Where ifDesc -like "*Intel*I350*" | Set-NetAdapterAdvancedProperty -DisplayName "Maximum Number of RSS Queues" -DisplayValue "8 Queues"

    $InitiatorAdapter | Where ifDesc -like "*Qlogic*5709*" | Set-NetAdapterAdvancedProperty -DisplayName "Maximum Number of RSS Queues" -DisplayValue "8"

    $InitiatorAdapter | Where ifDesc -like "*Broadcom*" | Set-NetAdapterAdvancedProperty -DisplayName "RSS Base Processor Number" -DisplayValue "2"

    $InitiatorAdapter | Where ifDesc -like "*Intel*I350*" | Set-NetAdapterAdvancedProperty -DisplayName "RSS Base Processor Number" -DisplayValue "2"

    $InitiatorAdapter | Where ifDesc -like "*Qlogic*5709*" | Set-NetAdapterAdvancedProperty -DisplayName "Starting RSS CPU" -DisplayValue "2"
    
    # Enable RSS
    
    Write-Host "Enabling RSS"
    
    $InitiatorAdapter | Set-NetAdapterAdvancedProperty -DisplayName "Receive Side Scaling" -DisplayValue "Enabled"

    # Virtual Machine Queues
    
    Write-Host "Enabling VM Queues"
    
    $InitiatorAdapter | Set-NetAdapterAdvancedProperty -DisplayName "Virtual Machine Queues" -DisplayValue "Enabled"

    # Enable TCP/UDP Checksum Offload

    Write-Host "Enabling Checksum offload"
    
    $InitiatorAdapter | Where ifDesc -like "*Broadcom*" | Set-NetAdapterAdvancedProperty -DisplayName "TCP/UDP Checksum Offload (IPv4)" -DisplayValue "Rx & Tx Enabled"

    $InitiatorAdapter | Where ifDesc -like "*Broadcom*" | Set-NetAdapterAdvancedProperty -DisplayName "TCP/UDP Checksum Offload (IPv6)" -DisplayValue "Rx & Tx Enabled"

    $InitiatorAdapter | Where ifDesc -like "*Intel*" | Set-NetAdapterAdvancedProperty -DisplayName "TCP Checksum Offload (IPv4)" -DisplayValue "Rx & Tx Enabled"

    $InitiatorAdapter | Where ifDesc -like "*Intel*" | Set-NetAdapterAdvancedProperty -DisplayName "TCP Checksum Offload (IPv6)" -DisplayValue "Rx & Tx Enabled"

    $InitiatorAdapter | Where ifDesc -like "*Intel*" | Set-NetAdapterAdvancedProperty -DisplayName "UDP Checksum Offload (IPv4)" -DisplayValue "Rx & Tx Enabled"

    $InitiatorAdapter | Where ifDesc -like "*Intel*" | Set-NetAdapterAdvancedProperty -DisplayName "UDP Checksum Offload (IPv6)" -DisplayValue "Rx & Tx Enabled"

    $InitiatorAdapter | Where ifDesc -like "*Intel*" | Set-NetAdapterAdvancedProperty -DisplayName "IPv4 Checksum Offload" -DisplayValue "Rx & Tx Enabled"

    # Get Interface registry path
    
    $IntKeyToChange = @()

    Get-ChildItem -Path HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces -Recurse `
    | %{ Get-ItemProperty -Path $_.PSPath } | Where IPAddress | %{ If ($_.IPAddress -In $InitiatorAddresses) { $IntKeyToChange +=  $_.PSPath } }

    # Create TcpAckFrequency and TcpNoDelay
    
    Write-Host "Setting up TcpAckFrequency / TcpNoDelay / Tcp1323Opts / SackOpts"
    
    $IntKeyToChange | %{ New-ItemProperty -Path $_ -Name TcpAckFrequency -PropertyType DWord -Value 1 -Force }
    $IntKeyToChange | %{ New-ItemProperty -Path $_ -Name TcpNoDelay -PropertyType DWord -Value 1 -Force }
    $IntKeyToChange | %{ New-ItemProperty -Path $_ -Name Tcp1323Opts -PropertyType DWord -Value 3 -Force }
    $IntKeyToChange | %{ New-ItemProperty -Path $_ -Name SackOpts -PropertyType DWord -Value 1 -Force }
    
    # Disable a bunch of Interface HW parameters

    $ParentKeyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}'

    $InstanceIDs = @()
    $InitiatorAdapter | %{ $InstanceIDs += $_.InstanceID }

    $KeyToChange = @()
    Get-ChildItem -Path $ParentKeyPath -Recurse -ErrorAction SilentlyContinue  `
    | %{ Get-ItemProperty -Path $_.PSPath } | Where NetCfgInstanceId | %{ If ($_.NetCfgInstanceId -In $InstanceIDs) { $KeyToChange +=  $_.PSPath } }

    
    # Disable the "Allow the computer to turn off this adapter to save power" option
    
    Write-Host "Disabling Interface sleep mode"
    
    $KeyToChange | %{  New-ItemProperty -Path $_ -Name PnPCapabilities -PropertyType DWord -Value 24 -Force }

    # Getting iSCSI Class

    $iSCSIClassKey = (Get-ChildItem -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue  -Recurse `
    | %{ Get-ItemProperty -Path $_.PSPath } | Where LinkDownTime ).PSPath

    # Setting up LinkDownTime
    
    Write-Host "Setting up iSCSI LinkDownTime"
    $iSCSIClassKey | %{ New-ItemProperty -Path $_ -Name LinkDownTime -PropertyType DWord -Value 5 -Force }

    # Mpio service cutomization
    
    Write-Host "Setting up MPIO Path Verification"
    
    $KeyPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\mpio\Parameters'

    New-ItemProperty -Path $KeyPath -Name PathVerifyEnabled -PropertyType DWord -Value 1 -Force
    New-ItemProperty -Path $KeyPath -Name PathVerificationPeriod -PropertyType DWord -Value 5 -Force
    New-ItemProperty -Path $KeyPath -Name RetryCount -PropertyType DWord -Value 6 -Force
    New-ItemProperty -Path $KeyPath -Name RetryInterval -PropertyType DWord -Value 1 -Force

    # OntapDsm customization
     
    Write-Host "Setting up OntapDSM"
     
    $KeyPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\ontapdsm\Parameters'

    If (Get-Item -Path $KeyPath -ErrorAction SilentlyContinue) {
        New-ItemProperty -Path $KeyPath -Name PathVerifyEnabled -PropertyType DWord -Value 1 -Force
        New-ItemProperty -Path $KeyPath -Name PathVerificationPeriod -PropertyType DWord -Value 5 -Force
        New-ItemProperty -Path $KeyPath -Name RetryCount -PropertyType DWord -Value 6 -Force
        New-ItemProperty -Path $KeyPath -Name RetryInterval -PropertyType DWord -Value 1 -Force
    }

    # Disable TCP Chimney 
    
    Write-Host "Setting up TCP Chimney"
    
    Start-Process 'netsh' -ArgumentList 'int tcp set supplemental template=datacenter'-Wait
    Start-Process 'netsh' -ArgumentList 'int tcp set global rss=enabled'-Wait
    Start-Process 'netsh' -ArgumentList 'int tcp set global chimney=disabled'-Wait
    
    #
    # End of iSCSI Customization
    #
    
    #
    # iSCSI Connection
    #
    
    $PortalIPTarget = @()
    $Variable.Installer.iSCSI.Portal.IP | %{ $PortalIPTarget += $_ }
    
    Write-Host -ForegroundColor Cyan "iSCSI Connection"
    
    Write-Host -ForegroundColor Cyan "Getting dedicated iSCSI interfaces"

    $InitatorAdapters = (Get-NetAdapter -Physical | Where Name -like "*iSCSI*")

    $InitiatorInterfaces = ($InitatorAdapters | Get-NetIPAddress -AddressFamily IPv4 )

    $InitiatorAddresses = $InitiatorInterfaces.IPAddress

    $InitiatorInterfaces | Sort InterfaceAlias | %{Write-Host $_.InterfaceAlias ":" $_.IPAddress " [ MTU : " ($InitatorAdapters | Where ifIndex -eq $_.ifIndex | Select MtuSize  ).MtuSize"]" }
    
    # Adding Portal
    
    Write-Host -ForegroundColor Cyan "Creating portals :"
    
    # Chap authentication variables

    $ChapAuth = $False
    $ChapUsr = "user"
    $ChapPwd = "password"
    
    # Note : AuthenticationType has to be UPPERCASE : ONEWAYCHAP or MUTUALCHAP

    $PortalIPTarget | %{ $TGPIP = $_ ; 
                        $InitiatorAddresses | %{
                                                    If (($_.Split("."))[2] -eq ($TGPIP.Split("."))[2]) {
                                                        If ($ChapAuth) {
                                                            New-iSCSITargetPortal –TargetPortalAddress $TGPIP -InitiatorPortalAddress $_ -AuthenticationType ONEWAYCHAP -ChapUsername $ChapUsr -ChapSecret $ChapPwd
                                                        }
                                                        Else {
                                                            New-iSCSITargetPortal –TargetPortalAddress $TGPIP -InitiatorPortalAddress $_
                                                        }
                                                        Write-Host $_ 
                                                    }
                                                }
                    }
    
    # Getting Portal node information

    $Target = Get-iSCSITarget

    $TargetPortal = Get-iSCSITargetPortal

    Write-Host -ForegroundColor Cyan "Current target portals :"

    $TargetPortal | %{ Write-Host $_.TargetPortalAddress":"$_.TargetPortalPortNumber }
    
    # Connecting to portals from all iSCSI Interfaces
    # With 2 /24 Subnet 

    Write-Host -ForegroundColor Cyan 'Creating following connections : '

    $TargetPortal | %{ $TGIP = $_.TargetPortalAddress ; 
                        $InitiatorAddresses | %{
                                                        If (($_.Split("."))[2] -eq ($TGIP.Split("."))[2]) {
                                                            $_ + " -> " + $TGIP
                                                        }
                                                    } 
                                                }


    $TargetPortal | sort TargetPortalAddress | %{ $TGIP = $_.TargetPortalAddress ; $InitiatorAddresses | Sort InterfaceAlias | %{
            # Connect only if subnet is the same
            If (($_.Split("."))[2] -eq ($TGIP.Split("."))[2]) {
                If ($ChapAuth) {
                    # Connect with Chap authentication
                    Connect-iSCSITarget –NodeAddress $Target.NodeAddress -TargetPortalAddress $TGIP -IsMultipathEnabled $True -IsPersistent $True -InitiatorPortalAddress $_ -ReportToPnP $True -AuthenticationType ONEWAYCHAP -ChapUsername $ChapUsr -ChapSecret $ChapPwd
                }
                Else {
                    # Connect without authentication
                    Connect-iSCSITarget –NodeAddress $Target.NodeAddress -TargetPortalAddress $TGIP -IsMultipathEnabled $True -IsPersistent $True -InitiatorPortalAddress $_ -ReportToPnP $True
                }
                Sleep -Milliseconds 100
            }
        } 
            
    }

    Write-Host
    
    # Diplay connections

    Write-Host -ForegroundColor Cyan 'iSCSI connection : '

    Get-iSCSIConnection

    Write-Host
    
    # Display sessions

    Write-Host -ForegroundColor Cyan 'iSCSI sessions : '

    Get-iSCSISession

    Write-Host

    #
    # End Of iSCSI Connection
    #
    
    #
    # iSCSI Luns
    #
    
    If ($DeploymentHost -like $env:COMPUTERNAME) {
        If ($FormatiSCSIDisk -Like "True") { 
            
            Write-Host "iSCSI LUN Discovery" 
            
            $AlliSCSIDisk = Get-Disk | Where-Object BusType –eq "iSCSI"
            
            Write-Host "Disks Initialization and format (PartitionStyle : GPT - FileSystem : NTFS - AllocationUnitSize : 4096)"
            
            $AlliSCSIDisk | %{ Set-Disk -IsOffline $False -Confirm:$False }
            
            $AlliSCSIDisk | %{ Initialize-Disk –Number $_.Number –PartitionStyle GPT –PassThru -Confirm:$False | New-Partition –AssignDriveLetter –UseMaximumSize -Confirm:$False | Format-Volume -FileSystem NTFS -AllocationUnitSize 4096 -Confirm:$False}
        }
        Else {           
            Write-Host "iSCSI LUN Discovery and format disabled in Variable.xml"
        }    
    }
    Else {
        Write-Host "iSCSI LUN Discovery disabled -> Current Host is not DeploymentHost"
    }
    
    
    #
    # Disabling DHCP on all interfaces
    #
    
    Write-Host "Disabling DHCP on all interfaces"
    Get-NetIPInterface | Set-NetIPInterface -Dhcp Disabled
    
    #
    # Firewall Rules
    #
    Write-Host "Disabling DHCP on all interfaces"
    
    # Enabling Inbound Remote Shutdown fw rule (for cluster aware update)
    Write-Host "Enabling Inbound Remote Shutdown fw rule (for cluster aware update)"
    Get-NetFirewallRule -Group "@firewallapi.dll,-36751" | Enable-NetFirewallRule
                                                               
    # Set RunOnce script and autologon
    Write-Host "Setting up next script after reboot"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "Deployment" -Value $AfterRebootScriptCMD
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoLogonCount" -Value 1
    
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUsername" -Value $InstallerUserName
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -Value $InstallerPassword
    
    # Restart
    Write-Host "Restarting" -ForegroundColor Yellow
    Sleep -Seconds 2
    Restart-Computer -Force -Confirm:$false
}

Write-Host "`nScript started at: $StartDate"
$Date = Get-Date
Write-Host "Script finished at: $Date"
Write-Host "`nScript execution time in minutes:" 
$TotalTime = $Date - $StartDate
Write-Host $TotalTime.TotalMinutes

If ($EnableLogging)
{
    Stop-Transcript
}