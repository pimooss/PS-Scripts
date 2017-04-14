$VMName = "vmxxx"

$VM = Get-VM -Name $VMName

If ($VM.State -ne "off") {
    Write-Host -ForegroundColor Yellow "Stopping $VMName"
    $VM | Stop-VM -Confirm:$false
}

If ($VM.State -eq "off") {
    $VM.HardDrives | %{
        $VHDxPath = $_.Path
        Write-Host -ForegroundColor Cyan "Optimizing $VHDxPath"
        Mount-VHD -Path $VHDxPath -NoDriveLetter -ReadOnly
        Optimize-VHD -Path $VHDxPath -Mode Full
        Dismount-VHD -Path $VHDxPath
     }

    Write-Host -ForegroundColor Green "Starting $VMName"
    $VM | Start-VM
}
Else {
    Write-Host -ForegroundColor Red $VMName "is not powered off"
}