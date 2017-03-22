#
# Unfinished attempt to make a configuration GUI  
#
# Some functions could be usefull, so i'm keeping it
# v.0.1
#
#


Function Check-Syntax {
    param(
        [Parameter(Mandatory = $true,Position = 0)]
        $tocheck
    )
    $ValidSyntax = $False
    If ($tocheck -eq $null){
        Return "I need an input..."
        Write-Host -ForegroundColor Red "I need an input..."
    }    
    Else {
        If ($tocheck.Trim().Length -eq 0) {
            Return "I need an input..."
            Write-Host -ForegroundColor Red "I need an input..."
        }
        Else {
            If ($tocheck.GetType().Name -eq "String") {
                $strpattern = '[a-zA-Z]'
                $intpattern = '[0-9]'
                If ($tocheck -match $strpattern) {
                    $ValidSyntax = $True
                    $Type = "String"
                }
                ElseIf ($tocheck -match $intpattern) {
                    $ValidSyntax = $True
                    $Type = "Int"
                }
                Else {
                    Write-Host -ForegroundColor Red "Invalid String"
                    Return "Invalid String"
                }
            }
        }
    }
    [hashtable]$Return = @{} 
    $Return.Valid = $ValidSyntax
    $Return.Type = $Type
    Return, $Return
}

Function Validate-Answer {
    param(
        [Parameter(Mandatory = $true,Position=0)]
        $Answer,
        [Parameter(Mandatory = $true,Position=1)]
        [hashtable]$Data,
        [Parameter(Mandatory = $false,Position=2)]
        [ValidateSet("Both","Int","String")]
        $Type = "Both",
        [Parameter(Mandatory = $false,Position=3)]
        $a = (@{Expression={$_.Name};Label="Id"},
                @{Expression={$_.Value};Label="Possible Actions"})
    )
    
    $ValidAnswer = $False
    $CheckSyntax = (Check-Syntax $Answer)

    If ($CheckSyntax.Valid) {
        If ($CheckSyntax.Type -like "String") {
            $Found = $Data.GetEnumerator() | Where {$_.Value -like '*'+($Answer.ToLower() -replace " ","*")+'*'}
            If ($Found.Count -gt 0) {
                While ($Found.Count -gt 1) {
                    Write-Host "Which one ? : "
                    $Found.GetEnumerator() | Sort-Object -Property Name | Format-Table -AutoSize $a | Out-Host

                    $Choice = Read-Host "Enter your choice"
                    $Check = (Check-Syntax $Choice)
                    If ($Check.Valid) {
                        If ($Check.Type -eq "Int") {
                            $Found = $Found.GetEnumerator() | Where {$_.Key -eq $Choice}
                        }
                        ElseIf ($Check.Type -like "String") {
                            $Found = $Found.GetEnumerator() | Where {$_.Value -like '*'+($Choice.ToLower() -replace " ","*")+'*'}
                        }
                    }
                }
                If ($Found.Count -eq 1) {
                    $ValidAnswer = $True
                }
            }
            
        }
        ElseIf ($CheckSyntax.Type -like "Int*") {
            $Found = $Data.GetEnumerator() | Where {$_.Key -eq $Answer}
            If ($Found.Count -eq 0) {
                Return {"Id not found"}
            }
            ElseIf ($Found.Count -eq 1) {
                $ValidAnswer = $True
            }
        }
    }
    If ($ValidAnswer) {
        $Id = $Found.Key
    }
    Else {
        $Id = $False
    }

    [hashtable]$Return = @{} 
    $Return.Valid = $ValidAnswer
    $Return.Type = $CheckSyntax.Type
    $Return.Id = $Id
    Return,$Return

}

Function List-Hosts {
    param(
        [Parameter(Mandatory = $false,Position=0)]
        [string]$search = "*",
        [Parameter(Mandatory = $false)]
        [Switch]$OutHost,
        [Switch]$Strict

    )

    If ($Strict) {
        $search = $search -replace "\*","" -replace "\?",''
    }

    $Data = $ConfigFiles | %{
                                $xml = New-Object -TypeName XML; 
                                $xml.Load($_.FullName);
                                If ($xml.Host.Name -like $search) {
                                    Write-Output $xml.Host
                                }
                                
                            }
    If ($OutHost) {
        $Data | Select Name, fqdn, Org, Enabled , Principal | Sort -Property Name | Format-Table -AutoSize | Out-Host
    }

    If ($Data) {
        Return,$Data
    }
    Else {
        Return $false
    }
}

Function List-Tasks {
    param(
        [Parameter(Mandatory = $true,Position=0)]
        $search,
        [Parameter(Mandatory = $false)]
        [Switch]$OutHost
    )

    $a = @{Expression={$_.ParentNode.Name};Label="HostName"},
        @{Expression={$_.ParentNode.Org};Label="Org"},
        @{Expression={$_.ParentNode.Enabled};Label="HostEnabled"},
        @{Expression={$_.Name};Label="JobName"},
        @{Expression={$_.Enabled};Label="JobEnabled"},
        @{Expression={$_.Type};Label="Type"},
        @{Expression={$_.Action};Label="Action"},
        @{Expression={$_.Arguments};Label="Arguments"},
        @{Expression={$_.Trigger};Label="Trigger"},
        @{Expression={$curObj = $_ ; Switch($_.Trigger.ToLower()){
                        "daily" {If($curObj.Daily.DaysInterval -match '[0-7]') {"Every "+$curObj.Daily.DaysInterval +" Days"}; break}

                        "weekly" {If($curObj.Weekly.DaysofWeek -match '[a-zA-Z]') {

                         If($curObj.Weekly.WeeksInterval -match '[0-52]') {$curObj.Weekly.DaysofWeek + " Every "+$curObj.Weekly.WeeksInterval +" Weeks"}}
                         Else {$curObj.Weekly.DaysofWeek} ;break}

                        "monthly" {If ($curObj.Monthly.WeekDayOfMonth -match '[a-zA-Z]') {$curObj.Monthly.WeekDayOfMonthPosition + " " + $curObj.Monthly.WeekDayOfMonth}
                                   ElseIf($curObj.Monthly.DaysofMonth -match '[0-31]') {"Every " + $curObj.Monthly.DaysofMonth} break}
                        }
         };Label="When"},
        @{Expression={$_.AT};Label="At"},
        @{Expression={$_.Description};Label="Description"},
        @{Expression={If($_.Principal -eq ""){$_.ParentNode.Principal}Else{$_.Principal}};Label="Principal"}

    $HostData = $ConfigFiles | Where-Object Name -like ($search + '*') | %{
                                $xml = New-Object -TypeName XML; 
                                $xml.Load($_.FullName); 
                                Write-Output $xml.Host
                            }
    If ($OutHost) {
        $HostData.Job | Format-Table -AutoSize $a | Out-Host
    }
    
    Return,$HostData.Job

}

