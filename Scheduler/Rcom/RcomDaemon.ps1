#
# Powershell Scheduler for Windows - Experimental Remote Command 
#
# XML Config files must be placed (or created via Create-xml.ps1 script) in .\Configs
# One XML file by host
#
# Usage: RcomDaemon.ps1 [-DoOnly <hostname>]
#           Without parameters, it will do every xml files. 
#           If [-DoOnly] parameter is set, it will try to find the xml file corresponding to the given hostname.
#
# Example: RcomDaemon.ps1 -DoOnly wsus01
#            Will only do wsus01 if the xml file exists
#          RcomDaemon.ps1
#            Will do every xml files in .\Configs
#
# Auth: Joris Decombe
# Date: 08/07/2015
# Version: 1.0
#


#
# Log function
#
Function LogWrite
{
   Param ([string]$logstring)
   Add-content $logfile -value ((Get-Date -Format yyyyMMdd_HHmmss) + " : " + $logstring)
}

# Parameters variables
$scriptpath = Split-Path $MyInvocation.MyCommand.Path
$script:dir = Split-Path -Parent $scriptpath

$script:Rcom_Poll_Path = $scriptpath + "\In"
$script:Out_Path = $scriptpath + "\Out"
$script:Error_Path = $scriptpath + "\Error"

$script:Config_Path = $dir + "\Configs" | Get-ChildItem -Filter "*.xml"
$script:Script_Path = $dir + "\Scripts"

$script:Key_Path = $dir + "\Secure\AES.key"

$PollInterval = 30 #sec

$ForegroundColors = "Black","Blue","Cyan","DarkBlue","DarkCyan","DarkGray","DarkGreen","DarkMagenta","DarkRed","DarkYellow","Gray","Green","Magenta","Red","White","Yellow"

$logfilepath = $dir + "\Logs"

$logfilename = "Rcom_" + (Get-Date -Format yyyyMMdd_HHmmss) + ".log"

$script:logfile = $logfilepath + "\" + $logfilename

LogWrite ("Start")

# Polling loop
For ($i=1;$i -gt 0; Sleep $PollInterval) {
    
    $Content = $Rcom_Poll_Path | Get-ChildItem -Filter "*.xml"
    If ($Content) {
        $jobids = @()
        $Exec_Start = Get-Date
        Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("--------------------------------------")
        Write-Host  $Exec_Start
        Write-Host -ForegroundColor Yellow ("Start Polling")
        Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("--------------------------------------")

        ForEach ($Job In $Content) {

            $xml = New-Object -TypeName XML
            $xml.Load($Job.FullName)

            # Changing status if pending
            $item = Select-XML -Xml $xml -XPath ("//Job[1]")
            If ($item.Node.Status -like 'pending') {

                #$item.Node.SetAttribute('Status','InProgress')
                #$xml.Save($Job.FullName)

                $hostname = $xml.Host.Name
                $Config_File = ($Config_Path | Where Name -like ($hostname+".xml"))

                If (Test-Path ($Config_File.Fullname)) {

                    Write-Host -ForegroundColor Green ("Found " + $Config_File.Name)
                    LogWrite ("Processing " + $Job.Name + " with config from " + $Config_File.Name)

                    $hostxml = New-Object -TypeName XML
                    $hostxml.Load($Config_File.FullName)   
                    $fqdn = $hostxml.Host.fqdn
            
                    If ([System.Convert]::ToBoolean($hostxml.Host.Enabled)) {

                        $ToLaunch = $scriptpath + "\RcomThread.Ps1"

                        $Arguments = $hostxml, $xml, $Job.FullName
                        $Result = Invoke-Command -ComputerName "LocalHost" -FilePath $ToLaunch -ArgumentList $Arguments -JobName ('JNRcom' + $hostname) -ThrottleLimit 32 -AsJob

                        Write-Host -ForegroundColor DarkCyan ("Job launched for " + $Config_File + " | JobID : " + $Result.Id)
                        $jobids += $Result.Id

                    }
                    Else {
                        Write-Host $hostname "is disabled"
                        LogWrite ($hostname + " : is disabled")
                    }
                }
                Else {
                    Write-Host -ForegroundColor Red ($Job.Name + " : Couldn't find any config file matching " + $hostname)
                    LogWrite ($Job.Name + " : Error : Couldn't find any config file matching " + $hostname)
                } 
            }
            ElseIf ($item.Node.Status -like 'InProgress') {
                Write-Host -ForegroundColor Gray ('Skipping ' + $hostname + " : " + $Job.Name + " : Already in progress")
                LogWrite ($hostname + " : " + $Job.Name + " : Already in progress")
            }
            ElseIf ($item.Node.Status -like 'Error') {
                Move-Item -Path $Job.FullName -Destination $Error_Path -Force | Out-Null
            }
            ElseIf ($item.Node.Status -like 'Success') {
                Write-Host -ForegroundColor Green ("Moving " + $hostname + " : " + $Job.Name + " : Success ")
                LogWrite ("Moving " + $hostname + " : " + $Job.Name + " : Success ")

                Move-Item -Path $Job.FullName -Destination $Out_Path -Force | Out-Null
            }
            Else {
                Write-Host -ForegroundColor Red ($hostname + " : " + $Job.Name + " : Status error")
                LogWrite ($hostname + " : " + $Job.Name + " : Status error")  
            }
            
        }
        If (Get-Job | ? {$jobids -contains $_.Id}) {
            Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("--------------------------------------")
            Write-Host -ForegroundColor White ("Waiting for Jobs to complete")
            Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("--------------------------------------")
        }

        # Waiting for jobs and getting results
        Get-Job | ? {$jobids -contains $_.Id} | Wait-Job -Verbose | Receive-Job
        
        $Exec_End = Get-Date
        Write-Host -ForegroundColor Yellow ("Polling time : " + ($Exec_End - $Exec_Start).TotalSeconds + "s")
        Write-Host -ForegroundColor Gray ("Next poll in " + $PollInterval + "s")
    }
    Else {
        Write-Host -ForegroundColor Gray ((Get-Date).ToString() + " : Poller -> Nothing to do... waiting for " + $PollInterval + "s")
    }
}

LogWrite ("End")
