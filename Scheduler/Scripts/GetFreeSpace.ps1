#
# GetFreeSpace.ps1
# 
# What it tries to do : 
#                1/ Polls for free space on a specific drive ($Drive or cli param [-Drive x:], WMI query)
#                2/ Export it to a data file (simple xml)
#                3/ Get a trend of space consumption 
#                4/ Estimates a full disk date if free space is descreasing
#                5/ Make a graph of space usage stats
#                6/ Alert by Email if estimated full disk date is close (defined by $Alert) or if threshold is reached
#
# Comments : It will better results if it runs every day at the same time
#            Polling interval should be no less than 24h
#
# Date : 10/08/2015
# Version : 1.0
# Auth : Joris DECOMBE
#

param (
    [Parameter(Mandatory=$false)]
    [ValidateScript({ Test-Path $_ })]
    [string]$Drive = "C:",

    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "LocalHost",

    [Parameter(Mandatory=$false)]
    # Alert n Days before disk is full
    [int]$Alert = 10,

    [Parameter(Mandatory=$false)]
    # Keep n Days of data history
    [int]$dtk = 30,

    [Parameter(Mandatory=$false)]
    # Do chart ?
    [bool]$DoChart = $True

)

# Alert threshold : Will send an alert if free space is less than n%
$AlertThreshold = 8 #% of free space remaining on disk

# Define hostname
If ($ComputerName.ToLower() -eq "localhost") {$hostname = $Env:Computername}
Else {$hostname = $ComputerName}

# Email parameters
$PSEmailServer = "shiva.as30781.net"
$Email_From = "sh-ecm@jaguar-network.com"
$Email_To = "sh-ecm@jaguar-network.com"
#$Email_To = "joris.decombe@jaguar-network.com"
$Email_Subject = "Free disk space warning : " + $hostname + " (" + $Drive +")"

$head = "<style>"
$head += "BODY{background-color:#FFFFFF;}"
$head += ' div.freespace {color:black;font-family: Calibri, sans-serif;font-size:0.75em;}"'
$head += "</style>"
$ItemStyleBegin = "<p style='font-size: 10pt; color: #978C30; font-family: Calibri;'><strong><i><u>"
$ItemStyleEnd = "</u></i></strong></p>"
$body = "<div class='freespace'>" 

# Path
$dir = Split-Path $MyInvocation.MyCommand.Path
$OutputPath = $dir + "\GetFreeSpaceData"

If (!(Test-Path $OutputPath)) {
    New-Item $OutputPath -ItemType Directory | Out-Null
}

# Rotate Charts
$MaxCharts = 30
$GetCharts = @(Get-ChildItem -Path $OutputPath\* | Where{$_.Name -like "disk_usage_" + $hostname + "*.png"} | Sort -Property LastWriteTime) 
$NbrCharts = $GetCharts.count

$i = 0 
While ($NbrCharts -ge $MaxCharts) { 
    $GetCharts[$i] | Remove-Item -Force -Recurse -Confirm:$false 
    $NbrCharts -= 1
    $i++ 
} 

# XML file name
$xmlfile = $OutputPath+"\GetFreeSpace_"+$hostname+"_"+($Drive -replace ":","")+".xml"

# Chart file
$ChartFile = $OutputPath + "\disk_usage_" + $hostname + "_" + (Get-Date -Format "ddMMyyyy_hhmmss") +".png"

# Get disk info (WMI)
$disk = Get-WmiObject Win32_LogicalDisk -ComputerName $ComputerName -Filter "DeviceID='$Drive'" | Select-Object Size,FreeSpace

If (!$?) {
    Write-Host -ForegroundColor Red ("Error while retrieving WMI disk info on " + $hostname + " (" + $Drive + ") : ")
    Write-Host -ForegroundColor Red ($error[0])
    Return
}

# Test XML file if exists, delete it if wrong syntax
If (Test-Path $xmlfile){
    # Check for Load or Parse errors when loading the XML file
    $xml = New-Object System.Xml.XmlDocument
    Try {
        $xml.Load((Get-ChildItem -Path $xmlfile).FullName)
        $ValidXml = $True
    }
    Catch [System.Xml.XmlException] {
        Write-Host "$xmlfile : $($_.toString())"
        $ValidXml = $False
    }
    If (!$ValidXml) {
        Move-Item $xmlfile ($xmlfile+".bad") -Force -Confirm:$false | Out-Null
    }
}