Function Save-Config {
    param(
        [Parameter(Mandatory = $true,Position=0)]
        $Hostname
    )
    $xmlfile = ($ConfigPath | Get-ChildItem -Filter "*.xml" | Where Name -like ($HostName+".xml")).FullName
    
    $now = (Get-Date -Format ddMMyyyy_hhmmss)
    
    If (!(Test-Path $BackupPath)) {New-Item -ItemType Directory $BackupPath | Out-Null}

    $target = $BackupPath + "\" + $HostName + "_" + $now + ".xml"
    Copy-Item $xmlfile $target | Out-Null

    If ($?) {
        Write-Host ($xmlfile + " has been saved")
    }
    Else {
        Write-Host -ForegroundColor Red ($xmlfile + " could not been saved")
        Write-Host -ForegroundColor $Error[0]
    }
}

Function Validate-Trigger {
    param(
        [Parameter(Mandatory = $false)]
        $JobTrigger,
        [Parameter(Mandatory = $false)]
        [Switch]$cli,
        [Int]$JobDaysInterval,
        [String]$JobDaysOfWeek,
        [Int]$JobWeeksInterval,
        [String]$JobWeekDayOfMonthPosition,
        [String]$JobWeekDayOfMonth,
        [Int]$JobDaysOfMonth
    )

    $Job = @{}

    If ($cli) {
        If (!$JobTrigger) {
            Write-Host -ForegroundColor Red ("Missing JobTrigger")
            Return $False
        }
        If ($PossibleTriggers -notcontains $JobTrigger) {
            Write-Host -ForegroundColor Red ("JobTrigger " + $Job.Trigger + " is invalid")
            $PossibleTriggers | Format-List
            Return $False
        }
        $Job.Trigger = $JobTrigger
    }
    Else {
         # Job Triggers
        Write-Host $separator
        Write-Host ("Possible triggers")
        Write-Host $separator
        $PossibleTriggers | Write-Host -ForegroundColor Green
        Write-Host $separator
        $Job.Trigger = Read-Host ("Please enter a trigger")
        While ($PossibleTriggers -notcontains $Job.Trigger) {
            $Job.Trigger = Read-Host ("Try again")
        }

    }

    # Getting specifics
    Switch ($Job.Trigger.Tolower()) {

        "daily" {
            $Job.Daily = @{}
            If (!$JobDaysInterval) {
                $JobDaysInterval = 1
            }
            If ($cli) {
                $Job.Daily.DaysInterval = $JobDaysInterval
                If ((1..365) -notcontains $Job.Daily.DaysInterval) {
                    Write-Host -ForegroundColor Red ("DaysInterval " + $Job.Daily.DaysInterval + " is invalid")
                    Return $False
                }
            }
            Else {
                $Job.Daily.DaysInterval = Read-Host ("Please enter an interval (1-365) or empty for default")
                If ($Job.Daily.DaysInterval  -eq "") {
                    $Job.Daily.DaysInterval = 1
                }
                While ((1..365) -notcontains $Job.Daily.DaysInterval) {
                    $Job.Daily.DaysInterval = Read-Host ("Please enter an interval (1-365)")
                }
            }
        ;break}

        "weekly" {
            
            $Job.Weekly = @{}

            If ($cli) {

                # Day of the week
                $Job.Weekly.DaysOfWeek = $JobDaysOfWeek
                If (("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday") -Contains $Job.Weekly.DaysOfWeek) {
                    Write-Host -ForegroundColor Red ("DaysOfWeek " + $Job.Weekly.DaysOfWeek + " is invalid")
                    Return $False
                }

                # Weeks Interval
                If (!$JobWeeksInterval) {
                    $JobWeeksInterval = 1
                }

                $Job.Weekly.WeeksInterval = $JobWeeksInterval

                If ((1..52) -NotContains $Job.Weekly.WeeksInterval) {
                    Write-Host -ForegroundColor Red ("WeeksInterval " + $Job.Weekly.WeeksInterval + " is invalid")
                    Return $False
                }
            }
            Else {

                $Job.Weekly.DaysOfWeek = ""

                While (("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday") -NotContains $Job.Weekly.DaysOfWeek) {
                        $Job.Weekly.DaysOfWeek = Read-Host ('Please enter a day of the week ("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")') 
                }

                $Job.Weekly.WeeksInterval = Read-Host ('Please enter a week interval (1-52) or empty for default')

                If ($Job.Weekly.WeeksInterval -eq "") {
                    $Job.Weekly.WeeksInterval = 1
                }

                While ((1..52) -NotContains $Job.Weekly.WeeksInterval) {
                        $Job.Weekly.WeeksInterval = Read-Host ('Please enter a week interval (1-52)')
                }
            }
        ;break}
        
        "monthly" {
            $Job.Monthly = @{}

            If ($cli) {
                If (!$JobWeekDayOfMonthPosition -and !$JobWeekDayOfMonth) {
                    $MonthlyType = 2
                }
                Else {
                    $MonthlyType = 1
                }

                If ($MonthlyType -eq 1) {
                    $Job.Monthly.WeekDayOfMonthPosition = $JobWeekDayOfMonthPosition
                    If (("First","Second","Third","Fourth","Last") -notcontains $Job.Monthly.WeekDayOfMonthPosition) {
                        Write-Host -ForegroundColor Red ("WeekDayOfMonthPosition " + $Job.Monthly.WeekDayOfMonthPosition + " is invalid")
                        Return $False
                    }
                    $Job.Monthly.WeekDayOfMonth = $JobWeekDayOfMonth
                    If (("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday") -NotContains $Job.Monthly.WeekDayOfMonth) {
                        Write-Host -ForegroundColor Red ("WeekDayOfMonth " + $Job.Monthly.WeekDayOfMonth + " is invalid")
                        Return $False
                    }
                }
                ElseIf ($MonthlyType -eq 2) {
                    $Job.Monthly.DaysOfMonth = $JobDaysOfMonth
                    If ((1..31) -notcontains $Job.Monthly.DaysOfMonth) {
                        Write-Host -ForegroundColor Red ("DaysOfMonth " + $Job.Monthly.DaysOfMonth + " is invalid")
                        Return $False
                    }
                }
            }
            Else {

                Write-Host -ForegroundColor Green ('[1: By week day (ex: every second Monday)]')
                Write-Host -ForegroundColor Green ('[2: By month day (ex: every 13th)]')

                $MonthlyType = ""
                While ((1..2) -notcontains $MonthlyType) {
                    $MonthlyType = Read-Host ("Please choose between above choices (1-2)")
                }

                If ($MonthlyType -eq 1) {

                    $Job.Monthly.WeekDayOfMonthPosition = ""
                    While (("First","Second","Third","Fourth","Last") -notcontains $Job.Monthly.WeekDayOfMonthPosition) {
                        $Job.Monthly.WeekDayOfMonthPosition = Read-Host ('Day position ("First","Second","Third","Fourth","Last")')
                    }

                    $Job.Monthly.WeekDayOfMonth  = ""
                    While (("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday") -NotContains $Job.Monthly.WeekDayOfMonth) {
                        $Job.Monthly.WeekDayOfMonth = Read-Host ('Day of the week ("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")')
                    }

                }
                ElseIf ($MonthlyType -eq 2) {
                    $Job.Monthly.DaysOfMonth = ""
                    While ((1..31) -notcontains $Job.Monthly.DaysOfMonth) {
                        $Job.Monthly.DaysOfMonth = Read-Host ('Day of month (1-31)')
                    }
                }
            }
        ;break}
    }
    Return,$Job
}

