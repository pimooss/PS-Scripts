#
# RadiusFamedIp Management script
#
# J.DECOMBE 
#

# IP Math Functions
$IPCalc = "C:\Scripts\IP-Calc.ps1"
If (!(Test-Path $IPCalc)) {

    Return ($IPCalc + "not found")
}

# End Functions

# Table formating
$a =    @{Expression={$_.SamAccountName};Label="User"},
        @{Expression={$_.Department};Label="Department"},
        @{Expression={[System.Linq.Enumerable]::Reverse(([System.Net.IPAddress]$_.msRADIUSFramedIPAddress).IPAddressToString.Split(".")) -join "."};Label="RadiusFramedIP"}

# Ip Pools
$IPPoolSubnet = @{}
$IPPoolSubnet["Group1"] = "10.0.1.0/24"
$IPPoolSubnet["Group2"] = "10.0.2.0/24"

$IPPoolArray = @()

$SubnetArray= @()

# Getting Group members
ForEach ($IPPool In $IPPoolSubnet.GetEnumerator()) {
    $GroupMembers = Get-AdGroupMember $IPPool.Name

    # Generating Subnet Array
    $subnet = $IPPool.Value
    $IP = ($subnet -split "/")[0]
    $Masklength = ($subnet -split "/")[1]
    $NetworkObj = &$IPCalc -IPAddress $IP -PrefixLength $Masklength -CreateIParray
    $IPArray = ($NetworkObj.IParray | Select -Skip 2 | Select -First (($NetworkObj.IParray).Count - 4))

    $IPArray | %{ $SubnetArray += [pscustomobject]@{ Group = $IPPool.Name ; IP = $_ ; Used = $False ; UsedBy = ""} }

    If ($GroupMembers) {
        ForEach ($User In $GroupMembers) {
            $UserObj = Get-ADUser $User -Properties msRADIUSFramedIPAddress,Department
            If ($UserObj.msRADIUSFramedIPAddress) {
                # FramedIP is already set
                $UserFramedIP = [System.Linq.Enumerable]::Reverse(([System.Net.IPAddress]$UserObj.msRADIUSFramedIPAddress).IPAddressToString.Split(".")) -join "."
                $IPPoolArray += [pscustomobject]@{Group = $IPPool.Name ;Department = $UserObj.Department ;SamAccountName = $UserObj.SamAccountName ; FramedIP = $UserFramedIP ; msRADIUSFramedIPAddress = $UserObj.msRADIUSFramedIPAddress ; Set = $True}
            }
            Else {
                # Not set
                $IPPoolArray += [pscustomobject]@{Group = $IPPool.Name ;Department = $UserObj.Department ; SamAccountName = $UserObj.SamAccountName ; FramedIP = "" ; msRADIUSFramedIPAddress = "" ; Set = $False}
            }
        }
    }
    Else {
        Write-Host -ForegroundColor Yellow "Group $IPPool.Name not found or empty"
    }
}


# Assigned Subnet Validation

# Valid assignement 
$IPPoolArray | Where Set -eq $True | ?{ ($SubnetArray | Where Group -EQ $_.Group).IP -contains $_.FramedIP } | % {
        Write-host -ForegroundColor Green "Valid assignment for" $_.SamAccountName
        # Updating $SubnetArray
        ($SubnetArray |Where Group -EQ $_.Group | Where IP -EQ $_.FramedIP).Used = $True
        ($SubnetArray |Where Group -EQ $_.Group | Where IP -EQ $_.FramedIP).UsedBy = $_.SamAccountName
}

# Invalid assignments
$IPPoolArray | Where Set -eq $True | ?{ ($SubnetArray | Where Group -NE $_.Group).IP -contains $_.FramedIP } | % {
        Write-host -ForegroundColor Yellow "Warning: Invalid assignment for " $_.SamAccountName
        # Get a free IP
        $IP2Set = ($SubnetArray | Where Used -eq $false | Where Group -EQ $_.Group).IP | Select -First 1
        # Convert to decimal
        [int32]$DecimalIP2Set = (&$IPCalc -IPAddress $IP2Set -PrefixLength 32).ToDecimal
        
        # Setting up user
        Write-host -ForegroundColor Cyan $_.SamAccountName "replacing" $_.msRADIUSFramedIPAddress "("$_.FramedIP")" "with" $DecimalIP2Set "("$IP2Set")"
        Set-ADUser $_.SamAccountName -Replace @{msRADIUSFramedIPAddress = $DecimalIP2Set; msRASSavedFramedIPAddress = $DecimalIP2Set}

        # Updating $SubnetArray with old and new ip
        ($SubnetArray | Where IP -EQ $_.FramedIP).Used = $True
        ($SubnetArray | Where IP -EQ $_.FramedIP).UsedBy = $_.SamAccountName
        ($SubnetArray | Where IP -EQ $IP2Set).Used = $True
        ($SubnetArray | Where IP -EQ $IP2Set).UsedBy = $_.SamAccountName

}


# To set
$IPPoolArray | Where Set -eq $False | %{
    # Get a free IP
    $IP2Set = ($SubnetArray | Where Used -eq $false | Where Group -EQ $_.Group).IP | Select -First 1
    # Convert to decimal
    [int32]$DecimalIP2Set = (&$IPCalc -IPAddress $IP2Set -PrefixLength 32).ToDecimal

    Write-host -ForegroundColor Cyan $_.SamAccountName ": setting up FramedIP to" $DecimalIP2Set "("$IP2Set")"
    Set-ADUser $_.SamAccountName -Replace @{msRADIUSFramedIPAddress = $DecimalIP2Set; msRASSavedFramedIPAddress = $DecimalIP2Set}
    ($SubnetArray | Where IP -EQ $IP2Set).Used = $True
    ($SubnetArray | Where IP -EQ $IP2Set).UsedBy = $_.SamAccountName
}


# IP Conflict Resolution - TODO

 
# Cleaning up disabled account
#$Toclean = Get-ADUser -filter * -SearchBase "OU=Users,OU=Jaguar-Network,DC=user,DC=as30781,DC=net" -Properties msRADIUSFramedIPAddress,Department,MemberOf | Where Enabled -EQ $False | Where msRADIUSFramedIPAddress

# Summary
#$users = Get-ADUser -filter * -SearchBase "OU=Users,OU=Jaguar-Network,DC=user,DC=as30781,DC=net" -Properties msRADIUSFramedIPAddress,Department,MemberOf | Where msRADIUSFramedIPAddress
#$users | select SamAccountName,Department,msRADIUSFramedIPAddress | Sort Department,msRADIUSFramedIPAddress | Format-Table $a 
