# Add to Trusted list example

$ToAdd = 192.168.1.1

$curValue = (get-item wsman:\localhost\Client\TrustedHosts).value

set-item wsman:\localhost\Client\TrustedHosts -value "$curValue, $ToAdd"