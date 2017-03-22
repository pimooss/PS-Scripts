#
# Powershell Scheduler for Windows- Experimental Remote Command 
#
# XML Config files must be placed (or created via Create-xml.ps1 script) in .\Configs
# One XML file by host
#
# Usage: RcomThread.ps1 [-DoOnly <hostname>]
#           Without parameters, it will do every xml files. 
#           If [-DoOnly] parameter is set, it will try to find the xml file corresponding to the given hostname.
#
# Example: RcomThread.ps1 -DoOnly wsus01
#            Will only do wsus01 if the xml file exists
#          RcomThread.ps1
#            Will do every xml files in .\Configs
#
# Auth: Joris Decombe
# Date: 08/07/2015
# Version: 1.0
#

param(
    [Parameter(Mandatory = $true,Position = 0)]
    $hostxml,
    [Parameter(Mandatory = $true,Position = 1)]
    $xml,
    [Parameter(Mandatory = $true,Position = 2)]
    $xmlfile
)

#
# Log function
#

Function LogWrite
{
   Param ([string]$logstring)
   Add-content $logfile -value ((Get-Date -Format yyyyMMdd_HHmmss) + " : " + $logstring)
}

Function ChangeJobStatus {
    param (
        [Parameter(Mandatory = $true,Position = 0)]
        [string]$xmlpath,
        [switch]$Success,
        [switch]$Error,
        [switch]$InProgress
    )

    $xml = New-Object -TypeName XML
    $xml.Load($xmlpath)

    # Changing status
    $item = Select-XML -Xml $xml -XPath ("//Job[1]")
    If ($Success) {
        $item.Node.SetAttribute('Status','Success')
    }
    If ($Error) {
        $item.Node.SetAttribute('Status','Error')
    }
    If ($InProgress) {
        $item.Node.SetAttribute('Status','InProgress')
    }
    $xml.Save($xmlpath)


}

