# ========================================================================================
# GESTOR INTEGRAL DE SERVICIOS DE RED (DHCP & DNS) - VERSIÓN CORREGIDA
# ========================================================================================
# Variables Globales de Sesión
$script:RespaldoRed = $null
$script:NombreInterfaz = "Ethernet 2"

# ================= FUNCIONES DE APOYO (IP) =================

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


function Instalar-DHCP {
    Clear-Host
    Write-Host "===== INSTALACION DE ROL DHCP ====="
    if ((Get-WindowsFeature DHCP).Installed) {
        Write-Host "El rol DHCP ya esta instalado." -ForegroundColor Yellow
    } else {
        Install-WindowsFeature DHCP -IncludeManagementTools
        Write-Host "Instalacion completada." -ForegroundColor Green
    }
}

function Configurar-DHCP {
    if (-not (Get-WindowsFeature DHCP).Installed) {
        Write-Host "Error: Instale el rol DHCP primero." -ForegroundColor Red
        return
    }

    Clear-Host
    Write-Host "===== CONFIGURACION DE AMBITO =====" -ForegroundColor Cyan

    $nombre   = Read-Host "Nombre del ambito"
    $ipInicio = pedir-ip "IP del Servidor (IP fija del servidor)"
    $ipFin    = pedir-ip "IP Final del rango"

    if ((ip-a-entero $ipInicio) -ge (ip-a-entero $ipFin)) {
        Write-Host "Error: Rango invalido." -ForegroundColor Red
        return
    }

    $mask = "255.255.255.0"
    $scopeId = ($ipInicio.Split('.')[0..2] -join '.') + ".0"
    $gateway = pedir-ip "Gateway (Opcional - Enter para saltar)" $true
    $dns1 = pedir-ip "DNS Primario"
    $dns2 = pedir-ip "DNS Secundario (Opcional)" $true

    $segundos = Read-Host "Tiempo de Concesion (segundos, Enter=499)"
    if ([string]::IsNullOrWhiteSpace($segundos)) { $segundos = 499 }
    $leaseTime = New-TimeSpan -Seconds ([int]$segundos)

    Cambiar-IP-Servidor -NuevaIP $ipInicio -Mascara $mask

    
    Start-Sleep -Seconds 3

    # ASEGURAR QUE DNS ESTE INICIADO
    Start-Service DNS -ErrorAction SilentlyContinue
    Restart-Service DNS
    Start-Sleep -Seconds 3

    

    try {

        if (Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction SilentlyContinue) {
            Remove-DhcpServerv4Scope -ScopeId $scopeId -Force
        }

        Add-DhcpServerv4Scope `
            -Name $nombre `
            -StartRange $ipInicio `
            -EndRange $ipFin `
            -SubnetMask $mask `
            -State Active `
            -LeaseDuration $leaseTime

        Add-DhcpServerv4ExclusionRange -ScopeId $scopeId -StartRange $ipInicio -EndRange $ipInicio

        if ($gateway) {
            Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 3 -Value $gateway
        }

       $dnsList = @()

        if ($dns1) { $dnsList += $dns1 }
        if ($dns2) { $dnsList += $dns2 }

        if ($dnsList.Count -gt 0) {
            Set-DhcpServerv4OptionValue `
            -ScopeId $scopeId `
            -OptionId 6 `
            -Value $dnsList `
            -Force
        }

        Set-DhcpServerv4Binding -InterfaceAlias $script:NombreInterfaz -BindingState $true

        Restart-Service DHCPServer

        Write-Host "DHCP configurado con exito." -ForegroundColor Green

    } catch {
        Write-Host "Error DHCP: $($_.Exception.Message)" -ForegroundColor Red
    }
}
function Eliminar-Ambito {
    Clear-Host
    Write-Host "===== ELIMINAR AMBITO =====" -ForegroundColor Yellow
    $id = pedir-ip "Ingrese el ScopeId a eliminar (ej. 192.168.1.0)"
    if ($id) {
        try {
            Remove-DhcpServerv4Scope -ScopeId $id -Force -ErrorAction Stop
            Write-Host "Ambito $id eliminado." -ForegroundColor Green
        } catch { Write-Host "Error: No se encontro el ambito." -ForegroundColor Red }
    }
}
function Mostrar-Menu-DHCP {
    do {
        Clear-Host
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "    GESTOR DHCP - ETHERNET 2 (V.PRO)      " -ForegroundColor Cyan
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "1. Instalar Rol DHCP"
        Write-Host "2. Configurar Ambito"
        Write-Host "3. Verificar Estado General"
        Write-Host "4. Monitorear Clientes"
        Write-Host "5. Eliminar Ambito"
        Write-Host "6. Ver Datos de Ethernet 2"
        Write-Host "8. VOLVER AL MENU PRINCIPAL"
        Write-Host "=========================================="
        $op = Read-Host "Seleccione"
        switch ($op) {
            "1" { Instalar-DHCP; Pause }
            "2" { Configurar-DHCP; Pause }
            "3" { 
                Get-Service DHCPServer | Select-Object Status, Name
                Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Format-Table Name, ScopeId, State -AutoSize
                Pause 
            }
            "4" { 
                Write-Host "Ctrl+C para salir..." -ForegroundColor Yellow; Start-Sleep 1
                try {
                    while($true) {
                        Clear-Host
                        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
                        if (-not $scopes) { Write-Host "No hay ámbitos."; break }
                        foreach ($s in $scopes) {
                            Write-Host "Ambito: $($s.ScopeId)" -ForegroundColor Cyan
                            Get-DhcpServerv4Lease -ScopeId $s.ScopeId | Format-Table IPAddress, HostName -AutoSize
                        }
                        Start-Sleep 5
                    }
                } catch { }
            }
            "5" { Eliminar-Ambito; Pause }
            "6" { Get-NetIPConfiguration -InterfaceAlias $script:NombreInterfaz | Format-List; Pause }
            "7" { Restaurar-IP-Original; Pause }
        }
    } while ($op -ne "8")
}