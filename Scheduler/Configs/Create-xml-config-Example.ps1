

param (
    [Parameter(Mandatory=$false)]
    [String]
    $Server = "ServerName",
    [String]$fqdn = "ServerFQDN"
)

#Script Path
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$Output_file_path = $dir + "\"
If(-Not (Test-Path $Output_file_path)) {New-Item -Path $Output_file_path -ItemType directory | Out-Null}
If(-Not (Test-Path $Output_file_path+"\"+$Server+".xml")) {
    $xml_output_file = $Output_file_path+"\"+$Server+".xml"
    $XmlWriter = New-Object System.XMl.XmlTextWriter($xml_output_file,$Null)
    $xmlWriter.Formatting = 'Indented'
    $xmlWriter.Indentation = 1
    $XmlWriter.IndentChar = "`t"
    $xmlWriter.WriteStartDocument()
    $XmlWriter.WriteComment(("Schedule tasks for "+$Server))
    $xmlWriter.WriteStartElement('Host')
    $XmlWriter.WriteAttributeString('Name', $Server)
    $XmlWriter.WriteAttributeString('fqdn', $fqdn)
    $XmlWriter.WriteAttributeString('Org', "Company")
    $XmlWriter.WriteAttributeString('Enabled', "True")
    #Authentification
    $XmlWriter.WriteComment(("Host Principal (user account to logon and to make the task run"))
    $XmlWriter.WriteElementString('Principal', "DOMAIN\USER")
    $XmlWriter.WriteElementString('SecString', "secure string")

    #Exemple
    $XmlWriter.WriteComment(("Job Name will be the name of the scheduled task, Type can be Task or Job"))
    $xmlWriter.WriteStartElement('Job')
    $XmlWriter.WriteAttributeString('Name', "Monthly reboot")
    
    $XmlWriter.WriteAttributeString('Enabled', "False")
    $XmlWriter.WriteAttributeString('Type', "Task")
    $XmlWriter.WriteElementString('Description', "JN Scheduled Reboot task")

    $XmlWriter.WriteComment(("Task Principal (user account to logon and to make the task run"))

    $XmlWriter.WriteElementString('Principal', "")
    $XmlWriter.WriteElementString('SecString', "")
    $XmlWriter.WriteComment(("Command : To use only if Job Type = Command"))
    $XmlWriter.WriteElementString('Command', "")
    $XmlWriter.WriteComment(("Action : To use only if Job Type = Job or Task"))
    $XmlWriter.WriteElementString('Action', "Reboot")
    $XmlWriter.WriteComment(("Arguments : will be arguments of an action or a command"))
    $XmlWriter.WriteElementString('Arguments', "")
    
    $XmlWriter.WriteComment(("Trigger can be ( Daily | Weekly | Monthly)"))
    $xmlWriter.WriteElementString('Trigger',"Monthly")

    $xmlWriter.WriteStartElement('Daily')
    $XmlWriter.WriteComment(("DaysInterval (1-365)"))
    $xmlWriter.WriteElementString('DaysInterval',"")
    $xmlWriter.WriteEndElement()

    $xmlWriter.WriteStartElement('Weekly')
    
    $XmlWriter.WriteComment(("WeeksInterval (1-52)"))

    $xmlWriter.WriteElementString('WeeksInterval',"")   
    $XmlWriter.WriteComment(("DaysofWeek (Monday | Tuesday | Wednesday | Thursday | Friday | Saturday | Sunday)"))
    $xmlWriter.WriteElementString('DaysofWeek',"Friday")

    $xmlWriter.WriteEndElement()

    $xmlWriter.WriteStartElement('Monthly')

    $XmlWriter.WriteComment(("DaysofMonth (1-31 but 1-28 is recommended)"))
    $xmlWriter.WriteElementString('DaysofMonth',"")
    
    $XmlWriter.WriteComment(("WeekDayOfMonthPosition (First | Second | Third | Fourth | Last)"))
    $xmlWriter.WriteElementString('WeekDayOfMonthPosition',"Second")
    
    $XmlWriter.WriteComment(("WeekDayOfMonth (Monday | Tuesday | Wednesday | Thursday | Friday | Saturday | Sunday)"))
    $xmlWriter.WriteElementString('WeekDayOfMonth',"Wednesday")

    $xmlWriter.WriteEndElement()
    
    $XmlWriter.WriteComment(("At Time of the Job (3am, or 03:00)"))
    $xmlWriter.WriteElementString('At',"22:13")

    $xmlWriter.WriteEndElement()
    
    $xmlWriter.WriteEndDocument()
    $xmlWriter.Flush()
    $xmlWriter.Close()
}
Else {
    Write-Host $Output_file_path"\"$Server".xml" "already exists"
}