#
# Function ProcessHost : processing a Host from XML file object, everything happens here !
#
Function RcomProcessHost {
    param(
        [Parameter(Mandatory = $true)]
        $xml,
        [Parameter(Mandatory = $true)]
        $hostxml
    )

    ChangeJobStatus $xmlfile -InProgress

    #Listing Scripts for Actions
    $PossibleActions = @()
    ForEach ($Script_File In ($Script_Path | Get-ChildItem -Filter "*.ps1")) {
        $PossibleActions += (($Script_File.Name.Split("."))[0])
    }
    $PossibleActions += "Command"

    If ((($hostxml.Host.fqdn).Trim()).Length -eq 0) {
        Return($hostxml.Host.Name + " - Host FQDN is Empty!")
    }

    $fqdn = $hostxml.Host.fqdn
    $hostname = $xml.Host.Name

    $Host_Reachable = $False
    $TCP_Reachable = $False

    #Ping fqdn
    If (Test-Connection -count 2 $fqdn) {
        $Host_Reachable = $True
    }
    #TCPTest WinRM Port (HTTP: 5985 & HTTPS: 5986) : If this is okay, we don't care if we ping the host
    If ((tnc $fqdn -port 5985).TcpTestSucceeded ) {
        $TCP_Reachable = $True
    }

    If (!$Host_Reachable -and $TCP_Reachable) {
        Write-Host -ForegroundColor Yellow ("Ping failed but WinRM TCP Port is reachable (so it's ok, just telling)")
        LogWrite ("Ping failed but WinRM TCP Port is reachable (so it's ok, just telling)")
    }
    ElseIf (!$Host_Reachable -and !$TCP_Reachable) {
        Write-Host -ForegroundColor Red ("Ping and WinRM TCP Port failed : " + $fqdn + " is unreachable")
        LogWrite ("Ping and WinRM TCP Port failed : " + $fqdn + " is unreachable")
        
        ChangeJobStatus $xmlfile -Error

        Return
    }
    ElseIf ($Host_Reachable -and !$TCP_Reachable) {
        Write-Host -ForegroundColor Red ("Ping succeeded but WinRM TCP Port failed : WinRM on " + $fqdn + " is unreachable")
        LogWrite ("Ping succeeded but WinRM TCP Port failed : WinRM on " + $fqdn + " is unreachable")

        ChangeJobStatus $xmlfile -Error

        Return
    }

    # End of TCP connectivity tests

    If ($TCP_Reachable) {

        $Host_Auth = $False
        If (($hostxml.Host.Principal.Trim().Length -gt 0) -and ($hostxml.Host.SecString.Trim().Length -gt 0)) {
            $Host_Auth = $True
        }

        If ($Host_Auth) {
            $key = Get-Content $Key_Path
            $HostSS = ConvertTo-SecureString $hostxml.Host.SecString -key $key
            $Host_Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $hostxml.Host.Principal,$HostSS
            $Host_Session_Options = New-PSSessionOption -Culture "fr-fr"
            $Host_Session = New-PSSession -ComputerName $fqdn -Credential $Host_Credentials -SessionOption $Host_Session_Options -ErrorAction SilentlyContinue
            If (!$?) {
                Write-Host -ForegroundColor Red ("Error Opening PSSession")
                Write-Host -ForegroundColor Yellow $error[0]
                LogWrite ("Error Opening PSSession")
                LogWrite ($error[0])

                ChangeJobStatus $xmlfile -Error

                Return
            }

        }

        #Jobs
        ForEach ($Job In $xml.Host.Job) {

            # Processing job
            $JobName = $Job.Name.Trim()
            If ($JobName.Length -gt 0) {
                If ($Job.Action -eq "Command") {
                    Write-Host -ForegroundColor Cyan ("Processing " + $fqdn + " - Name : " + $Job.Name + " - Command : " + $Job.Command)
                    LogWrite ("Processing " + $fqdn + " - Name : " + $Job.Name + " - Command : " + $Job.Command)
                }
                Else {
                    Write-Host -ForegroundColor Cyan ("Processing " + $fqdn + " - Name : " + $Job.Name + " - Action : " + $Job.Action)
                    LogWrite ("Processing " + $fqdn + " - Name : " + $Job.Name + " - Action : " + $Job.Action)
                }

                $Now = Get-Date

                # Processing Action parameters

                If ($Job.Action -eq "Command") {
                    If ($Job.Command.Trim().Length -gt 0) {
                        $Command = $Job.Command
                        $Command_Argument = $Job.Arguments
                        If ($Job.Arguments.Length -gt 0) {
                            $Action = $Command
                            $JobArgument = $Command_Argument
                        }
                        Else {
                            $Action = $Command
                            $JobArgument = ""
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
                    $RemoteScript = $True

                    #$Remote_Argument = " -ComputerName " + $fqdn

                    $FullScriptPath = $Script_Path +"\"+ $Job.Action +".ps1"
                    $PowershellArg = " -ExecutionPolicy Bypass -Command "

                    #Argument of the script will be $Job.Arguments
                    If ($Job.Arguments.Length -gt 0) {
                        $Action = "&powershell.exe" + $PowershellArg
                        $JobArgument = $Job.Arguments
                    }
                    Else {
                        $Action = "&powershell.exe" + $PowershellArg
                        $JobArgument = ''
                    }
                        
                }
                Else {
                    LogWrite ("Invalid parameter Action: " + $Job.Action)
                    Return ("Invalid parameter Action: " + $Job.Action)
                }

                If ($Host_Auth) {
                    $Session = $Host_Session
                    $Credentials = $Host_Credentials
                    $ValidAuth = $True
                    Write-Host -ForegroundColor Gray ("Using Host Creds")
                    LogWrite ("Using Host Credentials")
                }
                    
                #Launching remote commands
                If ($ValidAuth) {

                    $JobName = $Job.Name

                    #
                    # Command
                    #                  

                    If ($RemoteScript) {
                        # launching script
                        #$Script_Content = Get-Content $FullScriptPath
                        #$ScriptBlock = [Scriptblock]::Create($Script_Content)
                        $JobArgs = ($JobArgument)
                        #$Block = {param($Action, $ScriptBlock,$JobArgument) $ScriptBlock +' '+ $JobArgument}
                        $Result = Invoke-Command -Session $Session -FilePath $FullScriptPath -ArgumentList $JobArgs
                    }
                    Else {
                       
                        # Parameters to pass remotely
                        $JobArgs = ($Action,$JobArgument)
                        $Block = {param($Command,$Arg) cmd /c $Command $Arg }
                        # launching remote Command
                        $Result = Invoke-Command -Session $Session -ScriptBlock $Block -ArgumentList $JobArgs
                    }
                    

                    If ($?) {
                        Write-Host -ForegroundColor Green ("Successfully launched " + $JobName + " - Command : " + $Action  + " - Args : " + $JobArgument )
                        LogWrite ("Successfully launched " + $JobName + " - Command : " + $Action  + " - Args : " + $JobArgument )

                        ChangeJobStatus $xmlfile -Success
                    }
                    Else {
                        Write-Host -ForegroundColor Red ("Error while launching " + $JobName)
                        Write-Error ("Error while launching " + $JobName)
                        LogWrite ("Error while launching " + $JobName)

                        ChangeJobStatus $xmlfile -Error
                    }
                }

            }
            Else {
                    Write-Host -ForegroundColor Red ("Error: JobName is Empty : " + $Job.Name)
                    Write-Error ("JobName is Empty : " + $Job.Name)
                    LogWrite ("Error: JobName is Empty : " + $Job.Name)

                    ChangeJobStatus $xmlfile -Error
            }
        }
        #Terminating Host Session
        If ($Host_Auth) {
            Remove-PSSession $Host_Session
            Write-Host -ForegroundColor DarkGray "Terminating Host Session"
        }
    }
}

$scriptpath = "E:\Scheduler_Dev\RCom"
$script:dir = Split-Path -Parent $scriptpath

$script:Script_Path = $dir + "\Scripts"
$script:Key_Path = $dir + "\Secure\AES.key"

$script:Rcom_Poll_Path = $scriptpath + "\In"
$script:Out_Path = $scriptpath + "\Out"
$script:Error_Path = $scriptpath + "\Error"

$fqdn = $hostxml.Host.fqdn
$hostname = $hostxml.Host.Name

$logfilepath = $scriptpath + "\Logs"
$logfilename = "Process_"+ $hostname +"_" + (Get-Date -Format yyyyMMdd_HHmmss) + ".log"
$script:logfile = $logfilepath + "\" + $logfilename
$ForegroundColors = "Black","Blue","Cyan","DarkBlue","DarkCyan","DarkGray","DarkGreen","DarkMagenta","DarkRed","DarkYellow","Gray","Green","Magenta","Red","White","Yellow"

#
# Go : Process Host
#

$Start = Get-Date

Write-Host -ForegroundColor White ("Processing " + $hostname)
Write-Host -ForegroundColor (Get-Random -InputObject $ForegroundColors) ("********************************")

RcomProcessHost -xml $xml -hostxml $hostxml

$End = Get-Date
$Time = ($End - $Start).TotalSeconds
Write-Host -ForegroundColor Green ($hostname + " processed in " + $Time + "s")
