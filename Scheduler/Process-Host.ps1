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
    $xml
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
# Function FindDateToTrigger : defining if trigger date is in current month, if not it will return the corrected date the month after
#
Function FindDateToTrigger {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $DayOfMonth,
        [Parameter(Mandatory = $true)]
        [string]
        $JobTime
    )

    $Now = Get-Date
    $TimeSpan = New-TimeSpan -Start $Now -End (Get-Date($DayOfMonth.ToString() +"/"+$Now.Month+"/"+$Now.Year+" "+$JobTime))
    If ($TimeSpan.TotalSeconds -gt 20) { #DayOfMonth is still more than one minute in the future
        [DateTime]$DateOfTrigger = Get-Date($DayOfMonth +"/"+$Now.Month+"/"+$Now.Year+" "+$JobTime)
    }
    Else {#DayOfMonth has passed, planning for next month
        [DateTime]$DateOfTrigger = ((Get-Date($DayOfMonth +"/"+$Now.Month+"/"+$Now.Year+" "+$JobTime)).AddMonths(1))
    }
    Return $DateOfTrigger
}

#
# Function GetTaskTrigger : processing Trigger parameters (Planification)
#

Function GetTaskTrigger {
    param (
        [Parameter(Mandatory = $true)]
        $Job
    )
    $Now = Get-Date

    switch ($Job.Trigger) {
        "Daily" {
            If ($Job.DaysInterval.Length -gt 0) {
                If ((1..365) -Contains $Job.Daily.DaysInterval) {
                    $Trigger = New-ScheduledTaskTrigger -Daily -DaysInterval $Job.Daily.DaysInterval -At $Job.At
                    Return $Trigger
                }
                Else {
                    Write-Host "Invalid parameter DaysInterval : " $Job.Daily.DaysInterval
                    LogWrite ("Invalid parameter DaysInterval : " + $Job.Daily.DaysInterval)
                }
            }
            Else {
                $Trigger = New-ScheduledTaskTrigger -Daily -At $Job.At
                Return $Trigger
            }
            break;
        }
        "Weekly" {
            If (("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday") -Contains $Job.Weekly.DaysofWeek) {
                If ($Job.Weekly.WeeksInterval.Length -gt 0) {
                    If ((1..52) -Contains $Job.Weekly.WeeksInterval) {
                        $Trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval $Job.Weekly.WeeksInterval -At $Job.At -DaysOfWeek $Job.Weekly.DaysofWeek
                        Return $Trigger
                    }
                    Else {
                        Write-Host "Invalid parameter WeeksInterval : " $Job.Weekly.WeeksInterval
                        LogWrite ("Invalid parameter WeeksInterval : " + $Job.Weekly.WeeksInterval)
                    }
                }
                Else {
                    $Trigger = New-ScheduledTaskTrigger -Weekly -At $Job.At -DaysOfWeek $Job.Weekly.DaysofWeek
                    Return $Trigger
                }
            }
            Else {
                Write-Host ("Invalid parameter DaysofWeek : " + $Job.Weekly.DaysofWeek)
                LogWrite ("Invalid parameter DaysofWeek : " + $Job.Weekly.DaysofWeek)
            }
            break;
        }
        "Monthly" {
            #If DayOfMonth is defined in xml and WeekDayOfMonth is not
            If ($Job.Monthly.DayOfMonth.Length -gt 0 -and $Job.Monthly.WeekDayOfMonth.Length -eq 0) {
                                
                $DateOfTrigger = FindDateToTrigger -DayOfMonth $Job.Monthly.DayOfMonth -JobTime $Job.At
                $Trigger = New-ScheduledTaskTrigger -Once -At $DateOfTrigger
                Return $Trigger   
            }
            #If WeekDayOfMonth is defined, and DayOfMonth is not
            ElseIf ($Job.Monthly.WeekDayOfMonth.Length -gt 0 -and $Job.Monthly.DayOfMonth.Length -eq 0) {
                If ((("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday") -contains $Job.Monthly.WeekDayOfMonth) -and (("First","Second","Third","Fourth","Last") -contains $Job.Monthly.WeekDayOfMonthPosition)) {                                

                    switch ($Job.Monthly.WeekDayOfMonthPosition) {
                        "First" {
                            1..7|%{If ( (Get-Date($_.ToString() + "/" + $Now.Month + "/" + $Now.Year)).DayOfWeek -eq $Job.Monthly.WeekDayOfMonth ) {$TriggerDayOfMonth = $_.ToString()}}
                            break;
                        }
                        "Second" {
                            1..14|%{If ( (Get-Date($_.ToString() + "/" + $Now.Month + "/" + $Now.Year)).DayOfWeek -eq $Job.Monthly.WeekDayOfMonth ) {$TriggerDayOfMonth = $_.ToString()}}
                            break;
                        }
                        "Third" {
                            1..21|%{If ( (Get-Date($_.ToString() + "/" + $Now.Month + "/" + $Now.Year)).DayOfWeek -eq $Job.Monthly.WeekDayOfMonth ) {$TriggerDayOfMonth = $_.ToString()}}
                            break;
                        }
                        "Fourth" {
                            1..28|%{If ( (Get-Date($_.ToString() + "/" + $Now.Month + "/" + $Now.Year)).DayOfWeek -eq $Job.Monthly.WeekDayOfMonth ) {$TriggerDayOfMonth = $_.ToString()}}
                            break;
                        }
                        "Last" {
                            $FirstDayOfMonth = Get-Date( "01"+"/"+(Get-Date).Month+"/"+(Get-Date).Year)
                            [int]$LastDayOfMonth = Get-Date(($FirstDayOfMonth).AddMonths(1).AddSeconds(-1)) -format dd
                            1..$LastDayOfMonth|%{If ( (Get-Date($_.ToString() + "/" + $Now.Month + "/" + $Now.Year)).DayOfWeek -eq $Job.WeekDayOfMonth ) {$TriggerDayOfMonth = $_.ToString()}}
                            break;
                        }                                        
                    }
                                        
                    $DateOfTrigger = FindDateToTrigger -DayOfMonth $TriggerDayOfMonth -JobTime $Job.At
                    $Trigger = New-ScheduledTaskTrigger -Once -At $DateOfTrigger
                    Return $Trigger
                }
                Else {
                    Write-Host "Invalid parameters WeekDayOfMonthPosition WeekDayOfMonth : " $Job.Monthly.WeekDayOfMonthPosition $Job.Monthly.WeekDayOfMonth
                    LogWrite ("Invalid parameters WeekDayOfMonthPosition WeekDayOfMonth : " + $Job.Monthly.WeekDayOfMonthPosition + " " + $Job.Monthly.WeekDayOfMonth)
                }
            }
            ElseIf (($Job.Monthly.WeekDayOfMonth.Length -gt 0 -and $Job.Monthly.DayOfMonth.Length -gt 0)) {
                Write-Host "Monthly parameters are incorrect : WeekDayOfMonth and DayOfMonth should not be both filled"
                LogWrite ("Monthly parameters are incorrect : WeekDayOfMonth and DayOfMonth should not be both filled")
            }

            Else {
                Write-Host "Monthly parameters are incorrect"
                LogWrite ("Monthly parameters are incorrect")
            }
            break;
        }
    }
    
}

