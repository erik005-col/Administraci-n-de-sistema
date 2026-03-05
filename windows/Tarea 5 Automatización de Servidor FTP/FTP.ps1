# ==============================================================================
# FTP SERVER ADMINISTRADOR - VERSION PROFESIONAL v3
# IIS + FTP + Usuarios + Grupos + Home Automático
# Compatible: Windows Server 2016 / 2019 / 2022
# ==============================================================================

Import-Module ServerManager
Import-Module WebAdministration

$ftpRoot = "C:\FTP"
$ftpSite = "FTP_SERVER"

# ------------------------------------------------------------------------------
# INSTALAR IIS + FTP
# ------------------------------------------------------------------------------

function Instalar-FTP {

    Write-Host "`nInstalando IIS + FTP..." -ForegroundColor Cyan

    $features = @(
        "Web-Server",
        "Web-WebServer",
        "Web-FTP-Server",
        "Web-FTP-Service",
        "Web-FTP-Ext"
    )

    foreach ($f in $features) {

        if (!(Get-WindowsFeature $f).Installed) {

            Install-WindowsFeature $f -IncludeManagementTools
        }
    }

    Start-Service W3SVC
    Set-Service W3SVC -StartupType Automatic

    Start-Service ftpsvc
    Set-Service ftpsvc -StartupType Automatic

    Write-Host "IIS + FTP instalado correctamente." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# FIREWALL
# ------------------------------------------------------------------------------

function Configurar-Firewall {

    Write-Host "`nConfigurando firewall..." -ForegroundColor Cyan

    New-NetFirewallRule `
        -DisplayName "FTP 21" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 21 `
        -Action Allow `
        -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName "FTP Passive Ports" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 50000-51000 `
        -Action Allow `
        -ErrorAction SilentlyContinue

    netsh advfirewall firewall add rule name="FTP Service" `
        action=allow `
        service=ftpsvc `
        protocol=TCP `
        dir=in 2>$null

    Write-Host "Firewall listo." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# CREAR GRUPOS
# ------------------------------------------------------------------------------

function Crear-Grupos {

    $grupos = @("reprobados","recursadores","ftpusuarios")

    foreach ($g in $grupos) {

        if (!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {

            New-LocalGroup $g
            Write-Host "Grupo $g creado."
        }
    }
}

# ------------------------------------------------------------------------------
# ESTRUCTURA FTP
# ------------------------------------------------------------------------------

function Crear-Estructura {

  
    Write-Host "`nCreando estructura FTP..." -ForegroundColor Cyan

    if (!(Test-Path $ftpRoot)) {

        New-Item $ftpRoot -ItemType Directory
    }

    New-Item "$ftpRoot\general" -ItemType Directory -Force
    New-Item "$ftpRoot\reprobados" -ItemType Directory -Force
    New-Item "$ftpRoot\recursadores" -ItemType Directory -Force
    New-Item "$ftpRoot\LocalUser" -ItemType Directory -Force

    Write-Host "Estructura creada." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# PERMISOS
# ------------------------------------------------------------------------------

function Asignar-Permisos {

    icacls $ftpRoot /inheritance:r

    # Administradores
    icacls $ftpRoot /grant "*S-1-5-32-544:(OI)(CI)F"

    # Sistema
    icacls $ftpRoot /grant "*S-1-5-18:(OI)(CI)F"

    # Servicio IIS FTP
    icacls $ftpRoot /grant "IIS_IUSRS:(OI)(CI)M"

    # Usuarios del sistema
    icacls $ftpRoot /grant "Usuarios:(OI)(CI)M"

    # Grupos FTP
    icacls "$ftpRoot\reprobados" /grant "reprobados:(OI)(CI)F"
    icacls "$ftpRoot\recursadores" /grant "recursadores:(OI)(CI)F"
    icacls "$ftpRoot\general" /grant "ftpusuarios:(OI)(CI)M"
    icacls "$ftpRoot\general" /grant "IUSR:(OI)(CI)R"

    Write-Host "Permisos aplicados correctamente." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# CONFIGURAR FTP
# ------------------------------------------------------------------------------

function Configurar-FTP {

    Write-Host "`nConfigurando servidor FTP..." -ForegroundColor Cyan

    if (Get-WebSite $ftpSite -ErrorAction SilentlyContinue) {
        Remove-WebSite $ftpSite
    }
    

    New-WebFtpSite `
        -Name $ftpSite `
        -Port 21 `
        -PhysicalPath $ftpRoot `
        -Force
   
    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.userIsolation.mode `
        -Value "None"

    # Autenticación
    
   
    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled `
        -Value $true

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled `
        -Value $true

   
    # ------------------------------
    # SOLUCIÓN ERROR 534 SSL
    # ------------------------------

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.ssl.controlChannelPolicy `
        -Value 0

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.ssl.dataChannelPolicy `
        -Value 0

    # Desactivar SSL GLOBAL
    Set-WebConfigurationProperty `
        -Filter /system.ftpServer/security/ssl `
        -Name controlChannelPolicy `
        -Value "SslAllow"

    Set-WebConfigurationProperty `
        -Filter /system.ftpServer/security/ssl `
        -Name dataChannelPolicy `
        -Value "SslAllow"

    # ------------------------------
    # MODO PASIVO
    # ------------------------------

    & $env:SystemRoot\System32\inetsrv\appcmd.exe set config `
        -section:system.ftpServer/firewallSupport `
        /lowDataChannelPort:50000 `
        /highDataChannelPort:51000 `
        /commit:apphost

    # ------------------------------
    # AUTORIZACIÓN FTP
    # ------------------------------

    Clear-WebConfiguration `
        -Filter system.ftpServer/security/authorization `
        -PSPath IIS:\ `
        -Location $ftpSite

    Add-WebConfiguration `
        -Filter system.ftpServer/security/authorization `
        -PSPath IIS:\ `
        -Location $ftpSite `
        -Value @{accessType="Allow";roles="ftpusuarios";permissions="Read,Write"}

     # acceso anonimo solo lectura
    Add-WebConfiguration `
    -Filter system.ftpServer/security/authorization `
    -PSPath IIS:\ `
    -Location $ftpSite `
    -Value @{accessType="Allow";users="anonymous";permissions="Read"}

    # Reiniciar servicio FTP
    Restart-Service ftpsvc

   
    
    Write-Host "FTP configurado y iniciado correctamente." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# CREAR USUARIO
# ------------------------------------------------------------------------------

function Crear-Usuario {
    $cantidad = Read-Host "¿Cuantos usuarios desea crear?"

    for ($i=1; $i -le $cantidad; $i++) {

    Write-Host ""
    Write-Host "Creando usuario $i de $cantidad" -ForegroundColor Yellow

    $usuario = Read-Host "Nombre del usuario"
    $pass = Read-Host "Contraseña" -AsSecureString
    $grupo = Read-Host "Grupo (reprobados/recursadores)"

    New-LocalUser `
    -Name $usuario `
    -Password $pass `
    -Description "Usuario FTP" `
    -ErrorAction SilentlyContinue

    Add-LocalGroupMember -Group $grupo -Member $usuario
    Add-LocalGroupMember -Group "ftpusuarios" -Member $usuario

    $userFolder = "$ftpRoot\LocalUser\$usuario"

    New-Item $userFolder -ItemType Directory -Force


    icacls $userFolder /grant "${usuario}:(OI)(CI)F"

    
    Write-Host "Usuario $usuario creado y configurado." -ForegroundColor Green
}
}

# ------------------------------------------------------------------------------
# ESTADO
# ------------------------------------------------------------------------------

function Ver-Estado {

    Write-Host "`nServicios:" -ForegroundColor Yellow

    Get-Service W3SVC
    Get-Service ftpsvc

    Write-Host "`nUsuarios FTP:" -ForegroundColor Cyan

    Get-LocalUser
}
# ------------------------------------------------------------------------------
# CAMBIAR USUARIO DE GRUPO
# ------------------------------------------------------------------------------

function Cambiar-Grupo {

    Write-Host ""
    $usuario = Read-Host "Usuario a modificar"

    Write-Host "Nuevo grupo:"
    Write-Host "1) reprobados"
    Write-Host "2) recursadores"

    $op = Read-Host "Seleccione opción"

    if ($op -eq "1") {
        $nuevoGrupo = "reprobados"
        $grupoViejo = "recursadores"
    }
    elseif ($op -eq "2") {
        $nuevoGrupo = "recursadores"
        $grupoViejo = "reprobados"
    }
    else {
        Write-Host "Opción inválida" -ForegroundColor Red
        return
    }

    Remove-LocalGroupMember -Group $grupoViejo -Member $usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $nuevoGrupo -Member $usuario

    Write-Host "Usuario $usuario ahora pertenece a $nuevoGrupo" -ForegroundColor Green
}
# ------------------------------------------------------------------------------
# MENÚ ADMIN
# ------------------------------------------------------------------------------

function Menu {

    while ($true) {

        Write-Host ""
        Write-Host "================================="
        Write-Host "   ADMINISTRADOR FTP UNIVERSIDAD"
        Write-Host "================================="

        Write-Host "1) Instalar IIS + FTP"
        Write-Host "2) Configurar Firewall"
        Write-Host "3) Crear Grupos"
        Write-Host "4) Crear Estructura"
        Write-Host "5) Asignar Permisos"
        Write-Host "6) Configurar FTP"
        Write-Host "7) Crear Usuario"
        Write-Host "8) Ver Estado"
        Write-Host "9) Cambiar grupo de usuario"
        Write-Host "0) Salir"

        $op = Read-Host "Seleccione opción"

        switch ($op) {

            "1" { Instalar-FTP }
            "2" { Configurar-Firewall }
            "3" { Crear-Grupos }
            "4" { Crear-Estructura }
            "5" { Asignar-Permisos }
            "6" { Configurar-FTP }
            "7" { Crear-Usuario }
            "8" { Ver-Estado }
            "9" { Cambiar-Grupo }
            "0" { break }
        }
    }
}
Menu