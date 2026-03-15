# ============================================================
# ADMINISTRADOR SERVIDOR FTP - VERSION PROFESIONAL
# Windows Server 2016 / 2019 / 2022
# Erik ortiz leal
# ============================================================

Import-Module ServerManager
Import-Module WebAdministration

$ftpRoot = "C:\FTP"
$ftpSite = "FTP_SERVER"
$logFile = "C:\FTP\ftp_log.txt"

# ------------------------------------------------------------
# LOG
# ------------------------------------------------------------
function Log {
    param($msg)
    if (-not (Test-Path "C:\FTP")) {
        New-Item "C:\FTP" -ItemType Directory -Force | Out-Null
    }
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content $logFile "$fecha - $msg"
}

# ------------------------------------------------------------
# INSTALAR FTP
# ------------------------------------------------------------
function Instalar-FTP {

    Write-Host "Instalando IIS + FTP..."

    $features = @(
        "Web-Server",
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
    Start-Service ftpsvc
    Set-Service ftpsvc -StartupType Automatic

    Write-Host "FTP instalado."
    Log "FTP instalado"
}

# ------------------------------------------------------------
# FIREWALL
# ------------------------------------------------------------
function Configurar-Firewall {

    Remove-NetFirewallRule -DisplayName "FTP 21"      -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "FTP Passive" -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName "FTP 21" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 21 `
        -Action Allow

    New-NetFirewallRule `
        -DisplayName "FTP Passive" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 50000-51000 `
        -Action Allow

    Write-Host "Firewall configurado"
    Log "Firewall configurado"
}

# ------------------------------------------------------------
# CREAR GRUPOS
# ------------------------------------------------------------
function Crear-Grupos {

    $grupos = @("reprobados", "recursadores", "ftpusuarios")

    foreach ($g in $grupos) {
        if (!(Get-LocalGroup $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup $g
            Write-Host "Grupo $g creado"
        } else {
            Write-Host "Grupo $g ya existe"
        }
    }

    Log "Grupos verificados/creados"
}

# ------------------------------------------------------------
# ESTRUCTURA
# ------------------------------------------------------------
function Crear-Estructura {

    # Crear carpetas base
    New-Item "$ftpRoot"              -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\general"      -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\reprobados"   -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\recursadores" -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\Data\Usuarios" -ItemType Directory -Force | Out-Null

    # Carpeta publica para anonimos
    New-Item "$ftpRoot\LocalUser\Public" -ItemType Directory -Force | Out-Null

    # Enlace de general en Public para anonimos
    if (-not (Test-Path "$ftpRoot\LocalUser\Public\general")) {
        cmd /c mklink /J "$ftpRoot\LocalUser\Public\general" "$ftpRoot\general"
    }

    Write-Host "Estructura creada"
    Log "Estructura FTP creada"
}

# ------------------------------------------------------------
# PERMISOS
# Resolucion de cuentas por SID - independiente del idioma
# S-1-5-18     = SYSTEM / SISTEMA
# S-1-5-32-544 = BUILTIN\Administrators / BUILTIN\Administradores
# ------------------------------------------------------------
function Permisos {

    $sidSystem = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $sidAdmins = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $cuentaSystem = $sidSystem.Translate([System.Security.Principal.NTAccount]).Value
    $cuentaAdmins = $sidAdmins.Translate([System.Security.Principal.NTAccount]).Value

    # ROOT - IUSR necesita RX para que anonimo pueda entrar
    icacls $ftpRoot /inheritance:r
    icacls $ftpRoot /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls $ftpRoot /grant "$cuentaSystem`:(OI)(CI)F"
    icacls $ftpRoot /grant "IUSR:(OI)(CI)RX"

    # LOCALUSER - IUSR necesita acceso para aislamiento
    icacls "$ftpRoot\LocalUser" /inheritance:r
    icacls "$ftpRoot\LocalUser" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpRoot\LocalUser" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpRoot\LocalUser" /grant "IUSR:(OI)(CI)RX"

    # PUBLIC - carpeta del anonimo
    icacls "$ftpRoot\LocalUser\Public" /inheritance:r
    icacls "$ftpRoot\LocalUser\Public" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpRoot\LocalUser\Public" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpRoot\LocalUser\Public" /grant "IUSR:(OI)(CI)RX"

    # GENERAL - lectura para todos, escritura para ftpusuarios
    icacls "$ftpRoot\general" /inheritance:r
    icacls "$ftpRoot\general" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpRoot\general" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpRoot\general" /grant "ftpusuarios:(OI)(CI)M"
    icacls "$ftpRoot\general" /grant "IUSR:(OI)(CI)RX"

    # REPROBADOS
    icacls "$ftpRoot\reprobados" /inheritance:r
    icacls "$ftpRoot\reprobados" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpRoot\reprobados" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpRoot\reprobados" /grant "reprobados:(OI)(CI)M"

    # RECURSADORES
    icacls "$ftpRoot\recursadores" /inheritance:r
    icacls "$ftpRoot\recursadores" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpRoot\recursadores" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpRoot\recursadores" /grant "recursadores:(OI)(CI)M"

    Write-Host "Permisos aplicados correctamente"
    Log "Permisos aplicados"
}

# ------------------------------------------------------------
# CONFIGURAR FTP
# Modo aislamiento 1 = IsolateAllDirectories (compatible)
# SSL deshabilitado para permitir conexion sin TLS
# ------------------------------------------------------------
function Configurar-FTP {

    # Eliminar sitio previo si existe
    if (Get-WebSite $ftpSite -ErrorAction SilentlyContinue) {
        Remove-WebSite $ftpSite
    }

    # Crear sitio FTP
    New-WebFtpSite `
        -Name $ftpSite `
        -Port 21 `
        -PhysicalPath $ftpRoot `
        -Force

    # Modo aislamiento 1 = IsolateAllDirectories
    # Usa C:\FTP\LocalUser\<usuario> como home de cada usuario
    # Usa C:\FTP\LocalUser\Public como home del anonimo
    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.userIsolation.mode `
        -Value 1

    # SSL opcional (0 = SslAllow) - acepta conexiones sin TLS
    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.ssl.controlChannelPolicy `
        -Value 0

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.ssl.dataChannelPolicy `
        -Value 0

    # Autenticacion anonima y basica habilitadas
    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled `
        -Value $true

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled `
        -Value $true

    # Reglas de autorizacion
    Clear-WebConfiguration `
        -Filter system.ftpServer/security/authorization `
        -PSPath IIS:\ `
        -Location $ftpSite

    # Anonimo: solo lectura
    Add-WebConfiguration `
        -Filter system.ftpServer/security/authorization `
        -PSPath IIS:\ `
        -Location $ftpSite `
        -Value @{accessType="Allow"; users="?"; permissions="Read"}

    # Usuarios autenticados del grupo ftpusuarios: lectura y escritura
    Add-WebConfiguration `
        -Filter system.ftpServer/security/authorization `
        -PSPath IIS:\ `
        -Location $ftpSite `
        -Value @{accessType="Allow"; roles="ftpusuarios"; permissions="Read,Write"}

    Restart-Service ftpsvc

    Write-Host "FTP configurado"
    Log "FTP configurado"
}

# ------------------------------------------------------------
# CREAR USUARIO
# ------------------------------------------------------------
function Crear-Usuario {

    $cantidad = Read-Host "Cuantos usuarios desea crear"

    for ($i = 1; $i -le $cantidad; $i++) {

        Write-Host ""
        Write-Host "Creando usuario $i de $cantidad"

        $usuario = Read-Host "Usuario"
        $pass    = Read-Host "Contrasena" -AsSecureString
        $grupo   = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo invalido" -ForegroundColor Red
            continue
        }

        if (Get-LocalUser $usuario -ErrorAction SilentlyContinue) {
            Write-Host "El usuario ya existe" -ForegroundColor Yellow
            continue
        }

        # Crear usuario local
        New-LocalUser $usuario -Password $pass -PasswordNeverExpires

        # Agregar a grupos
        Add-LocalGroupMember $grupo       -Member $usuario
        Add-LocalGroupMember "ftpusuarios" -Member $usuario

        # Crear estructura de carpetas del usuario
        $userHome = "$ftpRoot\LocalUser\$usuario"
        New-Item $userHome -ItemType Directory -Force | Out-Null
        New-Item "$ftpRoot\Data\Usuarios\$usuario" -ItemType Directory -Force | Out-Null

        # Crear enlaces de carpetas visibles al hacer login
        cmd /c mklink /J "$userHome\general"  "$ftpRoot\general"
        cmd /c mklink /J "$userHome\$grupo"   "$ftpRoot\$grupo"
        cmd /c mklink /J "$userHome\$usuario" "$ftpRoot\Data\Usuarios\$usuario"

        # Permisos NTFS para el usuario en su home y carpeta personal
        icacls "$userHome"                         /grant "${usuario}:(OI)(CI)RX"
        icacls "$ftpRoot\Data\Usuarios\$usuario"   /grant "${usuario}:(OI)(CI)F"

        Write-Host "Usuario $usuario creado en grupo $grupo" -ForegroundColor Green
        Log "Usuario $usuario creado en grupo $grupo"
    }

    Restart-Service ftpsvc
    Write-Host "Usuarios creados correctamente"
}

