
Param (
    [parameter(Mandatory=$true)][string]$Tenant
)

#
# Delete-Tenant.ps1
# Multi Tenant Active Directory - Tenant Deletion Script
#
# Auth : Joris DECOMBE
# Usage : Delete-Tenant.ps1 -Tenant <tenant_name>
#


#
# Modules
#

Import-Module ActiveDirectory

#
# Variables
#

$ScriptPath = "C:\Joris\Scripts\"

#
# Global Variables and Functions Import
#

$GlobalFile = $ScriptPath+"Global.ps1"

$script:ClientName = $env:CLIENTNAME
$script:CurrentUser = $env:USERNAME

$Jobs = @()

#
# Log
#

Start-Transcript $LogFile
Write-Host "Script Launched by $CurrentUser from $ClientName"

#
# Functions Import
#

Write-Host "DotSourcing $ScriptPath\Global.ps1"

."$ScriptPath\Global.ps1"

#
# Go
#


If ($Tenant) {

    $TenantPath = "$ScriptPath\Tenants\$Tenant"

    $xmlfile = ($TenantPath | Get-ChildItem -Filter $xmlFileName | Select -First 1).FullName
    $xml = New-Object -TypeName XML
    $xml.Load($xmlfile)
    If ($xml.Tenant) {
        If ($xml.Tenant.guid) {
            $TenantGUID = $xml.Tenant.guid
        }
        Else {
            # Something wrong, no guid for this client
            Write-Host -ForegroundColor Red (Get-Date -Format 'HH:mm:ss') ": Error : No GUID found for Tenant [$Tenant]"            
        }
    }

    $TenantComputerOU = "OU=$TenantGUID,$ComputerDomainOU"
    $TenantUserOU = "OU=$TenantGUID,$UserDomainOU"

    #
    # Moving Directory
    #

    If (!(Test-Path "$ScriptPath\Deleted" -ErrorAction SilentlyContinue)) {
        New-Item -Path "$ScriptPath" -ItemType Directory -Name "Deleted" -Confirm:$false | Out-Null
    }

    $datetime = (get-date -Format yyyyMMdd-HHmmss)
    If (Test-Path $TenantPath -ErrorAction SilentlyContinue) {
        Write-Host -ForegroundColor White "Moving Directory [$TenantPath}"
        Move-Item -Path $TenantPath -Destination ("$ScriptPath\Deleted\$Tenant"+"-deleted-$datetime") -Confirm:$false | Out-Null
    }
    
    #
    # Removing OU on User Domain
    #

    If (Get-ADOrganizationalUnit $TenantUserOU -Server $UserDomainFQDN -ErrorAction SilentlyContinue) {
        Write-Host -ForegroundColor White "Removing OU [$TenantUserOU}"
        Set-ADOrganizationalUnit $TenantUserOU -ProtectedFromAccidentalDeletion $False -Server $UserDomainFQDN
        Remove-ADOrganizationalUnit $TenantUserOU -Server $UserDomainFQDN -Recursive -Confirm:$false

    }

    #
    # Removing OU on Computer Domain
    #

    If (Get-ADOrganizationalUnit $TenantComputerOU -Server $ComputerDomainFQDN -ErrorAction SilentlyContinue) {
        Write-Host -ForegroundColor White "Removing OU [$TenantComputerOU}"
        Set-ADOrganizationalUnit $TenantComputerOU -ProtectedFromAccidentalDeletion $False -Server $ComputerDomainFQDN
        Remove-ADOrganizationalUnit $TenantComputerOU -Server $ComputerDomainFQDN -Recursive -Confirm:$false
    }

    #
    # Removing GPO
    #

    $GPOName = "GPO-$TenantGUID-MGMT"
    Get-GPO -Name $GPOName -Domain $ComputerDomainFQDN | Remove-GPO -Domain $ComputerDomainFQDN

    Stop-Transcript
}