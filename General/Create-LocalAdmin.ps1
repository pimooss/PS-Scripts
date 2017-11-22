
$UserName = "localadmin01"
$Computer = [ADSI]"WinNT://$env:COMPUTERNAME,Computer"
$LocalAdmin = $Computer.Create("User", $username)
$LocalAdmin.SetPassword("Passw0rd")
$LocalAdmin.SetInfo()
$LocalAdmin.FullName = "it-test"
$LocalAdmin.Description = "Local admin account"
$LocalAdmin.UserFlags = 65536 #ADS_UF_DONT_EXPIRE_PASSWD
$LocalAdmin.SetInfo()

$LocalAdminGroup = "Administrators"
Try {
    [ADSI]("WinNT://$env:COMPUTERNAME/$LocalAdminGroup,group")
}
Catch {
    $LocalAdminGroup = "Administrateurs"    
}

$group = [ADSI]("WinNT://$env:COMPUTERNAME/$LocalAdminGroup,group")
$group.Add($LocalAdmin.Path)
