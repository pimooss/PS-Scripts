# 
# Openstack Windows Image Creation
# 
#   . Creates Openstack images
#
# auth : Joris DECOMBE
# 

$OS_Session_Init_Script = "init_venv_openstack.ps1"
$Image_Path = "E:\Images\OpenStack"

$BuildDate = (Get-date -Format "dd-MM-yyyy").ToString()

$images = @()
$images += "windows-2016-en-std"
$images += "windows-2016-fr-std"
$images += "windows-2012r2-en-std"
$images += "windows-2012r2-fr-std"

$OS_Command_ListImage = @'
openstack image list --public -f json
'@

$OS_Command_GetOldImageInfo = @'
openstack image show %OLD_IMAGE_ID% -f json
'@

$OS_Command_Rotate_Old_Template = @'
openstack image set --private %OLD_IMAGE_ID%
openstack image set --name %OLD_IMAGE_NAME% %OLD_IMAGE_ID%
'@

$OS_Command_Upload_Template = @'
openstack image create --container-format bare --disk-format vhd --file %VHDX_PATH% %IMAGE_NAME% -f json --private
'@

$OS_Command_Config_Template = @'
openstack image set --property architecture=x86_64 %IMAGE_ID%
openstack image set --property hypervisor_type=qemu %IMAGE_ID%
openstack image set --property os_distro=windows %IMAGE_ID%
openstack image set --property os_version=%OS_VERSION% %IMAGE_ID%
openstack image set --property os_type=windows %IMAGE_ID%
openstack image set --property build_date=%BUILD_DATE% %IMAGE_ID%
openstack image set --property jn_os_label=%IMAGE_OSLABEL% %IMAGE_ID%
openstack image set --property hw_qemu_guest_agent=yes %IMAGE_ID%
openstack image set --property os_require_quiesce=yes %IMAGE_ID%
openstack image set --min-ram 2048 %IMAGE_ID%
openstack image set --min-disk 20 %IMAGE_ID%
'@

$OS_Command_Template_SetPublic = @'
openstack image set --public %IMAGE_ID%
openstack image set --name %IMAGE_NAME% %IMAGE_ID%
'@


