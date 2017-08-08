#
# Create-Dedicated-Tenant.ps1
# Multi Tenant Active Directory - Dedicated Tenant Creation Script
# 
#
# Auth : Joris DECOMBE
#
#

Param (
    [parameter(Mandatory=$true)][ValidateLength(1,17)][string]$Tenant
)

#
# Modules
#

Import-Module ActiveDirectory
Import-Module Hyper-V

#
# Script specific Variables
#

$script:ClientName = $env:CLIENTNAME
$script:CurrentUser = $env:USERNAME

$ScriptPath = "C:\Joris\Scripts\"

#
# Log
#

$LogPath = $ScriptPath+"Logs"
$LogFileName = "Create-Dedicated-Tenant-"+(Get-Date -Format yyyyMMdd-HHmmss)+".log"
$LogFile = "$LogPath\$LogFileName"

Start-Transcript $LogFile
Write-Host (Get-Date -Format 'HH:mm:ss') ": Script Launched by $CurrentUser from $ClientName"

#
# Global Variables and Functions Import
#

$GlobalFile = $ScriptPath+"Global.ps1"

If (Test-Path $GlobalFile) {
    Write-Host (Get-Date -Format 'HH:mm:ss') ": DotSourcing $GlobalFile"
}
Else {
    Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": DotSourcing $GlobalFile : Error File Not Found"
    Stop-Transcript
    Exit
}

. $GlobalFile

#
# Go
#

# Tenant folder and file

# Creating Folder structure

If (!(Test-Path "$ScriptPath\Tenants" -ErrorAction SilentlyContinue)) {
    New-Item -Path "$ScriptPath" -ItemType Directory -Name "Tenants" -Confirm:$false | Out-Null
}

$TenantPath = "$ScriptPath\Tenants\$Tenant"

If (!(Test-Path $TenantPath -ErrorAction SilentlyContinue)) {
    New-Item -Path "$ScriptPath\Tenants" -ItemType Directory -Name $Tenant -Confirm:$false | Out-Null
}

$Outputfile = $TenantPath + "\" + $xmlFileName

$Exists = $False

If (Test-Path $Outputfile) {
    $Exists = $True
}

$datetime = (Get-Date -Format yyyyMMdd-HHmmss)

If (!$Exists) {

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": New Tenant [$Tenant]"

    # Creating xml file
    $xmlWriter = New-Object System.XMl.XmlTextWriter($Outputfile,$Null)
    $xmlWriter.Formatting = 'Indented'
    $xmlWriter.Indentation = 1
    $xmlWriter.IndentChar = "`t"
    $xmlWriter.WriteStartDocument()
    $xmlWriter.WriteComment("Tenant info")
    $xmlWriter.WriteComment("Created $datetime")
    $xmlWriter.WriteStartElement('Tenant',"")
    $xmlWriter.WriteAttributeString('Name', $Tenant)

    $xmlWriter.WriteEndElement()
    $xmlWriter.WriteEndDocument()
    $xmlWriter.Flush()
    $xmlWriter.Close()

}
Else {
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Existing Tenant [$Tenant]"
}

# Reading tenant xml file
$xml = New-Object -TypeName XML
$xml.Load($Outputfile)

$DD_Exists = $False
If ($xml | Select-Xml -Xpath "//DedicatedDomain[@enabled=true]") {
    $DD_Exists = $True
    Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": Dedicated Domain already exists for Tenant [$Tenant] :"
    ($xml | Select-Xml -Xpath "//DedicatedDomain[@enabled=true]").Node.DedicatedDomain.Name | %{Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ":" $_ }
}

# Getting existing dedicated DCs

Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Getting all Dedicated DC VMs"

$All_Tenants_DD_VMs = @()
$Hypervisors | %{ Get-VM -ComputerName $_ | Where Name -like "$DD_VMPrefix*" | %{$All_Tenants_DD_VMs += $_ } }

Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": "$All_Tenants_DD_VMs.Count" DC VMs found"

#
# Generating dedicated DCs Name
#

$Tenant_DCs_Name = @()

If ($All_Tenants_DD_VMs) {
    [int]$lastdc_id = $All_Tenants_DD_VMs | Sort | Select -Last 1 | %{ $_.Name -replace $DD_VMPrefix,"" }
}
Else {
    [int]$lastdc_id = 0
}

If ($lastdc_id % 2 -eq 0) { $incr = 1 } #add 1 if last id is even
ElseIf ($lastdc_id % 2 -eq 1) { $incr = 2 } #add 2 if last id is odd

$Tenant_DCs_Name += $DD_VMPrefix + ($lastdc_id+ $incr).ToString("000")
$incr++
$Tenant_DCs_Name += $DD_VMPrefix + ($lastdc_id+ $incr).ToString("000")

Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Generated DC VMs names"
Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": ----------------------"
$Tenant_DCs_Name | %{Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ":" $_ }
Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": ----------------------"

#
# Generating dedicated domain name
#

# Getting all tenants info in xml files

$xmlfiles = ((Split-Path $TenantPath) | Get-ChildItem -Filter $xmlFileName -Recurse).FullName

$all_Tenants_DD = @()

$xmlfiles | % {
    [xml]$content = Get-content $_
    $query = $content | Select-Xml -Xpath "//DedicatedDomain"
    $query_tenant = ($content | Select-Xml -Xpath "//Tenant").Node.Name
    If ($query) {
        $all_Tenants_DD += [pscustomobject]@{TenantName=$query_tenant ; DedicatedDomain = $query.Node} 
    }
}

