# 
# Openstack Windows Image Creation
# 
#   . Creates vhdx ready for Openstack from stock wim (extracted from iso)
#
# auth : Joris DECOMBE
# 
# Thanks to Microsoft's Convert-WindowsImage.ps1
# 

Set-Location "$env:userprofile\Documents"
. .\Convert-WindowsImage.ps1

$DriverPath = ".\drivers\amd64\" # From qemu
$imgPath = "c:\Images\Stock" # Path to stock wim image
$OutPath = "c:\Images\OpenStack\"

# Name your wim as the following : version_lang.wim
$stockImages = @()
$stockImages += "$imgPath\2016_en.wim"
$stockImages += "$imgPath\2016_fr.wim"
$stockImages += "$imgPath\2012r2_en.wim"
$stockImages += "$imgPath\2012r2_fr.wim"

$editions = @()
$editions += "ServerDataCenter"
$editions += "ServerDataCenterCore"
$editions += "ServerStandard"
$editions += "ServerStandardCore"

Foreach ($image In $stockImages) {
    Foreach ($edition In $editions) {

        $os = ((split-path $image -Leaf) -split "_" )[0]
        $lang = ((split-path $image -Leaf) -split "_" )[1] -replace ".wim",""

        Switch ($os) {
            "2012r2" { $ThisDriverPath = $DriverPath + "\Win2012R2" }
            "2016" { $ThisDriverPath = $DriverPath + "\Win2016" ; }
        }

        Switch ($edition) {
            "ServerStandard" { $vhdname = "$os-$lang-std" }
            "ServerStandardCore" { $vhdname = "$os-$lang-std-core" }
            "ServerDataCenter" { $vhdname = "$os-$lang-dc" }
            "ServerDataCenterCore" { $vhdname = "$os-$lang-dc-core" }
        }

        $vhdpath = $OutPath + "\" + $vhdname + ".vhdx"
        
        $ConvertWindowsImageParam = @{
            SourcePath          = $image
            RemoteDesktopEnable = $True
            Passthru            = $True
            BCDinVHD            = "VirtualMachine"
            VHDPartitionStyle   = "MBR"
            VHDFormat           = "VHDX"
            SizeBytes           = 20GB
            Driver              = $ThisDriverPath
            VHDPath             = $vhdpath
            Edition             = @($edition)

        }

        Convert-WindowsImage @ConvertWindowsImageParam -Verbose
    }
}