Function Validate-JobName {
    param(
        [Parameter(Mandatory = $False)]
        [String]$HostName,
        [Parameter(Mandatory = $False)]
        [String]$JobName,
        [Switch]$Silent
    )

    If (!$HostName) {
        Write-Host -ForegroundColor Red ("Missing Hostname")
        Return $False
    }
    If (!$JobName) {
        Write-Host -ForegroundColor Red ("Missing JobName")
        Return $False
    }      
    If ((List-Tasks $HostName | %{$_.Name -like $JobName})) {
        If (!$Silent) {
            Write-Host -ForegroundColor Red ("JobName " + $JobName + " already exists, please choose another name")
        }
        Return $False
    }
    Else {
        Return $True
    }
}

Function Create-Host {
    param(
        [Switch]$cli,
        [Parameter(Mandatory = $True)]
        [String]$HostName,
        [String]$FQDN,
        [String]$Org,
        [String]$Principal,
        [String]$Password
    )
    
    $xmlfile = $ConfigPath+"\"+$HostName+".xml"

    # New Host
    Write-Host -ForegroundColor DarkCyan ("Creating New Host")
    If (!$cli) {
        $fqdn = Read-Host ("FQDN (server.as30781.net) or IP address")
        $org = Read-Host ("Organisation (Type CORP for Corp servers in the same Domain)")
    }
    If ($org.ToUpper() -eq "CORP") {
        $principal = $DefaultPrincipal
        $password = $DefaultPassword
    }
    Else {
        If (!$cli) {
            $principal = Read-Host ("User account for this host (ex: Domain\Name or User )")
            $password = Read-Host -AsSecureString ("Password") | ConvertFrom-SecureString -Key $key 
            $confirmpassword = Read-Host -AsSecureString ("Confirm Password") | ConvertFrom-SecureString -Key $key

            If ($password -eq $confirmpassword) {
                    
            }
            Else {
                Write-Host -ForegroundColor Red ("Password does not match")
                Return $False
            }
        }
    }

    # ToDo : fqdn Syntax check

    Write-Host -ForegroundColor Yellow ("HostName : " + $HostName)
    Write-Host -ForegroundColor Yellow ("FQDN or IP : " + $FQDN.ToLower())
    Write-Host -ForegroundColor Yellow ("Org : " + $Org.ToUpper())

    If ($org.ToUpper() -ne "CORP") {
        Write-Host -ForegroundColor Yellow ("User:" + $principal.ToLower())
    }
    If (!$cli) {
        $Confirm = Read-Host "Confirm ? [Y/N]"
        If ($Confirm.ToUpper() -eq "Y") {$Confirm = $True}
    }

    # Validate cli host parameters

    If ($cli) {
        If (!$HostName) {
            Write-Host -ForegroundColor Red ('Missing HostName')
            Return $False               
        }
        If (!$fqdn) {
            Write-Host -ForegroundColor Red ('Missing fqdn')  
            Return $False              
        }
        If (!$org) {
            Write-Host -ForegroundColor Red ('Missing org')
            Return $False              
        }
        If ($org.ToUpper() -ne "CORP") {
            If (!$principal) {
                Write-Host -ForegroundColor Red ('Missing principal')
                Return $False            
            }
           
            If (!$password) {
                Write-Host -ForegroundColor Red ('Missing password')
                Return $False            
            }
            Else {
                $password = $password | ConvertFrom-SecureString -Key $key 
            }
        }
        $Confirm = $True
    }

    If ($Confirm) {

        # Create XML
        If(-Not (Test-Path $xmlfile)) {
            $xmlWriter = New-Object System.XMl.XmlTextWriter($xmlfile,$Null)
            $xmlWriter.Formatting = 'Indented'
            $xmlWriter.Indentation = 1
            $xmlWriter.IndentChar = "`t"
            $xmlWriter.WriteStartDocument()
            $xmlWriter.WriteComment(("Schedule tasks for "+$HostName))
            $xmlWriter.WriteStartElement('Host')
            $xmlWriter.WriteAttributeString('Name', $HostName)
            $xmlWriter.WriteAttributeString('fqdn', $fqdn)
            $xmlWriter.WriteAttributeString('Org', $org)
            $xmlWriter.WriteAttributeString('Enabled', "False")
            $xmlWriter.WriteElementString('Principal', $principal)
            $xmlWriter.WriteElementString('SecString', $password)
            $xmlWriter.WriteEndElement()
            $xmlWriter.WriteEndDocument()
            $xmlWriter.Flush()
            $xmlWriter.Close()

            If ($?) {
                Write-Host ("Host Successfully added")
                Return $True
            }
        }
        Else {
            Write-Host -ForegroundColor Red ("Hum... " + $xmlfile + " already exists ... it really shouldn't")
            Return $False
        }
    }   
}