If ($all_Tenants_DD | Where TenantName) {
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": found" (($all_Tenants_DD).TenantName).Count "Tenant with dedicated domains"
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": found" (($all_Tenants_DD).DedicatedDomain.Name).Count "dedicated domains"
    # Getting last id
    ($all_Tenants_DD).DedicatedDomain.Name | Sort | Select -Last 1 | %{ [int]$lastdd_id = ($_ -replace $DD_DomainPrefix,"") -replace $DD_DomainSuffix,"" }
}
Else {
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": found 0 Tenant with dedicated domains"
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": found 0 dedicated domains"
    [int]$lastdd_id = 0
}

# Generating Name

$Tenant_DD_Name = $DD_DomainPrefix + ($lastdd_id + 1).ToString("000") + $DD_DomainSuffix
$Tenant_DD_Netbios_Name = $DD_DomainPrefix + ($lastdd_id + 1).ToString("000")
$Tenant_DD_Recovery_Pwd = Generate-Password
$Tenant_DD_Admin_Pwd = Generate-Strong-Password
$Tenant_DD_Admin_Pwd_SS = ConvertTo-SecureString -String $Tenant_DD_Admin_Pwd -AsPlainText -Force

$Tenant_DD_User = "it-"+$Tenant
$Tenant_DD_Pwd = Generate-Password
$Tenant_DD_SS = $Tenant_DD_Pwd | ConvertTo-SecureString -AsPlainText -Force

Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Generated Dedicated Domain name : $Tenant_DD_Name"
Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Generated Dedicated Domain netbios name : $Tenant_DD_Netbios_Name"
Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Generated Dedicated Domain Recovery Password : $Tenant_DD_Recovery_Pwd"

# Getting template GPO 

$GPOTemplate_WSUS = "GPO-Template-WSUS"
$GPOTemplate_WSUS_Content = Get-GPRegistryValue $GPOTemplate_WSUS -Key "HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\WindowsUpdate\" | Where Type -ne "Unknown" | Where Value

#$GptTmplFile = $ScriptPath + "\GptTmpl.inf"
#If (Test-Path $GptTmplFile) {
#    $GPOTemplate_Delegation_Ini_Content = Get-IniContent $GptTmplFile
#}
#Else {
#    Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": [$GptTmplFile] not found!"
#}

#
# Preparing xml data
#

$newnode = $xml.CreateElement('DedicatedDomain')
        
$AttrToWrite = @{}
$AttrToWrite.CreatedBy = $CurrentUser
$AttrToWrite.CreatedFrom = $ClientName
$AttrToWrite.CreationDateTime = (Get-Date -Format yyyyMMdd-HHmmss)
$AttrToWrite.GetEnumerator() | %{
    $newnode.SetAttribute($_.Key, $_.Value) | Out-Null
}

$ElemToWrite = @{}
$ElemToWrite.Name = $Tenant_DD_Name
$ElemToWrite.NetbiosName = $Tenant_DD_Netbios_Name
$ElemToWrite.DCs = ($Tenant_DCs_Name -join ",")
$ElemToWrite.Enabled = "true"
$ElemToWrite.RecoveryPassword = $Tenant_DD_Recovery_Pwd
$ElemToWrite.AdminPassword = $Tenant_DD_Admin_Pwd
$ElemToWrite.TenantUser = $Tenant_DD_User
$ElemToWrite.TenantPassword = $Tenant_DD_Pwd
$ElemToWrite.GetEnumerator() | %{
    $nodekey = $_.Key.ToString()
    $subnode = $xml.CreateElement($nodekey)
    $newnode.AppendChild($subnode) | Out-Null
    $newnode.$nodekey = $_.Value.ToString()
}

$xml.Tenant.AppendChild($newnode) | Out-Null
$xml.Save($Outputfile)

#
# Creating VMs
#

$start = Get-Date

# Making variable array

$Deployment_Info = @()

# Even VM on Even HV
$Tenant_DCs_Name | Where { [int]($_ -replace '[a-zA-Z]','') % 2 -eq 0 } | %{
    $IP = $DD_IP_Prefix + ":" + ([int]($_ -replace '[a-zA-Z]',''))
    $HV = ($Hypervisors | Where { [int]($_ -replace '[a-zA-Z]','') % 2 -eq 0 } | Select -First 1 ) 
    $Deployment_Info += [pscustomobject]@{VM = $_ ; IP = $IP ; HV = $HV }
}

# Odd VM on Odd HV
$Tenant_DCs_Name | Where { [int]($_ -replace '[a-zA-Z]','') % 2 -eq 1 } | %{
    $IP = $DD_IP_Prefix + ":" + ([int]($_ -replace '[a-zA-Z]',''))
    $HV = ($Hypervisors | Where { [int]($_ -replace '[a-zA-Z]','') % 2 -eq 1 } | Select -First 1 )
    $Deployment_Info += [pscustomobject]@{VM = $_ ; IP = $IP ; HV = $HV }
}

#
# Creating DNS Delegation
#

Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": Creating stub zone [$Tenant_DD_Name] [Masters:"(($Deployment_Info | Sort VM).IP -join ",")"] on [$RootDomainFQDN]"
Add-DnsServerStubZone -Name $Tenant_DD_Name -MasterServers ($Deployment_Info | Sort VM).IP -ReplicationScope Domain -PassThru -ComputerName $RootDomainFQDN | Out-Null

#
# Deploy
#

