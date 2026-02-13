# =========================================================
#   GESTOR DHCP PROFESIONAL - WINDOWS SERVER 2022
# =========================================================

# =========================================================
#   FUNCIONES DE VALIDACION
# =========================================================

function Validar-IP {
    param ([string]$IP)

    if ($IP -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') { return $false }

    $octetos = $IP.Split('.')
    foreach ($o in $octetos) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false }
    }

    if ($IP -in @("0.0.0.0","255.255.255.255","127.0.0.1")) { return $false }

    return $true
}

function Pedir-IP {
    param(
        [string]$Mensaje,
        [bool]$Opcional = $false
    )

    do {
        $ip = Read-Host $Mensaje

        if ($Opcional -and [string]::IsNullOrWhiteSpace($ip)) {
            return ""
        }

        if (-not (Validar-IP $ip)) {
            Write-Host "IP invalida" -ForegroundColor Red
        }

    } while (-not (Validar-IP $ip))

    return $ip
}

function IP-a-Entero($ip) {
    $o = $ip.Split('.')
    return ([int64]$o[0] -shl 24) -bor
           ([int64]$o[1] -shl 16) -bor
           ([int64]$o[2] -shl 8)  -bor
           ([int64]$o[3])
}

# =========================================================
#   INSTALAR DHCP
# =========================================================
function Instalar-DHCP {

    Clear-Host
    Write-Host "===== INSTALACION DHCP ====="

    $feature = Get-WindowsFeature -Name DHCP

    if ($feature -and $feature.Installed) {
        Write-Host "El Rol DHCP ya esta instalado." -ForegroundColor Yellow
        return
    }

    try {
        Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop
        Write-Host "Instalacion completada correctamente." -ForegroundColor Green
    }
    catch {
        Write-Host "Error durante la instalacion." -ForegroundColor Red
    }
}

# =========================================================
#    VERIFICAR ESTADO DHCP
# =========================================================
function Verificar-DHCP {

    Clear-Host
    Write-Host "===== VERIFICACION DHCP ====="

    $feature = Get-WindowsFeature -Name DHCP

    if (-not $feature -or -not $feature.Installed) {
        Write-Host "El Rol DHCP NO esta instalado." -ForegroundColor Red
        return
    }

    Write-Host "Rol DHCP: INSTALADO" -ForegroundColor Green

    $servicio = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue

    if (-not $servicio) {
        Write-Host "Servicio no encontrado." -ForegroundColor Red
        return
    }

    Write-Host "Estado del Servicio: $($servicio.Status)"

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopes) {
        Write-Host "`nAmbitos configurados:"
        $scopes | Format-Table Name, ScopeId, State -AutoSize
    }
    else {
        Write-Host "`nNo hay ambitos configurados."
    }
}

