# Enable VMQ on physical net adapters and automatically assign core over different network card depending on total number of cores

# Change if needed
$PhysicalAdapters = Get-NetAdapter -Physical # | Where Name -like "vSwitchNIC-*"

[int]$NumberOfCoresPerCPU * [int]$NumberOfCPU / $PhysicalAdapters.Count

$NumberOfCPU = ((Get-WmiObject –class Win32_processor).NumberOfCores).Count
$NumberOfCoresPerCPU = (Get-WmiObject –class Win32_processor | Select -First 1).NumberOfCores
$CorePerAdapter = $NumberOfCoresPerCPU * $NumberOfCPU / $PhysicalAdapters.Count
$ThisBase = 1
        
$PhysicalAdapters | %{ Set-NetadapterVmq -BaseProcessorNumber $ThisBase -MaxProcessors $CorePerAdapter -Enabled $true ; $ThisBase = $ThisBase + $CorePerAdapter }
