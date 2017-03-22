

#Semi-Secure : Read-Host "Enter Password" -AsSecureString | ConvertFrom-SecureString -Key (1..16) | Out-Host


$key = Get-Content "drive:\Scheduler\Secure\AES.key"
Read-Host "Enter Password" -AsSecureString | ConvertFrom-SecureString -Key $key | Out-Host