#
# XML file management
#

# Create XML if doesn't exists (first launch)
If(!(Test-Path $xmlfile)) {
    Write-Host -ForegroundColor Green ("First launch for " + $hostname + " - Drive : " + $Drive)
    
    $XmlWriter = New-Object System.XMl.XmlTextWriter($xmlfile,$Null)
    $XmlWriter.Formatting = 'Indented'
    $XmlWriter.Indentation = 1
    $XmlWriter.IndentChar = "`t"
    $XmlWriter.WriteStartDocument()
    $XmlWriter.WriteComment(("Free space on "+$Drive+" for host "+$hostname))

    $XmlWriter.WriteStartElement('Info')
    $XmlWriter.WriteAttributeString('hostname', $hostname )
    $XmlWriter.WriteAttributeString('drive', $Drive)
    $XmlWriter.WriteAttributeString('creationtime', (Get-Date))
    

    $XmlWriter.WriteStartElement('Data')
    
    $XmlWriter.WriteStartElement('Poll')
    $XmlWriter.WriteElementString('DateTime',(Get-Date).ToString())
    $XmlWriter.WriteElementString('Size',$disk.Size.ToString())
    $XmlWriter.WriteElementString('FreeSpace',$disk.FreeSpace.ToString())
    $XmlWriter.WriteEndElement()
    
    $XmlWriter.WriteEndElement()
    $XmlWriter.WriteEndElement()
    $XmlWriter.WriteEndDocument()
    $XmlWriter.Flush()
    $XmlWriter.Close()
}
# Else load it, add new data, and purge oldest entries
Else {
    # Clone an existing node and append childnode with fresh data

    $xml = New-Object -TypeName XML
    $xml.Load($xmlfile)

    $item = Select-XML -Xml $xml -XPath '//Poll[1]'
    $newnode = $item.Node.CloneNode($true)
    $newnode.DateTime = (Get-Date).ToString()
    $newnode.Size = $disk.Size.ToString()
    $newnode.FreeSpace = $disk.FreeSpace.ToString()

    $Data = Select-XML -Xml $xml -XPath '//Data'
    $Data.Node.AppendChild($newnode) | Out-Null

    # Purge oldest entries
    $PurgeOlderThan = 365 #Days
    $ToPurge = $xml.Info.Data.Poll | Sort-Object {If ($_.DateTime -like "*PM*" -or "*AM*") {[System.DateTime]::ParseExact($_.DateTime, "G", $null)} Else {[System.DateTime]::ParseExact($_.DateTime, "dd/MM/yyyy HH:mm:ss", $null)}} | ?{ (Get-Date $_.DateTime) -lt ((Get-Date).AddDays(-$PurgeOlderThan)) }

    If ($ToPurge.Count -gt 0) {
        Write-Host ("Purge of oldest entries (more than "+ $PurgeOlderThan + " Days) : Deleting " + $ToPurge.Count + " entries")
        ForEach ($e In $ToPurge) {
            $item = Select-XML -Xml $xml -XPath ('//Poll[DateTime="'+$e.DateTime+'"]')
            $null = $item.Node.ParentNode.RemoveChild($item.node)
        }
    }

    $xml.Save($xmlfile)
}

# ReLoad updated xml data
$xml = New-Object -TypeName XML
$xml.Load($xmlfile)

# Getting sorted data from XML
$History = $xml.Info.Data.Poll | Sort-Object { If ($_.DateTime -like "*PM*" -or "*AM*") {[System.DateTime]::ParseExact($_.DateTime, "G", $null)} Else {[System.DateTime]::ParseExact($_.DateTime, "dd/MM/yyyy HH:mm:ss", $null)} }

# Exit if data history < 3 polls
If ($History.Count -lt 3) {Return ("Not enough data to calculate a trend")}

# Last free space and disk size data
[long]$lds = ($History)[-1].Size
[long]$lfp = ($History)[-1].FreeSpace
# Last date
$lfd = (Get-Date ($History)[-1].DateTime)
# First filtered date
$ffd = (Get-Date ($History | ?{ (Get-Date $_.DateTime) -ge ($lfd.AddDays(-$dtk)) })[0].DateTime)

