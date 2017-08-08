$cloud = "MAR02 SILAE"
$cloudObj = Get-SCCloud -Name $cloud
Write-Verbose "Creating VM $VMName in cloud $cloud"
# Setup Vm Template from lab library 
$Template = Get-SCVMTemplate | Where-Object {$_.Name -like "Template - Frontal - Grappe 5"} 
# Build Vm Configuration 
$VMConfig = New-SCVMConfiguration -VMTemplate $Template -Name VMConfig01 -Cloud $cloudObj
Update-SCVMConfiguration -VMConfiguration $VMConfig 
$VNAConfig = Get-SCVirtualNetworkAdapterConfiguration -VMConfiguration $VMConfig


$VMsToDeploy = @()
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.20" ; Name = "JSX000AQ73" ; Description = "Grappe 5 Frontal #11" ; ComputerName = "vm1689.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.21" ; Name = "JSX000AQ74" ; Description = "Grappe 5 Frontal #12" ; ComputerName = "vm1690.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.22" ; Name = "JSX000AQ75" ; Description = "Grappe 5 Frontal #13" ; ComputerName = "vm1691.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.23" ; Name = "JSX000AQ76" ; Description = "Grappe 5 Frontal #14" ; ComputerName = "vm1692.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.24" ; Name = "JSX000AQ77" ; Description = "Grappe 5 Frontal #15" ; ComputerName = "vm1693.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.25" ; Name = "JSX000AQ78" ; Description = "Grappe 5 Frontal #16" ; ComputerName = "vm1694.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.26" ; Name = "JSX000AQ79" ; Description = "Grappe 5 Frontal #17" ; ComputerName = "vm1695.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.27" ; Name = "JSX000AQ80" ; Description = "Grappe 5 Frontal #18" ; ComputerName = "vm1696.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.28" ; Name = "JSX000AQ81" ; Description = "Grappe 5 Frontal #19" ; ComputerName = "vm1697.jn-hebergement.com" }
$VMsToDeploy += [PSCustomObject]@{IPv4Address = "10.49.0.29" ; Name = "JSX000AQ82" ; Description = "Grappe 5 Frontal #20" ; ComputerName = "vm1698.jn-hebergement.com" }

$Threads = 4
$Jobs = @()

$VMsToDeploy | Sort Name | %{


    $ScriptBlock = {
        param($VNAConfig, $IPv4Address, $Name,  $VMConfig, $cloudObj, $Description, $ComputerName)
        Set-SCVirtualNetworkAdapterConfiguration -VirtualNetworkAdapterConfiguration $VNAConfig -IPv4Address $IPv4Address  ; 
        New-SCVirtualMachine -Name $Name -VMConfiguration $VMConfig -Cloud $cloudObj -Description $Description -ComputerName $ComputerName
    }

    While (($Jobs | Where State -EQ "Running").Count -le $Threads ) {
        $Jobs += Start-Job -ScriptBlock $ScriptBlock -ArgumentList ($VNAConfig, $_.IPv4Address, $_.Name,  $VMConfig, $cloudObj, $_.Description, $_.ComputerName)
        Sleep -Seconds 1
    }

}

$Jobs | Receive-Job


