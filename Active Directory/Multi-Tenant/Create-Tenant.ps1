#
# Create-Tenant.ps1
# Multi Active Directory - Tenant Creation Script
#
# Auth : Joris DECOMBE
#
#

Param (
    [parameter(Mandatory=$true)][ValidateLength(1,17)][string]$Tenant
)

#
# Modules
#

Import-Module ActiveDirectory

#
# Script specific Variables
#

$script:ClientName = $env:CLIENTNAME
$script:CurrentUser = $env:USERNAME

$ScriptPath = "C:\Joris\Scripts\"

#
# Log
#

$LogPath = $ScriptPath+"Logs"
$LogFileName = "Create-Tenant-"+(Get-Date -Format yyyyMMdd-HHmmss)+".log"
$LogFile = "$LogPath\$LogFileName"

Start-Transcript $LogFile
Write-Host (Get-Date -Format 'HH:mm:ss') ": Script Launched by $CurrentUser from $ClientName"

#
# Global Variables and Functions Import
#

$GlobalFile = $ScriptPath+"Global.ps1"

If (Test-Path $GlobalFile) {
    Write-Host (Get-Date -Format 'HH:mm:ss') ": DotSourcing $GlobalFile"
}
Else {
    Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": DotSourcing $GlobalFile : Error File Not Found"
    Stop-Transcript
    Exit
}

. $GlobalFile

$Jobs = @()

#
# Go
#

Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": RootDomain        [$RootDomainFQDN]       Infrastructure Master   [$RootDomainDC]"
Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": ComputerDomain    [$ComputerDomainFQDN]   Infrastructure Master   [$ComputerDomainDC] "
Write-Host -ForegroundColor Cyan (Get-Date -Format 'HH:mm:ss') ": UserDomain        [$UserDomainFQDN]   Infrastructure Master   [$UserDomainDC]"

If (!(Test-NetConnection $RootDomainDC -CommonTCPPort WINRM -InformationLevel Quiet)) {
    Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": Communication problem with Infrastructure Master [$RootDomainDC]"
    Exit
}
If (!(Test-NetConnection $ComputerDomainDC -CommonTCPPort WINRM -InformationLevel Quiet)) {
    Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": Communication problem with Infrastructure Master [$ComputerDomainDC]"
    Exit
}
If (!(Test-NetConnection $UserDomainDC -CommonTCPPort WINRM -InformationLevel Quiet)) {
    Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": Communication problem with Infrastructure Master [$UserDomainFQDN]"
    Exit
}