# Sorting data and getting diffs
$date = @{}
$freespace = @{}
$calcunits = @()
$ChartDS = @()

$i = 0
$j = 1

ForEach ($d In ($History | ?{ (Get-Date $_.DateTime) -ge ($lfd.AddDays(-$dtk)) }) ) {
    $date.Add($i,(Get-Date $d.DateTime))
    $freespace.Add($i,[long]$d.FreeSpace)
    If ($i -gt 0) {
        $LastIndex = $i-$j
        $timespan = New-TimeSpan ($date[$i]) ($date[$LastIndex])
        If ($timespan.TotalHours -lt -1) {
            $j = 1
            # Get diff between two polls
            [long]$diff = ($freespace[$i] - $freespace[$LastIndex])
            # Size consumed per hour between 2 polls
            $calcunits += [long]($diff / $timespan.TotalHours)
            Write-Host -ForegroundColor Gray $date[$LastIndex] " -> " $date[$i] " : " ([Math]::Round($diff/1MB,2)) "Mo - New free Space :" ([Math]::Round($freespace[$i]/1MB,2)) "Mo"

            $ChartDS += $d
        }
        Else {
            Write-Host -ForegroundColor DarkGray $date[$i] " : Ignoring data : not enough time between polls"
            $j++
        }
    }
    $i++
}

# Exit if calcunits is empty (it would mean that the oldest data is less than 1 hour old)
If ($calcunits.Count -eq 0) {Return "Data is too fresh ! 1 delta hour minimum"}

If ($calcunits.Count -lt 3) {Return "Not enough data to calculate a trend (3 valid poll requiered)"}

# Getting Trend (bytes/hour)

[long]$total_avg = 0
[long]$last3 = 0
[long]$next3 = 0
[long]$last6 = 0

ForEach ($k In $calcunits) {
    # Last 3
    If (($calcunits.Count - $i) -le 3) {
        $last3 += [Long]($k)
    }
    # next 3
    If ((($calcunits.Count - $i) -le 6) -and (($calcunits.Count - $i) -gt 3) ) {
        $next3 += [Long]($k)
    }
    # Last 6
    If (($calcunits.Count - $i) -le 6) {
        $last6 += [Long]($k)
    }

    #Write-Host ("Mo/h " + [Math]::Round(($k/1MB),2) + " Mo")
    #Write-Host $total_avg "+" ([Math]::Truncate($k))
    $total_avg += [Long]($k)
}

$MaxSpaceConsoph =  $calcunits | Measure-Object -Maximum -Minimum -Sum | %{$_.Maximum}
$MinFreeSpace = ( $History | ?{ (Get-Date $_.DateTime) -ge ($lfd.AddDays(-$dtk)) } ).FreeSpace | Measure-Object -Maximum -Minimum -Sum | %{$_.Minimum}

$Results = @{}
$Results.Add('Total Average',[Math]::Round($total_avg / $calcunits.Count,0) )
$Results.Add('Last 3',[Math]::Round($last3 /3,0))
$Results.Add('Next 3',[Math]::Round($next3 /3,0))
$Results.Add('Last 6',[Math]::Round($last6 /6,0))

$SendMail = $False
$body += $ItemStyleBegin 
$body += $Email_Subject + " - (Retention = "+ $dtk + " days) Filtered data start: " + $ffd.ToString()
$body +=  $ItemStyleEnd

# Space info
$body += "<br>Disk size is : " + [Math]::Round($lds/1GB,2) + " Go"
$body += "<br>Free space is : " + [Math]::Round($lfp/1GB,2) + " Go"

# Is free space less than Threshold ? Send email if true
$LastfreespacePercentage = ($lfp/$lds)*100
$str = "Current free space is " + [Math]::Round($LastfreespacePercentage,1) + "%"
If ($LastfreespacePercentage -le $AlertThreshold) {
    $color = "Red"
    $SendMail = $True
    $body += '<br><b><font color=red>Current free space is below defined Threshold (<'+$AlertThreshold+'%)</font></b>'
}
ElseIf ($LastfreespacePercentage -le ($AlertThreshold + 2)) {$color = "Yellow"}
Else {$color = "White"}
$body += "<br><font color=" + (($color -replace "White","Black") -replace "Yellow","#FF9900") + ">" + ($str -replace '(\d+)','<b>$1</b>') +"</font><br>"
Write-Host -ForegroundColor $color ($str)