# ------------------------------------------------------------
# ELIMINAR USUARIO
# ------------------------------------------------------------
function Eliminar-Usuario {

    $usuario = Read-Host "Usuario a eliminar"

    Remove-LocalUser $usuario -ErrorAction SilentlyContinue
    Remove-Item "$ftpRoot\LocalUser\$usuario"       -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$ftpRoot\Data\Usuarios\$usuario"   -Recurse -Force -ErrorAction SilentlyContinue

    Restart-Service ftpsvc

    Write-Host "Usuario $usuario eliminado"
    Log "Usuario eliminado: $usuario"
}

# ------------------------------------------------------------
# CAMBIAR GRUPO
# ------------------------------------------------------------
function Cambiar-Grupo {

    $usuario = Read-Host "Usuario"
    $grupo   = Read-Host "Nuevo grupo (reprobados/recursadores)"

    if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
        Write-Host "Grupo invalido" -ForegroundColor Red
        return
    }

    # Quitar de grupos anteriores
    Remove-LocalGroupMember -Group "reprobados"   -Member $usuario -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "recursadores" -Member $usuario -ErrorAction SilentlyContinue

    # Agregar al nuevo grupo
    Add-LocalGroupMember -Group $grupo -Member $usuario

    $userHome = "$ftpRoot\LocalUser\$usuario"

    # Eliminar enlaces viejos de grupo
    if (Test-Path "$userHome\reprobados")   { cmd /c rmdir "$userHome\reprobados" }
    if (Test-Path "$userHome\recursadores") { cmd /c rmdir "$userHome\recursadores" }

    # Crear nuevo enlace
    cmd /c mklink /J "$userHome\$grupo" "$ftpRoot\$grupo"

    iisreset | Out-Null

    Write-Host "Usuario $usuario cambiado al grupo $grupo"
    Log "Usuario $usuario cambiado al grupo $grupo"
}

