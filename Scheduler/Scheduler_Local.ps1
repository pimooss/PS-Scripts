#
# Powershell Scheduler for Windows
#
# XML Config files must be placed (or created via Create-xml.ps1 script) in .\Configs
# One XML file by host
#
# Usage: Schedule.ps1 [-DoOnly <hostname>]
#           Without parameters, it will do every xml files. 
#           If [-DoOnly] parameter is set, it will try to find the xml file corresponding to the given hostname.
#
# Example: Schedule.ps1 -DoOnly server01
#            Will only do server01 if the xml file exists
#          Schedule.ps1
#            Will do every xml files in .\Configs
#
# Auth: Joris Decombe
# Date: 08/07/2015
# Version: 1.0
#

param(
    [string]$DoOnly
)

#
# Log function
#
Function LogWrite
{
   Param ([string]$logstring)
   Add-content $logfile -value ((Get-Date -Format yyyyMMdd_HHmmss) + " : " + $logstring)
}

# Parameters variables
$scriptpath = $MyInvocation.MyCommand.Path
$script:dir = Split-Path $scriptpath

$script:Config_Path = $dir + "\Configs" | Get-ChildItem -Filter "*.xml"
$script:Script_Path = $dir + "\Scripts"

$script:Key_Path = $dir + "\Secure\AES.key"
$script:DefaultTaskPath = "\Scheduler\Auto"

$ForegroundColors = "Black","Blue","Cyan","DarkBlue","DarkCyan","DarkGray","DarkGreen","DarkMagenta","DarkRed","DarkYellow","Gray","Green","Magenta","Red","White","Yellow"

$logfilepath = $dir + "\Logs"
If ($DoOnly.Trim().Length -gt 0) {
    $logfilename = "Scheduler_OnDemand_" + (Get-Date -Format yyyyMMdd_HHmmss) + ".log"
}
Else {
    $logfilename = "Scheduler_" + (Get-Date -Format yyyyMMdd_HHmmss) + ".log"
}
$script:logfile = $logfilepath + "\" + $logfilename

LogWrite ("Start")

$Found = "NoNeed"
#Do only one host if DoOnly exists 
If ($DoOnly.Trim().Length -gt 0) {
    Write-Host "Will do only" $DoOnly
    LogWrite ("Will do only" + $DoOnly)
    $Found = $False
}

$Exec_Result = @{}
$jobids = @()
$Exec_Start = Get-Date
#Listing Config files and process each hosts
ForEach ($Config_File In $Config_Path) {
    $xml = New-Object -TypeName XML
    $xml.Load($Config_File.FullName)
    
    $fqdn = $xml.Host.fqdn
    $hostname = $xml.Host.Name

    #Do only one host if DoOnly exists 
    $DoThisOne =$False
    If ($DoOnly.Trim().Length -gt 0) {
        If ($hostname -eq $DoOnly) {
            $DoThisOne = $True
            $Found = $True
        }
        Else {$DoThisOne = $False}
    }
    Else {$DoThisOne = $True}

    If ($DoThisOne) {
        #Hosts
        If ([System.Convert]::ToBoolean($xml.Host.Enabled)) {
            #
            # Go : Process Host
            #

            $Exec_Result[$hostname] = @{}
            $Exec_Result[$hostname]['hostname'] = $hostname
            $Exec_Result[$hostname]['start_time'] = Get-Date

            LogWrite ("Processing " + $Config_File)
           
            
            
            $ToLaunch = $dir+"\Process-Host.Ps1"
            $Exec_Result[$hostname]['result'] = Invoke-Command -ComputerName "LocalHost" -FilePath $ToLaunch -ArgumentList $xml -JobName ('Processing' + $hostname) -ThrottleLimit 32 -AsJob

            Write-Host -ForegroundColor DarkCyan ("Job launched for " + $Config_File + " | JobID : " + $Exec_Result[$hostname]['result'].Id)
            $jobids += $Exec_Result[$hostname]['result'].Id

            $Exec_Result[$hostname]['end_time'] = Get-Date
            $Exec_Result[$hostname]['execution_time'] = ($Exec_Result[$hostname]['end_time'] - $Exec_Result[$hostname]['start_time']).TotalSeconds
        }
        Else {
            Write-Host $hostname "is disabled"
            LogWrite ($hostname + " : is disabled")
       }
    }    
}

Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("--------------------------------------")
Write-Host -ForegroundColor White ("Waiting for Jobs to complete")
Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("--------------------------------------")

# Writing progress
$jobs = get-job | ?{$_.State -eq "running" -and ($jobids -contains $_.id)}
$total = (get-job | ?{$jobids -contains $_.id}).Count
$runningjobs = $jobs.count
$jobsfinished = @()
while ($runningjobs -gt 0) {
    Write-Progress -Activity "Processing hosts ..." -Status ("Progress : " + ($total-$runningjob) + "/" + $total + " jobs are running " ) -PercentComplete (($total-$runningjob)/$total*100)
    
    If ($runningjobs -gt (Get-Job | ?{$_.State -eq "running" -and ($jobids -contains $_.id)}).Count) {
        get-job | ?{($_.State -eq "completed") -and ($jobids -contains $_.id) -and ($jobsfinished -notcontains $_.Id)} | %{Write-Host -ForegroundColor DarkGray ($_.Name + " is completed") ; $jobsfinished += $_.Id }        
    }

    $runningjobs = (Get-Job | ?{$_.State -eq "running" -and ($jobids -contains $_.id)}).Count
}

# Waiting for jobs and getting results
Get-Job | ? {$jobids -contains $_.Id} | Wait-Job -Verbose | Receive-Job

#ForEach ($JobInfo In $Exec_Result.GetEnumerator()) {
#       $JobResult = $JobInfo.Value['result'] | Wait-Job | Receive-Job -keep | %{LogWrite($_.ChildJobs)}
#        Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("********************************")
#}


$Exec_End = Get-Date
Write-Host -ForegroundColor Yellow ("Execution time : " + ($Exec_End - $Exec_Start).TotalSeconds + "s") 

If (!$Found) {
    Write-Host "XML not found for host" + $DoOnly
    LogWrite ($DoOnly + " : XML Not Found")
}

LogWrite ("End")
