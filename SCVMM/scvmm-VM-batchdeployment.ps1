#
# Deploy multiple VMs at the same time
# Limit the number of thread with $thread variable
#
# Joris DECOMBE

Import-Module VirtualMachineManager

$cloud = "CloudName"
$TeamplateName = "TemplateName"
$Threads = 5

$VMsToDeploy = @()

$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.0.0.1" ; Name = "vm001"; Description = "vm001"; ComputerName = "vm001" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.0.0.2" ; Name = "vm001"; Description = "vm002"; ComputerName = "vm002" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.0.0.3" ; Name = "vm001"; Description = "vm003"; ComputerName = "vm003" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.0.0.4" ; Name = "vm001"; Description = "vm004"; ComputerName = "vm004" }
#etc


$Jobs = @()

$ScriptBlock = {
    param( $IPv4Address , $Name , $Description , $ComputerName , $cloud, $TeamplateName, $preferred , $grappe)
    Import-Module VirtualMachineManager

    $cloudObj = Get-SCCloud -Name $cloud
    $Template = Get-SCVMTemplate | Where-Object {$_.Name -like $TeamplateName}
    
    $VMConfig = New-SCVMConfiguration -VMTemplate $Template -Name VMConfig01 -Cloud $cloudObj
    $Update = Update-SCVMConfiguration -VMConfiguration $VMConfig 
    $VNAConfig = Get-SCVirtualNetworkAdapterConfiguration -VMConfiguration $VMConfig

    Write-Verbose "Creating VM $Name in cloud $cloud"

    Set-SCVirtualNetworkAdapterConfiguration -VirtualNetworkAdapterConfiguration $VNAConfig -IPv4Address $IPv4Address
    New-SCVirtualMachine -Name $Name -VMConfiguration $VMConfig -Cloud $cloudObj -Description $Description -ComputerName $ComputerName
    
}

$VMsToDeploy | Sort Name | %{

    While (($Jobs | Where State -EQ "Running").Count -ge $Threads) {
        Sleep -Seconds 1
    }
    Write-Host $_.IPv4Address "," $_.Name "," $_.Description "," $_.ComputerName
    $Jobs += Microsoft.PowerShell.Core\Start-Job -ScriptBlock $ScriptBlock -ArgumentList ($_.IPv4Address, $_.Name, $_.Description, $_.ComputerName , $cloud, $TeamplateName, $preferred, $grappe)

} 
