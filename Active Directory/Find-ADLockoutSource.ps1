
# Getting User SamAccountName

$User = Read-Host -Prompt "Please enter a user SamAccountName"

# Timespan
$h = 1

$TimeSpan = $h * 3600000

# Specify PDCe

$PDC = Get-ADDomainController -Discover -Service PrimaryDC


#Collect lockout events for user from last hour

Get-WinEvent -ComputerName $PDC -Logname Security -FilterXPath "*[System[EventID=4740 and TimeCreated[timediff(@SystemTime) <= '$TimeSpan']] and EventData[Data[@Name='TargetUserName']='$User']]" | Select-Object TimeCreated,@{Name='User Name';Expression={$_.Properties[0].Value}},@{Name='Source Host';Expression={$_.Properties[1].Value}}


