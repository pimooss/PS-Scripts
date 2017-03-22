<?php

echo '<HTML><HEAD><title>Scheduler Configs</title></head>';

$dir = '//scheduler/share$/Scheduler/Configs';
If (isset($_GET['dev'])) {
	$dir = '//scheduler/share$/Scheduler_dev/Configs';
}

$files = scandir($dir);
$k = 0;
//$key = fopen("C:/Scripts/Scheduler/Secure/AES.key", "r") or die("Unable to open file!");
//$key_content = fread($key,filesize("C:/Scripts/Scheduler/Secure/AES.key"));
//fclose($key);

echo '<center><font face="Calibri" color=#132F6E><h3>Scheduler configs</font></h3></center>';
echo '<center><TABLE BORDER=0 bordercolor=#132F6E color=#132F6E CELLPADDING=1 width=95%><TR bgcolor="#132F6E">';
echo '<TD><center><font color=white face="Calibri">Host</center></TD>';
echo '<TD><center><font color=white face="Calibri">fqdn</center></TD>';
echo '<TD><center><font color=white face="Calibri">JobName</center></TD>';
echo '<TD><center><font color=white face="Calibri">JobAction</center></TD>';
echo '<TD><center><font color=white face="Calibri">Trigger</center></TD>';
echo '<TD><center><font color=white face="Calibri">JobWhen</center></TD>';
echo '<TD><center><font color=white face="Calibri">JobAt</center></TD>';
echo '<TD><center><font color=white face="Calibri">Arg</center></TD>';
echo '</tr></center></font>';

Foreach(glob($dir."/*.xml") as $configfile) {
	$i = 0;
	$color = ($k % 2 == 1 ? "EFEFEF" : "E5E5E5");
	$green = ($k % 2 == 1 ? "00b200" : "009900");
	$red = ($k % 2 == 1 ? "FF0000" : "DD0000");
	$k++;
	
	$dom = DomDocument::load($configfile);
	
	$host = $dom->getElementsByTagName('Host')->item(0);
	$jobs = $host->getElementsByTagName('Job');
	
	//Host Attributs
	$host_name = $host->getAttribute("Name");
	$host_fqdn = $host->getAttribute("fqdn");
	$host_enabled = $host->getAttribute("Enabled");
	$host_org = $host->getAttribute("org");
	$host_principal = $host->getElementsByTagName('Principal')->item(0)->nodeValue;
	$host_secstring = $host->getElementsByTagName('SecString')->item(0)->nodeValue;
	
	//print_r(mcrypt_decrypt(MCRYPT_RIJNDAEL_128,$key_content,$host_secstring,'MCRYPT_MODE_CBC'));
	
	//foreach ($jobs as $job) {
	//}
	echo '<tr bgcolor='.$color.'>';
	If ($host_enabled == "True") {
		echo '<td rowspan='.$jobs->length.'><font color='.$green.' size=2 face="Calibri"><center><b>';
	}
	Else {
		echo '<td rowspan='.$jobs->length.'><font color='.$red.' size=2 face="Calibri"><center><b>';
	}
	echo $host_name;
	echo '</b></font></center></td>';
	
	echo '<td rowspan='.$jobs->length.'><font size=2 face="Calibri"><center><b>';
	echo $host_fqdn;
	echo '</b></font></center></td>';
	
	foreach ($jobs as $job) {
		$job_name = $job->getAttribute("Name");
		$job_enabled = $job->getAttribute("Enabled");
		$job_action = $job->getElementsByTagName('Action')->item(0)->nodeValue;
		$job_at = $job->getElementsByTagName('At')->item(0)->nodeValue;
		If (isset($job->getElementsByTagName('Arguments')->item(0)->nodeValue)) {
			$job_arg = $job->getElementsByTagName('Arguments')->item(0)->nodeValue;
		}
		Else {
			$job_arg = "";
		}
		If (isset($job->getElementsByTagName('Principal')->item(0)->nodeValue)) {
			$job_principal = $job->getElementsByTagName('Principal')->item(0)->nodeValue;
		}
		Else {
			$job_principal = "";
		}
		If (isset($job->getElementsByTagName('SecString')->item(0)->nodeValue)) {
			$job_secstring = $job->getElementsByTagName('SecString')->item(0)->nodeValue;
		}
		Else {
			$job_secstring = "";
		}
		If ($i > 0) {
			/*$color = ($k % 2 == 1 ? "EFEFEF" : "E5E5E5");
			$green = ($k % 2 == 1 ? "00b200" : "009900");
			$red = ($k % 2 == 1 ? "FF0000" : "DD0000");
			$k++;*/
			echo '<tr bgcolor='.$color.'>';
			//$k++;
		}
		
		If ($job_enabled == "True") {
			echo '<td><font color='.$green.' size=2 face="Calibri"><center><b>';
		}
		Else {
			echo '<td><font color='.$red.' size=2 face="Calibri"><center><b>';
		}
        echo $job_name;
        echo '</b></font></center></td>';
		
		echo '<td><font size=2 face="Calibri"><center>';
        echo $job_action;
        echo '</font></center></td>';
		
		echo '<td><font size=2 face="Calibri"><center>';
        echo $job->getElementsByTagName('Trigger')->item(0)->nodeValue;
        echo '</font></center></td>';
		
		Switch (strtolower($job->getElementsByTagName('Trigger')->item(0)->nodeValue)) {
			case 'monthly':
				$Trigger = $job->getElementsByTagName('Monthly')->item(0);
				echo '<td><font size=2 face="Calibri"><center><b>';
				if (trim($Trigger->getElementsByTagName("DaysofMonth")->item(0)->nodeValue) != "") {
					echo "Every ".$Trigger->getElementsByTagName("DaysofMonth")->item(0)->nodeValue;
				}
				else {
					echo $Trigger->getElementsByTagName("WeekDayOfMonthPosition")->item(0)->nodeValue;
					echo ' ';
					echo $Trigger->getElementsByTagName("WeekDayOfMonth")->item(0)->nodeValue;
				}
				echo '</b></font></center></td>';
			break;
			case 'weekly':
				$Trigger = $job->getElementsByTagName('Weekly')->item(0);
				echo '<td><font size=2 face="Calibri"><center><b>';
				if (trim($Trigger->getElementsByTagName("WeeksInterval")->item(0)->nodeValue) != "") {
					echo "Every ".$Trigger->getElementsByTagName("WeeksInterval")->item(0)->nodeValue." ";
				}
				echo $Trigger->getElementsByTagName("DaysofWeek")->item(0)->nodeValue;
				echo '</b></font></center></td>';
			break;
			case 'daily':
				$Trigger = $job->getElementsByTagName('Daily')->item(0);
				echo '<td><font size=2 face="Calibri"><center><b>';
				if (trim($Trigger->getElementsByTagName("DaysInterval")->item(0)->nodeValue) != "") {
					echo "Every ".$Trigger->getElementsByTagName("DaysInterval")->item(0)->nodeValue." days";
				}
				echo '</b></font></center></td>';
			break;
		}
		
		echo '<td><font size=2 face="Calibri"><center>';
        echo $job_at;
        echo '</font></center></td>';
		echo '<td><font size=2 face="Calibri"><center>';
        echo $job_arg;
        echo '</font></center></td>';
		
		$i++;
	}
	
}

echo "</table><br>";
?>