Function Create-Task {
    param (
        [Parameter(Mandatory = $false)]
        [string]$HostName,
        [Parameter(Mandatory = $false)]
        [Switch]$cli,
        # CLI parameters
        [String]$fqdn,
        [String]$org,
        [String]$principal,
        [String]$password,
        [String]$JobName,
        [String]$JobType,
        [String]$JobDescription,
        [String]$JobAction,
        [String]$JobCommand,
        [String]$JobArguments,
        [String]$JobAt,
        [String]$JobTrigger,
        [Int]$JobDaysInterval,
        [String]$JobDaysOfWeek,
        [Int]$JobWeeksInterval,
        [String]$JobWeekDayOfMonthPosition,
        [String]$JobWeekDayOfMonth,
        [Int]$JobDaysOfMonth,
        [String]$JobPrincipal,
        [String]$JobPassword
    )

    If (!$cli) {
        $HostName = Read-Host "HostName"
    }
    
    $JobCreation = $False

    $ValidAnswer = $False

    $CheckSyntax = (Check-Syntax $HostName)

    If ($CheckSyntax.Valid) {
        $HostName = $HostName.ToUpper()
        If (List-Hosts $HostName) {
            $NewHost = $False

            Write-Host -ForegroundColor Cyan ($HostName + " already exists in db")
            List-Hosts $HostName -OutHost | Out-Null
            If (!$cli) {
                $Confirm = Read-Host ("Confirm HostName")
                If ($Confirm.ToUpper() -eq $HostName.ToUpper()) {
                    $ValidAnswer = $True
                }
                Else {
                    Write-Host -ForegroundColor Yellow ("Confirmation failed")
                    MainMenu $MainMenuData
                }
            }
            Else {
                $ValidAnswer = $True
            }
        }
        Else {
            $NewHost = $True
            Write-Host -ForegroundColor Cyan ("Host is not recorded yet : " + $HostName)
            If (!$cli) {
                $Confirm = Read-Host ("Confirm HostName")
                If ($Confirm.ToUpper() -eq $HostName.ToUpper()) {
                    $ValidAnswer = $True
                }
                Else {
                    Write-Host -ForegroundColor Yellow ("Confirmation failed")
                    MainMenu $MainMenuData
                }
            }
            Else {
                $ValidAnswer = $True
            }
        }
    }

    If ($ValidAnswer) {

        If ($NewHost) {
            If ($cli) {
                $CreateHost = Create-Host -HostName $HostName -FQDN $fqdn -Org $org -Principal $principal -Password $password -cli
            }
            Else {
                $CreateHost = Create-Host -HostName $HostName
                If ($CreateHost) {
                    $JobCreation = $True
                }
            }  
        }
        Else {
            # Existing Host
            Write-Host -ForegroundColor Cyan ("Existing Scheduled tasks for " + $HostName)
            List-Tasks $HostName -OutHost | Out-Null
            $JobCreation = $True      
        }

        # Job Creation
        If ($JobCreation) {
            
            $xmlfile = ($ConfigPath | Get-ChildItem -Filter "*.xml" | Where Name -like ($HostName+".xml")).FullName

            Write-Host ("Creating Task for host " + $HostName)

            # Making Job Hashtable
            $Job = @{}
            $Job.Attribut = @{}
            
            # Getting parameters

            If ($cli) {

                #
                # CLI version
                #

                # Validating mandatory parameters

                # Job Name
                If (Validate-JobName -HostName $HostName -JobName $JobName) {
                    $Job.Attribut.Name = $JobName
                }
                Else {
                    Return $False
                }
                
                # Job Type
                If (!$JobType) {
                    Write-Host -ForegroundColor Red ("Missing JobType")
                    Return $False
                }
                $Job.Attribut.Type = $JobType
                If ($PossibleJobTypes -notcontains $Job.Attribut.Type) {
                    Write-Host -ForegroundColor Red ("JobType " + $Job.Attribut.Type + " is invalid")
                    Return $False
                }

                # Job Enabled
                $Job.Attribut.Enabled = $True

                # Job Description
                $Job.Description = $JobDescription

                # Job Action
                If (!$JobAction) {
                    Write-Host -ForegroundColor Red ("Missing JobAction")
                    Return $False
                }

                $Job.Action = $JobAction
                
                If ($PossibleActions -notcontains $Job.Action) {
                    Write-Host -ForegroundColor Red ("JobAction " + $Job.Action + " is invalid")
                    $PossibleActions | Format-List
                    Return $False
                }

                # Command
                
                If ($Job.Action.ToLower() -eq "Command") {
                    If (!$JobCommand) {
                        Write-Host -ForegroundColor Red ("Missing Command")
                        Return $False
                    }
                    $Job.Command = $JobCommand
                }
                Else {
                    $Job.Command = ""
                }

                # Arguments
                $Job.Arguments = $JobArguments

                # Job Triggers
                $GetTrigger = Validate-Trigger -JobTrigger $JobTrigger -JobDaysInterval $JobDaysInterval -JobWeeksInterval $JobWeeksInterval -JobDaysOfWeek $JobDaysOfWeek -JobWeekDayOfMonth $JobWeekDayOfMonth -JobWeekDayOfMonthPosition $JobWeekDayOfMonthPosition -JobDaysOfMonth $JobDaysOfMonth -cli
                
                If (!$GetTrigger) {
                    Write-Host -ForegroundColor Red ("Invalid Trigger")
                    Return $False
                }
                Else {
                    # Putting results in Job Hash Table
                    $GetTrigger.GetEnumerator() | %{$Job.($_.key) = $_.Value}
                }

                # Job Time
                If (!$JobAt) {
                    Write-Host -ForegroundColor Red ("Missing JobAt")
                    Return $False
                }

                $Job.At = $JobAt

                If (($Job.At -notmatch "([01]?[0-9]|2[0-3]):[0-5][0-9]") -or (($Job.At).Length -gt 5)) {
                    Write-Host -ForegroundColor Red ("At " + $Job.At + " is invalid")
                    Return $False
                }

                $Confirm = $True
                
                # End of CLI version

            }
            Else {

                #
                # Menu version
                #

                $Job.Attribut.Name = Read-Host ("Enter a Job Name")
                While (!(Validate-JobName -HostName $HostName -JobName $Job.Attribut.Name)) {
                    Write-Host -ForegroundColor Red ($Job.Attribut.Name + " already exists, please choose another name")
                    $Job.Attribut.Name = Read-Host ("Enter a Job Name")
                }

                $Job.Attribut.Type = Read-Host ("Enter a Job Type (Task or Remote_Task)")
                $Job.Attribut.Enabled = $True
                $Job.Description = Read-Host ("Enter a Job description")
                
                # Job Actions
                Write-Host $separator
                Write-Host ("Possible actions")
                Write-Host $separator

                $PossibleActions | Write-Host -ForegroundColor Green
                Write-Host $separator
                $Job.Action = Read-Host ("Please type an action")
                While ($PossibleActions -notcontains $Job.Action) {
                    $Job.Action = Read-Host ("Try again")
                }

                If ($Job.Action.ToLower() -eq "Command") {
                    $Job.Command = Read-Host ("Enter a Job Command")
                }
                Else {
                    $Job.Command = ""
                }

                Switch ($Job.Action.ToLower()) {
                    'getfreespace' {
                        $HelpMsg = "-Drive X:"
                        ;break
                    }
                    'start-service' {
                        $HelpMsg = '-ServiceName "Service Name" (wildcard accepted)'
                        ;break
                    }
                    'stop-service' {
                        $HelpMsg = '-ServiceName "Service Name" (wildcard accepted)'
                        ;break
                    }

                }

                $Job.Arguments = Read-Host ('Enter a Job Arguments ('+$HelpMsg+')')
                
                # Job Triggers
                $GetTrigger = Validate-Trigger
                If (!$GetTrigger) {
                    Write-Host -ForegroundColor Red ("Invalid Trigger")
                    Return $False
                }
                Else {
                    # Putting results in Job Hash Table
                    $GetTrigger.GetEnumerator() | %{$Job.($_.key) = $_.Value}
                }

                # Job Time
                $Job.At = ""
                While (($Job.At -notmatch "([01]?[0-9]|2[0-3]):[0-5][0-9]") -or (($Job.At).Length -gt 5)) {
                    $Job.At = Read-Host ('Job time (24h format) (ex: 22:15)')
                }

                # Confirmation

                Write-Host -ForegroundColor Cyan $separator
                Write-Host -ForegroundColor Cyan ("Summary")
                Write-Host -ForegroundColor Cyan $separator

                $Confirm = $False
                $Job.GetEnumerator() | %{
                    If ($_.Value.GetType().Name -eq 'HashTable') {
                        If ($_.Key -eq "Attribut") {
                            $_.Value.GetEnumerator() | %{Write-Host -ForegroundColor Green ("Job." + $_.Key + " = " + $_.Value)}
                        }
                        Else {
                            Write-Host -ForegroundColor Green ("Job."+$_.Key)
                            $nodekey = $_.Key
                            $_.Value.GetEnumerator() | %{
                                        Write-Host -ForegroundColor Green ("Job."+ $nodekey + "." + $_.Key + " = " + $_.Value)
                                    }
                        }
                    }
                    Else {
                        Write-Host -ForegroundColor Green ("Job." + $_.Key + " = " + $_.Value)
                    }
                }
                Write-Host -ForegroundColor Cyan $separator
                $AskConfirm = Read-Host ('Confirm? [Y/N]')
                If ($AskConfirm -like "Y") {$Confirm = $True}
                Else {Write-Host -ForegroundColor Yellow ("Job creation cancel")}

                # End of Menu version
            }

            #
            # Writing into XML conf file
            #

            If ($Confirm) {
                
                # Saving current config
                Save-Config $HostName

                # Appending XML node

                Write-Host -ForegroundColor Cyan $separator
                Write-Host -ForegroundColor Cyan ("Creating " + $Job.Attribut.Name)
                Write-Host -ForegroundColor Cyan $separator

                $xml = New-Object -TypeName XML
                $xml.Load($xmlfile)

                $newnode = $xml.CreateElement('Job')
            
                $Job.GetEnumerator() | %{
                    If ($_.Value.GetType().Name -eq 'HashTable') {
                        If ($_.Key -eq "Attribut") {
                            $_.Value.GetEnumerator() | %{$newnode.SetAttribute($_.Key, $_.Value)}
                        }
                        Else {
                            $childnode = $xml.CreateElement($_.Key)
                            $_.Value.GetEnumerator() | %{
                                    $nodekey = $_.Key.ToString()
                                    $subnode = $xml.CreateElement($nodekey)
                                    $childnode.AppendChild($subnode)
                                    $childnode.$nodekey = $_.Value.ToString() 
                                }
                            $newnode.AppendChild($childnode)
                        }
                    }
                    Else {
                        $nodekey = $_.Key.ToString()
                        $subnode = $xml.CreateElement($nodekey)
                        $newnode.AppendChild($subnode)
                        $newnode.$nodekey = $_.Value.ToString()
                    
                    }  
                
                } | Out-Null

                $xml.Host.AppendChild($newnode)
                $xml.Save($xmlfile)
                
                If ($?) {
                    Write-Host -ForegroundColor Green ("Job successfully created")
                    Return $True
                }
            }
        }
    }

}

