# 
# Openstack Windows Image Creation
#
# /!\/!\/!\ This step is optional /!\/!\/!\ 
# Openstack is able to manage VHDx file, but if QCOW2 format is needed :
# This script connects to a linux box, with kvm installed 
# Installed package : qemu-kvm qemu-img virt-manager libvirt libvirt-python libvirt-client virt-install virt-viewer bridge-utils
#
# Auth : Joris DECOMBE

Install-Module Posh-SSH # Once
Import-Module Posh-SSH

$TargetHost = "tmplmaker.corp" #linux server with sshd enabled

$vhdximgdir = "C:\Images\OpenStack\VHDX"
$qcow2imgdir = "C:\Images\OpenStack\QCOW2"

$remote_workingdir = "/opt"
$remote_user = "root"
$remote_password = "P@ssw0rd"

If (!(Test-Path $qcow2imgdir)) {New-Item $qcow2imgdir -ItemType Directory}

$Images = Get-ChildItem $vhdximgdir -Filter "*.vhdx"  | select -Last 1

$SecStr = ConvertTo-SecureString -String $remote_password -AsPlainText -Force
$Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $remote_user,$SecStr

$secpas = $Credentials.Password

$sshSession = New-SSHSession -ComputerName $TargetHost -Credential $Credentials -AcceptKey -Force

$user = Invoke-SSHCommand -SSHSession $sshSession -Command {whoami}
$SSHUserName = $user.Output | Out-String
$SSHUserName = $SSHUserName.Trim()

If ($remote_workingdir -ne "/" -and $remote_workingdir -ne "" -and $user) {

    $sftpSession = New-SFTPSession -ComputerName $TargetHost -Credential $Credentials -AcceptKey -Force
    
    $stream = $sshSession.Session.CreateShellStream("PS-SSH", 0, 0, 0, 0, 100)

    ForEach ($Image In $Images) {
        
        $vhdx = $($Image.Name)
        $qcow2 = $vhdx -replace "vhdx","qcow2"

        Write-Host $vhdx '->' $qcow2

        Write-Host "Uploading $($Image.FullName) to $remote_workingdir"
        Set-SFTPFile -SFTPSession $sftpSession -LocalFile $Image.FullName -RemotePath $remote_workingdir -Overwrite

        $stream.WriteLine("qemu-img convert -p -O qcow2 $remote_workingdir/$vhdx $remote_workingdir/$qcow2 ")
        $stream.Expect(']#')
        $stream.Read()
        
        $stream.WriteLine("rm -f $remote_workingdir/$vhdx")
        $stream.Expect(']#')
        $stream.Read()

        Get-SFTPFile -SFTPSession $sftpSession -RemoteFile "$remote_workingdir/$qcow2" -LocalPath $qcow2imgdir -Overwrite

        $stream.WriteLine("rm -f $remote_workingdir/$qcow2")
        $stream.Expect(']#')

    }
    
    Remove-SFTPSession $sftpSession 
}

Remove-SSHSession $sshSession