#
# Function ProcessHost : processing a Host from XML file object, everything happens here !
#
Function ProcessHost {
    param(
        [Parameter(Mandatory = $true)]
        $xml
    )
    #Listing Scripts for Actions
    $PossibleActions = @()
    ForEach ($Script_File In ($Script_Path | Get-ChildItem -Filter "*.ps1")) {
        $PossibleActions += (($Script_File.Name.Split("."))[0])
    }
    $PossibleActions += "Command"

    If ((($xml.Host.fqdn).Trim()).Length -eq 0) {
        Return($xml.Host.Name + " - Host FQDN is Empty!")
    }

    $fqdn = $xml.Host.fqdn
    $hostname = $xml.Host.Name

    $Host_Reachable = $False
    $TCP_Reachable = $False

    #Ping fqdn
    If (Test-Connection -count 2 $fqdn) {
        $Host_Reachable = $True
    }
    #TCPTest WinRM Port (HTTP: 5985 & HTTPS: 5986) : If this is okay, we don't care if we ping the host
    If ((tnc $fqdn -port 5985).TcpTestSucceeded -or (tnc $fqdn -port 5986 -WarningAction SilentlyContinue).TcpTestSucceeded) {
        $TCP_Reachable = $True
        If ((tnc $fqdn -port 5986 -WarningAction SilentlyContinue).TcpTestSucceeded) {
            $Use_SSL = $True
        }
        Else {
            $Use_SSL = $False
        }
    }

    If (!$Host_Reachable -and $TCP_Reachable) {
        Write-Host -ForegroundColor Yellow ("Ping failed but WinRM TCP Port is reachable (so it's ok, just telling)")
        LogWrite ("Ping failed but WinRM TCP Port is reachable (so it's ok, just telling)")
    }
    ElseIf (!$Host_Reachable -and !$TCP_Reachable) {
        Write-Host -ForegroundColor Red ("Ping and WinRM TCP Port failed : " + $fqdn + " is unreachable")
        LogWrite ("Ping and WinRM TCP Port failed : " + $fqdn + " is unreachable")
        Return
    }
    ElseIf ($Host_Reachable -and !$TCP_Reachable) {
        Write-Host -ForegroundColor Red ("Ping succeeded but WinRM TCP Port failed : WinRM on " + $fqdn + " is unreachable")
        LogWrite ("Ping succeeded but WinRM TCP Port failed : WinRM on " + $fqdn + " is unreachable")
        Return
    }

    # End of TCP connectivity tests


    If ($TCP_Reachable) {

        $Host_Auth = $False
        If (($xml.Host.Principal.Trim().Length -gt 0) -and ($xml.Host.SecString.Trim().Length -gt 0)) {
            $Host_Auth = $True
        }

        If ($Host_Auth) {
            $key = Get-Content $Key_Path
            $HostSS = ConvertTo-SecureString $xml.Host.SecString -key $key
            $Host_Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $xml.Host.Principal,$HostSS
            $Host_Session_Options = New-PSSessionOption -Culture "fr-fr"
            If ($Use_SSL) {
                $Host_Session_Options = New-PSSessionOption -Culture "fr-fr" -SkipCACheck -SkipCNCheck -SkipRevocationCheck
                $Host_Session = New-PSSession -ComputerName $fqdn -Credential $Host_Credentials -SessionOption $Host_Session_Options -ErrorAction SilentlyContinue -UseSSL
            }
            Else {
                $Host_Session = New-PSSession -ComputerName $fqdn -Credential $Host_Credentials -SessionOption $Host_Session_Options -ErrorAction SilentlyContinue
            }

            If (!$?) {
                Write-Host -ForegroundColor Red ("Error Opening PSSession")
                Write-Host -ForegroundColor Yellow $error[0]
                LogWrite ("Error Opening PSSession")
                LogWrite ($error[0])
                Return
            }

            #Cleaning All Scheduled task under $TaskPath

            If ($DefaultTaskPath.Trim().Length -gt 0) {
                $HostCommand_UnRegister = { param($TaskPath) Unregister-ScheduledTask -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue}
                $HostUnRegister = Invoke-Command -Session $Host_Session -ScriptBlock $HostCommand_UnRegister -Args ($DefaultTaskPath + "\")
                Write-Host -ForegroundColor Gray ("Cleaning " + $DefaultTaskPath)
                LogWrite ("Cleaning " + $DefaultTaskPath)
            }
            Else {
                Write-Host -ForegroundColor Red ("Error: DefaultTaskPath is empty!")
                LogWrite ("Error: DefaultTaskPath is empty!")
                Return("Error: DefaultTaskPath is empty!")
            }
        }

        #Jobs
        ForEach ($Job In $xml.Host.Job) {
            #Is the job enabled?
            $JobName = $Job.Name.Trim()
            If (([System.Convert]::ToBoolean($Job.Enabled)) -and ($JobName.Length -gt 0)) {
                If ($Job.Action -eq "Command") {
                    Write-Host -ForegroundColor Cyan ("Processing " + $fqdn + " - Name : " + $Job.Name + " - Command : " + $Job.Command)
                    LogWrite ("Processing " + $fqdn + " - Name : " + $Job.Name + " - Command : " + $Job.Command)
                }
                Else {
                    Write-Host -ForegroundColor Cyan ("Processing " + $fqdn + " - Name : " + $Job.Name + " - Action : " + $Job.Action)
                    LogWrite ("Processing " + $fqdn + " - Name : " + $Job.Name + " - Action : " + $Job.Action)
                }
                $Trigger = $Null
                $Now = Get-Date
                $JobTime = $Job.At

                # Processing trigger parameter             

                $ValidTrigger = $False

                $Trigger = GetTaskTrigger($Job)

                If ($Trigger.GetType().Name  -eq "ScheduledJobTrigger") {
                    $ValidTrigger = $True
                }
                Else {
                    $ValidTrigger = $False
                }

                If ($ValidTrigger) {

                    # Getting Job Type
                    $JobType = $Job.Type

                    $Remote = $False

                    If ($JobType.Length -gt 0) {
                        Switch ($JobType.ToLower()) {
                            "task" {
                                $Remote = $False
                                $Remote_Argument = ""
                            break;
                            }
                            "job" {
                                #TODO
                                $Remote = $False
                                $Remote_Argument = ""
                            break;
                            }
                            "remote_task" {
                                $Remote = $True
                                $Remote_Argument = " -ComputerName " + $fqdn
                            break;
                            }
                            "remote_command" {
                                $Remote = $True
                                $Remote_Argument = " -ComputerName " + $fqdn
                            break;
                            }
                            
                        }
                    }

                    # Processing Action parameters

                    If ($Job.Action -eq "Command") {
                        If ($Job.Command.Trim().Length -gt 0) {
                            $Command = $Job.Command
                            $Command_Argument = $Job.Arguments
                            If ($Job.Arguments.Length -gt 0) {
                                $Action = New-ScheduledTaskAction -Execute ($Command) -Argument ($Command_Argument + $Remote_Argument)
                            }
                            Else {
                                If ($Remote) {
                                    $Action = New-ScheduledTaskAction -Execute ($Command) -Argument ($Remote_Argument)
                                }
                                Else {
                                    $Action = New-ScheduledTaskAction -Execute ($Command)
                                }
                            }
                        }
                        Else {
                            Write-Host -ForegroundColor Red ("Error: Command is empty!")
                            Write-Error ("Error: Command is empty!")
                            LogWrite ("Invalid parameter : Command is empty")
                            Return ("Invalid parameter : Command is empty")
                        }
                    }
                    ElseIf ($PossibleActions -contains $Job.Action) {
                        
                        
                        #Script to launch in the scheduled task
                        
                        If ($Remote) {
                            $FullScriptPath = $Script_Path +"\"+ $Job.Action +".ps1"
                        }
                        Else {
                            $FullScriptPath = $Local_Script_Path +"\"+ $Job.Action +".ps1"
                        }

                        #Argument of the script will be $Job.Arguments
                        #Powershell.exe argument (Direcly behind powershell.exe)
                        $PowershellArg = " -ExecutionPolicy Bypass -File "

                        If ($Job.Arguments.Length -gt 0) {
                            $Action = New-ScheduledTaskAction -Execute ("powershell.exe") -Argument ($PowershellArg + $FullScriptPath + " " + $Job.Arguments + $Remote_Argument)
                        }
                        Else {
                            $Action = New-ScheduledTaskAction -Execute ("powershell.exe") -Argument ($PowershellArg + $FullScriptPath + $Remote_Argument)
                        }
                        
                    }
                    Else {
                        LogWrite ("Invalid parameter Action: " + $Job.Action)
                        Return ("Invalid parameter Action: " + $Job.Action)
                    }

                    #Auth

                    $Job_Auth = $False

                    # Processing Job Credentials if exist
                    If (($Job.Principal.Length -gt 0) -and ($Job.SecString.Length -gt 0)) {
                                
                        $Job_Auth = $True
                        $ValidAuth = $False
                                
                        $JobsSS = ConvertTo-SecureString $Job.SecString -key $key

                        $Job_Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Job.Principal,$JobsSS
                        $Job_Session = New-PSSession -ComputerName $fqdn -Credential $Job_Credentials

                        If (!$?) {
                            Write-Host -ForegroundColor Red ("Error Opening Job PSSession")
                            Write-Error ("Error Opening Job PSSession")
                            Write-Host -ForegroundColor Yellow $error[0]
                            LogWrite ("Error Opening PSSession")
                            LogWrite ($error[0])
                            $ValidAuth = $False
                        }
                        Else {$ValidAuth = $True}
                    }
                    Else {
                        If (!$Host_Auth) {
                            LogWrite ("Invalid Principal or SecString empty : " + $Job.Principal)
                            Write-Host -ForegroundColor Red ("Invalid Principal or SecString empty : " + $Job.Principal)
                        }
                    }

                    
                    If ($Job_Auth) {
                        $Session = $Job_Session
                        $Credentials = $Job_Credentials
                        Write-Host -ForegroundColor Gray ("Using Job Creds")
                        LogWrite ("Using Job Credentials")
                    }
                    ElseIf ($Host_Auth) {
                        $Session = $Host_Session
                        $Credentials = $Host_Credentials
                        $ValidAuth = $True
                        Write-Host -ForegroundColor Gray ("Using Host Creds")
                        LogWrite ("Using Host Credentials")
                    }
                    
                    If ($Remote) {
                        # TO MODIFY WHEN RUN FROM SCHEDULED TASK !!: 
                        $Session = New-PSSession -ComputerName $RemoteScriptHost -Credential $Credentials
                        # TO
                        #$Session = New-PSSession -ComputerName $RemoteScriptHost
                        Write-Host -ForegroundColor Cyan ("Using session on" + $RemoteScriptHost)
                        LogWrite ("Using session on" + $RemoteScriptHost)
                    }

                    #Not working without LogonType on W2K12, but seems to work on W10... Don't ask me, i don't know why
                    #$Principal = New-ScheduledTaskPrincipal -UserId $Credentials.UserName -RunLevel Highest
                    $Principal = New-ScheduledTaskPrincipal -UserId $Credentials.UserName -RunLevel Highest -LogonType ServiceAccount

                    $Settings = New-ScheduledTaskSettingsSet -DisallowDemandStart

                    #With principals
                    $Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings -Description $Job.Description -Principal $Principal

                    #Without principals
                    #$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings -Description $Job.Description
                            
                    #Launching remote commands
                    If ($ValidAuth) {

                        # Changing task path if remote
                        If ($Remote) {
                            $JobName = $hostname + "_" + $Job.Name
                            $TaskPath = $DefaultRemoteTaskPath
                        }
                        Else {
                            $JobName = $Job.Name
                            $TaskPath = $DefaultTaskPath
                        }

                        # Unregister JobAuth tasks
                        If (!$Host_Auth) {
                            $JobCommand_UnRegister = { param($TaskName) Get-ScheduledTask -TaskName $TaskName | Unregister-ScheduledTask -Confirm:$false }
                            $UnRegister = Invoke-Command -Session $Session -ScriptBlock $JobCommand_UnRegister -Args $JobName
                        }

                        #
                        # Unregister Remote tasks
                        #

                        If ($Remote) {
                            $Args = ( ($DefaultRemoteTaskPath + "\"), ($hostname + "*"))
                            $RemoteCommand_UnRegister = { param($TaskPath,$TaskName) Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue }
                            $RemoteUnRegister = Invoke-Command -Session $Session -ScriptBlock $RemoteCommand_UnRegister -Args $Args
                            Write-Host -ForegroundColor Gray ("Cleaning " + $DefaultRemoteTaskPath)
                            LogWrite ("Cleaning " + $DefaultRemoteTaskPath)
                        }

                        #
                        #Registering Scheduled Task
                        #

                        # Parameters to pass remotely
                        $JobArgs = ($Task,$JobName,$TaskPath,$Credentials)

                        # Register task
                        $JobCommand_Register = { param($Task,$TaskName,$TaskPath,$Credentials) Register-ScheduledTask $TaskName -TaskPath $TaskPath -InputObject $Task -User $Credentials.UserName -Password $Credentials.GetNetworkCredential().Password }
                        $Register = Invoke-Command -Session $Session -ScriptBlock $JobCommand_Register -Args $JobArgs

                        If ($?) {
                            Write-Host -ForegroundColor Green ("Successfully registered " + $JobName + " - At " + $JobTime + " - " + $Job.Trigger + " - " + $Job.Description)
                            LogWrite ("Successfully registered " + $JobName + " - At " + $JobTime + " - " + $Job.Trigger + " - " + $Job.Description)
                        }
                        Else {
                            Write-Host -ForegroundColor Red ("Error while registering " + $JobName)
                            Write-Error ("Error while registering " + $JobName)
                            LogWrite ("Error while registering " + $JobName)
                        }

                        # Copying scripts (Get Content from scheduler side, and transfer it throught the remote encrypted PSSession, then create the new file on the remote host
                        If (!$Remote) {
                            If ($Job.Action -ne "Command") {
                                $Script_Content = Get-Content ($Script_Path + "\" + $Job.Action + ".ps1")
                                $Sync_Script_Command = { param($FileName,$Flux) If (!(Test-Path (Split-Path $FileName))) {New-Item (Split-Path $FileName) -Type Directory}; Set-Content -path $FileName -value $Flux -Force }
                                $Sync_Script = Invoke-Command -Session $Session -ScriptBlock $Sync_Script_Command -Args $FullScriptPath,$Script_Content
                            }
                        }

                        # Terminating Job Session
                        If ($Job_Auth) {
                            Write-Host "Terminating Job Session"
                            Remove-PSSession $Job_Session
                        }
                    }
                }
                Else {
                    LogWrite ("Invalid Trigger : skipping Job : "+ $Job.Name)
                    Write-Host -ForegroundColor Red ("Invalid Trigger : skipping Job : " + $Job.Name)
                }
            }
            Else {
                If ($JobName.Length -eq 0) {
                    Write-Host -ForegroundColor Red ("Error: JobName is Empty : " + $Job.Name)
                    Write-Error ("JobName is Empty : " + $Job.Name)
                    LogWrite ("Error: JobName is Empty : " + $Job.Name)
                }
                Else {
                    Write-Host -ForegroundColor Gray ($Job.Name + " is Disabled")
                    LogWrite ($Job.Name + " is Disabled")
                }
            }
        }
        #Terminating Host Session
        If ($Host_Auth) {
            Remove-PSSession $Host_Session
            Write-Host -ForegroundColor DarkGray "Terminating Host Session"
        }
    }
}


$script:dir = "drive:\rootpath"

$script:Script_Path = $dir + "\Scripts"
$script:Key_Path = $dir + "\Secure\AES.key"
$script:DefaultTaskPath = "\Scheduler\Auto"
$script:DefaultRemoteTaskPath = $DefaultTaskPath + "\Remote"
$script:Local_Script_Path = "C:\Scheduler\Scripts\"

$script:RemoteScriptHost = "scheduler_host_fqdn"

$fqdn = $xml.Host.fqdn
$hostname = $xml.Host.Name

$logfilepath = $dir + "\Process_Logs"
$logfilename = "Process_"+ $hostname +"_" + (Get-Date -Format yyyyMMdd_HHmmss) + ".log"
$script:logfile = $logfilepath + "\" + $logfilename
$ForegroundColors = "Black","Blue","Cyan","DarkBlue","DarkCyan","DarkGray","DarkGreen","DarkMagenta","DarkRed","DarkYellow","Gray","Green","Magenta","Red","White","Yellow"

#
# Go : Process Host
#

$Start = Get-Date

Write-Host -ForegroundColor White ("Processing " + $hostname)
Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("********************************")
ProcessHost -xml $xml

$End = Get-Date
$Time = ($End - $Start).TotalSeconds
Write-Host -ForegroundColor Green ($hostname + " processed in " + $Time + "s")

#Return (0)