Function Modify-Task {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$cli,
        [string]$HostName,
        [String]$JobName,
        [String]$NewJobName,
        [String]$JobType,
        [String]$JobDescription,
        [String]$JobAction,
        [String]$JobCommand,
        [String]$JobArguments,
        [String]$JobAt,
        [String]$JobTrigger,
        [Int]$JobDaysInterval,
        [String]$JobDaysOfWeek,
        [Int]$JobWeeksInterval,
        [String]$JobWeekDayOfMonthPosition,
        [String]$JobWeekDayOfMonth,
        [Int]$JobDaysOfMonth,
        [String]$JobPrincipal,
        [String]$JobPassword,
        [Switch]$Enabled,
        [Switch]$Disable,
        [Switch]$Delete
    )

    $DoChange = $False
    $Job = @{}

    If ($cli) {

        # Command line interface

        If (!$HostName) {
            Write-Host -ForegroundColor Red ("Missing HostName")
            Return $False
        }
        If (!$JobName) {
            Write-Host -ForegroundColor Red ("Missing JobName")
            Return $False
        }

        $hostjobs = List-Tasks -search $HostName
        $JobtoChange = $hostjobs | Where {$_.Name -like $JobName}

        If ($JobtoChange) {
            Write-Host -ForegroundColor Cyan ("Job's current config : ") 
            $JobtoChange | Out-Host
            $DoChange = $True

        }
        Else {
            Write-Host -ForegroundColor Red ("Job not found : " + $JobName)
            Return $False
        }

    }
    Else {

        # Menu Interface
        List-Hosts -OutHost

        $ValidAnswer = $False
       

        $HostName = Read-Host "Please enter a HostName (partly or wildcard accepted)"
        $CheckSyntax = (Check-Syntax $HostName)
        Write-Host -ForegroundColor Cyan ("Please select a task for " + $HostName)
        $hostjobs = List-Tasks $HostName -OutHost

        $JobName = Read-Host ("Enter a Job Name")
        While (Validate-JobName -HostName $HostName -JobName $JobName -Silent) {
            Write-Host -ForegroundColor Red ($JobName + " doesn't exists")
            $JobName = Read-Host ("Enter a Job Name")
        }

        $JobtoChange = $hostjobs | Where {$_.Name -like $JobName}
        
        If ($JobtoChange) {
            Write-Host -ForegroundColor Cyan ("Job's current config : ") 
            
            $JobItemArray = @{}
            $i = 0

            $JobtoChange.Attributes | Sort Name | %{If ($_.Name -ne "#comment") { $JobItemArray.Add($i,@($_.Name,$_.Value)) ;$i++}}
            $JobtoChange.ChildNodes | Sort Name | %{If (($_.Name -NotIn ("#comment","Daily","Weekly","Monthly"))) { $JobItemArray.Add($i,@($_.Name,$_.InnerText)) ;$i++}} 
            $JobItemArray.Add(99,@("Delete Job"))
            $JobItemArray.GetEnumerator() | Sort Name | Format-Table @{Expression = {$_.Name}; Label = "ID" }, @{Expression = {$_.Value[0]}; Label = "Setting"}, @{Expression = {$_.Value[1]}; Label = "Value"} -AutoSize | Out-Host
            

            $IDsToChange = (Read-Host ("Enter the IDs you want to modify separated by comma (ex: 1,3,4)")) -split ","
            While (!($JobItemArray.GetEnumerator() | Where Name -In $IDsToChange)) {
                $IDsToChange = (Read-Host ("Enter the IDs you want to modify separated by comma (ex: 1,3,4)")) -split ","
            }

            $ValidAnswer = $True

        }

        # Getting new value
        If ($ValidAnswer) {
            
            # Delete Job
            If ($IDsToChange -Contains 99) {
                $Delete = $True
                $Confirm = Read-Host ("Confirm deletion ? [Y/N]")
                If ($Confirm -like "Y") {
                    $DoChange = $True
                }
                Else {
                    $DoChange = $False
                }
            }
            Else {
                $JobItemArray.GetEnumerator() | Where Name -In $IDsToChange | Sort Name | %{
                    $Key = $_.Value[0]
                    $CurrentValue = $_.Value[1]
                
                    Switch ($Key.ToLower()) {
                        "enabled" {
                            If ([System.Convert]::ToBoolean($CurrentValue)) {
                                $Confirm = Read-Host ("Disable Job ? [Y/N]")
                                If ($Confirm -like "Y") {
                                    $Job.Enabled = $False.ToString()
                                }
                                Else {Write-Host ("Keeping job enabled")}
                            }
                            Else {
                                $Confirm = Read-Host ("Enable Job ? [Y/N]")
                                If ($Confirm -like "Y") {
                                    $Job.Enabled = $True.ToString()
                                }
                                Else {Write-Host ("Keeping job disabled")}
                            }
                            ;break
                        }

                        "name" {
                            $Job.Name = Read-Host ("Enter a New Job Name ( Current : " + $CurrentValue + ")")
                            While (!(Validate-JobName -HostName $HostName -JobName $Job.Name)) {
                                Write-Host -ForegroundColor Red ($Job.Name + " already exists, please choose another name")
                                $Job.Name = Read-Host ("Enter a New Job Name( Current : " + $CurrentValue + ")")
                            }
                            ;break
                        }

                        "action" {
                            # Job Actions
                            Write-Host $separator
                            Write-Host ("Possible actions")
                            Write-Host $separator

                            $PossibleActions | Write-Host -ForegroundColor Green
                            Write-Host $separator
                            $Job.$Key = Read-Host ("Please type an action" + " (Current : " + $CurrentValue + ")")
                            While ($PossibleActions -notcontains $Job.$Key) {
                                $Job.$Key = Read-Host ("Try again" + " (Current : " + $CurrentValue + ")")
                            }

                            If ($Job.$Key.ToLower() -eq "Command") {
                                $Job.Command = Read-Host ("Enter a Job Command")
                            }
                            Else {
                                $Job.Command = ""
                            }

                            Switch ($Job.$Key.ToLower()) {
                                'getfreespace' {
                                    $HelpMsg = "-Drive X:"
                                    ;break
                                }
                                'start-service' {
                                    $HelpMsg = '-ServiceName "Service Name" (wildcard accepted)'
                                    ;break
                                }
                                'stop-service' {
                                    $HelpMsg = '-ServiceName "Service Name" (wildcard accepted)'
                                    ;break
                                }

                            }

                            $Job.Arguments = Read-Host ('Enter a Job Arguments ('+$HelpMsg+')')

                            ;break
                        }

                        "arguments" {
                        
                            Switch ($Job.$Key.ToLower()) {
                                'getfreespace' {
                                    $HelpMsg = "-Drive X:"
                                    ;break
                                }
                                'start-service' {
                                    $HelpMsg = '-ServiceName "Service Name" (wildcard accepted)'
                                    ;break
                                }
                                'stop-service' {
                                    $HelpMsg = '-ServiceName "Service Name" (wildcard accepted)'
                                    ;break
                                }

                            }

                            $Job.Arguments = Read-Host ('Enter Job Arguments ('+$HelpMsg+') ' + " (Current : " + $CurrentValue + ")")

                            ;break
                        }

                        "trigger" {
                            # Job Triggers
                            Write-Host ("Current Trigger : " + $CurrentValue + "")
                            $GetTrigger = Validate-Trigger
                            If (!$GetTrigger) {
                                Write-Host -ForegroundColor Red ("Invalid Trigger")
                                Return $False
                            }
                            Else {
                                # Putting results in Job Hash Table
                                $GetTrigger.GetEnumerator() | %{$Job.($_.key) = $_.Value}
                            }
                            ;break
                        }

                        "at" {
                                # Job Time
                            $Job.At = ""
                            While (($Job.At -notmatch "([01]?[0-9]|2[0-3]):[0-5][0-9]") -or (($Job.At).Length -gt 5)) {
                                $Job.At = Read-Host ('Job time (24h format) (ex: 22:15)' + " (Current : " + $CurrentValue + ")")
                            }
                            ;break
                        }
                    
                        "delete job" {
                        
                            ;break
                        }

                        default {
                            $Job.$Key = Read-Host ("Enter a New Job " + $Key + " (Current : " + $CurrentValue + ")")
                            ;break
                        }

                    }
            
                }
                # Confirmation
                 $Job.GetEnumerator() | %{
                    If ($_.Value.GetType().Name -eq 'HashTable') {
                        If ($_.Key -eq "Attribut") {
                            $_.Value.GetEnumerator() | %{Write-Host -ForegroundColor Green ("Job." + $_.Key + " = " + $_.Value)}
                        }
                        Else {
                            Write-Host -ForegroundColor Green ("Job."+$_.Key)
                            $nodekey = $_.Key
                            $_.Value.GetEnumerator() | %{
                                        Write-Host -ForegroundColor Green ("Job."+ $nodekey + "." + $_.Key + " = " + $_.Value)
                                    }
                        }
                    }
                    Else {
                        Write-Host -ForegroundColor Green ("Job." + $_.Key + " = " + $_.Value)
                    }
                }
                Write-Host -ForegroundColor Cyan $separator
                $AskConfirm = Read-Host ('Confirm? [Y/N]')
                If ($AskConfirm -like "Y") {$DoChange = $True}
                Else {Write-Host -ForegroundColor Yellow ("Job creation cancel")}
            }
        }

    }

    # Processing changes

    If ($DoChange) {
        # Saving current config
        Save-Config $HostName

        # Merging cli variables
    
        If ($Enable) {
            $Job.Enabled = $True.ToString()
        }
        If ($Disable) {
            $Job.Enabled = $False.ToString()
        }
        If ($NewJobName) {
            $Job.Name = $NewJobName
        }
        If ($JobType) {
            $Job.Type = $JobType
        }
        If ($JobDescription) {
            $Job.Description = $JobDescription
        }
        If ($JobAction) {
            $Job.Action = $JobAction
        }
        If ($JobCommand) {
            $Job.Command = $JobCommand
        }
        If ($JobArguments) {
            $Job.Arguments = $JobArguments
        }
        
        If ($JobTrigger) {

            # Job Triggers
            $GetTrigger = Validate-Trigger -JobTrigger $JobTrigger -JobDaysInterval $JobDaysInterval -JobWeeksInterval $JobWeeksInterval -JobDaysOfWeek $JobDaysOfWeek -JobWeekDayOfMonth $JobWeekDayOfMonth -JobWeekDayOfMonthPosition $JobWeekDayOfMonthPosition -JobDaysOfMonth $JobDaysOfMonth -cli  
            If (!$GetTrigger) {
                Write-Host -ForegroundColor Red ("Invalid Trigger")
                Return $False
            }
            Else {
                # Putting results in Job Hash Table
                $GetTrigger.GetEnumerator() | %{$Job.($_.key) = $_.Value}
            }
        }

        # Job Time
        If ($JobAt) {
            $Job.At = $JobAt
            
            If (($Job.At -notmatch "([01]?[0-9]|2[0-3]):[0-5][0-9]") -or (($Job.At).Length -gt 5)) {
                Write-Host -ForegroundColor Red ("At " + $Job.At + " is invalid")
                Return $False
            }
        }

        If ($JobPrincipal) {
            $Job.Principal = $JobPrincipal
        }
        If ($JobPassword) {
            $Job.Password = $JobPassword  | ConvertFrom-SecureString -Key $key 
        }

        # Getting Task

        $xmlfile = ($ConfigFiles | Where Name -like ($HostName+".xml")).FullName
        $xml = New-Object -TypeName XML
        $xml.Load($xmlfile)

        $item = Select-XML -Xml $xml -XPath ("//Job[@Name='"+$JobName+"']")

        If ($Delete) {
            Write-Host -ForegroundColor DarkYellow ("Deleting job "+ $JobName)
            $null = $item.Node.ParentNode.RemoveChild($item.Node)
        }
        Else {
            $Job.GetEnumerator() | %{
                If ($_.Value.GetType().Name -eq 'HashTable') {
                    If ($_.Key -eq "Attribut") {
                        $_.Value.GetEnumerator() | %{$item.Node.SetAttribute($_.Key, $_.Value)}
                    }
                    Else {
                        $childnode = $item.Node.SelectSingleNode($_.Key)
                        $append = $false
                        If (!$childnode) {
                            $childnode = $xml.CreateElement($_.Key)
                            $append = $true
                        }
                        $_.Value.GetEnumerator() | %{
                                $nodekey = $_.Key.ToString()
                                $subnode = $childnode.SelectSingleNode($nodekey)
                                If (!$subnode) {
                                    $subnode = $xml.CreateElement($nodekey)
                                    $childnode.AppendChild($subnode)
                                }
                                $childnode.$nodekey = $_.Value.ToString()  
                            }
                        If ($append) {
                            $item.Node.AppendChild($childnode)
                        }

                    }
                }
                Else {
                    $nodekey = $_.Key.ToString()
                    $item.node.$nodekey = $_.Value.ToString() 
                }

                
            }
        }

        # Saving changes to xml file
        $xml.Save($xmlfile)
    }
}