# Sorting stats and defining if disk will be full before $Alert, send email if true
ForEach ($sph In $Results.GetEnumerator()) {
    Write-Host -ForegroundColor White $sph.Key
    If ($sph.Value -ne 0) {
        # TimeSpan to zero free space
        $2zero = New-TimeSpan -Hours ($lfp / $sph.Value)

        # Estimated full disk time
        $eft = $lfd + $2zero

        If ($sph.Value -gt 0) {
            If ($2zero.TotalHours -le 24) { $color = "Red" }
            ElseIf ($2zero.TotalHours -le 72) {$color = "Yellow"}
            Else {$color = "White"}

            If ($sph.Key -notlike "Next 3") {
                $body += ("<br><u><b>" + $sph.Key + " : </b></u>")

                $str = "Freespace on " + $Drive + " is decreasing at " + [Math]::Round(($sph.Value/1MB),2) + " Mo per hour [" + [Math]::Round(($sph.Value*24/1GB),2) + " Go/Day]"
                Write-Host -ForegroundColor $color ($str)
                $body += "<br>"+ ($str -replace '(\d+)','<b>$1</b>') + "<br>"

                $str = "Estimated date of full disk : " + $eft + " (In " + [Math]::Truncate($2zero.TotalDays) + " days)"
                Write-Host -ForegroundColor $color ($str)
                $body += ""+ ($str -replace '(\d+)','<b>$1</b>') + "<br>"
            }
            # Alerting
            If ($2zero.TotalDays -le $Alert) {
                If ($sph.Key -like "Total Average") {
                    $SendMail = $True
                }
                ElseIf ($sph.Key -like "Last 3") {

                    # Calculating % difference between last 6 polls
                    
                    $Diff = ($sph.Value / $Results["Next 3"].Value) * 100
                    # Sending mail Only if Last 3 sph is 10% more than Next 3
                    If ($Diff -ge 110) {
                        $SendMail = $True
                    }

                    $Diff = ($sph.Value / $Results["Last 6"].Value) * 100
                    # Sending mail Only if Last 3 sph is 10% more than Last 6
                    If ($Diff -ge 110) {
                        $SendMail = $True
                    }
                }
                ElseIf ($sph.Key -like "Last 6") {
                    $SendMail = $True
                }
            }
        }
        If ($sph.Value -lt 0) {
            Write-Host -ForegroundColor Green ("Freespace on " + $Drive + " is increasing at " + [Math]::Round(($sph.Value/1MB),2)*-1 + " Mo per hour")
        }
    }
    Else {
        Write-Host -ForegroundColor Green ("Freespace on " + $Drive + " is constant")
    }
}

# Getting max space usage per hour in total average
If ($MaxSpaceConsoph -ne 0) {
    If ($MaxSpaceConsoph -gt 0) {
        
        $2zero = New-TimeSpan -Hours ($MinFreeSpace / $MaxSpaceConsoph)
        If ($2zero.TotalHours -le 24) {$color = "Red"}
        ElseIf ($2zero.TotalHours -le 72) {$color = "Yellow"}
        Else {$color = "White"}

        If ($2zero.TotalDays -gt 0) {$etastr = ($2zero.ToString().Replace("."," Day(s) ")).Replace(":00:00",'h')}
        Else {$etastr = [Math]::Round($2zero.TotalHours,0) + " hours"}

        $body += ("<br><u><b>Maximum usage rate details: </u></b>")
        $body += ("<font color="+$color+">" -replace "White","black") -replace "Yellow","#FF9900"
        $str = "Max space consumption per hour : " + [Math]::Round(($MaxSpaceConsoph/1MB),2) + " Mo"
        Write-Host -ForegroundColor Cyan ($str)
        $body += "<br>" + ($str -replace '(\d+)','<b>$1</b>') + "<br>"

        $str = "It would take " + $etastr + " to fill the drive at max rate with the lowest free space recorded"
        Write-Host -ForegroundColor $color ($str)
        $body += ($str -replace '(\d+)','<b>$1</b>') + "<br>"

        $body += "</font>"
    }
}