# =========================================================
#    CONFIGURAR DHCP (MODIFICADO SOLO LO NECESARIO)
# =========================================================
function Configurar-DHCP {

    Clear-Host
    Write-Host "===== CONFIGURACION DHCP ====="

    $scopeName = Read-Host "Nombre del ambito"
    $segmento = Pedir-IP "Segmento de red (ej: 192.168.1.0)"
    $subnetMask = Pedir-IP "Mascara de red (ej: 255.255.255.0)"

    $scopeID = $segmento

    $ipInicio = Pedir-IP "IP Inicial"
    $ipFin = Pedir-IP "IP Final"

    $inicioInt = IP-a-Entero $ipInicio
    $finInt = IP-a-Entero $ipFin

    if ($finInt -le $inicioInt) {
        Write-Host "IP Final debe ser mayor que IP Inicial." -ForegroundColor Red
        return
    }

    # =====================================================
    #   NUEVA LOGICA: IP INICIAL = IP ESTATICA SERVIDOR
    # =====================================================

    $IPServidor = $ipInicio

    $redBase = $ipInicio.Substring(0, $ipInicio.LastIndexOf('.'))
    $octIni = [int]$ipInicio.Split('.')[-1]
    $ipPoolInicio = "$redBase." + ($octIni + 1)

    Write-Host "`nLa IP $IPServidor sera configurada como IP ESTATICA del servidor." -ForegroundColor Yellow
    Write-Host "El pool DHCP real sera: $ipPoolInicio - $ipFin"

    # Cambiar IP del servidor (prefijo 24 por defecto)
    cambiar-ip-servidor -NuevaIP $IPServidor -Prefijo 24

    # =====================================================

    $leaseHoras = Read-Host "Tiempo de concesion (horas)"
    if (-not ($leaseHoras -match '^\d+$')) {
        Write-Host "Tiempo invalido." -ForegroundColor Red
        return
    }

    $leaseTime = New-TimeSpan -Hours $leaseHoras

    $gateway = Pedir-IP "Gateway (Enter para omitir)" $true
    $dns = Pedir-IP "DNS (Enter para omitir)" $true

    Write-Host "`nResumen:"
    Write-Host "Ambito: $scopeName"
    Write-Host "Red: $segmento"
    Write-Host "Mascara: $subnetMask"
    Write-Host "Rango DHCP: $ipInicio - $ipFin"
    Write-Host "IP Servidor: $IPServidor"

    $conf = Read-Host "Confirmar (C)"
    if ($conf -notin @("C","c")) { return }

    if (Get-DhcpServerv4Scope -ScopeId $scopeID -ErrorAction SilentlyContinue) {
        Remove-DhcpServerv4Scope -ScopeId $scopeID -Force
    }

    Add-DhcpServerv4Scope `
        -Name $scopeName `
        -StartRange $ipInicio `
        -EndRange $ipFin `
        -SubnetMask $subnetMask `
        -State Active

    Set-DhcpServerv4Scope `
        -ScopeId $scopeID `
        -LeaseDuration $leaseTime

    # Excluir IP del servidor
    Add-DhcpServerv4ExclusionRange `
        -ScopeId $scopeID `
        -StartRange $IPServidor `
        -EndRange $IPServidor

    if ($gateway) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeID -OptionId 3 -Value $gateway
    }

    if ($dns) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeID -OptionId 6 -Value $dns
    }

    Restart-Service DHCPServer

    Write-Host "Configuracion aplicada correctamente." -ForegroundColor Green
}
# =========================================================
#    ELIMINAR AMBITO
# =========================================================
function Eliminar-Scope {

    Clear-Host
    Write-Host "===== ELIMINAR AMBITO DHCP ====="

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

    if (-not $scopes) {
        Write-Host "No existen ambitos configurados." -ForegroundColor Yellow
        return
    }

    $scopes | Format-Table Name, ScopeId, State -AutoSize

    $scopeID = Read-Host "`nIngrese el ScopeId a eliminar"

    if (-not (Validar-IP $scopeID)) {
        Write-Host "ScopeId invalido." -ForegroundColor Red
        return
    }

    $conf = Read-Host "Confirma eliminar? (S/N)"
    if ($conf -notin @("S","s")) { return }

    Remove-DhcpServerv4Scope -ScopeId $scopeID -Force
    Write-Host "Ambito eliminado correctamente." -ForegroundColor Green
}

# =========================================================
#   MONITOREAR DHCP
# =========================================================
function Monitorear-DHCP {

    while ($true) {
        Clear-Host
        Write-Host "===== MONITOR DHCP ====="

        Get-Service DHCPServer

        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

        foreach ($scope in $scopes) {
            Write-Host "`nAmbito: $($scope.Name)"
            Get-DhcpServerv4Lease -ScopeId $scope.ScopeId |
                Format-Table IPAddress, HostName, ClientId, LeaseExpiryTime -AutoSize
        }

        Start-Sleep -Seconds 3
    }
}

# =========================================================
#   VER IP ACTUAL DEL SERVIDOR
# =========================================================
function Ver-IP-Servidor {

    Clear-Host
    Write-Host "===== INFORMACION DE RED DEL SERVIDOR =====`n"

    $config = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -ne $null }

    foreach ($c in $config) {

        Write-Host "Adaptador: $($c.InterfaceAlias)"
        Write-Host "IP IPv4 : $($c.IPv4Address.IPAddress)"
        Write-Host "Mascara : $($c.IPv4Address.PrefixLength)"
        
        if ($c.IPv4DefaultGateway) {
            Write-Host "Gateway : $($c.IPv4DefaultGateway.NextHop)"
        }

        if ($c.DnsServer.ServerAddresses) {
            Write-Host "DNS     : $($c.DnsServer.ServerAddresses -join ', ')"
        }

        Write-Host "------------------------------------------"
    }

    Read-Host "`nPresiona Enter para continuar..."
}

# =========================================================
#   MENU PRINCIPAL
# =========================================================
do {
    Clear-Host
    Write-Host "========================================"
    Write-Host "   GESTOR DHCP - WINDOWS SERVER 2022"
    Write-Host "========================================"
    Write-Host "1. Instalar DHCP"
    Write-Host "2. Verificar Estado "
    Write-Host "3. Configurar DHCP"
    Write-Host "4. Eliminar Ambito DHCP"
    Write-Host "5. Monitorear DHCP"
    Write-Host "6. Ver IP del Servidor"
    Write-Host "7. Salir"
    Write-Host "========================================"

    $opcion = Read-Host "Opcion"

    switch ($opcion) {
        "1" { Instalar-DHCP; Read-Host "Enter para continuar..." }
        "2" { Verificar-DHCP; Read-Host "Enter para continuar..." }
        "3" { Configurar-DHCP; Read-Host "Enter para continuar..." }
        "4" { Eliminar-Scope; Read-Host "Enter para continuar..." }
        "5" { Monitorear-DHCP }
        "6" { Ver-IP-Servidor }
        "7" { exit }
        default { Write-Host "Opcion no valida"; Start-Sleep 2 }
    }

} while ($true)



