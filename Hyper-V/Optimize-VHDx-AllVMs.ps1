#
# HYPER-V VHDx Compact0r scrip
# 
# .Check if the VM is off -> if not, clean STOP of the VM
# .Mount VHDx in RO
# .Optimize -full on the VHDx
# .Unmount
# .Start VM
#
# Date : 20/05/2016
# Version : 0.1
# Auth : Joris DECOMBE
#

$Path = (Get-Location)
$Script:ScriptLog = "$Path\Optimize-VHDx-" + (Get-Date -f yy.MM.dd-HH.mm.ss) + ".log"

Start-Transcript -Path $Script:ScriptLog

$StartDate = Get-Date

# Elevate
$StartDate=Get-Date ; Write-Host "JNDeployment started at: $StartDate"
Write-Host "Checking for elevation... " -NoNewline
$CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
if (($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) -eq $false)  {
    $ArgumentList = "-noprofile -noexit -file `"{0}`" -Path `"$Path`""
    If ($Setup) {$ArgumentList = $ArgumentList + " -Setup $Setup"}
    If ($Mode) {$ArgumentList = $ArgumentList + " -Mode $Mode"}
    Write-Host "elevating"
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($ArgumentList -f ($myinvocation.MyCommand.Definition))
    Exit
}

# Set Background to black
$Host.UI.RawUI.BackgroundColor = "Black"; Clear-Host

# Change to path
If (Test-Path $Path -PathType Container) {
    Set-Location $Path
} Else {
    $Validate = $false
    Write-Host "Invalid path" -ForegroundColor Red
}

Get-VM | %{

    $VM = $_
    $VMName = $VM.Name

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

}


Write-Host "`nScript started at: $StartDate"
$Date = Get-Date
Write-Host "Script finished at: $Date"
Write-Host "`nScript execution time in minutes:"
$TotalTime = $Date - $StartDate
Write-Host $TotalTime.TotalMinutes

Stop-Transcript