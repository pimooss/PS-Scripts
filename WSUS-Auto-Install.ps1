#
# WSUS Conf
#

$TargetDrive = "D:"

# Install Features

Install-WindowsFeature -Name UpdateServices -IncludeManagementTools
Install-WindowsFeature -Name BITS -IncludeManagementTools

# Post Install

New-Item -Path $TargetDrive -Name WSUS -ItemType Directory
$WsusUtil = "C:\Program Files\Update Services\Tools\wsusutil.exe"
&$WsusUtil postinstall CONTENT_DIR=$TargetDrive\WSUS

# Get WSUS Server Object

$wsus = Get-WSUSServer

# Connect to WSUS server configuration

$wsusConfig = $wsus.GetConfiguration()

# Set to download updates from Microsoft Updates

Set-WsusServerSynchronization –SyncFromMU

# Set Update Languages to French/English and save configuration settings

$wsusConfig.AllUpdateLanguagesEnabled = $false
$wsusConfig.SetEnabledUpdateLanguages("en")
$wsusConfig.SetEnabledUpdateLanguages("fr")   
$wsusConfig.Save()

# Get WSUS Subscription and perform initial synchronization to get latest categories

$subscription = $wsus.GetSubscription()
$subscription.StartSynchronizationForCategoryOnly()

While ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {

    Write-Host "." -NoNewline
    Start-Sleep -Seconds 5

}

Write-Host "Sync is done."

# Configure the Platforms that we want WSUS to receive updates

Get-WsusProduct | where-Object {

    $_.Product.Title -in (
    'Windows Server 2008 R2',
    'Windows Server 2012 R2')
} | Set-WsusProduct

# Configure the Classifications

Get-WsusClassification | Where-Object {
    $_.Classification.Title -in (
    'Update Rollups',
    'Security Updates',
    'Critical Updates',
    'Service Packs',
    'Updates')
} | Set-WsusClassification

# Configure Synchronizations

$subscription.SynchronizeAutomatically = $true

# Set synchronization scheduled for midnight each night

$subscription.SynchronizeAutomaticallyTimeOfDay = (New-TimeSpan -Hours 0)
$subscription.NumberOfSynchronizationsPerDay = 1
$subscription.Save()

# Kick off a synchronization

$subscription.StartSynchronization()

# Tada