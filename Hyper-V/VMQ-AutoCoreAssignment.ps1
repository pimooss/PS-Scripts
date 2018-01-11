# Enable VMQ on physical net adapters and automatically assign core over different network card depending on total number of cores

# Change if needed
<<<<<<< HEAD
$PhysicalAdapters = Get-NetAdapter -Physical | Where Status -eq "Up" # | Where Name -like "vSwitchNIC-*"

$NumberOfCPU = ((Get-WmiObject –class Win32_processor).NumberOfCores).Count
$NumberOfCoresPerCPU = (Get-WmiObject –class Win32_processor | Select -First 1).NumberOfCores
$NumberOfLogicalCoresPerCPU = (Get-WmiObject –class Win32_processor | Select -First 1).NumberOfLogicalProcessors

#$CorePerAdapter = $NumberOfCoresPerCPU * $NumberOfCPU / $PhysicalAdapters.Count 
$CorePerAdapter = 32..1 | Where { (32 % $_) -eq 0 } | Where {$_ -le $NumberOfCoresPerCPU} | Select -First 1

If ($NumberOfLogicalCoresPerCPU -ne $NumberOfCoresPerCPU) {
    #Hyperthreading ON
    $ThisBase = 2
}
Else {
    #Hyperthreading OFF
    $ThisBase = 1
}
        
$PhysicalAdapters | %{ Set-NetadapterVmq -Name $_.Name -BaseProcessorNumber $ThisBase -MaxProcessors $CorePerAdapter -Enabled $true ; $ThisBase = $ThisBase + $NumberOfLogicalCoresPerCPU }

$PhysicalAdapters | %{ Set-NetAdapterAdvancedProperty -Name $_.Name -RegistryKeyword "*NumRssQueues" -RegistryValue $CorePerAdapter }

=======
$PhysicalAdapters = Get-NetAdapter -Physical # | Where Name -like "vSwitchNIC-*"

[int]$NumberOfCoresPerCPU * [int]$NumberOfCPU / $PhysicalAdapters.Count

$NumberOfCPU = ((Get-WmiObject –class Win32_processor).NumberOfCores).Count
$NumberOfCoresPerCPU = (Get-WmiObject –class Win32_processor | Select -First 1).NumberOfCores
$CorePerAdapter = $NumberOfCoresPerCPU * $NumberOfCPU / $PhysicalAdapters.Count
$ThisBase = 1
        
$PhysicalAdapters | %{ Set-NetadapterVmq -BaseProcessorNumber $ThisBase -MaxProcessors $CorePerAdapter -Enabled $true ; $ThisBase = $ThisBase + $CorePerAdapter }
>>>>>>> 4fedd355a3687ec589ca14d31d87c0b9317db79f
