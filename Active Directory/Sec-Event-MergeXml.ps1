$xml_path = "C:\path\SecurityAudit_Hourly" | Get-ChildItem -Filter "*.xml" | Sort LastWriteTime

$merged_xml_path = "C:\path\Merged_SecurityAudit"
$merged_xml_file = "$merged_xml_path\all.xml"
$merged_xml = '<?xml version="1.0"?>'
$merged_xml = "<root>"

$Data = @{}
$count = 0

ForEach ($xml_file In $xml_path) {

    [xml]$File = Get-Content $xml_file.fullname
    If ($File.Events.timespan_from) {
        $date_from = ($File.Events.timespan_from -split " ")[0] -split "/"
        $Year_From = $date_from[2]
        $Month_From = $date_from[0]

        If ($File.Events.Event) {
            If (!($Data["$Year_From-$Month_From"])) {
                $Data["$Year_From-$Month_From"] += '<?xml version="1.0"?>'
                $Data["$Year_From-$Month_From"] += '<root>'
            }
            $Data["$Year_From-$Month_From"] += $File.Events.OuterXml

            $count += ($File.Events.Event.GUID).count

            If (($File.Events.Event.GUID).count -eq 1) {
                Write-Host "Processing $count"
            }
            Else {
                Write-Host "Processing"($count+1-($File.Events.Event.GUID).count)"->"$count
            }
            
            $merged_xml += $File.Events.OuterXml
        }
        
    }
    Else { 
        #useless empty xml 
    }
}

$Data.GetEnumerator() | %{ 
    
        $archive_file = $merged_xml_path+"\"+$_.Name.Tostring()+".xml";
        $archive_content = ""
        #$_.Value | %{$archive_content += $_}
        $archive_content += $_.Value
        $archive_content += "</root>"
        ([xml]$archive_content).Save($archive_file)
    
    }

$merged_xml += "</root>"
([xml]$merged_xml).Save($merged_xml_file)