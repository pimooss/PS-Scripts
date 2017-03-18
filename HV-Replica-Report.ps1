#
# HV-Replica-Report.ps1
#
# Features :
# Hyper-V Cluster Automatic Replication Report
# A simple script that build an HTML report of current Hyper-V replication with mail notification.
# Displays replication health, status and LastReplicationTime and scheduled initial replication.
# Also calculating current replication total size and max size (usefull for dynamic vhdx).
#
# Joris DECOMBE
#

# Mail variables
$Entity = "%COMPANY%"
$MSubject = $Entity + " - Hyper-V Replica Report"
$MTo = "to@company.com"
$MFrom = "hypervreplicareport@company.com"
$MSmtp = "smtp.company.com"

# Cluster Variable
# Change the following variable to your Hyper-V cluster 
$Cluster = "%ClusterFQDN%"

# Go
Import-Module Hyper-V

# Getting Cluster Nodes
$clusterNodes = Get-ClusterNode -Cluster $Cluster;

$VMArray = @()

Write-Host "Getting VMs for HVCluster : $Cluster"

ForEach($node in $clusterNodes) {
    #Uncomment following lines once to enable CredSSP on remote nodes if needed
    #Enable-WSManCredSSP –Role Client –DelegateComputer $node.name -Force
    #Invoke-Command –ComputerName  $node.name –ScriptBlock { Enable-WSManCredSSP –Role Server -Force }
    
    # Getting VMs
    $VMArray += Get-VM -ComputerName $node.Name
    
}

# Filtering Replicated & Running VMs
$VMReplicated = $VMArray | Where { ($_.ReplicationState -NE "Disable") -and  ($_.State -EQ "Running")  }

Write-Host

Write-Host "Replication status"

$VMReplicatedArray = @()
$VMFiltered = ($VMReplicated | Get-VMReplication)

