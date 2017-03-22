
Import-Module ActiveDirectory

$searchGroup = @()
$searchGroup += "CN=GroupName,OU=Org,DC=domain,DC=local"


$Members = @()

$searchGroup | %{

   Get-ADGroupMember $_ -Recursive | %{  $Members += $_.SamAccountName }

}
$Members = $Members | Select -Unique | Sort
$Members | Format-Table
Write-Host "Count ->" $Members.Count