If ($DoChart -and  $SendMail) {

   [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms.DataVisualization")
   # chart object
   $chart1 = New-object System.Windows.Forms.DataVisualization.Charting.Chart
   $chart1.Width = 800
   $chart1.Height = 400
   $chart1.BackColor = [System.Drawing.Color]::White
   # title 
   [void]$chart1.Titles.Add($hostname + " - Disk Space Usage - " + (Get-Date -Format "ddd dd/MM/yyyy HH:mm"))
   $chart1.Titles[0].Font = "Calibri,13pt"
   $chart1.Titles[0].Alignment = "topCenter"

   # chart area 
   $chartarea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
   $chartarea.Name = "ChartArea1"
   $chartarea.AxisY.Title = "Go"
   $chartarea.AxisX.Title = "Date"
   $chartarea.AxisY.Interval = 50
   $chartarea.AxisX.Interval = 1
   $chartarea.AxisX.IsMarginVisible = $false
   $chartarea.AxisX.IsLabelAutoFit = $true
   #$chartarea.AxisX.IntervalAutoMode = "VariableCount"
   $chart1.ChartAreas.Add($chartarea)

   # legend 
   $legend = New-Object system.Windows.Forms.DataVisualization.Charting.Legend
   $legend.name = "Legend1"
   $chart1.Legends.Add($legend)

   # data source
   $datasource = $ChartDS

   # data series
   [void]$chart1.Series.Add("DiskSize")
   $chart1.Series["DiskSize"].ChartType = "Line"
   $chart1.Series["DiskSize"].BorderWidth  = 3
   $chart1.Series["DiskSize"].IsVisibleInLegend = $true
   $chart1.Series["DiskSize"].chartarea = "ChartArea1"
   $chart1.Series["DiskSize"].Legend = "Legend1"
   $chart1.Series["DiskSize"].color = "#62B5CC"
   $datasource | ForEach-Object {$chart1.Series["DiskSize"].Points.addxy( (Get-Date $_.DateTime -Format "dd/MM/yy") , ($_.Size/1GB)) } | Out-Null

   # Not using free space for chart, better visualisation with disk usage (see below)
   # data series
   #[void]$chart1.Series.Add("FreeSpace")
   #$chart1.Series["FreeSpace"].ChartType = "Line"
   #$chart1.Series["FreeSpace"].IsVisibleInLegend = $true
   #$chart1.Series["FreeSpace"].BorderWidth  = 3
   #$chart1.Series["FreeSpace"].chartarea = "ChartArea1"
   #$chart1.Series["FreeSpace"].Legend = "Legend1"
   #$chart1.Series["FreeSpace"].color = "#E3B64C"
   #$chart1.Series["FreeSpace"].ShadowColor = "#000000"
   #$datasource | ForEach-Object {$chart1.Series["FreeSpace"].Points.addxy( $_.DateTime , ($_.FreeSpace/1GB)) } | Out-Null

   # data series
   [void]$chart1.Series.Add("UsedSpace")
   $chart1.Series["UsedSpace"].ChartType = "Line"
   $chart1.Series["UsedSpace"].IsVisibleInLegend = $true
   $chart1.Series["UsedSpace"].BorderWidth  = 3
   $chart1.Series["UsedSpace"].chartarea = "ChartArea1"
   $chart1.Series["UsedSpace"].Legend = "Legend1"
   $chart1.Series["UsedSpace"].color = "#E3B64C"
   $chart1.Series["UsedSpace"].ShadowColor = "#000000"
   $datasource | ForEach-Object {$chart1.Series["UsedSpace"].Points.addxy( (Get-Date $_.DateTime -Format "dd/MM/yy") , (($_.Size-$_.FreeSpace)/1GB)) } | Out-Null

   $chart1.SaveImage($ChartFile,"png")

}

$body += "<img src='" + (Split-Path -Leaf $ChartFile) + "'>"
$body += "</div></body>"
$MailObj = ConvertTo-Html -Head $head -Body $body | Out-String

If ($SendMail) {
    Send-MailMessage -from $Email_From -to $Email_To -subject $Email_Subject -Body $MailObj -BodyAsHtml -Attachments $ChartFile
    Write-Host "Sending Email"
}