ForEach ($VM In $VMFiltered) {
    
    # Getting vhdx size
    $Size = 0
    $MaxSize = 0
    $VM.ReplicatedDisks | %{ Get-VHD -ComputerName $_.ComputerName $_.Path | %{$Size += $_.FileSize ; $MaxSize = $_.Size} }
    
    # Putting it all in a custom array
    $VMReplicatedArray += [pscustomobject]@{Name = $VM.VMName ; `
                                                Health = $VM.Health ; `
                                                State = $VM.State ; `
                                                VSSEnabled = $VM.VSSSnapshotReplicationEnabled ; `
                                                VSSFreq = $VM.VSSSnapshotFrequencyHour ; `
                                                Compression = $VM.CompressionEnabled ; `
                                                LastReplication = $VM.LastReplicationTime ;`
                                                "Size GB" = [math]::Round($Size/1GB) ; `
                                                "MaxSize GB" = [math]::Round($MaxSize/1GB) ` 
                                            }
} 

$VMReplicatedArray | Sort Health,State,Name | Format-Table -AutoSize

# Getting initial replication schedules

Write-Host

Write-Host "Next Scheduled VMs for Initial Replication"

Write-Host

$WaitForInitVmsArray = @()

$WaitForInitVms = ($VMReplicated | Get-VMReplication | Where State -eq ReadyForInitialReplication)

ForEach ($VM In $WaitForInitVms) {
    
    $Size = 0
    $MaxSize = 0
    $VM.ReplicatedDisks | %{ Get-VHD -ComputerName $_.ComputerName $_.Path | %{$Size += $_.FileSize ; $MaxSize = $_.Size} }
    
    $WaitForInitVmsArray += [pscustomobject]@{Name = $VM.VMName ; `
                                                InitialReplStart = $VM.InitialReplicationStartTime ; `
                                                "Size GB" = [math]::Round($Size/1GB) ; `
                                                "MaxSize GB" = [math]::Round($MaxSize/1GB) `
                                            }
} 

$WaitForInitVmsArray | Sort InitialReplStart,VMName | Format-Table -AutoSize

Write-Host

Write-Host -ForegroundColor Green "Stats"

Write-Host

Write-Host -ForegroundColor Green "Total VHDx Size Replicated :" (($VMReplicatedArray | Where State -ne ReadyForInitialReplication )."Size GB" | Measure-Object -Sum).Sum "GB"

Write-Host -ForegroundColor Green "Total VHDx Max Size of replicated disk:" (($VMReplicatedArray | Where State -ne ReadyForInitialReplication )."MaxSize GB" | Measure-Object -Sum).Sum "GB"

Write-Host -ForegroundColor Green "Total VHDx Size Waiting for Inititial replication:" (($VMReplicatedArray | Where State -eq ReadyForInitialReplication )."Size GB" | Measure-Object -Sum).Sum "GB"

Write-Host -ForegroundColor Green "Total VHDx MaxSize Waiting for Inititial replication:" (($VMReplicatedArray | Where State -eq ReadyForInitialReplication )."MaxSize GB" | Measure-Object -Sum).Sum "GB"

Write-Host

Write-Host -ForegroundColor Green  "Total VMs" $VMArray.Count 
 
Write-Host -ForegroundColor Green  "Replicated VMs" $VMReplicated.Count 

Write-Host


# Building HTML Report 

$HTML_t1 = $VMReplicatedArray | Sort Health,State,Name | ConvertTo-Html -Fragment
$HTML_t2 = $WaitForInitVmsArray | Sort InitialReplStart,VMName | ConvertTo-Html -Fragment

$HTML_t3 = [pscustomobject]@{"Total VHDx Size Replicated (Go)" = (($VMReplicatedArray | Where State -ne ReadyForInitialReplication )."Size GB" | Measure-Object -Sum).Sum ; `
                            "Total VHDx Max Size of replicated disk (Go)" = (($VMReplicatedArray | Where State -ne ReadyForInitialReplication )."MaxSize GB" | Measure-Object -Sum).Sum ; `
                            "Total VHDx Size Waiting for Inititial replication (Go)" = (($VMReplicatedArray | Where State -eq ReadyForInitialReplication )."Size GB" | Measure-Object -Sum).Sum ; `
                            "Total VHDx MaxSize Waiting for Inititial replication (Go)" = (($VMReplicatedArray | Where State -eq ReadyForInitialReplication )."MaxSize GB" | Measure-Object -Sum).Sum `
                        } | ConvertTo-Html -Fragment -As List

$HTML_t4 = [pscustomobject]@{"Total VMs" = $VMArray.Count ;`
                            "VMs with replication configured" = $VMReplicated.Count  ; `
                            "Normal Replicating State" = ($VMReplicatedArray | Where State -eq Replicating ).Count ;
                            "Waiting for Initial Replicating State" = ($VMReplicatedArray | Where State -eq ReadyForInitialReplication ).Count ;
                            "Other State" = ($VMReplicatedArray | Where State -ne Replicating | Where State -ne ReadyForInitialReplication ).Count ;`
                            "Warning" = ($VMReplicatedArray | Where Health -eq Warning ).Count ;`
                            "Critical" = ($VMReplicatedArray | Where Health -eq Critical ).Count ;`
                        } | ConvertTo-Html -Fragment -As List

# HTML Report Css
$Head = "
<style>
body { font-family: Calibri }
h1, h5, th { text-align: center; }
table { margin: auto; font-family: Calibri; box-shadow: 10px 10px 5px #888; border: thin ridge grey; }
th { background: #0046c3; color: #fff; max-width: 400px; padding: 5px 10px; }
td { font-size: 11px; padding: 5px 20px; color: #000; }
tr { background: #b8d1f3; }
tr:nth-child(even) { background: #dae5f4; }
tr:nth-child(odd) { background: #b8d1f3; }
</style>"

# HTML Report Body
$Body = "Report Generated on " + ( Get-date ) + "<br>
    <br> $HTML_t4 <br>
    <br> <u>All replicated VM Status</u> <br><br> $HTML_t1 <br>
    <br> <u>Waiting for Initial Replication Schedule</u> <br><br> $HTML_t2 <br>
    <br> <u>Stats</u> <br><br> $HTML_t3 <br> "

$MBody = ConvertTo-HTML -Body $Body -Title "Replication Status" -Head $Head | Out-String

Send-MailMessage -To $MTo -From $MFrom -SmtpServer $MSmtp -Subject $MSubject -Body $MBody -BodyAsHtml