$i = 0
$Deployment_Info | Sort | %{

    $Deployment_VM = $_.VM
    $Deployment_HV = $_.HV
    $Deployment_VM_IP = $_.IP

    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": ----------------------"
    Write-Host -ForegroundColor DarkMagenta (Get-Date -Format 'HH:mm:ss') ": Deploying VM [$Deployment_VM] on hypervisor [$Deployment_HV]"
    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": ----------------------"

    Write-Host -ForegroundColor Gray (Get-Date -Format 'HH:mm:ss') ": Creating session on hypervisor [$Deployment_HV]"

    $Deployment_HV_Session = New-PSSession -ComputerName $Deployment_HV

    # Generating IP from name
    #$Deployment_VM_IP = $DD_IP_Prefix + ":" + [int]($Deployment_VM -replace '[a-zA-Z]','')
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Generated IP [$Deployment_VM_IP]"

    $Deployment_DD_DNS = ($Deployment_Info | Sort VM).IP -join ","

    If ($i -eq 0) {
        #$NextDeployment_VM_IP = ($Deployment_Info | Where { $_.VM -ne $Deployment_VM }).IP
        #$NextDeployment_VM_IP = $DD_IP_Prefix + ":" + (([int]($Deployment_VM -replace '[a-zA-Z]','')) + 1)
        #$Deployment_DD_PrincipalDNS = $Deployment_VM_IP
        #$Deployment_DD_DNS = $Deployment_DD_PrincipalDNS,$NextDeployment_VM_IP
    }
    Else {
        #$Deployment_DD_DNS = $Deployment_DD_PrincipalDNS,"::1"
    }

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Generated Primary DNS Server IP [$Deployment_DD_DNS]"

    $Deployment_VHD_Source = "\\" + $Deployment_HV + "\" + ($DD_Template_core -replace ':','$')
    $Deployment_VHD_Target = "\\" + $Deployment_HV + "\" + ($DD_VHD_Path -replace ':','$') + "\" + $Deployment_VM + ".vhdx"
    $VM_VHD_Target = $DD_VHD_Path + "\" + $Deployment_VM + ".vhdx"

    Write-Host (Get-Date -Format 'HH:mm:ss') ": Creating VM from template [$Deployment_VHD_Source]"

    If (!(Test-Path $Deployment_VHD_Target)) {
        Write-Host -ForegroundColor DarkMagenta (Get-Date -Format 'HH:mm:ss') ": Copying new VHD [$Deployment_VHD_Target]"
        Copy-Item $Deployment_VHD_Source $Deployment_VHD_Target
        Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": VHD Copy completed"
    }
    Else {
        Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$Deployment_VHD_Target] already exists ... using existing vhdx"
    }

    Write-Host -ForegroundColor DarkMagenta (Get-Date -Format 'HH:mm:ss') ": Creating VM [$Deployment_VM] [MemoryStartupBytes:$DD_MemoryStartupBytes] [VHDPath:$VM_VHD_Target] [SwitchName:$vSwitchName] [Generation:2]"
    New-VM -Name $Deployment_VM `
            -MemoryStartupBytes $DD_MemoryStartupBytes `
            -VHDPath $VM_VHD_Target `
            -SwitchName $vSwitchName `
            -Generation 2 `
            -ComputerName $Deployment_HV | Out-Null 
    
    $Deployment_AutoStartDelay = (Get-Random -Minimum 30 -Maximum 300) 
    Write-Host -ForegroundColor DarkMagenta (Get-Date -Format 'HH:mm:ss') ": Configuring VM [$Deployment_VM] [ProcessorCount:$DD_ProcessorCount] [DynamicMemory] [MemoryMinimumBytes:$DD_MemoryMinimumBytes] [MemoryMaximumBytes:$DD_MemoryMaximumBytes]"
    Write-Host -ForegroundColor DarkMagenta (Get-Date -Format 'HH:mm:ss') ": Configuring VM [$Deployment_VM] [AutomaticStartAction:StartIfRunning] [AutomaticStartDelay:$Deployment_AutoStartDelay] [AutomaticStopAction:Save]"
    
    Set-VM -Name $Deployment_VM `
            -ProcessorCount $DD_ProcessorCount `
            -DynamicMemory `
            -MemoryMinimumBytes $DD_MemoryMinimumBytes `
            -MemoryMaximumBytes $DD_MemoryMaximumBytes `
            -AutomaticStartAction StartIfRunning `
            -AutomaticStartDelay $Deployment_AutoStartDelay `
            -AutomaticStopAction Save `
            -ComputerName $Deployment_HV | Out-Null 
    
    Write-Host -ForegroundColor DarkMagenta (Get-Date -Format 'HH:mm:ss') ": Configuring VM [$Deployment_VM] [VlanID:$ADC_PFS_VLAN] [Mode:Access]"
    Set-VMNetworkAdapterVlan -VMName $Deployment_VM -Access -VlanId $ADC_PFS_VLAN -ComputerName $Deployment_HV

    $end = Get-Date

    $deploymentduration = New-TimeSpan -Start $start -End $End
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Deployment took" ([math]::round($deploymentduration.TotalSeconds)) "seconds"

    # Starting VM and post install
    Start-VM -VMName $Deployment_VM -ComputerName $Deployment_HV

    Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": Waiting for boot"
        
    Sleep -Seconds 5

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Launching Post Install"
    
    Invoke-Command $Deployment_HV_Session -ScriptBlock {

        param($Deployment_VM, $DD_TemplateAdmin_User, $DD_TemplateAdmin_SS, $DD_GW, $DD_DNS, $Deployment_VM_IP,$Tenant_DD_Name,$Tenant_DD_Netbios_Name, $i, $Deployment_DD_DNS, $Tenant_DD_Recovery_Pwd, $Tenant_DD_Admin_Pwd_SS, $NTPServer, $DD_DefaultSiteName, $RootDomainFQDN)

        $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DD_TemplateAdmin_User,$DD_TemplateAdmin_SS

        While ((New-PSSession -VMName $Deployment_VM -Credential $credentials -ErrorAction SilentlyContinue).Availability -ne "Available") {
            Sleep -Seconds 1
        }

        # Disabling Time synchronization

        Write-Host -ForegroundColor DarkMagenta (Get-Date -Format 'HH:mm:ss') ": Configuring VM [$Deployment_VM] [Disable-VMIntegrationService:Time Synchronization]"
        Disable-VMIntegrationService -VMName $Deployment_VM -Name "Time Synchronization"

        # Renaming VM
        
        $TargetSession = New-PSSession -VMName $Deployment_VM -Credential $credentials

        
        Invoke-Command $TargetSession -ScriptBlock {
            param($Deployment_VM) ; 
            Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Renaming VM to [$Deployment_VM]"
            Rename-Computer $Deployment_VM -Restart
        } -ArgumentList $Deployment_VM

        Sleep -Seconds 3

        # Assigning IP
        While ((New-PSSession -VMName $Deployment_VM -Credential $credentials -ErrorAction SilentlyContinue).Availability -ne "Available") {
            Sleep -Seconds 1
        }

        $TargetSession = New-PSSession -VMName $Deployment_VM -Credential $credentials

        Invoke-Command $TargetSession -ScriptBlock { 
            param($Deployment_VM_IP,$DD_GW);
            Write-Host -ForegroundColor DarkCyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] IP Configuration [IP:$Deployment_VM_IP][GW:$DD_GW]"
            $nic = Get-NetAdapter -Physical | Where Status -EQ Up | Select -First 1;
            New-NetIPAddress -InterfaceIndex $nic.IfIndex -IPAddress $Deployment_VM_IP -PrefixLength 64 -DefaultGateway $DD_GW -AddressFamily IPv6 | Out-Null 
        } -ArgumentList ($Deployment_VM_IP,$DD_GW)

        # DNS Configuration
        Invoke-Command $TargetSession -ScriptBlock {
            param($Deployment_DD_DNS);
            Write-Host -ForegroundColor DarkCyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] IP Configuration [DNS:$Deployment_DD_DNS]"
            $nic = Get-NetAdapter -Physical | Where Status -EQ Up | Select -First 1;
            Set-DnsClientServerAddress -InterfaceIndex $nic.IfIndex -ServerAddresses $Deployment_DD_DNS | Out-Null 
        } -ArgumentList $Deployment_DD_DNS

        Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Post Install -> Phase 2"
        Invoke-Command $TargetSession -ScriptBlock {
            param($Deployment_VM_IP,$DD_DNS,$NTPServer);

            # Enable RemoteDesktop
            Write-Host -ForegroundColor DarkBlue (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Enable RemoteDesktop"
            (Get-WmiObject Win32_TerminalServiceSetting -Namespace root\cimv2\TerminalServices).SetAllowTsConnections(1,1) | Out-Null
            (Get-WmiObject -Class "Win32_TSGeneralSetting" -Namespace root\cimv2\TerminalServices -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(0) | Out-Null
            Get-NetFirewallRule -Group "@FirewallAPI.dll,-28752" | Set-NetFirewallRule -Enabled true | Out-Null 

            # Enable Firewall rules
            Write-Host -ForegroundColor DarkBlue (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Enabling Firewall rules"
            Get-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" | Set-NetFirewallRule -Enabled true | Out-Null 
            Get-NetFirewallRule -Name "FPS-ICMP6-ERQ-In" | Set-NetFirewallRule -Enabled true | Out-Null 

            # Install SNMP
            Write-Host -ForegroundColor DarkBlue (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Installing SNMP"
            Install-WindowsFeature SNMP-Service -IncludeManagementTools | Out-Null 

            # AD DS
            Write-Host -ForegroundColor DarkYellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Installing AD DS Features"
            Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -IncludeAllSubFeature | Out-Null 
            Install-WindowsFeature DNS -IncludeManagementTools -IncludeAllSubFeature | Out-Null 

            # DNS Server Configuration
            Write-Host -ForegroundColor DarkYellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Configuring DNS Server [ListenAddress:$Deployment_VM_IP]"
            & dnscmd /ResetListenAddresses $Deployment_VM_IP | Out-Null
            
            Write-Host -ForegroundColor DarkYellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Configuring DNS Server [Forwarder:$DD_DNS]"
            Set-DnsServerForwarder -IPAddress $DD_DNS -PassThru | Out-Null 
            
            Restart-Service DNS -Force -Confirm:$false

            # NTP Configuration
            Write-Host -ForegroundColor DarkBlue (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Configuring NTP [NTPServer:$NTPServer]"
            & W32tm /config /manualpeerlist:$NTPServer /syncfromflags:manual /reliable:yes /update | Out-Null

        } -ArgumentList $Deployment_VM_IP,$DD_DNS,$NTPServer


        # Creating Domain if first deployment
        If ($i -eq 0) {
            #Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$Deployment_VM] Creating Domain [$Tenant_DD_Name]"
            Invoke-Command $TargetSession -ScriptBlock {
                param($Tenant_DD_Name,$Tenant_DD_Netbios_Name,$Tenant_DD_Recovery_Pwd,$DD_DNS,$Deployment_VM_IP,$RootDomainFQDN);
                
                Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating Domain [$Tenant_DD_Name]"
                Install-ADDSForest -CreateDnsDelegation:$False `
                                    -DatabasePath "C:\Windows\NTDS" `
                                    -DomainMode "Win2012R2" `
                                    -DomainName $Tenant_DD_Name `
                                    -DomainNetbiosName $Tenant_DD_Netbios_Name `
                                    -ForestMode "Win2012R2" `
                                    -InstallDns:$True `
                                    -LogPath "C:\Windows\NTDS" `
                                    -NoRebootOnCompletion:$True `
                                    -SysvolPath "C:\Windows\SYSVOL" `
                                    -Force:$True `
                                    -SafeModeAdministratorPassword ($Tenant_DD_Recovery_Pwd | ConvertTo-SecureString -AsPlainText -Force) `
                                    -SkipPreChecks
                
                Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating Domain [$Tenant_DD_Name] : Done"
                
                Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Configuring DNS Server"

                Set-DnsServerForwarder -IPAddress $DD_DNS -PassThru | Out-Null
                
                Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Configuring DNS listen addresses"
                & dnscmd /ResetListenAddresses $Deployment_VM_IP | Out-Null

                Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Restart"

                Restart-Computer -Force:$true -Confirm:$false

            } -ArgumentList ($Tenant_DD_Name,$Tenant_DD_Netbios_Name,$Tenant_DD_Recovery_Pwd,$DD_DNS,$Deployment_VM_IP,$RootDomainFQDN)

        }

        # Else, join domain
        Else {
            Invoke-Command $TargetSession -ScriptBlock {
                param($Tenant_DD_Name,$DD_TemplateAdmin_User,$DD_TemplateAdmin_SS,$Tenant_DD_Netbios_Name,$Tenant_DD_Recovery_Pwd,$DD_DNS,$Deployment_VM_IP,$RootDomainFQDN);

                Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Adding DC to domain [$Tenant_DD_Name]"
                $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "$Tenant_DD_Netbios_Name\$DD_TemplateAdmin_User",$DD_TemplateAdmin_SS
                
                Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Testing connectivity to [$Tenant_DD_Name]"
                $TestConnection = Test-NetConnection $Tenant_DD_Name
                While (!($TestConnection.PingSucceeded)) {
                    Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Waiting for connectivity to [$Tenant_DD_Name]"
                    Sleep -Seconds 5
                    Clear-DnsClientCache -Confirm:$false
                    $TestConnection = Test-NetConnection $Tenant_DD_Name
                }

                Install-ADDSDomainController -Credential $credentials `
                                             -DomainName $Tenant_DD_Name `
                                             -SafeModeAdministratorPassword ($Tenant_DD_Recovery_Pwd | ConvertTo-SecureString -AsPlainText -Force) `
                                             -Force:$True `
                                             -NoRebootOnCompletion:$True `
                                             -SkipPreChecks `
                                             -SiteName "Default-First-Site-Name" `
                                             -SysvolPath "C:\Windows\SYSVOL" `
                                             -DatabasePath "C:\Windows\NTDS" `
                                             -LogPath "C:\Windows\NTDS" `
                                             -InstallDns:$True
                
                Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Adding DC to domain [$Tenant_DD_Name] : Done"
                
                Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Configuring DNS Server"
                Set-DnsServerForwarder -IPAddress $DD_DNS -PassThru
                Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Configuring DNS listen addresses"
                & dnscmd /ResetListenAddresses $Deployment_VM_IP

                Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Restart"
                Restart-Computer -Force:$true -Confirm:$false

                #Add-computer -DomainName $Tenant_DD_Name -Credential $credentials -Restart

            } -ArgumentList ($Tenant_DD_Name,$DD_TemplateAdmin_User,$DD_TemplateAdmin_SS,$Tenant_DD_Netbios_Name,$Tenant_DD_Recovery_Pwd,$DD_DNS,$Deployment_VM_IP,$RootDomainFQDN)

            # Waiting for reboot
            # New Credentials
            $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "$Tenant_DD_Netbios_Name\$DD_TemplateAdmin_User",$DD_TemplateAdmin_SS
            While ((New-PSSession -VMName $Deployment_VM -Credential $credentials -ErrorAction SilentlyContinue).Availability -ne "Available") {
                Sleep -Seconds 1
            }

            # Active Directory Post Install
            
            $TargetSession = New-PSSession -VMName $Deployment_VM -Credential $credentials

            Invoke-Command $TargetSession -ScriptBlock {
                param($Tenant_DD_Name, $Tenant_DD_Admin_Pwd_SS, $DD_TemplateAdmin_SS, $DD_DefaultSiteName);
                
                Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Testing connectivity to [$Tenant_DD_Name]"
                $TestConnection = Test-NetConnection $Tenant_DD_Name
                While (!($TestConnection.PingSucceeded)) {
                    Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Waiting for connectivity to [$Tenant_DD_Name]"
                    Sleep -Seconds 5
                    Clear-DnsClientCache -Confirm:$false
                    $TestConnection = Test-NetConnection $Tenant_DD_Name
                }

                Import-Module ActiveDirectory
                
                # Changing Default Site Name
                Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Changing default site name to [$DD_DefaultSiteName]"
                Get-ADObject -SearchBase (Get-ADRootDSE).ConfigurationNamingContext -filter "objectclass -eq 'site'" | Rename-ADObject -NewName $DD_DefaultSiteName

                # Changing Default Administrator Password
                Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Changing password Policy"
                Get-ADDefaultDomainPasswordPolicy | Set-ADDefaultDomainPasswordPolicy -MinPasswordAge 0

                Sleep -Seconds 5
                
                Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Changing administrator password"
                Get-AdUser "Administrator" | Set-ADAccountPassword -OldPassword $DD_TemplateAdmin_SS -NewPassword $Tenant_DD_Admin_Pwd_SS -Confirm:$false
                Get-AdUser "Administrator" | Set-ADUser -PasswordNeverExpires $True -ChangePasswordAtLogon $False

             } -ArgumentList ($Tenant_DD_Name,$Tenant_DD_Admin_Pwd_SS , $DD_TemplateAdmin_SS, $DD_DefaultSiteName)


        }


    } -ArgumentList ($Deployment_VM, $DD_TemplateAdmin_User, $DD_TemplateAdmin_SS, $DD_GW, $DD_DNS, $Deployment_VM_IP, $Tenant_DD_Name, $Tenant_DD_Netbios_Name, $i, $Deployment_DD_DNS, $Tenant_DD_Recovery_Pwd, $Tenant_DD_Admin_Pwd_SS, $NTPServer, $DD_DefaultSiteName, $RootDomainFQDN)
    
    $end = Get-Date
    $deploymentduration = New-TimeSpan -Start $start -End $End
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": VM Total Deployment & Postinstall took" ([math]::round($deploymentduration.TotalSeconds)) "seconds"

    Remove-PSSession -Session $Deployment_HV_Session

    $i++
    # End of deployment on Hypervisors
}

#
# Post deployment
#

# DNS Stub Zone Transfert from master
Write-Host -ForegroundColor DarkGreen (Get-Date -Format 'HH:mm:ss') ": Refreshing stub zone [$Tenant_DD_Name]"
(Get-ADDomain $RootDomainFQDN).ReplicaDirectoryServers | %{ Start-DnsServerZoneTransfer -Name $Tenant_DD_Name -ComputerName $_ }

# Waiting for connectivity

Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Testing connectivity to [$Tenant_DD_Name]"
$TestConnection = Test-NetConnection $Tenant_DD_Name
While (!($TestConnection.PingSucceeded)) {
    Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Waiting for connectivity to [$Tenant_DD_Name]"
    Sleep -Seconds 5
    Clear-DnsClientCache -Confirm:$false
    $TestConnection = Test-NetConnection $Tenant_DD_Name
}   

# Trust relationship

Write-Host -ForegroundColor DarkGreen (Get-Date -Format 'HH:mm:ss') ": Setting up Trust relationship [$RootDomainFQDN]<-[$Tenant_DD_Name]"

$localContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Domain', $RootDomainFQDN) 
$localDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($localContext)

$remoteContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Domain', $Tenant_DD_Name ,"Administrator",$Tenant_DD_Admin_Pwd) 
$remoteDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($remoteContext)

$localDomain.CreateTrustRelationship($remoteDomain,'Inbound')

# Configuring Dedicated AD

Write-Host -ForegroundColor Green (Get-Date -Format 'HH:mm:ss') ": Configuring Dedicated AD"

$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "$Tenant_DD_Netbios_Name\Administrator",$Tenant_DD_Admin_Pwd_SS

# Waiting for connectivity

Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Testing authentication to [$Tenant_DD_Name]"
$TestConnection = Get-ADDomain $Tenant_DD_Name
While (!($TestConnection)) {
    Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Waiting for authentication success to [$Tenant_DD_Name]"
    Sleep -Seconds 5
    Clear-DnsClientCache -Confirm:$false
    $TestConnection = Get-ADDomain $Tenant_DD_Name
}   

$Tenant_DD_DN = (Get-ADDomain $Tenant_DD_Name).DistinguishedName
$Tenant_DD_RID = (Get-ADDomain $Tenant_DD_Name).InfrastructureMaster
$Tenant_DD_Admin_OU = "OU=Admin,"+$Tenant_DD_DN
$Tenant_DD_Base_OU = "OU=Tenant,"+$Tenant_DD_DN

$TargetSession = New-PSSession -ComputerName $Tenant_DD_RID -Credential $credentials

# Copying GPO files to remote session
$GPOTemplate_Source = $ScriptPath + "Template\GPO"
$GPOTemplate_Destination = "C:\Joris\GPO"

Copy-item $GPOTemplate_Source -Destination $GPOTemplate_Destination -Recurse -ToSession $TargetSession

# Getting Function ScriptBlock
$Func_SB_GetIni = ((Get-item function:Get-IniContent).scriptblock.ast.Extent.Text).ToString()
$Func_SB_OutIni = ((Get-item function:Out-IniFile).scriptblock.ast.Extent.Text).ToString()
#$GlobalFileContent = Get-content $GlobalFile

Invoke-Command $TargetSession -ScriptBlock {

    param($Func_SB_GetIni, $Func_SB_OutIni, $Tenant_DD_Netbios_Name, $Tenant_DD_User, $Tenant_DD_SS, $RootDomainFQDN, $Tenant_DD_DN, $Tenant_DD_Admin_OU, $Tenant_DD_Base_OU, $Tenant, $DefaultDelegationGroups_DD, $DD_DomainJoin_User, $DD_DomainJoin_SS, $DD_AdminGroup, $_AD_ReadAccount_User, $_AD_ReadAccount_SS, $DD_TenantAdminGroup, $DD_TenantUserGroup, $GPOTemplate_WSUS_Content, $GPOTemplate_Destination, $DD_DNS)
    
    . ([ScriptBlock]::Create($Func_SB_GetIni))
    . ([ScriptBlock]::Create($Func_SB_OutIni))
    
    #. ($GlobalFileContent)

    Import-Module ActiveDirectory

    #
    # OU
    #

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating OU Structures"

    # OU Structure

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating OU [$Tenant_DD_Base_OU]"
    New-ADOrganizationalUnit -Name "Tenant" -Path $Tenant_DD_DN

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating OU [$Tenant_DD_Admin_OU]"
    New-ADOrganizationalUnit -Name "Admin" -Path $Tenant_DD_DN

    $Tenant_DD_Users_OU = "OU=Users,$Tenant_DD_Base_OU"
    $Tenant_DD_Groups_OU = "OU=Groups,$Tenant_DD_Base_OU"
    $Tenant_DD_Servers_OU = "OU=Servers,$Tenant_DD_Base_OU"

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating OU [$Tenant_DD_Users_OU]"
    New-ADOrganizationalUnit -Name "Users" -Path $Tenant_DD_Base_OU

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating OU [$Tenant_DD_Groups_OU]"
    New-ADOrganizationalUnit -Name "Groups" -Path $Tenant_DD_Base_OU

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating OU [$Tenant_DD_Servers_OU]"
    New-ADOrganizationalUnit -Name "Servers" -Path $Tenant_DD_Base_OU

    #
    # Groups
    #
    
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating Group [$DD_AdminGroup] [Path:$Tenant_DD_Admin_OU]"
    New-ADGroup -Name $DD_AdminGroup -SamAccountName $DD_AdminGroup -GroupCategory Security -GroupScope DomainLocal -Path $Tenant_DD_Admin_OU
    
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating Group [$DD_TenantAdminGroup] [Path:$Tenant_DD_Admin_OU]"
    New-ADGroup -Name $DD_TenantAdminGroup -SamAccountName $DD_TenantAdminGroup -GroupCategory Security -GroupScope DomainLocal -Path $Tenant_DD_Admin_OU
    
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating Group [$DD_TenantUserGroup] [Path:$Tenant_DD_Admin_OU]"
    New-ADGroup -Name $DD_TenantUserGroup -SamAccountName $DD_TenantUserGroup -GroupCategory Security -GroupScope DomainLocal -Path $Tenant_DD_Admin_OU
    
    # Users

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating User [$DD_DomainJoin_User] [Path:$Tenant_DD_Admin_OU]"
    New-ADUser $DD_DomainJoin_User -ChangePasswordAtLogon $false -AccountPassword $DD_DomainJoin_SS -Path $Tenant_DD_Admin_OU -Enabled $true
    
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating User [$Tenant_DD_User] [Path:$Tenant_DD_Users_OU]"
    New-ADUser $Tenant_DD_User -ChangePasswordAtLogon $false -AccountPassword $Tenant_DD_SS -Path $Tenant_DD_Users_OU -Enabled $true

    # Groups membership

    $RootDomainCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AD_ReadAccount_User,$AD_ReadAccount_SS
    $DefaultDelegationGroups_DD | %{
        Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Getting [$_] info"
        $GroupToAdd = Get-ADGroup $_ -Credential $RootDomainCredentials -Server $RootDomainFQDN
        Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Adding [$_] to [$DD_AdminGroup]"
        Add-ADGroupMember $DD_AdminGroup -Members $GroupToAdd
        
    }
    $DefaultDelegationGroups_DD | Where {$_ -like "*N3-Admins*"} | %{
        Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Getting [$_] info"
        $GroupToAdd = Get-ADGroup $_ -Credential $RootDomainCredentials -Server $RootDomainFQDN
        Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Adding [$_] to [Domain Admins]"
        Add-ADGroupMember "Administrators" -Members $GroupToAdd
    }

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Adding [$Tenant_DD_User] to [$DD_TenantAdminGroup]"
    Add-ADGroupMember $DD_TenantAdminGroup -Members $Tenant_DD_User

    # ACLS

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Setting ACL on [$Tenant_DD_Base_OU] to [$Tenant_DD_Netbios_Name\$DD_AdminGroup]"
    &dsacls $Tenant_DD_Base_OU /G "$Tenant_DD_Netbios_Name`\$DD_AdminGroup"":GA" /I:P | Out-Null

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Setting ACL on [$Tenant_DD_Base_OU] to [$Tenant_DD_Netbios_Name\$DD_TenantAdminGroup]"
    &dsacls $Tenant_DD_Base_OU /G "$Tenant_DD_Netbios_Name`\$DD_TenantAdminGroup"":GA" /I:P | Out-Null
    
    $TargetOU = "CN=Computers" + $Tenant_DD_DN
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Setting ACL on [$TargetOU] to [$Tenant_DD_Netbios_Name\$DD_DomainJoin_User]"
    &dsacls $TargetOU /G "$Tenant_DD_Netbios_Name`\$DD_DomainJoin_User"":CC;computer" | Out-Null

    $TargetOU = $Tenant_DD_Servers_OU
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Setting ACL on [$TargetOU] to [$Tenant_DD_Netbios_Name\$DD_DomainJoin_User]"
    &dsacls $TargetOU /G "$Tenant_DD_Netbios_Name`\$DD_DomainJoin_User"":CC;computer" | Out-Null

    $TargetOU = "CN=Computers" + $Tenant_DD_DN
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Setting ACL on [$TargetOU] to [$Tenant_DD_Netbios_Name\$DD_TenantAdminGroup]"
    &dsacls $TargetOU /G "$Tenant_DD_Netbios_Name`\$DD_TenantAdminGroup"":CC;computer" | Out-Null

    $TargetOU = $Tenant_DD_Servers_OU
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Setting ACL on [$TargetOU] to [$Tenant_DD_Netbios_Name\$DD_TenantAdminGroup]"
    &dsacls $TargetOU /G "$Tenant_DD_Netbios_Name`\$DD_TenantAdminGroup"":CC;computer" | Out-Null

    # Creating GPO
    # Wsus GPO
    $Tenant_GPO_Name = "GPO-WSUS"

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating GPO [$Tenant_GPO_Name]"
    New-GPO $Tenant_GPO_Name | Out-Null

    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Setting up GPO [$Tenant_GPO_Name]"
    $GPOTemplate_WSUS_Content | %{ $_ | Set-GPRegistryValue $Tenant_GPO_Name | Out-Null }

    $TargetOU = "OU=Domain Controllers," + $Tenant_DD_DN
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Linking GPO [$Tenant_GPO_Name] to [$TargetOU]"
    Get-GPO $Tenant_GPO_Name | New-GPLink -Target $TargetOU -LinkEnabled Yes | Out-Null

    # Delegation GPO
    $Tenant_GPO_Name = "GPO-Delegation"
    Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Creating GPO [$Tenant_GPO_Name]"
    #New-GPO $Tenant_GPO_Name

    Import-GPO -Path $GPOTemplate_Destination -BackupGpoName "GPO-Template-Delegation" -TargetName $Tenant_GPO_Name -CreateIfNeeded | Out-Null
    $GPO = Get-GPO $Tenant_GPO_Name
    
    
    $TargetOU = $Tenant_DD_Base_OU
    $GPO | New-GPLink -Target $TargetOU -LinkEnabled Yes | Out-Null

    $GPOPath = "\\"+$GPO.DomainName+"\SYSVOL\"+$GPO.DomainName+"\Policies\{"+$GPO.Id+"}"
    $GptTmplFile = $GPOPath+"\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"

    #New-Item -ItemType Directory -Force -Path (Split-Path $GptTmplFile)

    # Getting SIDs
    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Getting SIDs"
    $Domain_Admins_SID = (Get-ADGroup "Domain Admins").SID.Value
    $Domain_Users_SID = (Get-ADGroup "Domain Users").SID.Value
    $Admins_SID = (Get-ADGroup $DD_AdminGroup).SID.Value
    $Tenant_Local_Admins_SID = (Get-ADGroup $DD_TenantAdminGroup).SID.Value
    $Tenant_Local_Users_SID = (Get-ADGroup $DD_TenantUserGroup).SID.Value

    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Domain_Admins_SID [$Domain_Admins_SID]"
    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Domain_Users_SID [$Domain_Users_SID]"
    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Admins_SID [$Admins_SID]"
    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Tenant_Local_Admins_SID [$Tenant_Local_Admins_SID]"
    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Tenant_Local_Users_SID [$Tenant_Local_Users_SID]"

    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Getting GPO content"

    # Editing Ini File

    #$Content = $GPOTemplate_Delegation_Ini_Content
    $Content = Get-IniContent $GptTmplFile

    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Modifying GPO content"
    $Content.'Group Membership'.'*S-1-5-32-544__Members' = "*" + $Domain_Admins_SID + ",*" + $Admins_SID + ",*" + $Tenant_Local_Admins_SID
    $Content.'Group Membership'.'*S-1-5-32-545__Members' = "*S-1-5-4" + ",*" + $Tenant_Local_Users_SID + ",*" + $Domain_Users_SID 

    Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": [$env:COMPUTERNAME] Writing new GPO content :"

    $Content.'Group Membership'.GetEnumerator() | Sort Name | %{ Write-Host -ForegroundColor Gray $_.Name "=" $_.Value }

    Move-Item $GptTmplFile ($GptTmplFile + ".old")
    Out-IniFile -InputObject $Content -FilePath $GptTmplFile

    # DNS Stub zone setting
    
    (Get-ADDomain).ReplicaDirectoryServers | %{
            
            Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [$_] Creating stub zone [$RootDomainFQDN] [Masters:"$DD_DNS"]"
            Add-DnsServerStubZone -Name $RootDomainFQDN -MasterServers $DD_DNS -ComputerName $_ -PassThru | Out-Null

        }
    
} -ArgumentList ($Func_SB_GetIni, $Func_SB_OutIni, $Tenant_DD_Netbios_Name, $Tenant_DD_User, $Tenant_DD_SS, $RootDomainFQDN, $Tenant_DD_DN, $Tenant_DD_Admin_OU, $Tenant_DD_Base_OU, $Tenant, $DefaultDelegationGroups_DD, $DD_DomainJoin_User, $DD_DomainJoin_SS, $DD_AdminGroup, $AD_ReadAccount_User, $AD_ReadAccount_SS, $DD_TenantAdminGroup, $DD_TenantUserGroup, $GPOTemplate_WSUS_Content, $GPOTemplate_Destination, $DD_DNS)

