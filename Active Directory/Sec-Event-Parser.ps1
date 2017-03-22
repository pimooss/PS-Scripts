# Security Audit Events Parser Script
#
# Auth : Joris DECOMBE
# Date : 15/06/2015
#

#############
# EVENT IDs #
#############
#
# Logons
#
#4624 : successfull logon
#4625 : failed logo
#
# Credential Validation
#
#4774 : An account was mapped for logon.
#4775 : An account could not be mapped for logon.
#4776 : The domain controller attempted to validate the credentials for an account.
#4777 : The domain controller failed to validate the credentials for an account.
# 
# Computer account
#
#4741 : Computer account created
#4743 : Computer account deleted
#
# Security Groups
#
#4727 : A security-enabled global group was created
#4728 : A member was added to a security-enabled global group.
#4729 : A member was removed from a security-enabled global group.
#4730 : A security-enabled global group was deleted.
#4731 : A security-enabled local group was created.
#4732 : A member was added to a security-enabled local group.
#4733 : A member was removed from a security-enabled local group.
#4734 : A security-enabled local group was deleted.
#4735 : A security-enabled local group was changed.
#4737 : A security-enabled global group was changed.
#4754 : A security-enabled universal group was created.
#4755 : A security-enabled universal group was changed.
#4556 : A member was added to a security-enabled universal group.
#4757 : A member was removed from a security-enabled universal group.
#4758 : A security-enabled universal group was deleted.
#4764 : A group's type was changed.
# 
# User Accounts
#
#4720 : A user account was created.
#4722 : A user account was enabled.
#4723 : An attempt was made to change an account's password.
#4724 : An attempt was made to reset an account's password.
#4725 : A user account was disabled.
#4726 : A user account was deleted.
#4781 : The name of an account was changed
#
#  User Accounts Lockouts
#
#4740 : A user account was locked out
#4767 : A user account was unlocked.
#

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("LastTenMinutes","LastHour","Hourly","Daily","Weekly","Monthly","OnDemand","LastWeek","LastMonth","Yesterday")]
    [String]
    $Type = "OnDemand",
    [int]$Days
)

#
# Timespan
#

$Now = Get-Date

If (!$Days) {
    Switch ($Type) {
        "LastTenMinutes" {$Days = 0
            $Auditfrom = $Now.AddMinutes(-10)
            ;break}
        "Hourly" {$Days = 0
            $Auditfrom = $Now.AddHours(-1)
            ;break}
        "LastHour" {$Days = 0
            $Now = Get-Date -Hour (Get-Date).Hour -Minute 00 -Second 00
            $Auditfrom = $Now.AddHours(-1)
            ;break}
        "OnDemand" {$Days = 1 ;break}
        "Daily" {$Days = 1 ;break}
        "Yesterday"{
            $YesterdayM = (Get-Date 00:00:00).AddDays(-1)
            $Now = $YesterdayM.AddDays(+1)
            $Days = 1 
            ;break}
        "Weekly" {$Days = 7 ;break}
        "LastWeek" { 
            1..7|%{If (((Get-Date).AddDays(-$_)).DayOfWeek -eq "Sunday") {$LastDayOfWeek = (Get-Date 00:00:00).AddDays(-$_)}}
            $FirstDayOfWeek = $LastDayOfWeek.AddDays(-7)
            $Days = 7
            $Now = $LastDayOfWeek
            ;break}
        "Monthly" {
            $FirstDayOfMonth = Get-Date( "01"+"/"+(Get-Date).Month+"/"+(Get-Date).Year)
            [int]$LastDayOfMonth = Get-Date(($FirstDayOfMonth).AddMonths(1).AddSeconds(-1)) -format dd
            $Days = $LastDayOfMonth
            ;break}
        "LastMonth" {
            $FirstDayOfMonth = Get-Date( "01"+"/"+(Get-Date).AddMonths(-1).Month+"/"+(Get-Date).AddMonths(-1).Year)
            [int]$LastDayOfMonth = Get-Date(($FirstDayOfMonth).AddMonths(1).AddSeconds(-1)) -format dd
            $Days = $LastDayOfMonth 
            $Now = Get-Date(($FirstDayOfMonth).AddMonths(1))
            ;break}
    }
}
Else {
    $Type = "OnDemand"
}

If ($Days -gt 0) {
    $Auditfrom = $Now.AddDays(-$Days)
}
Write-Host $Auditfrom " > " $Now


#Script Path
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$Output_file_path = $dir + "\SecurityAudit_" + $Type
If(-Not (Test-Path $Output_file_path)) {New-Item -Path $Output_file_path -ItemType directory | Out-Null}