Function Modify-Host {
    param (
        [Parameter(Mandatory = $false)]
        [string]$HostName,
        [Parameter(Mandatory = $false)]
        [Switch]$cli,
        # CLI parameters
        [String]$fqdn,
        [String]$org,
        [String]$principal,
        [String]$password
    )

    If (!$cli) {
        List-Hosts -OutHost | Out-Null
        $HostName = Read-Host "HostName"
        While (!(List-Hosts $HostName -Strict)) {
            $HostName = Read-Host "Try Again : HostName"
        }
    }
    
    $ValidAnswer = $False

    $CheckSyntax = (Check-Syntax $HostName)
    
    If ($CheckSyntax.Valid) {
        $HostName = $HostName.ToUpper()
        If (List-Hosts $HostName) {
            Write-Host $separator
            Write-Host -ForegroundColor Cyan ("Editing " + $HostName + "")
            $HostInfo = List-Hosts $HostName -OutHost -Strict

            Write-Host -ForegroundColor Cyan ("Host's current config : ") 
            
            If (!$cli) {
                $HostItemArray = @{}
                $i = 0

                $HostInfo.Attributes | Sort Name | %{If ($_.Name -ne "#comment") { $HostItemArray.Add($i,@($_.Name,$_.Value)) ;$i++}}
                $HostInfo.ChildNodes | Sort Name | %{If (($_.Name -NotIn ("#comment","Daily","Weekly","Monthly"))) { $HostItemArray.Add($i,@($_.Name,$_.InnerText)) ;$i++}} 
                $HostItemArray.Add(99,@("Delete Host"))
                $HostItemArray.GetEnumerator() | Sort Name | Format-Table @{Expression = {$_.Name}; Label = "ID" }, @{Expression = {$_.Value[0]}; Label = "Setting"}, @{Expression = {$_.Value[1]}; Label = "Value"} -AutoSize | Out-Host
            

                $IDsToChange = (Read-Host ("Enter the IDs you want to modify separated by comma (ex: 1,3,4)")) -split ","
                While (!($HostItemArray.GetEnumerator() | Where Name -In $IDsToChange)) {
                    $IDsToChange = (Read-Host ("Enter the IDs you want to modify separated by comma (ex: 1,3,4)")) -split ","
                }

                $ValidAnswer = $True

                If ($ValidAnswer) {
                    

                }
            }
        }
    }
}

