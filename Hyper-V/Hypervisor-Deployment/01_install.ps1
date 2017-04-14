#
# HYPER-V Deployment Script
# Phase 1 -> 
#   .Initial Configuration 
#   .Roles & features Installation
#   .iSCSI Configuration
#   .Netapp Tools Install
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
	$Script:ScriptLog = "$path\01_Install-" + (Get-Date -f yy.MM.dd-HH.mm.ss) + ".log"
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

# Validating sources & variables
If ($Validate) {
    $NetAppHU = $Path + "\" + ($Variable.Installer.Variable | Where-Object {$_.Name -eq "NetAppHU"}).Value
    $NetAppMPIO = $Path + "\" + ($Variable.Installer.Variable | Where-Object {$_.Name -eq "NetAppMPIO"}).Value
    $AfterRebootScript = $Path + "\02_configure.ps1"
    $AfterRebootScriptCMD = "c:\WINDOWS\system32\WindowsPowerShell\v1.0\powershell.exe -noexit -ExecutionPolicy Bypass -File $AfterRebootScript -Path $Path"
    
    $InstallerUsername = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "InstallerAccount"}).Value
    $InstallerPassword = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "InstallerAccountPassword"}).Value
    
    $DeploymentHost = ($Variable.Installer.Variable | Where-Object {$_.Name -eq "DeploymentHost"}).Value
    
    If ($DeploymentHost -like $env:COMPUTERNAME) {
        Write-Host "Deployment Host is current host "
    } 
    
    If (!(Test-Path $NetAppHU)) {
        $Validate = $false
        Write-Host "Missing $NetAppHU" -ForegroundColor Red
    }
    If (!(Test-Path $NetAppMPIO)) {
        $Validate = $false
        Write-Host "Missing $NetAppMPIO" -ForegroundColor Red
    }
    If (!(Test-Path $AfterRebootScript)) {
        $Validate = $false
        Write-Host "Missing $AfterRebootScript" -ForegroundColor Red
    }
}

