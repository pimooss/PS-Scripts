#
# Poller-Cluster-CSV-CustomPerfCounter.ps1
#
# Purpose :
#   Write all Cluster Shared Volume name, size, free space, used space in Bytes in a custom performance counter.
# 
# Usage :
#   Scheduled task
#
# Joris DECOMBE
#

# Target Cluster
$Cluster = "%Cluster_FQDN"

# Custom Performance Counter Category Name 
$categoryName = "CSV-Custom"

# Poller function

Function Get-CSVSizeInfo ($Cluster) {

    Import-Module FailoverClusters

    $CSVArray = @()

    Get-ClusterSharedVolume -Cluster $Cluster | %{

        $CSVName = $_.Name
        $CSVNode = $_.OwnerNode
        $CSVInfo = $_ | select -Expand SharedVolumeInfo 
        $PartitionInfo = $CSVInfo| select -Expand Partition 

        $CSVArray += [pscustomobject]@{Name = $CSVName ; `
                                        Node = $CSVNode ; `
                                        Path = $CSVInfo.FriendlyVolumeName ; `
                                        FreeSpace = $PartitionInfo.FreeSpace ; `
                                        PercentFree = $PartitionInfo.PercentFree ; `
                                        Size = $PartitionInfo.Size ; `
                                        UsedSpace = $PartitionInfo.UsedSpace ; `
                                        }
    }

    Return $CSVArray

}

# Polling and writing data to performance counter instances

$Poll = Get-CSVSizeInfo -Cluster $Cluster

$Poll | %{
    $perfInst1a = New-Object System.Diagnostics.PerformanceCounter($categoryName, "FreeSpaceBytes", $_.Name , $false)
    $perfInst1b = New-Object System.Diagnostics.PerformanceCounter($categoryName, "UsedSpaceBytes", $_.Name  , $false)
    $perfInst1c = New-Object System.Diagnostics.PerformanceCounter($categoryName, "SizeBytes", $_.Name , $false)

    $perfInst1a.RawValue = $_.FreeSpace
    $perfInst1b.RawValue = $_.UsedSpace
    $perfInst1c.RawValue = $_.Size

}



