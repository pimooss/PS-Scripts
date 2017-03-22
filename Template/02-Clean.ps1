#
#   Windows Server template automation - Phase 2
#


# Remove .Net3.5
Write-Host "Removing .Net3.5"
Uninstall-WindowsFeature NET-Framework-Core

# Cleaning SxS...
Write-Host "Cleaning SxS..."
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

$tempfolders = @(  "C:\Users\*\Appdata\Local\Temp\*" )

# Cleaning Temp
Write-Host "Cleaning Temp..."
@(
    "$env:localappdata\Nuget",
    "$env:localappdata\temp\*",
    "$env:windir\logs",
    "$env:windir\panther",
    "$env:windir\Temp\*",
    "$env:windir\winsxs\manifestcache",
    "$env:windir\Prefetch\*",
    "C:\Documents and Settings\*\Local Settings\temp\*",
    "C:\Users\*\Appdata\Local\Temp\*"
) | % {
        if(Test-Path $_) {
            Write-Host "Removing $_"
            Takeown /d Y /R /f $_
            Icacls $_ /GRANT:r administrators:F /T /c /q  2>&1 | Out-Null
            Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$False | Out-Null
        }
    }

# Defragging...
Write-Host "Defragging..."
Optimize-Volume -DriveLetter C

# 0ing out empty space...
Write-Host "Zer0ing empty space..."
mkdir $env:temp
wget http://download.sysinternals.com/files/SDelete.zip -OutFile sdelete.zip
[System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem")
[System.IO.Compression.ZipFile]::ExtractToDirectory("sdelete.zip", ".") 
./sdelete.exe /accepteula -z c:

Remove-Item ./sdelete.zip -Force -Confirm:$false
Remove-Item ./sdelete64.exe -Force -Confirm:$false
Remove-Item ./sdelete.exe -Force -Confirm:$false
Remove-Item ./eula.txt -Force -Confirm:$false

# Recreate Pagefile after sysprep
$System = GWMI Win32_ComputerSystem -EnableAllPrivileges
$System.AutomaticManagedPagefile = $true
$System.Put()


# Clear event logs

Get-Eventlog -list | % {Clear-Eventlog -log $_.Log -Confirm:$False}

