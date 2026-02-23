$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"})[0].IPAddress
Write-Host "Nombre: $(hostname)"
Write-Host "IP:   $ip"
Write-Host "Disco: $(( [math]::Round((Get-Volume C).SizeRemaining /1GB, 2))) GB "