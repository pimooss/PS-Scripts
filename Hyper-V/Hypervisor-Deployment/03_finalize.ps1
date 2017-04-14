#
# HYPER-V Deployment Script
# Phase 3 -> 
#   .Cleanup autologon entries
#   .MDT?
#
# Date : 14/04/2016
# Version : 0.1
# Auth : Joris DECOMBE
#

Param
(
    [Parameter(Mandatory=$false,Position=0)]
    [String]$Path = (Get-Location),
    [Parameter(Mandatory=$false)]
	[Switch]$EnableLogging = $true
)

# Enable logging
If ($EnableLogging)
{
	#$Script:Path = Get-Location
	$Script:ScriptLog = "$path\03_Finalize-" + (Get-Date -f yy.MM.dd-HH.mm.ss) + ".log"
	Start-Transcript -Path $Script:ScriptLog
}

$StartDate = Get-Date

# Elevate
$StartDate=Get-Date ; Write-Host "Deployment started at: $StartDate"
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
$Validate = $true

# Check OS version
If ((Get-WmiObject -Class Win32_OperatingSystem).Version.Split(".")[2] -lt 9200) {
    $Validate = $false
    Write-Host "Deployment should be run from Windows Server 2012 or later" -ForegroundColor Red
}

# Change to path
If (Test-Path $Path -PathType Container) {
    Set-Location $Path
} Else {
    $Validate = $false
    Write-Host "Invalid path" -ForegroundColor Red
}

# Validate variable.xml
Write-Host "Looking for Variable.xml"
If (Test-Path ".\Variable.xml") {
    try {$Variable = [XML] (Get-Content ".\Variable.xml")} catch {$Validate = $false;Write-Host "Invalid Variable.xml" -ForegroundColor Red}
} Else {
    $Validate = $false
    Write-Host "Missing Variable.xml" -ForegroundColor Red
}

If ($Validate) {
    Write-Host "Cleaning up"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoLogonCount" -Value 0
    
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value 0
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUsername"
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword"
    
    #Not much
    Write-Host "HV AutoDeploy is finshed -> You can now launch PDT"
}

Write-Host "`nScript started at: $StartDate"
$Date = Get-Date
Write-Host "Script finished at: $Date"
Write-Host "`nScript execution time in minutes:" 
$TotalTime = $Date - $StartDate
Write-Host $TotalTime.TotalMinutes

If ($EnableLogging)
{
    Stop-Transcript
}