# HTML Output format
$style = "<style>"
$style = $style + "BODY{background-color:#FFFFFF;}"
$style = $style + "TABLE{ border-width: 1px;border-style: solid;border-color: #91B9D1;border-collapse: separate; font-size: 10pt; font-color: #000000; font-family: Calibri; background-color:#FFFFFF; min-width: 80px;}"
$style = $style + "TH{background-color:#384F60;color: #FFFFFF;border-width: 1px;border-style: solid;border-color: #91B9D1;  text-align: center; padding-top: 2px;padding-bottom: 2px;padding-left: 2px;padding-right: 2px;min-width: 80px;}"
$style = $style + "TD{background-color:#E0F0FF;border-width: 1px;border-style: solid;border-color: #91B9D1; text-align: center;min-width: 80px;}"
$style = $style + "</style>"

$ItemStyleBegin = "<p style='font-size: 10pt; color: #978C30; font-family: Arial;'><strong><i><u>"
$ItemStyleEnd = "</u></i></strong></p>"

# create columns for HTML table 
$col1 = new-object system.data.datacolumn TimeCreated, ([DateTime]) 
$col2 = new-object system.data.datacolumn Id, ([int])
$col3 = new-object system.data.datacolumn Action, ([string])
$col4 = new-object system.data.datacolumn Message, ([string]) 
$col5 = new-object system.data.datacolumn Server, ([string])

######
# Go #
######

# Dynamicly getting Domain Controllers
Import-Module ActiveDirectory
$Dcs = @()
Get-ADComputer -SearchBase 'OU=Domain Controllers,DC=domain,DC=local' -Filter '*' | Select-Object Name | %{$Dcs += $_.Name}
#$Dcs = "AD01", "AD02", "AD03"

#
#Event Groups to find
#
$ToFind = @{
    "Users" = @(4720,4722,4723,4724,4725,4726,4781);
    "Computers" = @(4741,4743);
    "Groups" = @(4727,4728,4729,4730,4731,4732,4733,4734,4735,4737,4754,4755,4756,4757,4758,4764);
    #"Logons" = @(4624);  #Too long to parse, i'll put it in another script
    #"CredVal" = @(4776,4774);
    "Lockouts" = @(4740,4767)
}



