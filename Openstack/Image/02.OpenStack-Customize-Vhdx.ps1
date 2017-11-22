# 
# Openstack Windows Image Creation
#
#   . Inject qemu, cloudinit agent and unattend.xml file for first boot install
# 
# Auth : Joris DECOMBE

$Images = Get-ChildItem "C:\Images\OpenStack\" -Filter "*.vhdx"

$ToInjectPath = ".\ToInject"

$InstallerPath = "\Windows\Temp"
$UnattendPath = "\Windows\Panther\unattend.xml"

ForEach ($imgfile In $Images) {
    $namearray = ($imgfile.Name -replace ".vhdx","") -split "-"

    Switch ($namearray[1]) {
        "en" {$UnattendSource = "$ToInjectPath\Unattend-en_fr.xml"}
        "fr" {$UnattendSource = "$ToInjectPath\Unattend-fr_fr.xml"}
    }

    Switch ($namearray[0]) {
        "2012r2" {
            Switch ($namearray[2]) {
                "std"   { $key = "" } #<- Insert your productkey here
                "dc"    { $key = "" } #<- Insert your productkey here
            }
        }
        "2016" {
            Switch ($namearray[2]) {
                "std"   { $key = "" } #<- Insert your productkey here
                "dc"    { $key = "" } #<- Insert your productkey here
            }
        }
    }
    
    Write-Host -ForegroundColor Cyan "Processing $($imgfile.FullName)"

    $Mount = Mount-DiskImage $imgfile.FullName -StorageType VHDX -Access ReadWrite -PassThru

    $MountedDriveLetter = (Get-Disk | Where Location -eq $imgfile.FullName | Get-Partition).DriveLetter + ":"
    
    If (Test-Path $MountedDriveLetter) {

        New-Item -Path (Split-Path ($MountedDriveLetter + "" + $UnattendPath)) -ItemType Directory -Force -Confirm:$false | Out-Null
        New-Item -Path ($MountedDriveLetter + "" + $InstallerPath) -ItemType Directory -Force -Confirm:$false | Out-Null

        $src = $ToInjectPath + "\CloudbaseInit.msi"
        $dst = $MountedDriveLetter + "" + $InstallerPath + "\CloudbaseInit.msi"
        Copy-Item $src $dst -Force -Confirm:$false

        $src = $ToInjectPath + "\qemu-ga-x64.msi"
        $dst = $MountedDriveLetter + "" + $InstallerPath + "\qemu-ga-x64.msi"
        Copy-Item $src $dst -Force -Confirm:$false

        $src = $UnattendSource
        $dst = $MountedDriveLetter + "" + $UnattendPath
        $xmlContent = (Get-Content $src) -replace "%PRODUCTKEY%",$key
        $xmlContent | Set-Content $dst -Force -Confirm:$false
                
        If (Test-Path "$MountedDriveLetter\Convert-WindowsImageInfo.txt") {
            Remove-Item "$MountedDriveLetter\Convert-WindowsImageInfo.txt" -Force -Confirm:$false | Out-Null
        }
    }

    Dismount-DiskImage $imgfile.FullName
    Write-Host -ForegroundColor Green "Processing $($imgfile.FullName) : OK"

}