If ($Validate) {
    
    # Network configuration
    
    # Sort NICs and rename them
    Write-Host "Sorting and renaming NICs"
    $prefix = "NIC"
    $netAdapters = Get-NetAdapterHardwareInfo | Sort-Object Bus,Function
    $i = 0
    
    foreach ($netAdapter in $netAdapters){
    
        $interface = $netadapter | Get-NetAdapter
        $old = $interface.Name
        $newName = "TEMP" + $old
        $interface | Rename-NetAdapter -NewName $newName
        $i++
    }
    
    $i = 0
    
    foreach ($netAdapter in $netAdapters){
    
        $interface = $netadapter | Get-NetAdapter
        $old = $interface.Name -replace "TEMP",""
        $newName = $prefix + $i
        $interface | Rename-NetAdapter -NewName $newName
        $i++
        Write-Host "Renaming" $old "to:" $newName
    
    }
    
    # Setting up iSCSI Interface
    Write-Host "Setting up iSCSI Interfaces"
    
    $Variable.Installer.NetworkAdapter.iSCSI.IP | %{ 
            If (Get-NetAdapter | Where Name -Like $_.NIC) {
                $Adapter = Get-NetAdapter | Where Name -Like $_.NIC
                
                If (Get-NetLbfoTeamMember -Name $_.NIC -ErrorAction SilentlyContinue) {
                    Write-Host $_.NIC "is a member of" (Get-NetLbfoTeamMember -Name $_.NIC).Team
                    Write-Host "Removing "$_.NIC" of" (Get-NetLbfoTeamMember -Name $_.NIC).Team
                    Remove-NetLbfoTeamMember -Name $_.NIC -Team (Get-NetLbfoTeamMember -Name $_.NIC).Team
                }            
                
                Write-Host "Configuring" $_.NIC "for iSCSI : " $_.Prefix"/"$_.Mask
                $Adapter | Remove-NetIPAddress -AddressFamily IPv4 -Confirm:$False -ErrorAction SilentlyContinue
                $Adapter | Remove-NetIPAddress -AddressFamily IPv6 -Confirm:$False -ErrorAction SilentlyContinue
                
                If ($_.Gateway) {
                    $Adapter | New-NetIPAddress -AddressFamily IPv4 -IPAddress $_.Prefix -PrefixLength $_.Mask -DefaultGateway $_.Gateway -Confirm:$False
                }
                Else {
                    $Adapter | New-NetIPAddress -AddressFamily IPv4 -IPAddress $_.Prefix -PrefixLength $_.Mask -Confirm:$False
                }
                
                $newName = $_.NIC + " - iSCSI (vl" + $_.VLAN + ")"
                Write-Host "Renaming" $_.NIC "to" $newName
                $Adapter | Rename-NetAdapter -NewName $newName
            }        
    }
    
    # Enable WinRM
    Write-Host "Enabling PSRemoting/WinRM"
    Enable-PSRemoting -Force -Confirm:$false

    # Setting up power options to High Performance
    Write-Host "Setting up Power Configuration to High"
    Start-Process 'PowerCfg.exe' -ArgumentList '/s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'-Wait -PassThru | Out-Null

    # Disable APIPA
    Write-Host "Disabling APIPA"
    New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters -Name IPAutoconfigurationEnabled -PropertyType DWord -Value 0 -Force | Out-Null

    # Disable LUA
    Write-Host "Disabling LUA/UAC"
    New-ItemProperty -Path HKLM:Software\Microsoft\Windows\CurrentVersion\policies\system -Name EnableLUA -PropertyType DWord -Value 0 -Force | Out-Null

    # Installing roles & Features
    Write-Host "Install Hyper-V"
    Install-WindowsFeature Hyper-V -IncludeAllSubFeature -IncludeManagementTools -Confirm:$False
    Write-Host "Install Failover-Clustering"
    Install-WindowsFeature Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools -Confirm:$False
    Write-Host "Install Failover-Clustering Management Tools"
    Install-WindowsFeature RSAT-Clustering -IncludeAllSubFeature -Confirm:$False
    
    # iSCSI
    Write-Host "Enabling iSCSI"
    Set-Service -Name MSiSCSI -StartupType Automatic
    Start-Service MSiSCSI
    Get-Service -Name MSiSCSI
    
    # MPIO
    Write-Host "Installing MPIO Feature"
    Install-WindowsFeature Multipath-IO
   
    # PowerShell 2 ( Netapp MPIO DSM prerequisite )
    Write-Host "Installing Powershell 2"
    Get-WindowsFeature PowerShell-V2 | Install-WindowsFeature -IncludeAllSubFeature -IncludeManagementTools -Confirm:$False
    
    # Unattended Install of Netapp Host utilities MSI
    
    $msipath = $NetAppHU
    Write-Host "Installing Netapp Host utilities $msipath"
    
    If (Test-Path $msipath) {
        Start-Process 'msiexec.exe' -ArgumentList "/i $msipath /quiet MULTIPATHING=1 /norestart" -Wait
        Sleep -Seconds 2
    }
    
    # Unattended Install of Netapp MPIO MSI
    #!!! MOVED TO 02_Configure !!!
    
    #$msipath = $NetAppMPIO
    #Write-Host "Installing Netapp MPIO $msipath"
    
    #If (Test-Path $msipath) {
        #Write-Host "Starting Installer"
        #Start-Process 'msiexec.exe' -ArgumentList "/i $msipath /quiet HYPERVUTIL=1 USESYSTEMACCOUNT=1 LICENSECODE=NOEQSCYNQDDCMA /norestart" -Wait
        #Sleep -Seconds 10
    #}
    
    # After joining the host to a cluster :
    # Start-Process 'msiexec.exe' -ArgumentList "/f $msipath /quiet /norestart" -Wait -PassThru | Out-Null
    
    # Setting up DNS suffix to blank if computer is in a Workgroup
    If (!((gwmi win32_computersystem).partofdomain)) {
        Write-Host "Setting up DNS Suffix"
        Set-DnsClientGlobalSetting -SuffixSearchList @("")    
    }
    
    # Set RunOnce script and autologon
    Write-Host "Setting up next script after reboot"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "Deployment" -Value $AfterRebootScriptCMD
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoLogonCount" -Value 1
    
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUsername" -Value $InstallerUserName
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -Value $InstallerPassword
    
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion" -Name "AutoDeployPath" -Value $Path
    
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

If ($EnableLogging) {
    Stop-Transcript
}