If ($Tenant) {
    
    #
    # Todo :    Change OU name ($Tenant) to GUID 
    #           Check Tenant name in xml files
    #

    #
    # TenantName -> GUID update start here
    #

    $TenantPath = "$ScriptPath\Tenants\$Tenant"
    $Outputfile = $TenantPath + "\" + $xmlFileName

    $Exists = $False

    If (Test-Path $Outputfile) {
        $Exists = $True
    }

    If ($Exists) {
        $xml = New-Object -TypeName XML
        $xml.Load($Outputfile)
        If ($xml.Tenant) {
            If ($xml.Tenant.guid) {
                $TenantGUID = $xml.Tenant.guid
            }
            Else {
                # Something wrong, no guid for this client
                Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": Error : No GUID found for Tenant [$Tenant]"            
            }
        }

    }
    Else {
        $TenantGUID = (New-Guid).Guid
        Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": Generating new GUID for Tenant [$Tenant] [$TenantGUID]"
    }

    #
    # TenantName -> GUID update end here
    #

    $TenantComputerOU = "OU=$TenantGUID,$ComputerDomainOU"

    $TenantUserOU = "OU=$TenantGUID,$UserDomainOU"

    $CheckComputerOU = Get-ADOrganizationalUnit -Filter {distinguishedName -eq $TenantComputerOU} -Server $ComputerDomainDC
    
    If ($CheckComputerOU) {
        Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": Tenant OU already exists: $TenantComputerOU"
        $Exists = $True
    }

    If (!($Exists)) {
        $CheckUserOU = Get-ADOrganizationalUnit -Filter {distinguishedName -eq $TenantUserOU} -Server $UserDomainDC
    
        If ($CheckComputerOU) {
            Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": Tenant OU already exists: $TenantUserOU"
            $Exists = $True
        }
    }
    
    # Cleaning Up
    Get-Job -HasMoreData $false -State Completed | Remove-Job

    If (!$Exists) {
        
        # Creating Folder structure
        If (!(Test-Path "$ScriptPath\Tenants" -ErrorAction SilentlyContinue)) {
            New-Item -Path "$ScriptPath" -ItemType Directory -Name "Tenants" -Confirm:$false | Out-Null
        }
    
        If (!(Test-Path $TenantPath -ErrorAction SilentlyContinue)) {
            New-Item -Path "$ScriptPath\Tenants" -ItemType Directory -Name $Tenant -Confirm:$false | Out-Null
        }

        $Outputfile = $TenantPath + "\" + $xmlFileName

        $datetime = (Get-Date -Format yyyyMMdd-HHmmss)
        # Creating xml file
        $XmlWriter = New-Object System.XMl.XmlTextWriter($Outputfile,$Null)
        $xmlWriter.Formatting = 'Indented'
        $xmlWriter.Indentation = 1
        $XmlWriter.IndentChar = "`t"
        $xmlWriter.WriteStartDocument()
        $XmlWriter.WriteComment("Tenant Info")
        $XmlWriter.WriteComment("Created $datetime")
        $xmlWriter.WriteStartElement('Tenant',"")
        $XmlWriter.WriteAttributeString('Name', $Tenant)
        $XmlWriter.WriteAttributeString('guid',$TenantGUID)

        #If (!(Get-ADOrganizationalUnit "OU=$Tenant,$UserDomainOU" -Server $UserDomainDC -ErrorAction SilentlyContinue | Out-Null)) {
        #    Write-Host "$Tenant already exists"
        #}

        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Creating Tenant OU : [$ComputerDomainOU]"
        New-ADOrganizationalUnit -Name $TenantGUID -Path $ComputerDomainOU -Server $ComputerDomainDC

        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Creating Tenant OU : [$UserDomainOU]"
        New-ADOrganizationalUnit -Name $TenantGUID -Path $UserDomainOU -Server $UserDomainDC
    
        $xmlWriter.WriteStartElement('OU',"")
        $XmlWriter.WriteElementString('TenantComputerOU', $TenantComputerOU)
        $XmlWriter.WriteElementString('TenantUserOU', $TenantUserOU)
        $xmlWriter.WriteEndElement()

        # Creating Tenant Delegation Users

        #$xmlWriter.WriteStartElement('Users',"")

        $TenantUserName = "it-$Tenant"
    
        $DefaultPwd = Generate-Password
        $DefaultPwdSecureString = $DefaultPwd | ConvertTo-SecureString -AsPlainText -Force
    
        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Creating Tenant delegation account :"
        New-ADUser $TenantUserName -ChangePasswordAtLogon $false -AccountPassword $DefaultPwdSecureString -Server $UserDomainDC -Path $TenantUserOU -Enabled $true
    
        If ($TenantUserName) {
            $xmlWriter.WriteStartElement('User')
            $XmlWriter.WriteAttributeString('CreatedBy', $CurrentUser)
            $XmlWriter.WriteAttributeString('CreatedFrom', $ClientName)
            $XmlWriter.WriteAttributeString('CreationDateTime', $datetime)
            $XmlWriter.WriteElementString('SamAccountName', $TenantUserName)
            $XmlWriter.WriteElementString('Password', $DefaultPwd)
            $XmlWriter.WriteElementString('Type', 'Admin')
            $XmlWriter.WriteElementString('Domain', $UserDomainFQDN)
            $xmlWriter.WriteEndElement()
        }
       
        #$xmlWriter.WriteEndElement()
    
        Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": [ $TenantUserName / $DefaultPwd ]"

        # Creating UserDomain delegation group

        $TenantAdminGroupName =  "ADUG-$Tenant-Admins"
        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Creating Tenant Group : [$TenantAdminGroupName] in [$TenantUserOU]"
        New-ADGroup -Name $TenantAdminGroupName -SamAccountName $TenantAdminGroupName -GroupCategory Security -GroupScope Global -Path $TenantUserOU -Server $UserDomainDC

        $TenantUserGroupName =  "ADUG-$Tenant-Users"
        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Creating Tenant Group : [$TenantUserGroupName] in [$TenantUserOU]"
        New-ADGroup -Name $TenantUserGroupName -SamAccountName $TenantUserGroupName -GroupCategory Security -GroupScope Global -Path $TenantUserOU -Server $UserDomainDC

        # Creating ComputerDomain delegation group
        $TenantLocalAdminGroupName =  "$Tenant-LocalAdmins"
        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Creating Tenant Group : [$TenantLocalAdminGroupName] in [$TenantComputerOU]"
        New-ADGroup -Name $TenantLocalAdminGroupName -SamAccountName $TenantLocalAdminGroupName -GroupCategory Security -GroupScope DomainLocal -Path $TenantComputerOU -Server $ComputerDomainDC
               
        $TenantLocalUserGroupName =  "$Tenant-LocalUsers"
        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Creating Tenant Group : [$TenantLocalUserGroupName] in [$TenantComputerOU]"
        New-ADGroup -Name $TenantLocalUserGroupName -SamAccountName $TenantLocalUserGroupName -GroupCategory Security -GroupScope DomainLocal -Path $TenantComputerOU -Server $ComputerDomainDC

        $TenantComputerGroup = "$Tenant-Servers"
        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Creating Tenant Group : [$TenantComputerGroup] in [$TenantComputerOU]"
        New-ADGroup -Name $TenantComputerGroup -SamAccountName $TenantComputerGroup -GroupCategory Security -GroupScope DomainLocal -Path $TenantComputerOU -Server $ComputerDomainDC
        
        # Replicate
        Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": Replicating..."
        ReplicateNow
    
        # Adding delegation groups to Tenant Groups   

        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Launching Job : Adding Delegation Groups to [$TenantLocalAdminGroupName] in [$TenantComputerOU]"
        $ScriptBlock = {
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Job : Adding Delegation Groups to [$using:TenantLocalAdminGroupName] in [$using:TenantComputerOU]"

            Sleep -Seconds 10;

            $i = 0
            While ((!(Get-ADObject -LDAPFilter "SamAccountName=$using:TenantLocalAdminGroupName" -Server $using:ComputerDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor Gray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$using:TenantLocalAdminGroupName] [$using:ComputerDomainDC]"
                Sleep -Seconds 2
                $i++
            }

            $using:DefaultDelegationGroups | %{
                $GroupToAdd = Get-ADGroup $_ -Server $using:RootDomainDC
                Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding Delegation Group ["$GroupToAdd.DistinguishedName"] to [$using:TenantLocalAdminGroupName] in [$using:TenantComputerOU]"
                Add-ADGroupMember "CN=$using:TenantLocalAdminGroupName,$using:TenantComputerOU" -Members $GroupToAdd -Server $using:ComputerDomainDC
            }
        }
        $Jobs += Start-Job -ScriptBlock $ScriptBlock

        # Adding Tenant delegation groups and users to Tenant Groups
 
        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Launching Job : Adding [$TenantAdminGroupName] to [$TenantLocalAdminGroupName]"
    
        # Building ScriptBlock
        $ScriptBlock = {

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Job : Adding [$using:TenantAdminGroupName] to [$using:TenantLocalAdminGroupName]"
            
            Sleep -Seconds 10

            $i = 0
            While ((!(Get-ADObject -LDAPFilter "Name=$using:TenantAdminGroupName" -Server $using:UserDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$using:TenantAdminGroupName] [$using:UserDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            $i = 0

            While ((!(Get-ADObject -LDAPFilter "Name=$using:TenantLocalAdminGroupName" -Server $using:ComputerDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$using:TenantLocalAdminGroupName] [$using:ComputerDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            $i = 0

            While ((!(Get-ADObject -LDAPFilter "Name=$using:TenantUserName" -Server $using:UserDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$using:TenantUserName] [$using:UserDomainDC]"
                Sleep -Seconds 2
                $i++
            }

            $GroupToAdd = Get-ADGroup $using:TenantAdminGroupName -Server $using:UserDomainDC
            $Group = Get-ADGroup $using:TenantLocalAdminGroupName -Server $using:ComputerDomainDC

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding ["$GroupToAdd.DistinguishedName"] to ["$Group.DistinguishedName"]"
            Add-ADGroupMember "CN=$using:TenantLocalAdminGroupName,$using:TenantComputerOU" -Members $GroupToAdd -Server $using:ComputerDomainDC
            #Add-ADGroupMember "CN=$using:TenantLocalAdminGroupName,$using:TenantComputerOU" -Members "CN=$using:TenantAdminGroupName,$using:TenantUserOU" -Server $using:ComputerDomainDC

            # Adding Tenant Delegation Account
            $UserToAdd = Get-ADUser $using:TenantUserName -Server $using:UserDomainDC
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding ["$UserToAdd.DistinguishedName"] to ["$GroupToAdd.DistinguishedName"]"
        
            Add-ADGroupMember "CN=$using:TenantAdminGroupName,$using:TenantUserOU" -Members $UserToAdd -Server $using:UserDomainDC
        }

        # Starting Job
        $Jobs += Start-Job -ScriptBlock $ScriptBlock

        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Launching Job : Adding [$TenantUserGroupName] to [$TenantLocalUserGroupName]"

        # Building ScriptBlock
        $ScriptBlock = {
            param($TenantLocalUserGroupName, $TenantUserGroupName, $UserDomainFQDN, $ComputerDomainFQDN)

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Job : Adding [$TenantUserGroupName] to [$TenantLocalUserGroupName]"
        
            Sleep -Seconds 10;

            $i = 0
            
            While ((!(Get-ADObject -LDAPFilter "Name=$using:TenantUserGroupName" -Server $using:UserDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$TenantUserGroupName] [$using:UserDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            $i = 0

            While ((!(Get-ADObject -LDAPFilter "Name=$using:TenantLocalUserGroupName" -Server $using:ComputerDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$TenantLocalUserGroupName] [$using:ComputerDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            
            Sleep -Seconds 1

            $GroupToAdd = Get-ADGroup $TenantUserGroupName -Server $using:UserDomainDC
            $Group = Get-ADGroup $TenantLocalUserGroupName -Server $using:ComputerDomainDC
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding ["$GroupToAdd.DistinguishedName"] to ["$Group.DistinguishedName"]"
            Add-ADGroupMember "CN=$using:TenantLocalUserGroupName,$using:TenantComputerOU" -Members $GroupToAdd -Server $using:ComputerDomainDC
        }
        # Starting Job
        $Jobs += Start-Job -ScriptBlock $ScriptBlock -ArgumentList $TenantLocalUserGroupName,$TenantUserGroupName,$UserDomainFQDN,$ComputerDomain

        #Setting up acls

        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Launching Job : Modifyng permissions on Tenant OUs"

        $ScriptBlock = {
            param($TenantUserOU, $TenantComputerOU, $UserDomain, $ComputerDomain, $TenantAdminGroupName, $TenantUserGroupName, $TenantComputerGroup, $UserDomainFQDN, $ComputerDomainFQDN)

            Sleep -Seconds 10;

            $i = 0
            While ((!(Get-ADOrganizationalUnit $TenantUserOU -Server $using:UserDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$TenantUserOU] [$using:UserDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            $i = 0
            
            While ((!(Get-ADOrganizationalUnit $TenantComputerOU -Server $using:ComputerDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$TenantComputerOU] [$using:ComputerDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            $i = 0
            While ((!(Get-ADObject -LDAPFilter "Name=$using:TenantAdminGroupName" -Server $using:UserDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$TenantAdminGroupName] [$using:UserDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            $i = 0
            While ((!(Get-ADObject -LDAPFilter "Name=$using:TenantUserGroupName" -Server $using:UserDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$TenantUserGroupName] [$using:UserDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            $i = 0
            
            While ((!(Get-ADObject -LDAPFilter "Name=$using:TenantComputerGroup" -Server $using:ComputerDomainDC)) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$TenantComputerGroup] [$using:ComputerDomainDC]"
                Sleep -Seconds 2
                $i++
            }

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Job : Modifyng permissions on Tenant OUs"
            
            # Formating BaseOU for dsacls with DC name

            $ThisComputerDomainOUBase = "`\`\$using:ComputerDomainDC`\$TenantComputerOU"
            $ThisUserDomainOUBase = "`\`\$using:UserDomainDC`\$TenantUserOU"

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Removing LOLC permission for [Authenticated Users] on [$ThisUserDomainOUBase]"
            &dsacls $ThisUserDomainOUBase /R "Authenticated Users" | Out-Null
            &dsacls $ThisUserDomainOUBase /G "Authenticated Users:RCRP" | Out-Null

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Removing LOLC permission for [Authenticated Users] on [$ThisComputerDomainOUBase]"
            &dsacls $ThisComputerDomainOUBase /R "Authenticated Users" | Out-Null
            &dsacls $ThisComputerDomainOUBase /G "Authenticated Users:RCRP" | Out-Null

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding LOLC permission for [$UserDomain\$TenantAdminGroupName] on [$ThisUserDomainOUBase]"
            &dsacls $ThisUserDomainOUBase /G "$UserDomain`\$TenantAdminGroupName"":LOLC" | Out-Null
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding LOLC permission for [$UserDomain\$TenantUserGroupName] on [$ThisUserDomainOUBase]"
            &dsacls $ThisUserDomainOUBase /G "$UserDomain`\$TenantUserGroupName"":LOLC" | Out-Null
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding LOLC permission for [$ComputerDomain\$TenantComputerGroup] on [$ThisUserDomainOUBase]"
            &dsacls $ThisUserDomainOUBase /G "$ComputerDomain`\$TenantComputerGroup"":LOLC" | Out-Null

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding LOLC permission for [$UserDomain\$TenantAdminGroupName] on [$ThisComputerDomainOUBase]"
            &dsacls $ThisComputerDomainOUBase /G "$UserDomain`\$TenantAdminGroupName"":LOLC" | Out-Null
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding LOLC permission for [$UserDomain\$TenantUserGroupName] on [$ThisComputerDomainOUBase]"
            &dsacls $ThisComputerDomainOUBase /G "$UserDomain`\$TenantUserGroupName"":LOLC" | Out-Null
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding LOLC permission for [$ComputerDomain\$TenantComputerGroup] on [$ThisComputerDomainOUBase]"
            &dsacls $ThisComputerDomainOUBase /G "$ComputerDomain`\$TenantComputerGroup"":LOLC" | Out-Null

            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Adding LO permission for [$using:AD_JoinDomain_User] on [$ThisComputerDomainOUBase]"
            &dsacls $ThisComputerDomainOUBase /G "$using:AD_JoinDomain_User"":LO" | Out-Null
        }

        
        # Starting Job
        $Jobs += Start-Job -ScriptBlock $ScriptBlock -ArgumentList( $TenantUserOU, $TenantComputerOU, $UserDomain, $ComputerDomain, $TenantAdminGroupName, $TenantUserGroupName, $TenantComputerGroup, $UserDomainFQDN, $ComputerDomainFQDN )

        # Creating GPO and GPO links

        $GPOName = "GPO-$TenantGUID-MGMT"
    
        If (!(Get-GPO -Name $GPOName -Domain $ComputerDomainFQDN -ErrorAction SilentlyContinue)) {
            #Copying GPO from template
            $GPO = Copy-GPO -SourceDomain $ComputerDomainFQDN -SourceName  "GPO-Template-MGMT" -TargetName $GPOName -TargetDomain $ComputerDomainFQDN
        
            ReplicateNow
        }
        Else {
            #Using existing GPO
            $GPO = Get-GPO -Name $GPOName -Domain $ComputerDomainFQDN
        }

        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Launching Job : Linking GPO [$GPOName] to Tenant OU [$TenantComputerOU]"

        $ScriptBlock = {
            param($GPOName, $TenantComputerOU, $ComputerDomainFQDN)
            Sleep -Seconds 10

            $i = 0
            While ((!(Get-GPO -Name $using:GPOName -Domain $using:ComputerDomainFQDN)) -and ($i -le 30)) {
                Write-Host -ForegroundColor Gray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for GPO [$using:GPOName] [$using:ComputerDomainFQDN]"
                Sleep -Seconds 2
                $i++
            }

            $GPO = Get-GPO -Name $using:GPOName -Domain $using:ComputerDomainFQDN
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Job : Linking GPO ["$GPO.DisplayName"] to Tenant OU [$using:TenantComputerOU]"
            $GPO | New-GPLink -Target $TenantComputerOU -Domain $using:ComputerDomainFQDN -Server $using:ComputerDomainDC | Out-Null

        }
        
        # Starting Job
        
        $Jobs += Start-Job -ScriptBlock $ScriptBlock -ArgumentList( $GPOName,$TenantComputerOU,$ComputerDomainFQDN)

        $GPOPath = "\\"+$GPO.DomainName+"\SYSVOL\"+$GPO.DomainName+"\Policies\{"+$GPO.Id+"}"
        $GptTmplFile = $GPOPath+"\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"

        # Building ScriptBlock
        $ScriptBlock = {
            param($ComputerDomainFQDN, $TenantLocalAdminGroupName, $TenantLocalUserGroupName, $GPOPath, $GptTmplFile, $ScriptPath )
            
            ."$ScriptPath\Global.ps1"

            Sleep -Seconds 2;
        
            $i = 0
            While (!(Get-ADGroup $using:TenantLocalAdminGroupName -Server $using:ComputerDomainDC) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$using:TenantLocalAdminGroupName] [$using:ComputerDomainDC]"
                Sleep -Seconds 2
                $i++
            }
            $i = 0
            While (!(Get-ADGroup $using:TenantLocalUserGroupName -Server $using:ComputerDomainDC) -and ($i -le 30)) {
                Write-Host -ForegroundColor DarkGray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for group [$using:TenantLocalUserGroupName] [$using:ComputerDomainDC]"
                Sleep -Seconds 2
                $i++
            } 
            
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Job : GPO Customisation"

            # Getting SID
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Getting SIDs"
            $DomainAdminsSID = (Get-ADGroup "Domain Admins" -Server $using:ComputerDomainDC).SID.Value
            $TenantLocalAdminsSID = (Get-ADGroup $TenantLocalAdminGroupName -Server $using:ComputerDomainDC).SID.Value
            $TenantLocalUsersSID = (Get-ADGroup $TenantLocalUserGroupName -Server $using:ComputerDomainDC).SID.Value
        
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": DomainAdminsSID [$DomainAdminsSID]"
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": TenantLocalAdminsSID [$TenantLocalAdminsSID]"
            Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": TenantLocalUsersSID [$TenantLocalUsersSID]"

            $i = 0
            While (!(Test-Path($GptTmplFile)) -and ($i -le 30)) {
                Write-Host -ForegroundColor Gray (Get-Date -Format 'HH:mm:ss') ": Job : Waiting for GPO file [$GptTmplFile]"
                Sleep -Seconds 2
                $i++
            }

            If ( Test-Path ($GptTmplFile) ) {
                #$Content = Get-Content $GptTmplFile
                Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Getting GPO content"
                $Content = Get-IniContent $GptTmplFile

                Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Modifying GPO content"
                $Content.'Group Membership'.'*S-1-5-32-544__Members' = "*" + $DomainAdminsSID + ",*" + $TenantLocalAdminsSID
                $Content.'Group Membership'.'*S-1-5-32-545__Members' = "*S-1-5-4" + ",*" + $TenantLocalUsersSID 
            
                Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Writing new GPO content :"

                $Content.'Group Membership'.GetEnumerator() | Sort Name | %{ Write-Host -ForegroundColor Gray $_.Name "=" $_.Value }

                Move-Item $GptTmplFile ($GptTmplFile + ".old")
                #Remove-Item $GptTmplFile -Force -Confirm:$false
                Out-IniFile -InputObject $Content -FilePath $GptTmplFile

            }
            Else {
                Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": GPO File not found"
                Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": $GptTmplFile"
            }
        }

        # Starting Job
        Write-Host -ForegroundColor White (Get-Date -Format 'HH:mm:ss') ": Launching Job : GPO Customisation"

        $Jobs += Start-Job -ScriptBlock $ScriptBlock -ArgumentList( $ComputerDomainFQDN,$TenantLocalAdminGroupName,$TenantLocalUserGroupName,$GPOPath, $GptTmplFile, $ScriptPath)
    
        $xmlWriter.WriteEndElement()
    
        $xmlWriter.WriteEndDocument()
        $xmlWriter.Flush()
        $xmlWriter.Close()

    }
    Else {
        Write-Host (Get-Date -Format 'HH:mm:ss') ": Tenant [$Tenant] already exists -> Exiting script"

    }
}
Else {
    Write-Host -ForegroundColor Yellow (Get-Date -Format 'HH:mm:ss') ": Please specify a Tenant name"
}

If ($Jobs) {

    Write-Host (Get-Date -Format 'HH:mm:ss') ": Current Jobs : "

    $Jobs | Ft -AutoSize

    Write-Host (Get-Date -Format 'HH:mm:ss') ": Waiting for jobs to complete..."

    $Jobs | Wait-Job 

    Write-Host (Get-Date -Format 'HH:mm:ss') ": All jobs are completed "

    $Jobs | Get-Job -HasMoreData $true | Receive-Job

    # Cleaning Up

    Get-Job -HasMoreData $false -State Completed | Remove-Job

}



Stop-Transcript