Function Get-Configs {
    ForEach ($file In $ConfigFiles) {
        $file
    }
}

Function MainMenu {
    param(
        [Parameter(Mandatory = $true,Position=0)]
        [hashtable]$Data
    )

    Write-Host ($separator)
    Write-Host -ForegroundColor Cyan ("Main Menu")

    $a = @{Expression={$_.Name};Label="Id"},
    @{Expression={$_.Value};Label="Possible Actions"}

    $Data.GetEnumerator() | Sort-Object -Property Name | Format-Table -AutoSize $a | Out-Host

    # Reading choice

    $Answer = Read-Host "Enter your choice (partly or wildcard accepted)"

    $ValidAnswer = Validate-Answer -Answer $Answer -Data $Data -a $a

    If ($ValidAnswer.Valid) {
        #Clear
        Write-Host $separator
        Write-Host -ForegroundColor Cyan $Data[$ValidAnswer.Id]
        Write-Host $separator

        Switch ($ValidAnswer.Id) {
            1 {
                List-Hosts -OutHost
                $SearchHost = Read-Host "Please enter a HostName (partly or wildcard accepted)"
                Write-Host -ForegroundColor Cyan ("Showing tasks for " + $SearchHost)
                List-Tasks $SearchHost -OutHost
                ;break
            }
            2 {
                Create-Task
                ;break
            }
            3 {
                Modify-Task
                ;break
            }
            4 {
                Modify-Host
                ;break
            }
            5 {
                Write-Host "Not yet implemented"
                ;break
            }
            6 {
                Write-Host "Not yet implemented"
                ;break
            }
            99 {
                Write-Host "Bye"
                ;break
            }
        }
    }
    Else {
        Return ("Hum... what do you mean ? : "+ $Answer)
    }

    Return,$ValidAnswer
}