If (!(Test-Path ($Remote_Drive+":\"))) {
    Write-Host -ForegroundColor Cyan "Mounting image remote path"
    New-PSDrive -Name $Remote_Drive -PSProvider FileSystem -Root $Image_Path -Persist
}

$LocalImages = Get-ChildItem ($Remote_Drive+":\") -Filter "*.vhdx"

Write-Host -ForegroundColor Cyan "Init openstack env"
Write-Host -ForegroundColor Cyan $env:userprofile"\"$OS_Session_Init_Script
& ($env:userprofile + "\" + $OS_Session_Init_Script)

$images | %{
    $This_VHDx_Name = ($_ -replace "windows-","")+".vhdx"
    $This_VHDx_Image_Path = $Remote_Drive + ":\" + $This_VHDx_Name

    $namearray = $_ -split "-"
    
    Switch ($namearray[1]) {
        "2012r2" {
            $OSVersion = "6.3"
        }
        "2016" {
            $OSVersion = "10.0"
        }
    }

    If (Test-Path ($LocalImages | Where Name -like $This_VHDx_Name ).FullName) {
        $This_Image_Name = $_
        
        If (Test-Path $This_VHDx_Image_Path) {
            Write-Host -ForegroundColor Gray "Getting Old Image ID (Image Name : $This_Image_Name)"
            $This_ListImages = Invoke-Expression $OS_Command_ListImage | ConvertFrom-Json
            $This_OldImage = $This_ListImages | Where Status -eq "active" | Where Name -eq $This_Image_Name
            If ($This_OldImage) {
                $This_OldImageID = $This_OldImage.ID
            }
            Else {
                $This_OldImageID = $false
                Write-Host -ForegroundColor Yellow "$This_Image_Name ID not found -> Skipping rotation"
            }
            
            # Getting Old Image Info
            If ($This_OldImageID) {
                Write-Host -ForegroundColor Gray "Getting Old Image Info (Image ID : $This_OldImageID)"
                $This_Command_GetOldImageInfo = $OS_Command_GetOldImageInfo -replace "%OLD_IMAGE_ID%",$This_OldImageID
                $This_OldImageInfo = (Invoke-Expression $This_Command_GetOldImageInfo ) | ConvertFrom-Json
                $This_OldImageProperties = $This_OldImageInfo.properties -replace ", ","`n" | ConvertFrom-StringData
                $This_OldImage_BuildDate = $This_OldImageProperties.build_date -replace "'",""
                
                If ($This_OldImage_BuildDate) {
                    
                    # Uploading new template
                    $This_Image_TempName = "$This_Image_Name-$BuildDate"

                    Write-Host -ForegroundColor Cyan "Uploading new template $This_VHDx_Name (Image Name : $This_Image_TempName)"
                    $This_Command_Upload = $OS_Command_Upload_Template -replace "%IMAGE_NAME%",$This_Image_TempName
                    $This_Command_Upload = $This_Command_Upload -replace "%VHDX_PATH%",$This_VHDx_Image_Path
                    Write-Host -ForegroundColor Green $This_Command_Upload
                    $This_Upload_Image = Invoke-Expression $This_Command_Upload | ConvertFrom-Json
                    $This_Image_ID = $This_Upload_Image.ID
                    
                    If ($This_Image_ID) {
                        # Configuring new template
                        Write-Host -ForegroundColor Cyan "Configuring new template $This_VHDx_Name (Image Name : $This_Image_Name)"
                        
                        $This_Command_Config_Template = $OS_Command_Config_Template -replace "%IMAGE_NAME%",$This_Image_TempName
                        $This_Command_Config_Template = $This_Command_Config_Template -replace "%IMAGE_ID%",$This_Image_ID
                        $This_Command_Config_Template = $This_Command_Config_Template -replace "%VHDX_PATH%",$This_VHDx_Image_Path
                        $This_Command_Config_Template = $This_Command_Config_Template -replace "%BUILD_DATE%",$BuildDate
                        $This_Command_Config_Template = $This_Command_Config_Template -replace "%IMAGE_OSLABEL%",$This_Image_Name
                        $This_Command_Config_Template = $This_Command_Config_Template -replace "%OS_VERSION%",$OSVersion
                        Write-Host -ForegroundColor Green $This_Command_Config_Template
                        Invoke-Expression $This_Command_Config_Template

                        # Testing new uploaded Template

                        # Rotating new template and make public
                        Write-Host -ForegroundColor Cyan "Rotating New image and make it Public (Image Name : $This_Image_Name | ID : $This_Image_ID)"
                        $This_Command_Rotate_New_Template = $OS_Command_Template_SetPublic -replace "%IMAGE_NAME%",$This_Image_Name
                        $This_Command_Rotate_New_Template = $This_Command_Rotate_New_Template -replace "%IMAGE_ID%",$This_Image_ID
                        Write-Host -ForegroundColor Green $This_Command_Config_Template
                        Invoke-Expression $This_Command_Rotate_Old_Template

                        # Rotating Old Template and making it private
                        $This_OldImage_Name = "$This_Image_Name-$This_OldImage_BuildDate"
                        Write-Host -ForegroundColor Cyan "Rotating Old image and make it private (Old Image Name : $This_OldImage_Name | Old ID : $This_OldImageID)"
                        $This_Command_Rotate_Old_Template = $OS_Command_Rotate_Old_Template -replace "%OLD_IMAGE_ID%",$This_OldImageID
                        $This_Command_Rotate_Old_Template = $This_Command_Rotate_Old_Template -replace "%OLD_IMAGE_NAME%",$This_OldImage_Name
                        Write-Host -ForegroundColor Green $This_Command_Rotate_Old_Template
                        Invoke-Expression $This_Command_Rotate_Old_Template
                        

                    }
                    Else {
                        Write-Host -ForegroundColor Red "$This_Image_Name Uploaded image ID not found -> Skipping rotation"
                    }

                    
                }
                Else {
                    Write-Host -ForegroundColor Red "$This_Image_Name Info not found -> Skipping rotation and upload"
                }
                
            }
            
        }
        Else {
            Write-Host "Couldn't find $This_VHDx_Image_Path"
        }

    }
    Else {
        Write-Host -ForegroundColor Red "No image file found for $_"
    }
}