# ------------------------------------------------------------
# VER USUARIOS
# ------------------------------------------------------------
function Ver-Usuarios {

    Write-Host ""
    Write-Host "Usuarios FTP creados:" -ForegroundColor Cyan
    Write-Host ""

    Get-LocalGroupMember ftpusuarios | ForEach-Object {
        $u = $_.Name.Split("\")[-1]
        $grupos = @()
        if (Get-LocalGroupMember "reprobados"   -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$u" }) { $grupos += "reprobados" }
        if (Get-LocalGroupMember "recursadores" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$u" }) { $grupos += "recursadores" }
        Write-Host "Usuario: $u  |  Grupo: $($grupos -join ', ')"
    }
}

# ------------------------------------------------------------
# REINICIAR FTP
# ------------------------------------------------------------
function Reiniciar-FTP {
    Restart-Service ftpsvc
    Write-Host "FTP reiniciado"
}

# ------------------------------------------------------------
# ESTADO SERVIDOR
# ------------------------------------------------------------
function Estado {

    Write-Host "Servicio FTP:" -ForegroundColor Cyan
    Get-Service ftpsvc

    Write-Host ""
    Write-Host "Puerto 21:" -ForegroundColor Cyan
    netstat -an | find ":21"
}

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------
function Menu {

    while ($true) {

        Write-Host ""
        Write-Host "========= ADMIN FTP =========" -ForegroundColor Cyan
        Write-Host "1  Instalar FTP"
        Write-Host "2  Firewall"
        Write-Host "3  Crear Grupos"
        Write-Host "4  Crear Estructura"
        Write-Host "5  Permisos"
        Write-Host "6  Configurar FTP"
        Write-Host "7  Crear Usuario"
        Write-Host "8  Eliminar Usuario"
        Write-Host "9  Cambiar Grupo"
        Write-Host "10 Ver Usuarios"
        Write-Host "11 Estado Servidor"
        Write-Host "12 Reiniciar FTP"
        Write-Host "0  Salir"

        $op = Read-Host "Opcion"

        switch ($op) {
            "1"  { Instalar-FTP }
            "2"  { Configurar-Firewall }
            "3"  { Crear-Grupos }
            "4"  { Crear-Estructura }
            "5"  { Permisos }
            "6"  { Configurar-FTP }
            "7"  { Crear-Usuario }
            "8"  { Eliminar-Usuario }
            "9"  { Cambiar-Grupo }
            "10" { Ver-Usuarios }
            "11" { Estado }
            "12" { Reiniciar-FTP }
            "0"  { break }
        }
    }
}

Menu