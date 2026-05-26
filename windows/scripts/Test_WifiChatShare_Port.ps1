param(
  [string] $PeerIp
)

if ([string]::IsNullOrWhiteSpace($PeerIp)) {
  $PeerIp = Read-Host 'Enter the peer Ping IP shown in Wifi Chat Share'
}

if ([string]::IsNullOrWhiteSpace($PeerIp)) {
  Write-Error 'No peer IP address entered.'
  Read-Host 'Press Enter to close'
  exit 1
}

Write-Host "Testing TCP port 45873 on $PeerIp..."
Test-NetConnection -ComputerName $PeerIp -Port 45873
Read-Host 'Press Enter to close'
