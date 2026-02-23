# ========================================================================================
# GESTOR INTEGRAL DE SERVICIOS DE RED (DHCP & DNS) - VERSIÓN CORREGIDA
# ========================================================================================


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

# ================= FUNCIONES DE RED =================

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



# ================= MÓDULO DHCP =================

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
      if ((Get-WindowsFeature DHCP).InstallState -ne "Installed") {
        Write-Host "Error: Instale el servicio primero."
        Read-Host "Enter..."
        return
    }

    Write-Host "Interfaces disponibles:"
    $adapters = Get-NetAdapter | Where-Object Status -eq "Up"
    $adapters | Select-Object Name, InterfaceDescription, MacAddress | Format-Table -AutoSize
    Write-Host "----------------------------------------"
    
    # 1. Seleccionar Interfaz
    while ($true) {
        $ifaceName = Read-Host "1. Nombre exacto del Adaptador de red (ej. Ethernet)"
        if (Get-NetAdapter -Name $ifaceName -ErrorAction SilentlyContinue) { break }
        Write-Host " [!] La interfaz no existe." -ForegroundColor Red
    }

    $scopeName = Read-Host "2. Nombre del Ambito"

    # 3. Rango Inicial (IP del Servidor)
    while ($true) {
        $ipInicio = Read-Host "3. Rango inicial (IP Servidor)"
        if (Validar-IP $ipInicio) { break }
        Write-Host " [!] IP invalida" -ForegroundColor Red
    }

    # Calculos de red
    $ipObj = [System.Net.IPAddress]::Parse($ipInicio)
    $bytes = $ipObj.GetAddressBytes()
    # Aumentar el ultimo octeto en 1 para el inicio del pool
    $poolStartLastOctet = [int]$bytes[3] + 1
    $poolStart = "{0}.{1}.{2}.{3}" -f $bytes[0], $bytes[1], $bytes[2], $poolStartLastOctet
    $prefix = "{0}.{1}.{2}" -f $bytes[0], $bytes[1], $bytes[2]
    
    $subnetID = "$($prefix).0"

    # 4. Rango Final
    while ($true) {
        $ipFin = Read-Host "4. Rango final ($prefix.X)"
        if (-not (Validar-IP $ipFin)) { continue }
        
        if (-not $ipFin.StartsWith($prefix)) {
            Write-Host " [!] La IP debe estar en el segmento $prefix.x" -ForegroundColor Red
            continue
        }
        
        # Validar que fin > inicio
        $finLast = [int]$ipFin.Split('.')[3]
        if ($poolStartLastOctet -le $finLast) { break }
        Write-Host " [!] El rango final debe ser mayor a $poolStart" -ForegroundColor Red
    }

    # 5. Gateway
    while ($true) {
        $gateway = Read-Host "5. Gateway (Enter para omitir)"
        # Permitimos vacio (break)
        if ([string]::IsNullOrWhiteSpace($gateway)) { break }
        
        if (Validar-IP $gateway) {
            if ($gateway.StartsWith($prefix)) { break }
            Write-Host " [!] El Gateway debe pertenecer a la red $prefix.x" -ForegroundColor Red
        } else {
             Write-Host " [!] IP invalida" -ForegroundColor Red
        }
    }

    # 6. DNS
    $dns = Read-Host "6. DNS (Enter para omitir)"
    if (-not [string]::IsNullOrWhiteSpace($dns)) {
        if (-not (Validar-IP $dns)) { $dns = $null; Write-Host "DNS invalido, omitiendo." }
    }

    # 7. Tiempo de concesion
    while ($true) {
        $leaseTimeStr = Read-Host "7. Tiempo de concesion (segundos)"
        if ($leaseTimeStr -match "^\d+$") { break }
        Write-Host " [!] Debe ser un numero entero." -ForegroundColor Red
    }
    $leaseTimeSpan = New-TimeSpan -Seconds $leaseTimeStr

    # --- RESUMEN ---
    Clear-Host
    Write-Host "========================================"
    Write-Host "        RESUMEN DE CONFIGURACION"
    Write-Host "========================================"
    Write-Host "1- Adaptador:       $ifaceName"
    Write-Host "2- Ambito:          $scopeName"
    Write-Host "3- IP Servidor:     $ipInicio"
    Write-Host "4- Pool DHCP:       $poolStart - $ipFin"
    Write-Host "5- Gateway:         $($gateway)"
    Write-Host "6- DNS:             $($dns)"
    Write-Host "7- Concesion:       $leaseTimeStr segundos"
    Write-Host "========================================"
    $confirm = Read-Host "Confirmar configuracion (S/N)"

    if ($confirm -ne "s") { Write-Host "Cancelado."; return }

    # --- APLICACION DE CAMBIOS ---
    Write-Host "Configurando IP estatica en $ifaceName..." -ForegroundColor Cyan
    try {
        # Quitar IP anterior (si es dinamica o estatica vieja)
        Remove-NetIPAddress -InterfaceAlias $ifaceName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        
        # --- SOLUCION DEL ERROR ---
        # Validamos si $gateway tiene texto o esta vacio para ejecutar el comando correcto
        if ([string]::IsNullOrWhiteSpace($gateway)) {
            # Opcion A: Sin Gateway
            New-NetIPAddress -InterfaceAlias $ifaceName -IPAddress $ipInicio -PrefixLength 24 -Confirm:$false
        } else {
            # Opcion B: Con Gateway
            New-NetIPAddress -InterfaceAlias $ifaceName -IPAddress $ipInicio -PrefixLength 24 -DefaultGateway $gateway -Confirm:$false
        }

        if ($dns) { Set-DnsClientServerAddress -InterfaceAlias $ifaceName -ServerAddresses $dns }
    } catch {
        Write-Host "Nota: Error ajustando IP (quizas ya esta asignada), continuando..." -ForegroundColor Yellow
        Write-Host $_.Exception.Message
    }
    Start-Sleep -Seconds 2

    Write-Host "Configurando Servicio DHCP..." -ForegroundColor Cyan
    try {
        # Limpiar ambitos anteriores si existen
        Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

        # Crear nuevo ambito
        Add-DhcpServerv4Scope -Name $scopeName -StartRange $poolStart -EndRange $ipFin -SubnetMask 255.255.255.0 -State Active -LeaseDuration $leaseTimeSpan

        # Configurar Opciones (Router = ID 3, DNS = ID 6)
        # Aquí verificamos de nuevo si $gateway existe antes de agregarlo como opción DHCP
        if (-not [string]::IsNullOrWhiteSpace($gateway)) { 
            Set-DhcpServerv4OptionValue -ScopeId $subnetID -OptionId 3 -Value $gateway 
        }
        
        if ($dns) { Set-DhcpServerv4OptionValue -ScopeId $subnetID -OptionId 6 -Value $dns -Force}

        Restart-Service DhcpServer -Force
        Write-Host "[EXITO] Servicio configurado y activo." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Fallo la configuracion DHCP:" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    Read-Host "Presione Enter..."
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

# ================= MÓDULO DNS =================


function Estado-DNS {

    Clear-Host
    Write-Host "======================================="
    Write-Host "      ESTADO DEL SERVICIO DNS"
    Write-Host "======================================="

    $servicio = Get-Service -Name DNS -ErrorAction SilentlyContinue

    if ($servicio -eq $null) {
        Write-Host "Servicio DNS no instalado." -ForegroundColor Red
        Pause
        return
    }

    Write-Host "Estado actual: $($servicio.Status)"

    Write-Host ""
    Write-Host "1) Iniciar Servicio"
    Write-Host "2) Reiniciar Servicio"
    Write-Host "3) Volver"

    $op = Read-Host "Seleccione opcion"

    switch ($op) {
        "1" { Start-Service DNS }
        "2" { Restart-Service DNS }
        default { return }
    }

    Pause
}

function Instalar-DNS {

    Clear-Host

    if ((Get-WindowsFeature -Name DNS).Installed) {
        Write-Host "DNS ya está instalado." -ForegroundColor Yellow
        Pause
        return
    }

    Write-Host "Instalando servicio DNS..."
    Install-WindowsFeature -Name DNS -IncludeManagementTools

    if ((Get-WindowsFeature -Name DNS).Installed) {

        # Iniciar servicio DNS
        Start-Service DNS

        # Cambiar red interna a Private automáticamente
        Set-NetConnectionProfile `
            -InterfaceAlias "Ethernet 2" `
            -NetworkCategory Private `
            -ErrorAction SilentlyContinue

        # Permitir tráfico DNS en firewall
        Enable-NetFirewallRule `
            -DisplayGroup "DNS Server" `
            -ErrorAction SilentlyContinue

        # Habilitar regla oficial de ICMPv4 (Ping)
        Enable-NetFirewallRule `
            -Name FPS-ICMP4-ERQ-In `
            -ErrorAction SilentlyContinue

        Write-Host "Instalacion completada y firewall configurado correctamente." -ForegroundColor Green
    }
    else {
        Write-Host "Error en instalación." -ForegroundColor Red
    }

    Pause
}

function Nuevo-Dominio {

 Clear-Host

    # ==============================
    # 1. Solicitar nombre de dominio
    # ==============================
    $dominio = Read-Host "Ingrese el nombre del dominio"

    if ([string]::IsNullOrWhiteSpace($dominio)) {
        Write-Host "Dominio invalido." -ForegroundColor Red
        Pause
        return
    }

    # ==============================
    # 2. Validar si ya existe la zona
    # ==============================
    if (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue) {
        Write-Host "El dominio ya existe." -ForegroundColor Yellow
        Pause
        return
    }

    # ==============================
    # 3. Solicitar IP manualmente
    # ==============================
    do {
        $ipServidor = Read-Host "Ingrese la direccion IP que se asociara al dominio"

        $valida = -not [string]::IsNullOrWhiteSpace($ipServidor) -and (Validar-IP $ipServidor)

        if (-not $valida) {
            Write-Host "Debe ingresar una direccion IP valida." -ForegroundColor Red
        }

    } until ($valida)

    # ==============================
    # 4. Crear zona DNS
    # ==============================
    try {

        Write-Host "Creando zona DNS..."

        Add-DnsServerPrimaryZone `
            -Name $dominio `
            -ZoneFile "$dominio.dns" `
            -ErrorAction Stop

        # Registro A raiz (@)
        Add-DnsServerResourceRecordA `
            -ZoneName $dominio `
            -Name "@" `
            -IPv4Address $ipServidor `
            -ErrorAction Stop

        # Registro A www
        Add-DnsServerResourceRecordA `
            -ZoneName $dominio `
            -Name "www" `
            -IPv4Address $ipServidor `
            -ErrorAction Stop

        Write-Host "Dominio creado correctamente." -ForegroundColor Green
        Write-Host "IP asociada: $ipServidor"

    }
    catch {
        Write-Host "Error al crear el dominio: $($_.Exception.Message)" -ForegroundColor Red
    }

    Pause
}
function Borrar-Dominio {

    $dominio = Read-Host "Ingrese el dominio a eliminar"

    if (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $dominio -Force
        Write-Host "Dominio eliminado." -ForegroundColor Green
    }
    else {
        Write-Host "Dominio no existe." -ForegroundColor Red
    }

    Pause
}

function Consultar-Dominio {

    Clear-Host

    $zonas = Get-DnsServerZone | Where-Object { $_.ZoneType -eq "Primary" }

    if ($zonas.Count -eq 0) {
        Write-Host "No existen dominios configurados."
        Pause
        return
    }

    Write-Host "Dominios disponibles:"
    $i = 1
    foreach ($zona in $zonas) {
        Write-Host "$i) $($zona.ZoneName)"
        $i++
    }

    $seleccion = Read-Host "Seleccione numero"
    $dominio = $zonas[$seleccion - 1].ZoneName

    Write-Host ""
    Write-Host "Dominio seleccionado: $dominio"
    Write-Host "-----------------------------------"

    $registro = Get-DnsServerResourceRecord -ZoneName $dominio -RRType A |
                Where-Object { $_.HostName -eq "@" }

    if ($registro) {
        Write-Host "IP Asociada: $($registro.RecordData.IPv4Address)"
    }
    else {
        Write-Host "No se encontro registro A."
    }

    Pause
}


# ================= MENÚS DE NAVEGACIÓN =================

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

function Mostrar-Menu-DNS {
    
    do {
        Clear-Host
        Write-Host "==========================================" -ForegroundColor Magenta
        Write-Host "             MENU GESTION DNS             " -ForegroundColor Magenta
        Write-Host "==========================================" -ForegroundColor Magenta
        Write-Host "1. Instalar Rol DNS"
        Write-Host "2. Crear Dominio (Zona Primaria)"
        Write-Host "3. Listar Dominios"
        Write-Host "4. Ver Registros de un Dominio"
        Write-Host "5. Eliminar Dominio"
        Write-Host "6. Estado del Servicio DNS"
        Write-Host "7. VOLVER AL MENU PRINCIPAL"
        Write-Host "=========================================="

        $o = Read-Host "Seleccione"

        switch ($o) {

            "1" { 
                Instalar-DNS
                Pause
            }

            "2" { 
                Nuevo-Dominio
                Pause
            }

            "3" { 
                Get-DnsServerZone | Where-Object { $_.ZoneType -eq "Primary" } | 
                Format-Table ZoneName, ZoneType -AutoSize
                Pause
            }

            "4" { 
                Consultar-Dominio
                Pause
            }

            "5" { 
                Borrar-Dominio
                Pause
            }

            "6" { 
                Estado-DNS
                Pause
            }

            "7" { return }

            default {
                Write-Host "Opcion invalida." -ForegroundColor Red
                Start-Sleep 1
            }
        }

    } while ($true)
}
# ================= BLOQUE DE INICIO (MENÚ GLOBAL) =================

do {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "    SISTEMA DE ADMINISTRACION DE RED      " -ForegroundColor Green
    Write-Host "           DHCP + DNS v4.1                " -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "1. Gestionar Servicio DHCP"
    Write-Host "2. Gestionar Servicio DNS"
    Write-Host "3. salir"
    Write-Host "=========================================="
    
    $globalOp = Read-Host "Elija una opcion"

    switch ($globalOp) {
        "1" { Mostrar-Menu-DHCP }
        "2" { Mostrar-Menu-DNS }
        "3" { exit }
    }
} while ($true)