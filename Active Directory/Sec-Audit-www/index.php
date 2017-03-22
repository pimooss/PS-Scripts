
<?
echo '<HTML><HEAD><title>Security Audit</title>';
header( 'content-type: text/html; charset=utf-8' );
?>
<style type="text/css">
	
	a {color: #000000;}
	a:link {color: #000000;}
	a:visited {color: #000000;}
	a:hover {color: #0066CC;}
	a:active {color: #000000;}
	
	a.header {color: #FFFFFF;}
	a.header:link {color: #FFFFFF;}
	a.header:visited {color: #FFFFFF;}
	a.header:hover {color: #E5E5E5;}
	a.header:active {color: #FFFFFF;}
	
	div.header {
		padding:40px;
		float:left;
		color:black;
		font-family:"Calibri" verdana, sans-serif;
		font-size:0.75em;
	}
</style>

<script src="https://ajax.googleapis.com/ajax/libs/jquery/2.1.3/jquery.min.js" type="text/javascript"></script>
<script type="text/javascript">
$(document).ready(function(){
 //add index column with all content.
 $(".table tr:has(td)").each(function(){
   var t = $(this).text().toLowerCase(); //all row text
   $("<td class='indexColumn'></td>")
    .hide().text(t).appendTo(this);
 });//each tr
 $("#search").keyup(function(){
   var s = $(this).val().toLowerCase().split(" ");
   //show all rows.
   $(".table tr:hidden").show();
   $.each(s, function(){
       $(".table tr:visible .indexColumn:not(:contains('"
          + this + "'))").parent().hide();
   });//each
 });//key up.
});//document.ready
</script>
  
<?

If (isset($_GET['sortby'])) {
    $sortby = strtolower($_GET['sortby']);  
}
else {
	$sortby = "";  
}

If (!isset($_GET['sortorder'])) {
    $sortorder = SORT_ASC;
}
Else {
    Switch (strtolower($_GET['sortorder'])) {
        Case "asc":
            $sortorder = SORT_ASC;
        break;
        Case "desc":
            $sortorder = SORT_DESC;
        break;
        Default :
            $sortorder = SORT_ASC;
        break;
    }
}


$dir = '//server/share$/Merged_SecAudit';
$merged = True;

If (isset($_GET['logfile'])) {
	$logfile = $_GET['logfile'];
}
Else {
	$logfile = "last";
}

$allfiles = scandir($dir,1);

$xml_audit_file = null;
If ($logfile == "last") {		
	$xml_audit_file = $allfiles[1];
}
ElseIf ($logfile == "all") {		
	$xml_audit_file = $allfiles[0];
}
else {
	$tofind = $logfile.".xml";
	$xml_audit_file = $tofind;
	If (array_search($tofind, $allfiles)) {
		$xml_audit_file = $tofind;
	}
}

//Cache file, and expiration after 60 minutes
$filename = explode(".", $xml_audit_file)[0];
$data_cache = 'cache/audit.'.$filename.'.data';
$expire = time() - 3600;
If ((isset($_GET['refresh'])) || (file_exists($data_cache) && filemtime($data_cache) < $expire)) {$GenerateCache = True;}
Else {$GenerateCache = False;}

if(file_exists($data_cache) && filemtime($data_cache) > $expire && $GenerateCache === False) {
	$AllEventsArray = unserialize(file_get_contents($data_cache));
}
else {
	//Getting file
	$xml_audit_file_path = $dir."/".$xml_audit_file;

	$dom = new DOMDocument;
	$dom->preserveWhiteSpace = FALSE;
	if (@$dom->load($xml_audit_file_path) === true) {
		$dom->load($xml_audit_file_path);

		$root = $dom->getElementsByTagName('root')->item(0);
		$xml_root = $root->getElementsByTagName('Events');
	

		foreach ($xml_root as $Events_root) {
		
			foreach ($Events_root->getElementsByTagName('Event') as $Events) {
				$Type = $Events_root->getAttribute('type');
				$index = $Events->getAttribute('GUID');
				
				$AllEventsArray[$index]['Type'] = $Type;
				$AllEventsArray[$index]['TimeCreated'] = $Events->getElementsByTagName('TimeCreated')->item(0)->nodeValue;
				$AllEventsArray[$index]['ID'] = $Events->getElementsByTagName('Id')->item(0)->nodeValue;
				$AllEventsArray[$index]['Action'] = $Events->getElementsByTagName('Action')->item(0)->nodeValue;
				$AllEventsArray[$index]['Subject'] = $Events->getElementsByTagName('Subject')->item(0)->nodeValue;
				$AllEventsArray[$index]['Target'] = $Events->getElementsByTagName('Target')->item(0)->nodeValue;
				$AllEventsArray[$index]['Member'] = $Events->getElementsByTagName('Member')->item(0)->nodeValue;
				If (isset($Events->getElementsByTagName('Workstation')->item(0)->nodeValue)) {
					$AllEventsArray[$index]['Workstation'] = $Events->getElementsByTagName('Workstation')->item(0)->nodeValue;
				}
				Else {
					$AllEventsArray[$index]['Workstation'] = "";
				}
				If (isset($Events->getElementsByTagName('IP')->item(0)->nodeValue)) {
					$AllEventsArray[$index]['IP'] = $Events->getElementsByTagName('IP')->item(0)->nodeValue;
				}
				Else {
					$AllEventsArray[$index]['IP'] = "";
				}
				
				$AllEventsArray[$index]['Server'] = $Events->getElementsByTagName('Server')->item(0)->nodeValue;
				
			}
		}
	}
//Putting array in cache file
$cache = serialize($AllEventsArray);
file_put_contents($data_cache, $cache);
}

//Display header

echo '</head><body>';

echo '<center><font face="Calibri" color=#132F6E><h3>Administrator Security Audit</font></h3></center>';

echo '<div class=header>';
echo 'Choose log file : ';
ForEach ($allfiles as $file ) {
		$filename = explode(".",$file);
		if ( strtolower($filename[0]) != "all" ) {
			If ( strtolower($filename[1]) == "xml" ) {
				echo ' <a href="?logfile='.$filename[0].'">'.$filename[0].'</a> |';
			}		
		}
}
echo ' <a href="?logfile=all">all</a> ';
echo '<br><br>';

If ($GenerateCache) {
	echo '<font face="Calibri" size=2>Cache has been refreshed</font>';
}
Else {
	echo '<font face="Calibri" size=2><a class=nope href="?refresh=plop'.(isset($_GET["logfile"]) ? "&logfile=".$_GET["logfile"] : "").'">Force cache refresh</a> (current cache has been generated '.gmdate("H:i:s",(time() - filemtime($data_cache))).' ago)</font>';
}

echo '<br><br><input type="text" id="search" name="search" placeholder="Type to search"><br>';
echo '</div>';

$table_header = '<table class="table" width="95%" align="center" cellpadding="3"><tr bgcolor="#132F6E">
                        <th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=type'.(($sortorder == SORT_ASC) && ($sortby == 'type') ? "&sortorder=desc" : "&sortorder=asc").'">Type</a></font></th>
                        <th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=time'.(($sortorder == SORT_ASC) && ($sortby == 'time') ? "&sortorder=desc" : "&sortorder=asc").'">Time</a></font></th>
                        <th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=id'.(($sortorder == SORT_ASC) && ($sortby == 'id') ? "&sortorder=desc" : "&sortorder=asc").'">ID</a></font></th>
                        <th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=action'.(($sortorder == SORT_ASC) && ($sortby == 'action') ? "&sortorder=desc" : "&sortorder=asc").'">Action</a></font></th>
                        <th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=subject'.(($sortorder == SORT_ASC) && ($sortby == 'subject') ? "&sortorder=desc" : "&sortorder=asc").'">Subject</a></font></th>
                        <th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=target'.(($sortorder == SORT_ASC) && ($sortby == 'target') ? "&sortorder=desc" : "&sortorder=asc").'">Target</a></font></th>
                        <th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=member'.(($sortorder == SORT_ASC) && ($sortby == 'member') ? "&sortorder=desc" : "&sortorder=asc").'">Member</a></font></th>
						<th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=workstation'.(($sortorder == SORT_ASC) && ($sortby == 'workstation') ? "&sortorder=desc" : "&sortorder=asc").'">Workstation</a></font></th>
						<th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=ip'.(($sortorder == SORT_ASC) && ($sortby == 'ip') ? "&sortorder=desc" : "&sortorder=asc").'">IP</a></font></th>
						<th align="center"><font face="Calibri" size=2><a class=header href="?'.(isset($_GET["logfile"]) ? "logfile=".$_GET["logfile"]."&" : "").'sortby=server'.(($sortorder == SORT_ASC) && ($sortby == 'server') ? "&sortorder=desc" : "&sortorder=asc").'">Server</a></font></th>
						</tr>';
echo $table_header;



foreach ($AllEventsArray as $key => $row) {
    $temp_sort_date[$key] = $row['TimeCreated'];
}
array_multisort($temp_sort_date,SORT_DESC,$AllEventsArray);

foreach ($AllEventsArray as $key => $row) {
    $sort_type[$key]  = $row['Type'];
    $sort_time[$key] = $row['TimeCreated'];
    $sort_id[$key] = $row['ID'];
    $sort_action[$key] = $row['Action'];
    $sort_subject[$key] = $row['Subject'];
    $sort_target[$key] = $row['Target'];
	$sort_member[$key] = $row['Member'];
	$sort_workstation[$key] = $row['Workstation'];
	$sort_ip[$key] = $row['IP'];
	$sort_server[$key] = $row['Server'];
}


Switch ($sortby) {
    Case 'type':
        array_multisort($sort_type,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
    Case 'time':
        array_multisort($sort_time,$sortorder,$AllEventsArray);
    break;
    Case 'id':
        array_multisort($sort_id,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
    Case 'action':
        array_multisort($sort_action,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
    Case 'subject':
        array_multisort($sort_subject,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
    Case 'target':
        array_multisort($sort_target,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
	Case 'member':
        array_multisort($sort_member,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
	Case 'workstation':
        array_multisort($sort_workstation,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
    Case 'ip':
        array_multisort($sort_ip,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
	Case 'server':
        array_multisort($sort_server,$sortorder,$sort_time,SORT_DESC,$AllEventsArray);
    break;
	default:
        array_multisort($sort_time,SORT_DESC,$AllEventsArray);
    break;
}

$d = 0;
foreach ($AllEventsArray as $event) {
	$color = ($d % 2 == 1 ? 'EFEFEF' : 'E5E5E5');
    
    echo '<tr bgcolor=#'.$color.'>';
	echo '<td><font face="Calibri" size=2>'.$event['Type'].'</font></td>';
    echo '<td><font face="Calibri" size=2>'.$event['TimeCreated'].'</font></td>';
    echo '<td><font face="Calibri" size=2>'.$event['ID'].'</font></td>';
    echo '<td><font face="Calibri" size=2>'.$event['Action'].'</font></td>';
    echo '<td><font face="Calibri" size=2>'.$event['Subject'].'</font></td>';
    echo '<td><font face="Calibri" size=2>'.utf8_decode($event['Target']).'</font></td>';
    echo '<td><font face="Calibri" size=2>'.utf8_decode($event['Member']).'</font></td>';
	echo '<td><font face="Calibri" size=2>'.$event['Workstation'].'</font></td>';
	echo '<td><font face="Calibri" size=2>'.$event['IP'].'</font></td>';
	echo '<td><font face="Calibri" size=2>'.$event['Server'].'</font></td>';
    echo '</tr>';
   
    $d++;
	
}
echo '</table>';

echo '</body></html>';
?>