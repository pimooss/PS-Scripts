#
# HV-Replica-AutoConfig.ps1
#
# Purpose :
#   Hyper-V Cluster Automatic Replication Configuration for new VMs
#
# Features :
#   - Dynamic initial replication scheduled depending on bandwidth and VM size
#   - VSS capable VM detection
#   - Disk size limit filtering
#   - Shared VHDx filtering
#   - Log sent by mail
#
# Joris DECOMBE
#

# HV Infrastructure variables
$Cluster = "%CLUSTER_FQDN%"
$ReplicationTarget = "%HV_REPLICATION_BROKER_FQDN%"

# Replication settings variables

$ReplicationStartTime = "21:00"
$InitialReplicationStopTime = "05:00"
$ReplicationServerPort = 80
$AuthenticationType = "Kerberos"
$InitialReplicationStartTime = Get-Date $ReplicationStartTime

# Bandwidth variable
# Used to estimate time to transfert data
$Bandwidth = 1GB/8/3 #333mbits/s
# Ignoring VM with bigger vhdx than $DiskSizeLimit
$DiskSizeLimit = 300GB

$ReplicationFrequencySec = 5*60 

$AutoResynchronizeIntervalStart = "21:00:00"
$AutoResynchronizeIntervalEnd = "05:00:00"

$EnableWriteOrderPreservationAcrossDisks = $False

# Mail variables
$Entity = "%COMPANY%"
$MSubject = $Entity + " - Hyper-V Replica Report"
$MTo = "to@company.com"
$MFrom = "hypervreplicareport@company.com"
$MSmtp = "smtp.company.com"

# Log path variable
$logpath = "c:\Scripts\Logs" #To change if needed
$logpath += "\Set-Replication-MAR02-"+(get-date -Format "yyyymmdd-HHmmss")+".log"

# Create log path if needed
If (!(Test-Path (Split-Path $logpath))) { New-Item (Split-Path $logpath) -ItemType Directory }
# Start logging
Start-Transcript -Path $logpath

# Go
Import-Module Hyper-V

$clusterNodes = Get-ClusterNode -Cluster $Cluster;

$VMArray = @()

Write-Host "Setting up new HV replica for cluster $Cluster"
ForEach($node in $clusterNodes) {
    #Uncomment following lines once to enable CredSSP on remote nodes if needed
    #Enable-WSManCredSSP –Role Client –DelegateComputer $node.name -Force
    #Invoke-Command –ComputerName  $node.name –ScriptBlock { Enable-WSManCredSSP –Role Server -Force }
    
    Write-Host $node.Name
    $VMArray += Get-VM -ComputerName $node.Name

}

$VMReplicated = $VMArray | Where { ($_.ReplicationState -NE "Disable") -and  ($_.State -EQ "Running")  } | Sort Name
$VMsToDo = $VMArray | Where { ($_.ReplicationState -EQ "Disabled") -and  ($_.State -EQ "Running")  } | Sort Name

Write-Host "VMs without replication:" $VMsToDo.Count
Write-Host "VMs with replication:" $VMReplicated.Count

# Getting Waiting for Initial replication VMs 
$WaitForInitVmsArray = @()
$WaitForInitVms = ($VMReplicated | Get-VMReplication | Where State -eq ReadyForInitialReplication)
ForEach ($VM In $WaitForInitVms) {  
    $Size = 0
    $MaxSize = 0
    $VM.ReplicatedDisks | %{ Get-VHD -ComputerName $_.ComputerName $_.Path | %{$Size += $_.FileSize ; $MaxSize = $_.Size} }
    $WaitForInitVmsArray += [pscustomobject]@{Name = $VM.VMName ; `
                                                InitialReplStart = $VM.InitialReplicationStartTime ; `
                                                "Size" = $Size ; `
                                                "MaxSize" = $MaxSize `
                                            }
}

Write-Host
Write-Host "Next Scheduled VMs for Initial Replication"
Write-Host

$WaitForInitVmsArray | Sort InitialReplStart,VMName | Format-Table -AutoSize

If ($WaitForInitVmsArray.Count -gt 0) { 
    If (($WaitForInitVmsArray | Sort InitialReplStart | Select-Object -Last 1).InitialReplStart) {
        $InitialReplicationStartTime = ($WaitForInitVmsArray | Sort InitialReplStart | Select-Object -Last 1).InitialReplStart
        $InitialReplicationStartTime = $InitialReplicationStartTime.AddMinutes($InitialReplicationDelayMinutes)
    }
    Else {
        $InitialReplicationStartTime = $InitialReplicationStartTime
    }
}

#
# Setting up new replication
#

$NewRepl = 0

