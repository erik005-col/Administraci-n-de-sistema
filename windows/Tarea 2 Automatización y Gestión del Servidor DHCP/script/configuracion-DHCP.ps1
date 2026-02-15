# =========================================================
# GESTOR DHCP PROFESIONAL - ETHERNET 2 (V.FINAL)
# =========================================================

# Variables Globales de Sesión
$script:RespaldoRed = $null
$script:NombreInterfaz = "Ethernet 2"

# ================= FUNCIONES DE APOYO (IP) =================

function validar-ip {
    param ([string]$IP)
    
    # 1. Formato básico
    if ($IP -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') { return $false }
    
    $octetos = $IP.Split('.')
    $primero = [int]$octetos[0]

    # 2. BLOQUEO DE SEGURIDAD (IPs No Válidas para Hosts/Servidores)
    # Bloquear Red 0.x.x.x (Incluye 0.0.0.0 y 0.0.0.1)
    if ($primero -eq 0) {
        Write-Host "¡Error! IPs que inician con 0 ($IP) son reservadas." -ForegroundColor Red
        return $false
    }
    # Bloquear Loopback (127.x.x.x)
    if ($primero -eq 127) {
        Write-Host "¡Error! Rango 127.x.x.x es para pruebas locales (loopback)." -ForegroundColor Red
        return $false
    }
    # Bloquear Multicast/Experimental (224+)
    if ($primero -ge 224) {
        Write-Host "¡Error! Rango $IP es reservado o experimental." -ForegroundColor Red
        return $false
    }

    # 3. Validar rango de octetos (0-255)
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

# ================= FUNCIONES DE RED =================

function Cambiar-IP-Servidor {
    param($NuevaIP, $Mascara)
    
    $adaptador = Get-NetAdapter -Name $script:NombreInterfaz -ErrorAction SilentlyContinue
    if (-not $adaptador) {
        Write-Host "Error: No se encontro el adaptador '$($script:NombreInterfaz)'." -ForegroundColor Red
        return $null
    }

    # RESPALDO SEGURO
    $configActual = Get-NetIPAddress -InterfaceAlias $script:NombreInterfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    $gatewayActual = (Get-NetRoute -InterfaceAlias $script:NombreInterfaz -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue).NextHop

    if ($null -ne $configActual) {
        $script:RespaldoRed = @{
            IPAddress    = $configActual.IPAddress
            PrefixLength = $configActual.PrefixLength
            Gateway      = if ([string]::IsNullOrWhiteSpace($gatewayActual)) { $null } else { $gatewayActual }
        }
        Write-Host "`n[!] Respaldo guardado de Ethernet 2: $($script:RespaldoRed.IPAddress)" -ForegroundColor Gray
    }

    try {
        Write-Host "[!] Configurando IP estatica $NuevaIP ($Mascara)..." -ForegroundColor Yellow
        Get-NetIPAddress -InterfaceAlias $script:NombreInterfaz -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
        
        # Calcular PrefixLength desde máscara decimal
        $bits = 0
        $Mascara.Split('.') | ForEach-Object {
            $byte = [int]$_
            while ($byte -gt 0) { $bits += $byte % 2; $byte = [math]::Floor($byte / 2) }
        }

        New-NetIPAddress -InterfaceAlias $script:NombreInterfaz -IPAddress $NuevaIP -PrefixLength $bits -ErrorAction Stop
        Write-Host "OK: IP asignada correctamente." -ForegroundColor Green
        return $script:NombreInterfaz
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Restaurar-IP-Original {
    if ($null -eq $script:RespaldoRed) {
        Write-Host "No hay datos de respaldo para Ethernet 2." -ForegroundColor Yellow
        return
    }
    Write-Host "`n[!] Restaurando Ethernet 2 a su IP original..." -ForegroundColor Cyan
    try {
        Get-NetIPAddress -InterfaceAlias $script:NombreInterfaz -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
        $params = @{
            InterfaceAlias = $script:NombreInterfaz
            IPAddress      = $script:RespaldoRed.IPAddress
            PrefixLength   = $script:RespaldoRed.PrefixLength
            ErrorAction    = "Stop"
        }
        if ($null -ne $script:RespaldoRed.Gateway) { $params.Add("DefaultGateway", $script:RespaldoRed.Gateway) }
        New-NetIPAddress @params
        Write-Host "OK: Servidor restaurado." -ForegroundColor Green
        $script:RespaldoRed = $null
    } catch { Write-Host "Error al restaurar: $($_.Exception.Message)" -ForegroundColor Red }
}

# ================= MODULOS DHCP =================

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
    Write-Host "===== CONFIGURACION DE AMBITO (MODO MIXTO) =====" -ForegroundColor Cyan

    $nombre   = Read-Host "Nombre del ambito"
    $ipInicio = pedir-ip "IP del Servidor (IP inicial)"
    $ipFin    = pedir-ip "IP Final del rango"

    if ((ip-a-entero $ipInicio) -ge (ip-a-entero $ipFin)) {
        Write-Host "Error: Rango invalido." -ForegroundColor Red; return
    }

    # ELECCIÓN DE MÁSCARA
    $opMask = Read-Host "¿Desea calcular la mascara automaticamente? (S/N)"
    $mask = ""
    $scopeId = ""

    if ($opMask -eq "s" -or $opMask -eq "S") {
        $primerOcteto = [int]($ipInicio.Split('.')[0])
        if ($primerOcteto -le 126) { 
            $mask = "255.0.0.0"; $scopeId = "$($ipInicio.Split('.')[0]).0.0.0"; $tipo = "Clase A"
        } elseif ($primerOcteto -le 191) { 
            $mask = "255.255.0.0"; $scopeId = "$($ipInicio.Split('.')[0]).$($ipInicio.Split('.')[1]).0.0"; $tipo = "Clase B"
        } else { 
            $mask = "255.255.255.0"; $scopeId = "$($ipInicio.Split('.')[0]).$($ipInicio.Split('.')[1]).$($ipInicio.Split('.')[2]).0"; $tipo = "Clase C"
        }
        Write-Host "[i] Calculado: $mask ($tipo)" -ForegroundColor Gray
    } else {
        $mask = pedir-ip "Ingrese la Mascara de Subred manualmente"
        $oct = $ipInicio.Split('.')
        $scopeId = "$($oct[0]).$($oct[1]).$($oct[2]).0" # ScopeId genérico
    }

    $gateway = pedir-ip "Gateway (Opcional - Enter para saltar)" $true
    $dns     = pedir-ip "DNS (Opcional - Enter para saltar)" $true
    
    $segundos = Read-Host "Tiempo de Concesion (segundos, Enter=499)"
    if ([string]::IsNullOrWhiteSpace($segundos)) { $segundos = 499 }
    $leaseTime = New-TimeSpan -Seconds ([int]$segundos)

    # Aplicar cambios
    if (Cambiar-IP-Servidor -NuevaIP $ipInicio -Mascara $mask) {
        try {
            if (Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction SilentlyContinue) {
                Remove-DhcpServerv4Scope -ScopeId $scopeId -Force
            }

            Add-DhcpServerv4Scope -Name $nombre -StartRange $ipInicio -EndRange $ipFin -SubnetMask $mask -State Active -LeaseDuration $leaseTime
            Add-DhcpServerv4ExclusionRange -ScopeId $scopeId -StartRange $ipInicio -EndRange $ipInicio

            if ($gateway) { Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 3 -Value $gateway }
            if ($dns)     { Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 6 -Value $dns -ErrorAction SilentlyContinue }

            Set-DhcpServerv4Binding -InterfaceAlias $script:NombreInterfaz -BindingState $true
            Restart-Service DHCPServer
            Write-Host "`n[OK] DHCP configurado con exito." -ForegroundColor Green
        } catch { Write-Host "Error DHCP: $($_.Exception.Message)" -ForegroundColor Red }

        Write-Host "`n------------------------------------------------"
        $op = Read-Host "Desea restaurar la IP ORIGINAL de Ethernet 2? (S/N)"
        if ($op -eq "s" -or $op -eq "S") { Restaurar-IP-Original; Restart-Service DHCPServer }
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

# ================= MENU PRINCIPAL =================

do {
    Clear-Host
    Write-Host "=========================================="
    Write-Host "    GESTOR DHCP - ETHERNET 2 (V.PRO)      "
    Write-Host "=========================================="
    Write-Host "1. Instalar Rol DHCP"
    Write-Host "2. Configurar Ambito "
    Write-Host "3. Verificar Estado General"
    Write-Host "4. Monitorear Clientes "
    Write-Host "5. Eliminar Ambito"
    Write-Host "6. Ver Datos de Ethernet 2"
    Write-Host "7. Restaurar IP Original del Host"
    Write-Host "8. Salir"
    Write-Host "=========================================="

    $opcion = Read-Host "Seleccione"

    switch ($opcion) {
        "1" { Instalar-DHCP; Pause }
        "2" { Configurar-DHCP; Pause }
        "3" { 
                Get-Service DHCPServer | Select-Object Status, Name
                Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Format-Table Name, ScopeId, SubnetMask, State -AutoSize
                Pause 
            }
        "4" { 
                Write-Host "Monitoreo (Ctrl+C para salir)..."
                try {
                    while($true) {
                        Clear-Host
                        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
                        if (-not $scopes) { Write-Host "No hay ambitos activos."; break }
                        foreach ($s in $scopes) {
                            Write-Host "Ambito: $($s.ScopeId) ($($s.Name))" -ForegroundColor Cyan
                            Get-DhcpServerv4Lease -ScopeId $s.ScopeId | Format-Table IPAddress, HostName, ClientId -AutoSize
                        }
                        Start-Sleep 5
                    }
                } catch { return }
            }
        "5" { Eliminar-Ambito; Pause }
        "6" { Get-NetIPConfiguration -InterfaceAlias $script:NombreInterfaz | Format-List; Pause }
        "7" { Restaurar-IP-Original; Pause }
        "8" { exit }
    }
} while ($true)