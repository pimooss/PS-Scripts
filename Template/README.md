Windows Server template automation.

Theses scripts are intended to vanilla install of a windows server.

How does it work?

- Install Windows Server from ISO
- powershell -ExecutionPolicy Bypass 01-Init.ps1
- Server will reboot multiple times (updates)
- powershell -ExecutionPolicy Bypass 02-Clean.ps1
- Shutdown the VM
- The VM is ready for capture

What does it do ?

01-Init.ps1
- Enable RemoteDesktop
- Setup WinRM
- Set Culture and Keyboard to FR-fr
- Set Windows Update to Auto Update
- Install .NET3.5 (from source, since the feature is not present on the default install) 
- Enable Firewall rules to respond to ping ipv4 and ipv6
- Install SNMP
- Remove Pagefile (for capture)
- Launchd win-updates.ps1 script (Auto update + reboot as long as it's needed)

02-Clean.ps1
- Remove .NET3.5
- Clean SxS (Dism /Cleanup-Image etc...)
- Clean temp folder
- Defrag (to get contigous files)
- Zero out empty space
- Setup pagefile (Recreate after sysprep)
- Clear Eventlogs