Clear

$ScriptPath = Split-Path $MyInvocation.MyCommand.Path
$script:separator = "-"*40
$script:ConfigPath = $ScriptPath + "\Configs"
$script:ConfigFiles = $ConfigPath | Get-ChildItem -Filter "*.xml"
$script:SchedulerScriptsPath = $ScriptPath + "\Scripts"
$script:KeyPath = $ScriptPath + "\Secure\AES.key"
$script:BackupPath = $ScriptPath + "\Backup"
$script:DeletedPath = $ScriptPath + "\Deleted"

$script:key = Get-Content $KeyPath

$script:DefaultPrincipal = "DOMAIN\USER"
$script:DefaultPassword = "SecureString"

$script:ClienName = $env:CLIENTNAME
$script:CurrentUser = $env:USERNAME
# Job variables
$script:PossibleActions = @()
    ForEach ($ScriptFile In ($SchedulerScriptsPath | Get-ChildItem -Filter "*.ps1")) {
        $script:PossibleActions += (($ScriptFile.Name.Split("."))[0])
    }
$script:PossibleActions += "Command"
$script:PossibleTriggers = @("Daily","Weekly","Monthly")
$script:PossibleJobTypes = @("Task","Remote_Tasks")


$version = "v0.1"
$admin = "admin@company"

Write-Host ($separator)
Write-Host -ForegroundColor Cyan ("Hi!")
Write-Host -ForegroundColor Cyan ("Welcome to Scheduler " + $version)
Write-Host ($separator)
Write-Host -ForegroundColor Gray ("Questions? : " + $admin)

$MainMenuData = @{}
$MainMenuData.Add(1,"List Scheduled Task")
$MainMenuData.Add(2,"Create a new Scheduled Task")
$MainMenuData.Add(3,"Modify/Delete an existing Scheduled Task")
$MainMenuData.Add(4,"Modify Host settings")
$MainMenuData.Add(5,"Disable all jobs for a Host")
$MainMenuData.Add(6,"Launch Scheduler")
$MainMenuData.Add(99,"Exit")

# Main Menu
$Main = MainMenu $MainMenuData

$KeepGoing = $False

