#
# Scheduled Reboot Task
#
# Usage: Reboot.ps1
#
# Version: 1.0
# Date: 09/07/2015
# Author: Joris DECOMBE
#

#
# Log function
#
Function LogWrite
{
   Param ([string]$logstring)
   Add-content $logfile -value ((Get-Date -Format yyyyMMdd_HHmmss) + " : " + $logstring)
}

#
# Setting variables
#

$now = Get-Date -Format yyyyMMdd_HHmmss
$scriptname = (((($MyInvocation.MyCommand.Path).Split("\"))[((($MyInvocation.MyCommand.Path).Split("\")).Count) - 1]).Split("."))[0]
$scriptpath = Split-Path $MyInvocation.MyCommand.Path

$logfilepath = $scriptpath + "\Logs"
$logfilename = $env:COMPUTERNAME + "_" + $scriptname + "_" + $now + ".log"

If (!(Test-Path($logfilepath))) {New-Item -Path $logfilepath -ItemType Directory | Out-Null }

$script:logfile = $logfilepath + "\" + $logfilename

$Delay = 60 #seconds
$Desciption = "Scheduled Reboot : This server will reboot in " + $Delay.ToString() + " seconds"
$Reboot_Bin = "shutdown"
$Reboot_Arg = "/r /t " + $Delay + " /c " + '"' + $Desciption + '"' +" /d p:0:0"

#
# Writing in log file
#

LogWrite ("Script : " + $scriptname)
LogWrite ("Command : " + $Reboot_Bin + " " + $Reboot_Arg)

$p = Start-Process $Reboot_Bin -ArgumentList $Reboot_Arg -wait -NoNewWindow -PassThru

If ($p.ExitCode -eq 0) {
    LogWrite ("Result : OK")
    Exit 0
}
Else {
    LogWrite ("Result : NOTOK")
    LogWrite ("Error : " + $Error[0])
    Return $Error[0]
    Exit 1
}