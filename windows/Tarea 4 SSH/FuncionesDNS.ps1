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
    $dominio = Read-Host "Ingrese el nombre del dominio: "

    if ([string]::IsNullOrWhiteSpace($dominio)) {
        Write-Host "Dominio invalido." -ForegroundColor Red
        Pause
        return
    }

    # Detectar IP automáticamente (red interna)
    $ipServidor = (Get-NetIPAddress -AddressFamily IPv4 `
        | Where-Object { $_.IPAddress -notlike "169.*" -and $_.IPAddress -ne "127.0.0.1" } `
        | Select-Object -First 1).IPAddress

    if (-not $ipServidor) {
        Write-Host "No se pudo detectar IP." -ForegroundColor Red
        Pause
        return
    }

    if (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue) {
        Write-Host "El dominio ya existe." -ForegroundColor Yellow
        Pause
        return
    }

    Write-Host "Creando zona DNS..."

    Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"

    Add-DnsServerResourceRecordA `
        -ZoneName $dominio `
        -Name "@" `
        -IPv4Address $ipServidor

    Add-DnsServerResourceRecordA `
        -ZoneName $dominio `
        -Name "www" `
        -IPv4Address $ipServidor

    Write-Host "Dominio creado correctamente." -ForegroundColor Green
    Write-Host "IP asociada: $ipServidor"

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