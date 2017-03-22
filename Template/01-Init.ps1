#
#   Windows Server template automation - Phase 1
#

# Enable RemoteDesktop
Write-Host "Enable RemoteDesktop"
(Get-WmiObject Win32_TerminalServiceSetting -Namespace root\cimv2\TerminalServices).SetAllowTsConnections(1,1) | Out-Null
(Get-WmiObject -Class "Win32_TSGeneralSetting" -Namespace root\cimv2\TerminalServices -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(0) | Out-Null
Get-NetFirewallRule -Group "@FirewallAPI.dll,-28752" | Set-NetFirewallRule -Enabled true

# Setting up WinRM
Write-Host "Setting up WinRM"
Set-NetFirewallRule -Name WINRM-HTTP-In-TCP-PUBLIC -RemoteAddress Any
Enable-WSManCredSSP -Force -Role Server

Enable-PSRemoting -Force -SkipNetworkProfileCheck

    # Low winrm Security Parameters
    #winrm set winrm/config/client/auth '@{Basic="true"}'
    #winrm set winrm/config/service/auth '@{Basic="true"}'
    #winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Set Culture and Keyboard to FR-fr
Write-Host "Set Culture and Keyboard to FR-fr"
Set-Culture 1036
Set-WinUserLanguageList -LanguageList FR-FR -Confirm:$false
Set-WinDefaultInputMethodOverride -InputTip "040C:0000040C" 

# Enable AutoUpdate
Write-Host "Enable AutoUpdate"
$AU = (New-Object -com "Microsoft.Update.AutoUpdate")
$AU.EnableService()
$AUSettigns = (New-Object -com "Microsoft.Update.AutoUpdate").Settings
$AUSettigns.NotificationLevel = 4
$AUSettigns.Save

# Install .Net3.5
Write-Host "Installing .Net3.5"
$CD = (Get-Volume | Where DriveType -Eq "CD-ROM").DriveLetter.ToString()
$SourceDirectory = $CD + ":\Sources\sxs\" 
Install-WindowsFeature NET-Framework-Core  -Source $SourceDirectory 

# Enable Firewall rules
Write-Host "Enabling Firewall rules"
Get-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" | Set-NetFirewallRule -Enabled true
Get-NetFirewallRule -Name "FPS-ICMP6-ERQ-In" | Set-NetFirewallRule -Enabled true

# Install SNMP
Write-Host "Installing SNMP"
Install-WindowsFeature SNMP-Service -IncludeManagementTools

# Install NFS Client
Write-Host "Installing NFS Client"
Install-WindowsFeature NFS-Client

# Install Windows Server Backup
Write-Host "Installing Windows Server Backup"
Install-WindowsFeature Windows-Server-Backup

# Removing page file
Write-Host "Removing Page File"
$pageFileMemoryKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty -Path $pageFileMemoryKey -Name PagingFiles -Value ""

# Do a full Windows Update & Reboot
Write-Host "Launching Update script"
.\win-updates.ps1 

Write-Host "Rebooting"
Restart-Computer

