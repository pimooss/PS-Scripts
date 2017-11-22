#
# Secure server Firewall script
# 
# 1. Export firewall configuration (backup)
# 2. Check current RDP connections and let the operator add it's current source ip
# 3. Copy all fw rules
# 4. Limit new rules to a custom range
# 5. Disable default fw rules
#
# Auth: J.DECOMBE
#
#

# ValidRange function
Function ValidRange {
    param (
            [Parameter(Mandatory = $true,Position=0)]
            [string]$Range
            )
    $ErrorActionPreference = "SilentlyContinue"
    If ($Range -like "*.*.*.*-*.*.*.*") {
        $IP1 = ($Range -split "-")[0]
        $IP2 = ($Range -split "-")[1]
        If ([IPAddress]$IP1 -and [IPAddress]$IP2) {   
            Return $True
        }
    }
    ElseIf ($Range -like "*.*.*.*/*") {
        $IP = ($Range -split "/")[0]
        $nlength = ($Range -split "/")[1]
        If ([IPAddress]$IP) {
            If ([int]$nlength -ge 1 -and [int]$nlength -le 32) {
                Return $true
            }
            Else {Return $false}
        }
        Else {Return $false}
    }
    Else {Return $false}
}

$outdir = "$env:SystemDrive\SecureServer"

If (!(Test-Path($outdir))) { New-Item -Path $outdir -ItemType Directory}

 # Default Range
$range_to_add = @()
$range_to_add += "192.168.0.0/24"
$range_to_add += "10.0.0.0/8"
# Add your range hier

# Backing up firewall rules

$backup_file = "$outdir\fw_export_" + (Get-date -Format yyyy_MM_dd-HH_mm_ss).ToString() + ".wfw"

Write-Host "Exporting fw rules to $backup_file"

$backup = netsh advfirewall export $backup_file;

# Checking if backup file exists
If (Test-Path $backup_file) {
    

    Write-Host "Predifined range :"
    $range_to_add

    # Getting a custom Range
    $Answer = Read-Host "Do you want to specify a custom range [Y/N]"
    If ($Answer -like "Y") {
        $AllCustomRange = @()
        $Askformore = $True
        While (!(ValidRange($CustomRange = Read-Host "Custom IP Range (x.x.x.x-x.x.y.y or x.x.x.x/n)")) -or $Askformore) {
            If (ValidRange($CustomRange)) {
                $AllCustomRange += $CustomRange 
                $Answer = Read-Host "Specify more range ? [Y/N]"
                If ($Answer -like "Y") {
                    #$AllCustomRange += $CustomRange 
                }
                Else {
                    $Askformore = $False
                    Break
                }
            }
            ElseIf (!(ValidRange($CustomRange))) {
                Write-Host $CustomRange "is not a valid range"
            }
        }

        $AllCustomRange | %{ Write-host "Custome range :" $_ }
    
        $AllCustomRange | %{  $range_to_add += $_ }
    }
    Else {
        Write-host "Skipping custom range"
    }

    # Getting current RDP client IP

    $net = NetStat -a -n

    # Powershell 5 only
    #$rdp_con = $net | Select-String "ESTABLISHED" |  Select-String "3389" | ConvertFrom-String | Select P2,P3,P4,P5 | Where P3 -like "*.*.*.:3389"
    
    # Powershell 3/4
    $rdp_con_str = $net | Select-String "ESTABLISHED" |  Select-String "3389"
    $rdp_con = $rdp_con_str | % { 
                                   $line = ($_ -replace '^\s+','') -split '\s+' ; 
                                   $properties = @{
                                                    Protocol = $line[0]
                                                    LocalAddress = ($line[1] -split ":")[0]
                                                    LocalPort = ($line[1] -split ":")[1]
                                                    ForeignAddress = ($line[2] -split ":")[0]
                                                    ForeignPort = ($line[2] -split ":")[1]
                                                    State = $line[3]
                                                  };
                                    New-Object -TypeName PSObject -Property $properties                     
                                }

    $rdp_con = $rdp_con | Where LocalPort -Like "3389"

    If ($rdp_con) {
        
        Write-Host -ForegroundColor Cyan $rdp_con.LocalAddress.Count "RDP connection established"

        If ($rdp_con.ForeignAddress.Count -eq 1) {
            $remoteip = $rdp_con.ForeignAddress | Select -First 1
        }
        Else {
            $remoteip = $rdp_con.ForeignAddress | Out-GridView -OutputMode Single -Title "Select your IP"
        }

        Write-Host 'Creating RDP-IN rule for selected ip :' $remoteip
        
        # Creating RDP rule if rdp connection is detected (to keep the established connection)
    
        New-NetFirewallRule -DisplayName "SECURED - RDP-TCP-In (3389) from $remoteip" -Name "SECURED-RDP-TCP-IN-3389-INSTALL" -Direction Inbound -Protocol TCP -LocalPort 3389 -RemoteAddress $remoteip -Action Allow -Enabled True -Group "SECURED" | Out-Null

        New-NetFirewallRule -DisplayName "SECURED - RDP-UDP-In (3389) from $remoteip" -Name "SECURED-RDP-UDP-IN-3389-INSTALL" -Direction Inbound -Protocol UDP -LocalPort 3389 -RemoteAddress $remoteip -Action Allow -Enabled True -Group "SECURED" | Out-Null
    
    }
    Else {
        Write-Host "No rdp connection established"
    }

    # Rules inventory
    
    Write-host "Getting rules and applying filter"
    
    $AllRules = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -LocalOnlyMapping $False

    $Filtered_Rules = $AllRules | Where DisplayGroup -NotLike "Core Networking" | Where DisplayGroup -NotLike "Réseau de base"
    $Filtered_Rules = $Filtered_Rules | Where { (Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $_ ).RemoteAddress -EQ "Any" }
    $Filtered_Rules = $Filtered_Rules | Where { (Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_ ).Protocol –NE "41" }

    Write-host "Found "$Filtered_Rules.Count" rules"

    # Copying new custom rules from default

    Write-host "Copying rules"

    $suffix = "_SECURED"
    $Filtered_Rules | %{ Copy-NetFirewallRule $_.Name -NewName ($_.Name + $suffix) } 

    # Changing copied rules parameters

    Write-host "Setting up ranges"
    $NewRules = Get-NetFirewallRule -Direction Inbound -Action Allow | Where Name -Like "*$suffix"
    $NewRules | %{ Set-NetFirewallRule $_.Name -NewDisplayName ($_.DisplayName + $suffix) }
    $NewRules | %{ Set-NetFirewallRule $_.Name -RemoteAddress $range_to_add }

    # Disabling old rules

    Write-host "Disabling old rules"
    $Filtered_Rules | Disable-NetFirewallRule
    
    Write-host "All done - Server secured"
}

Else { 
    Write-Host -ForegroundColor Yellow "Couldn't find $backup_file - Something went wrong with firewall backup [Exiting script]"
}




