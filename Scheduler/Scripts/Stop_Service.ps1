#
# Scheduled Stop service
#
# Usage: Stop_Service.ps1 -ServiceName <ServiceName>
#
# Version: 1.0
# Date: 09/07/2015
# Author: Joris DECOMBE
#

param(
    [parameter(Mandatory = $true)]
    [string]
    $ServiceName
)

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

$script:logfile = $logfilepath + "\" + $logfilename

#
# Writing in log file
#

LogWrite ("Script : " + $scriptname)
LogWrite ("Parameters : " + $ServiceName)

#
# Check if service exists
#

Try {get-service $ServiceName -ErrorAction Stop | Out-Null}
Catch {
    $Result = $_.CategoryInfo.Category
}

If ($Result -eq "ObjectNotFound") {
    Return ("Message : Service Name not found")
    LogWrite ("Service Name not found " + $ServiceName)
    Exit 1
}
Else {

   #
   # Listing dependencies
   #

   $DependentServices = get-service $ServiceName | Select name, dependentservices
   
   #
   # Go
   #

   stop-service $ServiceName -force -confirm:$false -ErrorAction SilentlyContinue
   If ($?) {
        Return $DependentServices.dependentservices
        LogWrite ("DependentServices : " + $DependentServices.dependentservices)
        LogWrite ("Result : OK")
        Exit 0
    }
   Else {
        Return $Error[0]
        LogWrite ("Result : NOTOK")
        LogWrite ("Error : " +  $Error[0])
        Exit 1
   }
}

#
# The End
#