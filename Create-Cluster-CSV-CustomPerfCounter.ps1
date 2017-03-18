#
# Windows Server Cluster Shared Volume Custom Performance Counter
#
#
# This is a one shot script
# It creates a custom performance counter

# If you need to delete the performance object and have it re-created call this:
# [System.Diagnostics.PerformanceCounterCategory]::Delete("<categoryNameGoesHere>")

$categoryName = "CSV-Custom"
$categoryHelp = "A Performance object for CSV used and available space"
$categoryType = [System.Diagnostics.PerformanceCounterCategoryType]::MultiInstance

$categoryExists = [System.Diagnostics.PerformanceCounterCategory]::Exists($categoryName)

If (-Not $categoryExists)
{
  $objCCDC = New-Object System.Diagnostics.CounterCreationDataCollection
  
  $objCCD1 = New-Object System.Diagnostics.CounterCreationData
  $objCCD1.CounterName = "FreeSpaceBytes"
  $objCCD1.CounterType = "NumberOfItems64"
  $objCCD1.CounterHelp = "Volume FreeSpace in bytes"
  $objCCDC.Add($objCCD1) | Out-Null
  
  $objCCD2 = New-Object System.Diagnostics.CounterCreationData
  $objCCD2.CounterName = "UsedSpaceBytes"
  $objCCD2.CounterType = "NumberOfItems64"
  $objCCD2.CounterHelp = "Volume Used space in bytes"
  $objCCDC.Add($objCCD2) | Out-Null
  
  $objCCD3 = New-Object System.Diagnostics.CounterCreationData
  $objCCD3.CounterName = "SizeBytes"
  $objCCD3.CounterType = "NumberOfItems64"
  $objCCD3.CounterHelp = "Volume Size in bytes"
  $objCCDC.Add($objCCD3) | Out-Null

  [System.Diagnostics.PerformanceCounterCategory]::Create($categoryName, $categoryHelp, $categoryType, $objCCDC) | Out-Null
}