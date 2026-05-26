$app = Join-Path $PSScriptRoot 'wifi_chat_share.exe'

if (-not (Test-Path $app)) {
  Write-Error "wifi_chat_share.exe was not found beside this script."
  exit 1
}

$rules = @(
  @{ Name = 'Wifi Chat Share TCP In'; Protocol = 'TCP'; LocalPort = '45873' },
  @{ Name = 'Wifi Chat Share UDP Discovery In'; Protocol = 'UDP'; LocalPort = '45872' }
)

foreach ($rule in $rules) {
  Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule `
    -DisplayName $rule.Name `
    -Direction Inbound `
    -Action Allow `
    -Profile Any `
    -Program $app `
    -Protocol $rule.Protocol `
    -LocalPort $rule.LocalPort | Out-Null
}

Write-Host 'Firewall rules added for Wifi Chat Share on all network profiles.'
Write-Host 'Keep Wifi Chat Share open on both PCs while testing chat and file transfer.'
Read-Host 'Press Enter to close'
