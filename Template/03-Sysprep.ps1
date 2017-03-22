#
#   Windows Server template automation - Phase 3
#

New-Item C:/Windows/Panther/Unattend/ -ItemType Directory
If ( (gwmi Win32_OperatingSystem -ErrorAction Continue).OsLanguage -eq 1033 ) {
    Copy-Item .\postunattend.xml C:/Windows/Panther/Unattend/unattend.xml
}
Else {
    Copy-Item .\postunattend_fr.xml C:/Windows/Panther/Unattend/unattend.xml
}

Remove-Item .\*.ps1 -Force -Confirm:$false
Remove-Item .\*.xml -Force -Confirm:$false

C:/windows/system32/sysprep/sysprep.exe /generalize /oobe /unattend:C:/Windows/Panther/Unattend/unattend.xml /quiet /shutdown
