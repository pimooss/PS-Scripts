#
# Jaguar Network - Create VM for Windows 2016 (with powershell direct)
#
# J.DECOMBE
#
# Date : 23/03/2017
#
# V.1

# Hostname
$HostName =  Read-Host "Nom de la VM"

# Path
$SMBPath = "F:\Hyper-V"
$TemplatePath = $SMBPath + "\Templates"
$VHDPath = $SMBPath + "\Vhdx"
$VMPath = $SMBPath + "\VMs"

# Ip Configuration
$gw = "2001:4860:4860::1"
$dns = @("2001:4860:4860::8888","2001:4860:4860::8844")

$ipprefix = "2001:4860:4860::"
$ipsuffix = ""
$ip = ""

$ipsuffix = Read-Host "IP address 2001:4860:4860::xxx (ex: 102 or 1:232)"  
$ip = $ipprefix + ":" + $ipsuffix
Write-Host "Resulting ip: $ip"

# Domain Configuration
$domainfqn = contoso.local
$joindomainaccount = "contoso\administrator"

# Prompt or bypass
#$credentials = Get-Credential -Message "VM local Credentials"

$SS = ConvertTo-SecureString -String "stringpwd" -AsPlainText -Force
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "Administrator",$SS

# Go

$Template = "NOTSET"

If (!$HostName) {
    $HostName = "VM" + (Get-Random -Minimum 1000 -Maximum 9999).ToString()
}
Else {
    $HostName = $HostName -replace " ","_"
}

$Template = $TemplatePath + "\w2016-template.vhdx"


If ($Template -ne "NOTSET") {

    $start = Get-Date

    Write-Host "Creating" $HostName "from template" $Template
    $VHDTarget = $VHDPath + "\" + $HostName + ".vhdx"

    If (!(Test-Path $VHDTarget)) {

        Copy-Item $Template $VHDTarget
        #Resize-VHD $VHDTarget -SizeBytes 100GB

        New-VM -Name $HostName -MemoryStartupBytes 2GB -VHDPath $VHDTarget -SwitchName "vSwitch-ADCUST-PFS" -Generation 2

        Set-VM -Name $HostName -ProcessorCount 2 -DynamicMemory -MemoryMinimumBytes 256MB -MemoryMaximumBytes 4GB -AutomaticStartAction StartIfRunning -AutomaticStartDelay 2

        Set-VM -Name $HostName -AutomaticStopAction Save

        Set-VMNetworkAdapterVlan -VMName $HostName -Access -VlanId 2002
        
        Write-Host "VM Created"
        
        $end = Get-Date
    } 
    Else {
        Write-Host -ForegroundColor Yellow $VHDTarget "already exists, please choose another name"
    }

}

$deploymentduration = New-TimeSpan -Start $start -End $End
Write-Host -ForegroundColor Cyan "Deployment took" ([math]::round($deploymentduration.TotalSeconds)) "seconds"

#Read-Host "Press a key to start the VM $Hostname"

Start-VM -VMName $Hostname 

Write-Host -ForegroundColor Green "Vm Deployed : waiting for boot"

Sleep -Seconds 5

#While (!(Get-VM -Name $HostName | Where status -EQ "operating normally")) {
#    Sleep -Seconds 1
#}

While ((New-PSSession -VMName $Hostname -Credential $credentials).Availability -ne "Available") {
    Sleep -Seconds 1
}

#Read-Host "CTRL+C to stop now or any other key to continue"

$TargetSession = New-PSSession -VMName $Hostname -Credential $credentials

Invoke-Command $TargetSession -ScriptBlock {param($Hostname) ; Rename-Computer $Hostname -Restart} -ArgumentList $Hostname

Sleep -Seconds 3

While ((New-PSSession -VMName $Hostname -Credential $credentials).Availability -ne "Available") {
    Sleep -Seconds 1
}

$TargetSession = New-PSSession -VMName $Hostname -Credential $credentials

Invoke-Command $TargetSession -ScriptBlock { 
    param($ip,$gw);
    $nic = Get-NetAdapter -Physical |Where Status -EQ Up | Select -First 1;
    New-NetIPAddress -InterfaceIndex $nic.IfIndex -IPAddress $ip -PrefixLength 64 -DefaultGateway $gw -AddressFamily IPv6  
    } -ArgumentList ($ip,$gw)

Invoke-Command $TargetSession -ScriptBlock {
    param($dns);
    $nic = Get-NetAdapter -Physical |Where Status -EQ Up | Select -First 1;
    Set-DnsClientServerAddress -InterfaceIndex $nic.IfIndex -ServerAddresses $dns
 } -ArgumentList $dns

Invoke-Command $TargetSession -ScriptBlock {
    # Enable RemoteDesktop
    Write-Host "Enable RemoteDesktop"
    (Get-WmiObject Win32_TerminalServiceSetting -Namespace root\cimv2\TerminalServices).SetAllowTsConnections(1,1) | Out-Null
    (Get-WmiObject -Class "Win32_TSGeneralSetting" -Namespace root\cimv2\TerminalServices -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(0) | Out-Null
    Get-NetFirewallRule -Group "@FirewallAPI.dll,-28752" | Set-NetFirewallRule -Enabled true
    # Enable Firewall rules
    Write-Host "Enabling Firewall rules"
    Get-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" | Set-NetFirewallRule -Enabled true
    Get-NetFirewallRule -Name "FPS-ICMP6-ERQ-In" | Set-NetFirewallRule -Enabled true
    # Install SNMP
    Write-Host "Installing SNMP"
    Install-WindowsFeature SNMP-Service -IncludeManagementTools
}

$end = Get-Date
$deploymentduration = New-TimeSpan -Start $start -End $End
Write-Host -ForegroundColor Cyan "Total Deployment & Postinstall took" ([math]::round($deploymentduration.TotalSeconds)) "seconds"

$joindomain = Read-Host "Join domain ? (y/n)"

If ($joindomain -like "y") {
    Write-Host "Joining Domain"
    Invoke-Command $TargetSession -ScriptBlock {param($domainfqn,$joindomainaccount) ; Add-computer -DomainName $domainfqn -Credential $joindomainaccount -Restart} -ArgumentList ($domainfqn,$joindomainaccount)
}

#Copy-Item -ToSession $TargetSession -Path "$env:USERPROFILE\Downloads\iometer.zip" -Destination "c:\"