ForEach ($EventGroup In $ToFind.GetEnumerator()) {
    
    # create table for html report 
    $rpttb = new-object system.data.datatable ($EventGroup.Key + " Security Audit Report (" + $Auditfrom + " > " + $Now + ")")

    # add columns 
    $rpttb.columns.add($col1) 
    $rpttb.columns.add($col2) 
    $rpttb.columns.add($col3) 
    $rpttb.columns.add($col4)
    $rpttb.columns.add($col5)

    #
    # HTML Output file
    #
    $Output_file_name = $EventGroup.Key+"_"+(Get-Date -Format yyyyMMdd_HHmmss) + ".html"
    $Output_file = $Output_file_path + "\" + $Output_file_name
    
    #
    # XML Output file
    #
    $xml_output_file = $Output_file_path+"\"+$EventGroup.Key+"_"+(Get-Date -Format yyyyMMdd_HHmmss)+".xml"
    $XmlWriter = New-Object System.XMl.XmlTextWriter($xml_output_file,$Null)
    $xmlWriter.Formatting = 'Indented'
    $xmlWriter.Indentation = 1
    $XmlWriter.IndentChar = "`t"
    $xmlWriter.WriteStartDocument()
    $XmlWriter.WriteComment(("Security Audit report for "+ $EventGroup.Key + " ("+ $Auditfrom + " > " + $Now +")"))
    $xmlWriter.WriteStartElement('Events')
    $XmlWriter.WriteAttributeString('type', $EventGroup.Key)
    $XmlWriter.WriteAttributeString('timespan_from', $Auditfrom)
    $XmlWriter.WriteAttributeString('timespan_to', $Now)
    $XmlWriter.WriteAttributeString('author', 'Joris DECOMBE')

    #Check if log file exists (it shouldn't) and delete if it does

    If((Test-Path -Path $Output_file)){
        Remove-Item -Path $Output_file -Force
    }
   
    #Create file and start logging
    New-Item -Path $Output_file_path -Name $Output_file_name -ItemType File | Out-Null

    $result = $Output_file
    add-content $result "<br/>" 
    add-content $result "<div id='evtlgrpt'>" 
    add-content $result $ItemStyleBegin 
    add-content $result ($EventGroup.Key +" Security Audit (" + $Auditfrom + " > " + $Now + ")")
    add-content $result $ItemStyleEnd 

    
    ForEach ($Server In $Dcs) {
        Write-Host $EventGroup.Key $Server "[Event IDs :" $EventGroup.Value "]"
        Get-winevent -ComputerName $Server -FilterHashtable @{logname="Security"; id=$EventGroup.Value; StartTime=$auditfrom; EndTime=$now} -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, Message | %{
                     
            $msg_split = $_.Message.split("`n")
            $message_action = $msg_split[0].Replace(".","")
            $message_subject = ((($msg_split[5].split("`t"))[3]).Trim() + "\" + ($msg_split[4].split("`t")[3]).Trim())
            $message_member= ""

            # Formating message
            switch ($_.Id) {
                {@(4740,4767) -contains $_} {
                    $message_target = (($msg_split[11].split("`t")[3]).Trim() + "\" + ($msg_split[10].split("`t")[3]).Trim())
                    $message_subject = ($msg_split[10].split("`t")[3]).Trim()
                    $message = "Subject : " + $message_subject + "`r`n" + "Target : " + $message_target
                    ;break
                    }
                {@(4728,4729,4732,4733,4756,4757) -contains $_} {
                    $message_target = (($msg_split[15].split("`t")[3]).Trim() + "\" + ($msg_split[14].split("`t")[3]).Trim())
                    $message_member = ($msg_split[10].split("`t")[3]).Trim()
                    $message = "Subject : " + $message_subject + "`r`n" + "Group : " + $message_target + "`r`n" + "Member : " + $message_member
                    ;break
                }
                {@(4735,4737,4755,4727,4730,4731,4734,4754) -contains $_} {
                    $message_target = (($msg_split[11].split("`t")[3]).Trim() + "\" + ($msg_split[10].split("`t")[3]).Trim())
                    $message = "Subject : " + $message_subject + "`r`n" + "Target : " + $message_target
                    ;break
                }
                {@(4741,4743) -contains $_} {
                    $message_target = (($msg_split[11].split("`t")[3]).Trim() + "\" + ($msg_split[10].split("`t")[3]).Trim())
                    $message = "Subject : " + $message_subject + "`r`n" + "Target : " + $message_target
                    ;break
                }
                {@(4720,4722,4723,4724,4725,4726) -contains $_} {
                    $message_target = (($msg_split[11].split("`t")[3]).Trim() + "\" + ($msg_split[10].split("`t")[3]).Trim())
                    $message = "Subject : " + $message_subject + "`r`n" + "Target : " + $message_target
                    ;break
                }
                {@(4781) -contains $_} {
                    $message_target = (($msg_split[10].split("`t")[3]).Trim() + "\" + ($msg_split[11].split("`t")[3]).Trim() + " -> " + ($msg_split[12].split("`t")[3]).Trim())
                    $message = "Subject : " + $message_subject + "`r`n" + "Target : " + $message_target
                    ;break
                }
                {@(4624,4625) -contains $_} {
                    $message_subject = ((($msg_split[5].split("`t"))[3]).Trim() + "\" + ($msg_split[4].split("`t")[3]).Trim())
                    $message_target = (($msg_split[15].split("`t")[3]).Trim() + "\" + ($msg_split[14].split("`t")[3]).Trim())
                    $message_network_wks = ($msg_split[24].split("`t")[2]).Trim()
                    $message_network_ip = ($msg_split[25].split("`t")[2]).Trim()
                    $message = "Subject : " + $message_subject + "`r`n" + "Account : " + $message_target + "`r`n" + "Workstation : " + $message_network_wks + "`r`n" + "IP : " + $message_network_ip
                    ;break
                }
                {@(4774,4776) -contains $_} {
                    $message_subject = ($msg_split[3].split("`t")[3]).Trim()
                    $message_network_wks = ($msg_split[4].split("`t")[3]).Trim()
                    $message = "Logon Account : " + $message_subject + "`r`n" + "Source Wks : " + $message_network_wks
                    ;break
                }
                default {
                $message = $msg_split[2..$msg_split.Length] -join "`r`n"
                ;break}
            }
  
            # HTML Output
            $row = $rpttb.newrow() 
            $row.TimeCreated = $_.TimeCreated
            $row.Id = $_.Id
            $row.Action = $message_action
            $row.Message = $message
            $row.Server = $Server
            $rpttb.rows.add($row)

            # XML Output
            $guid = [System.GUID]::NewGuid().ToString()
            $xmlWriter.WriteStartElement('Event')
            $XmlWriter.WriteAttributeString('GUID', $guid)
            $xmlWriter.WriteElementString('TimeCreated',$_.TimeCreated)
            $xmlWriter.WriteElementString('Id',$_.Id)
            $xmlWriter.WriteElementString('Action',$message_action)
            $xmlWriter.WriteElementString('Subject',$message_subject)
            $xmlWriter.WriteElementString('Target',$message_target)
            $xmlWriter.WriteElementString('Member',$message_member)
            $xmlWriter.WriteElementString('Workstation', $message_network_wks)
            $xmlWriter.WriteElementString('IP', $message_network_ip)
            $xmlWriter.WriteElementString('Server',$Server)
            $xmlWriter.WriteEndElement()
        }
    }
    # HTML Output and close
    ($rpttb |sort-object TimeCreated -Descending |convertto-html -head $style TimeCreated,Id,Action,Message,Server) -replace '(?m)\s+$', "`r`n<BR>" |
    add-content $result   
    add-content $result "</div>"
    $rpttb.columns.Clear()
    $rpttb.rows.Clear()
    $rpttb.Clear()

    # Closing XML
    $xmlWriter.WriteEndElement()
    $xmlWriter.WriteEndDocument()
    $xmlWriter.Flush()
    $xmlWriter.Close()

}