ForEach ($VM In $VMsToDo) {
    
    If ($VM.HardDrives | %{ Get-VHD -ComputerName $VM.ComputerName $_.Path | Where Size -gt $DiskSizeLimit  } ) { 
        Write-Host -ForegroundColor Yellow $VM.VMName " VHDx is above size limit -> Skipping VM replication"
    }
    Else {
        
        $TimeSpan = New-TimeSpan -Start (Get-date) -End $InitialReplicationStartTime

        $VHDxSize = 0
        $VM.HardDrives | %{ Get-VHD -ComputerName $VM.ComputerName $_.Path | %{ $VHDxSize += $_.Size } }
        # Checking if InitialReplication Queue is greater than 7 days
        If ($TimeSpan.TotalHours -lt 7*24) {
            # Check if VM has shared VHDx
            If (!($VM.HardDrives | Where SupportPersistentReservations -EQ $True)) {
                
                # Check if VSS should be enabled
                $VSSEnabled = $False
                If (($VM.VMIntegrationService | Where Name -eq "VSS" | Where Enabled -eq $True | Where PrimaryStatusDescription -eq "OK")) {
                    $VSSEnabled = $True
                }
                Else {
                    $VSSEnabled = $False
                }

                Write-Host "Enabling replication for" $VM.VMName
                If ($VSSEnabled) {
                    Enable-VMReplication `
                                -VMName $VM.VMName `
                                -ComputerName $VM.ComputerName `
                                -ReplicaServerName $ReplicationTarget `
                                -ReplicaServerPort $ReplicationServerPort `
                                -AuthenticationType $AuthenticationType `
                                -CompressionEnabled $True `
                                -AutoResynchronizeEnabled $True `
                                -AutoResynchronizeIntervalStart $AutoResynchronizeIntervalStart `
                                -AutoResynchronizeIntervalEnd $AutoResynchronizeIntervalEnd `
                                -ReplicationFrequencySec $ReplicationFrequencySec `
                                -RecoveryHistory 24 `
                                -VSSSnapshotFrequencyHour 4
                }
                Else {
                    Enable-VMReplication `
                                -VMName $VM.VMName `
                                -ComputerName $VM.ComputerName `
                                -ReplicaServerName $ReplicationTarget `
                                -ReplicaServerPort $ReplicationServerPort `
                                -AuthenticationType $AuthenticationType `
                                -CompressionEnabled $True `
                                -AutoResynchronizeEnabled $True `
                                -AutoResynchronizeIntervalStart $AutoResynchronizeIntervalStart `
                                -AutoResynchronizeIntervalEnd $AutoResynchronizeIntervalEnd `
                                -ReplicationFrequencySec $ReplicationFrequencySec `
                                -RecoveryHistory 24
                }
                                
                        
                $EstimatedTimeToCopy = [System.Math]::Truncate(($VHDxSize / $Bandwidth) /60 ) #Minutes
         
                Write-Host "Setting up initial replication for" $VM.VMName "at $InitialReplicationStartTime"

                Write-Host "Estimated time for initial replication "$EstimatedTimeToCopy "minutes for" ($VHDxSize/1GB) "GB"

                Sleep -Seconds 1
        
                # Scheduled
                
                Start-VMInitialReplication -ComputerName $VM.ComputerName -VMName $VM.VMName -InitialReplicationStartTime $InitialReplicationStartTime
                
                $NewRepl++

                If ((($InitialReplicationStartTime.AddMinutes($InitialReplicationDelayMinutes)).Hour -gt (Get-Date $InitialReplicationStopTime).Hour) -and (($InitialReplicationStartTime.AddMinutes($InitialReplicationDelayMinutes)).Hour -lt (Get-Date $ReplicationStartTime).Hour)) {
                   $InitialReplicationStartTime = ($InitialReplicationStartTime.Date + $ReplicationStartTime).AddDays(1)
                }
                Else {
                   $InitialReplicationStartTime = $InitialReplicationStartTime.AddMinutes($EstimatedTimeToCopy + 30) #Adding an extra 30 minutes, just to be sure
                }
            }
            ElseIf ($VM.HardDrives | Where SupportPersistentReservations -EQ $True) {
                Write-Host -ForegroundColor Yellow "Shared VHDx detected -> Skipping "$VM.VMName
            }
        }
        Else {
            Write-Host -ForegroundColor Yellow "Initial Replication Queue is greater than 7 days -> Skipping "$VM.VMName
        }
    }
}

Stop-Transcript

$MBody = ((Get-Content $logpath -Encoding UTF8 -Raw)| Out-String ) -replace ("`r`n","`n") 

If ($NewRepl -gt 0) {
    Send-MailMessage -To $MTo -From $MFrom -SmtpServer $MSmtp -Subject $MSubject -Body $MBody -Encoding UTF8
}