Remove-PSSession -Session $TargetSession

$end = Get-Date
$deploymentduration = New-TimeSpan -Start $start -End $End
Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": Total deployment duration" ([math]::round($deploymentduration.TotalSeconds)) "seconds"

Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Generating Automation PostInstall Script"

$Deployment_Automation_Script = $DD_Automation_Script_Template
$Deployment_Automation_Script = $Deployment_Automation_Script -replace "%DNS_IP%", (($Deployment_Info | Sort VM).IP -join '","')
$Deployment_Automation_Script = $Deployment_Automation_Script -replace "%TARGETDOMAIN%",$Tenant_DD_Name
$Deployment_Automation_Script = $Deployment_Automation_Script -replace "%JD_ACCOUND_USERNAME%","$Tenant_DD_Netbios_Name\$DD_DomainJoin_User"
$Deployment_Automation_Script = $Deployment_Automation_Script -replace "%JD_ACCOUNT_PASSWORD%",$DD_DomainJoin_Pwd
$Deployment_Automation_Script = $Deployment_Automation_Script -replace "%TARGETOU%","OU=Servers,$Tenant_DD_Base_OU"

$Deployment_Automation_Script | Out-File "$TenantPath\Automation-PostInstall-Script.txt" -Force -Confirm:$false

Start-Process "notepad" "$TenantPath\Automation-PostInstall-Script.txt"

Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": End of deployment"

Stop-Transcript
