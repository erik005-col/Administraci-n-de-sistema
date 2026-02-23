function validar-ip {
    param ([string]$IP)
    if ($IP -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') { return $false }
    $octetos = $IP.Split('.')
    $primero = [int]$octetos[0]

    if ($primero -eq 0) {
        Write-Host "Error! IPs que inician con 0 son reservadas." -ForegroundColor Red
        return $false
    }
    if ($primero -eq 127) {
        Write-Host "Error! Rango 127.x.x.x es loopback." -ForegroundColor Red
        return $false
    }
    if ($primero -ge 224) {
        Write-Host "Error! Rango reservado o experimental." -ForegroundColor Red
        return $false
    }
    foreach ($o in $octetos) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false }
    }
    return $true
}

function pedir-ip {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = Read-Host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }
        $esValida = validar-ip $ip
        if (-not $esValida) { Write-Host "Intente de nuevo..." -ForegroundColor Yellow }
    } while (-not $esValida)
    return $ip
}

function ip-a-entero($ip) {
    $o = $ip.Split('.')
    return ([int64]$o[0] -shl 24) -bor ([int64]$o[1] -shl 16) -bor ([int64]$o[2] -shl 8) -bor [int64]$o[3]
}

function Cambiar-IP-Servidor {
    param($NuevaIP, $Mascara)
    $adaptador = Get-NetAdapter -Name $script:NombreInterfaz -ErrorAction SilentlyContinue
    if (-not $adaptador) {
        Write-Host "Error: No se encontro el adaptador '$($script:NombreInterfaz)'." -ForegroundColor Red
        return $null
    }

    $configActual = Get-NetIPAddress -InterfaceAlias $script:NombreInterfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    $gatewayActual = (Get-NetRoute -InterfaceAlias $script:NombreInterfaz -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue).NextHop

    if ($null -ne $configActual) {
        $script:RespaldoRed = @{
            IPAddress    = $configActual.IPAddress
            PrefixLength = $configActual.PrefixLength
            Gateway      = if ([string]::IsNullOrWhiteSpace($gatewayActual)) { $null } else { $gatewayActual }
        }
        Write-Host "Respaldo guardado de Ethernet 2: $($script:RespaldoRed.IPAddress)" -ForegroundColor Gray
    }

    try {
        Write-Host "Configurando IP estatica $NuevaIP..." -ForegroundColor Yellow
        Get-NetIPAddress -InterfaceAlias $script:NombreInterfaz -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
        $bits = 0
        $Mascara.Split('.') | ForEach-Object {
            $byte = [int]$_
            while ($byte -gt 0) { $bits += $byte % 2; $byte = [math]::Floor($byte / 2) }
        }
        New-NetIPAddress -InterfaceAlias $script:NombreInterfaz -IPAddress $NuevaIP -PrefixLength $bits -ErrorAction Stop
        Write-Host "OK: IP asignada." -ForegroundColor Green
        return $script:NombreInterfaz
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}