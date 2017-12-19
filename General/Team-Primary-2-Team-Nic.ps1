
$TeamName = "TEAM0"

If (Get-NetLbfoTeam -Name $TeamName -ErrorAction SilentlyContinue) {
    Get-NetLbfoTeamNic -Team $TeamName | Where Primary -eq $true  | Get-NetIPInterface | Where DHCP -eq Disabled | %{
                $IfConfig = Get-NetIPConfiguration $_.InterfaceAlias      
                $VLAN = ($_ | Get-NetAdapter).VlanID
                $IP = ($IfConfig.IPv4Address).IPAddress
                $PLength = ($IfConfig.IPv4Address).PrefixLength
                $GW = ($IfConfig.IPv4DefaultGateway).NextHop
                $DNS = ($IfConfig.DNSServer).ServerAddresses
    }

    $OldTeamNic = Get-NetLbfoTeamNic -Team $TeamName | Where Primary -eq $true  | Where {$_.VlanID -eq $VLAN} | Get-NetAdapter

    $OldTeamNic | Remove-NetIPAddress -AddressFamily IPv4 -Confirm:$False -ErrorAction SilentlyContinue
    $OldTeamNic | Remove-NetIPAddress -AddressFamily IPv6 -Confirm:$False -ErrorAction SilentlyContinue

    Get-NetLbfoTeamNic -Team $TeamName | Where Primary -eq $true  | Where {$_.VlanID -eq $VLAN} | Set-NetLbfoTeamNic -Default -Confirm:$False
    

    Add-NetLbfoTeamNic -Team $TeamName -VlanID $VLAN -Confirm:$False
    
    $TeamNic = Get-NetLbfoTeamNic -Team $TeamName | Where Primary -eq $false | Where {$_.VlanID -eq $VLAN} | Get-NetAdapter
    
    Write-Host "Getting TeamNIC" $TeamNic.Name
    $TeamNic | Set-NetIPInterface -Dhcp Enabled
    $TeamNic | Set-NetIPInterface -Dhcp Disabled
    $TeamNic | Remove-Netroute -Confirm:$False -ErrorAction SilentlyContinue
    
    $TeamNic | Remove-NetIPAddress -AddressFamily IPv4 -Confirm:$False -ErrorAction SilentlyContinue
    $TeamNic | Remove-NetIPAddress -AddressFamily IPv6 -Confirm:$False -ErrorAction SilentlyContinue
    $TeamNic | Remove-NetIPAddress -Confirm:$False -ErrorAction SilentlyContinue
    

    If ($GW) {
        Write-Host "Configuring IP for" $TeamNic.Name "->" $IP"/"$PLength" gw:"$GW
        $TeamNic | New-NetIPAddress -IPAddress $IP -PrefixLength $PLength -DefaultGateway $GW
    }
    Else {
        Write-Host "Configuring IP for" $TeamNic.Name "->" $IP"/"$PLength
        $TeamNic | New-NetIPAddress -IPAddress $IP -PrefixLength $PLength
    }
    
    Write-Host "Configuring DNS for" $TeamNic.Name "->" $DNS
    $TeamNic | Set-DnsClientServerAddress -ServerAddresses $DNS
    Write-Host "Disabling IPV6"
    $TeamNic | Disable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$False
    
}