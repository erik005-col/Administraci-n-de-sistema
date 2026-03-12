# ============================================================
# http_funciones.ps1
# Funciones para instalar IIS, Apache y Nginx en Windows Server
# Compatible: Windows Server 2019 / 2022
# ============================================================

# ============================================================
# Validar-Puerto
# ============================================================
function Validar-Puerto {
    param([string]$Puerto)

    $p = [int]$Puerto
    if ($p -lt 1 -or $p -gt 65535) {
        Write-Host "Puerto fuera de rango (1-65535)." -ForegroundColor Red
        return $false
    }

    $enUso = netstat -ano | Select-String ":$p " | Where-Object { $_ -match "LISTENING" }
    if ($enUso) {
        Write-Host "Advertencia: El puerto $p ya esta en uso." -ForegroundColor Yellow
    }

    return $true
}

# ============================================================
# Gestionar-Firewall
# ============================================================
function Gestionar-Firewall {
    param([int]$Puerto)

    $ruleName = "HTTP-$Puerto"
    $existe = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

    if (-not $existe) {
        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $Puerto `
            -Action Allow | Out-Null
        Write-Host "Regla de firewall creada para puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "Regla de firewall para puerto $Puerto ya existe." -ForegroundColor Yellow
    }
}

# ============================================================
# FIX: Aplicar ACL de forma segura
# Evita IdentityNotMappedException cuando IUSR/IIS_IUSRS
# no existen (Windows Server 2022 sin IIS, o Apache/Nginx solo).
# ============================================================
function Aplicar-ACL-Segura {
    param(
        [string]$Directorio,
        [string]$UsuarioLocal
    )

    if (-not (Test-Path $Directorio)) { return }

    $acl = Get-Acl $Directorio
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

    # Cuentas siempre presentes en Windows
    foreach ($cuenta in @("NT AUTHORITY\SYSTEM", "BUILTIN\Administrators")) {
        try {
            $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $cuenta, "FullControl",
                "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($regla)
        } catch {
            Write-Host "Advertencia: No se pudo agregar $cuenta." -ForegroundColor Yellow
        }
    }

    # IUSR e IIS_IUSRS solo existen cuando IIS esta instalado
    # Verificamos la existencia antes de crear la regla
    foreach ($cuenta in @("IUSR", "IIS_IUSRS")) {
        try {
            $null = (New-Object System.Security.Principal.NTAccount($cuenta)).Translate(
                [System.Security.Principal.SecurityIdentifier])
            $reglaOpc = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $cuenta, "ReadAndExecute",
                "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($reglaOpc)
        } catch {
            # Cuenta no existe en este sistema, se omite
        }
    }

    # Usuario de servicio dedicado
    if ($UsuarioLocal) {
        try {
            $reglaServicio = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $UsuarioLocal, "ReadAndExecute",
                "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($reglaServicio)
        } catch {
            Write-Host "Advertencia: No se pudo agregar $UsuarioLocal a la ACL." -ForegroundColor Yellow
        }
    }

    Set-Acl $Directorio $acl
    Write-Host "Permisos NTFS aplicados en $Directorio." -ForegroundColor Green
}

# ============================================================
# Listar versiones disponibles
# ============================================================
$global:IIS_VERSIONS   = @("10.0 (Windows Server 2019/2022)", "10.0 (Windows Server 2016)")
$global:APACHE_LATEST  = "2.4.63"
$global:APACHE_LTS     = "2.4.62"
$global:APACHE_OLDEST  = "2.4.58"
$global:NGINX_LATEST   = "1.27.4"
$global:NGINX_LTS      = "1.26.3"
$global:NGINX_OLDEST   = "1.24.0"

function Listar-Versiones-IIS {
    Write-Host ""
    Write-Host "Versiones disponibles de IIS:" -ForegroundColor Cyan
    Write-Host "1) IIS 10.0 (Windows Server 2019/2022) - Recomendada"
    Write-Host "2) IIS 10.0 (Windows Server 2016)"
    Write-Host ""
}

function Listar-Versiones-Apache {
    Write-Host ""
    Write-Host "Versiones disponibles de Apache HTTP Server:" -ForegroundColor Cyan
    Write-Host "1) Apache $global:APACHE_LATEST (Latest)"
    Write-Host "2) Apache $global:APACHE_LTS   (LTS)"
    Write-Host "3) Apache $global:APACHE_OLDEST (Legacy)"
    Write-Host ""
}

function Listar-Versiones-Nginx {
    Write-Host ""
    Write-Host "Versiones disponibles de Nginx:" -ForegroundColor Cyan
    Write-Host "1) Nginx $global:NGINX_LATEST (Latest)"
    Write-Host "2) Nginx $global:NGINX_LTS   (Stable)"
    Write-Host "3) Nginx $global:NGINX_OLDEST (Legacy)"
    Write-Host ""
}

# ============================================================
# IIS: Instalar y configurar
# ============================================================
function Instalar-IIS {
    param(
        [string]$Version,
        [int]$Puerto
    )

    Write-Host "Instalando IIS..." -ForegroundColor Cyan

    $features = @(
        "Web-Server", "Web-Common-Http", "Web-Default-Doc",
        "Web-Static-Content", "Web-Http-Errors", "Web-Http-Logging",
        "Web-Stat-Compression", "Web-Filtering", "Web-Mgmt-Tools"
    )

    foreach ($f in $features) {
        Install-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $webRoot = "C:\inetpub\wwwroot"

    $iisVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if ($iisVersion) { $Version = $iisVersion }

    $defaultSite = Get-WebSite -Name "Default Web Site" -ErrorAction SilentlyContinue
    if ($defaultSite) {
        Remove-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue
        New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $Puerto -IPAddress "*" -ErrorAction SilentlyContinue
        Start-WebSite -Name "Default Web Site" -ErrorAction SilentlyContinue
    } else {
        New-WebSite -Name "MiSitio" -Port $Puerto -PhysicalPath $webRoot -Force | Out-Null
        Start-WebSite -Name "MiSitio" -ErrorAction SilentlyContinue
    }

    Crear-Index -Servicio "IIS" -Version $Version -Puerto $Puerto -Directorio $webRoot
    Crear-Usuario-Restringido -Servicio "IIS" -Directorio $webRoot
    Gestionar-Firewall -Puerto $Puerto

    iisreset /restart | Out-Null

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : IIS"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
    Write-Host "URL      : http://localhost:$Puerto"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Apache Win64: Instalar y configurar
# FIX: Busqueda dinamica de ruta, soporte WinServer 2022,
#      httpd.conf escrito sin BOM, servicio reinstalado correctamente.
# ============================================================
function Instalar-Apache {
    param(
        [string]$Version,
        [int]$Puerto
    )

    Write-Host "Instalando Apache $Version..." -ForegroundColor Cyan

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Instalando Chocolatey..." -ForegroundColor Yellow
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
    }

    # Detener servicio previo
    $svcPrevio = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue
    if ($svcPrevio) {
        Stop-Service -Name $svcPrevio.Name -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Descargando Apache via Chocolatey..." -ForegroundColor Cyan
    choco install apache-httpd -y 2>&1 | Write-Host

    # ----------------------------------------------------------------
    # FIX: Busqueda de httpd.exe en multiples rutas posibles
    # En WinServer 2022 Chocolatey puede instalar en rutas distintas
    # ----------------------------------------------------------------
    $posiblesRutas = @(
        "C:\tools\Apache24",
        "C:\Apache24",
        "C:\Apache2",
        "$env:ProgramFiles\Apache24",
        "$env:ProgramFiles\Apache Software Foundation\Apache2.4",
        "$env:ProgramFiles\Apache Software Foundation\Apache2",
        "C:\tools\httpd",
        "C:\httpd"
    )

    $apacheBase = $null
    foreach ($ruta in $posiblesRutas) {
        if (Test-Path "$ruta\bin\httpd.exe") { $apacheBase = $ruta; break }
    }

    # Busqueda dinamica en directorios raiz
    if (-not $apacheBase) {
        foreach ($baseDir in @("C:\tools", "C:\", $env:ProgramFiles, "${env:ProgramFiles(x86)}")) {
            if (-not (Test-Path $baseDir)) { continue }
            $enc = Get-ChildItem $baseDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path "$($_.FullName)\bin\httpd.exe" } |
                Select-Object -First 1
            if ($enc) { $apacheBase = $enc.FullName; break }
        }
    }

    if (-not $apacheBase) {
        Write-Host "Error: No se encontro httpd.exe. Verifique la instalacion de Apache." -ForegroundColor Red
        return
    }

    Write-Host "Apache encontrado en: $apacheBase" -ForegroundColor Green

    $httpdExe = "$apacheBase\bin\httpd.exe"
    $confPath = "$apacheBase\conf\httpd.conf"
    $webRoot  = "$apacheBase\htdocs"

    $verReal = (& $httpdExe -v 2>&1) | Select-String "Server version" |
               ForEach-Object { ($_.ToString() -split "/")[1] -split " " | Select-Object -First 1 }
    if ($verReal) { $Version = $verReal.Trim() }

    # Leer y modificar httpd.conf
    $confContent = Get-Content $confPath -Raw -Encoding UTF8

    $apacheBaseSlash = $apacheBase -replace '\\', '/'
    $confContent = $confContent -replace '(?m)^ServerRoot\s+"[^"]*"', "ServerRoot `"$apacheBaseSlash`""
    $confContent = $confContent -replace '(?m)^Listen\s+\d+', "Listen $Puerto"

    if ($confContent -match '(?m)^ServerName\s+') {
        $confContent = $confContent -replace '(?m)^ServerName\s+\S+', "ServerName localhost:$Puerto"
    } elseif ($confContent -match '(?m)^#ServerName') {
        $confContent = $confContent -replace '(?m)^#ServerName[^\r\n]*', "ServerName localhost:$Puerto"
    } else {
        $confContent += "`nServerName localhost:$Puerto"
    }

    # Guardar SIN BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($confPath, $confContent, $utf8NoBom)
    Write-Host "httpd.conf actualizado con puerto $Puerto." -ForegroundColor Green

    Crear-Index -Servicio "Apache" -Version $Version -Puerto $Puerto -Directorio $webRoot
    Crear-Usuario-Restringido -Servicio "Apache" -Directorio $webRoot

    # Reinstalar servicio Windows con ruta correcta
    $svcExistente = Get-Service -Name "Apache" -ErrorAction SilentlyContinue
    if ($svcExistente) {
        & $httpdExe -k uninstall -n "Apache" 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    }

    & $httpdExe -k install -n "Apache" 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    $svc = Get-Service -Name "Apache" -ErrorAction SilentlyContinue
    if ($svc) {
        Start-Service -Name "Apache" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $svc.Refresh()
        if ($svc.Status -eq "Running") {
            Write-Host "Servicio Apache iniciado correctamente." -ForegroundColor Green
        } else {
            Write-Host "Advertencia: Servicio Apache no inicio. Ver: $apacheBase\logs\error.log" -ForegroundColor Yellow
        }
    } else {
        Start-Process -FilePath $httpdExe -ArgumentList "-k start" -WorkingDirectory "$apacheBase\bin" -WindowStyle Hidden
    }

    Gestionar-Firewall -Puerto $Puerto

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : Apache HTTP Server"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
    Write-Host "Ruta     : $apacheBase"
    Write-Host "URL      : http://localhost:$Puerto"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Nginx Windows: Instalar y configurar
# FIX: nginx.conf escrito sin BOM para evitar "unknown directive
#      i>>worker_processes" que rompia el arranque del servidor.
# ============================================================
function Instalar-Nginx {
    param(
        [string]$Version,
        [int]$Puerto
    )

    Write-Host "Instalando Nginx $Version..." -ForegroundColor Cyan

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Instalando Chocolatey..." -ForegroundColor Yellow
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
    }

    taskkill /f /im nginx.exe 2>&1 | Out-Null

    choco install nginx -y 2>&1 | Write-Host

    # Buscar nginx.exe
    $posiblesRutas = @("C:\nginx", "C:\tools\nginx", "$env:ProgramFiles\nginx")
    $nginxBase = $null

    foreach ($ruta in $posiblesRutas) {
        if (Test-Path "$ruta\nginx.exe") { $nginxBase = $ruta; break }
    }

    # Busqueda dinamica en C:\tools para carpetas nginx-X.X.X
    if (-not $nginxBase) {
        $enc = Get-ChildItem "C:\tools" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^nginx" -and (Test-Path "$($_.FullName)\nginx.exe") } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($enc) { $nginxBase = $enc.FullName }
    }

    if (-not $nginxBase) {
        Write-Host "Error: No se encontro nginx.exe." -ForegroundColor Red
        return
    }

    Write-Host "Nginx encontrado en: $nginxBase" -ForegroundColor Green

    $nginxExe = "$nginxBase\nginx.exe"
    $confPath = "$nginxBase\conf\nginx.conf"
    $webRoot  = "$nginxBase\html"

    $versionReal = (& $nginxExe -v 2>&1) | ForEach-Object { ($_.ToString() -split "/")[1] }
    if ($versionReal) { $Version = $versionReal.Trim() }

    Write-Host "Configurando puerto $Puerto..." -ForegroundColor Cyan

    # ----------------------------------------------------------------
    # FIX CRITICO: Usar [System.IO.File]::WriteAllText con UTF8 SIN BOM.
    # PowerShell Set-Content y Out-File agregan BOM automaticamente,
    # lo cual hace que nginx lea "i>>worker_processes" y falle.
    # ----------------------------------------------------------------
    $lineas = @(
        "worker_processes  1;",
        "",
        "events {",
        "    worker_connections  1024;",
        "}",
        "",
        "http {",
        "    include       mime.types;",
        "    default_type  application/octet-stream;",
        "    sendfile        on;",
        "    keepalive_timeout  65;",
        "",
        "    server_tokens off;",
        "",
        "    server {",
        "        listen       $Puerto;",
        "        server_name  _;",
        "        root         html;",
        "",
        "        location / {",
        "            index  index.html index.htm;",
        "        }",
        "",
        "        add_header X-Frame-Options `"SAMEORIGIN`";",
        "        add_header X-Content-Type-Options `"nosniff`";",
        "    }",
        "}"
    )
    $nginxConfTexto = $lineas -join "`n"

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($confPath, $nginxConfTexto, $utf8NoBom)

    Crear-Index -Servicio "Nginx" -Version $Version -Puerto $Puerto -Directorio $webRoot
    Crear-Usuario-Restringido -Servicio "Nginx" -Directorio $webRoot

    # Verificar config
    $testConf = & $nginxExe -t -p "$nginxBase" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error en configuracion de Nginx:" -ForegroundColor Red
        Write-Host ($testConf | Out-String) -ForegroundColor Red
        return
    }

    Write-Host "Configuracion de Nginx valida." -ForegroundColor Green

    Start-Process `
        -FilePath $nginxExe `
        -ArgumentList "-p `"$nginxBase`"" `
        -WorkingDirectory $nginxBase `
        -WindowStyle Hidden

    Start-Sleep -Seconds 2

    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "Nginx corriendo correctamente (PID: $($proc[0].Id))." -ForegroundColor Green
    } else {
        Write-Host "Advertencia: Nginx no inicio. Ver: $nginxBase\logs\error.log" -ForegroundColor Yellow
    }

    Gestionar-Firewall -Puerto $Puerto

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : Nginx"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
    Write-Host "Ruta     : $nginxBase"
    Write-Host "URL      : http://localhost:$Puerto"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Crear pagina index.html personalizada
# ============================================================
function Crear-Index {
    param(
        [string]$Servicio,
        [string]$Version,
        [int]$Puerto,
        [string]$Directorio
    )

    if (-not (Test-Path $Directorio)) {
        New-Item -ItemType Directory -Path $Directorio -Force | Out-Null
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Servidor HTTP - $Servicio</title>
<style>
  body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; text-align: center; padding-top: 80px; }
  h1   { color: #00d4ff; font-size: 2.5em; }
  h2   { color: #aaa; }
  .box { display: inline-block; background: #16213e; padding: 30px 60px; border-radius: 12px;
         border: 1px solid #0f3460; margin-top: 20px; }
  .ok  { color: #00ff88; font-weight: bold; font-size: 1.2em; margin-top: 20px; }
</style>
</head>
<body>
  <div class="box">
    <h1>$Servicio</h1>
    <h2>Version: $Version</h2>
    <h2>Puerto: $Puerto</h2>
    <p class="ok">Servidor funcionando correctamente</p>
  </div>
</body>
</html>
"@

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText("$Directorio\index.html", $html, $utf8NoBom)
    Write-Host "index.html creado en $Directorio" -ForegroundColor Green
}

# ============================================================
# Crear usuario dedicado con permisos restringidos (NTFS)
# ============================================================
function Crear-Usuario-Restringido {
    param(
        [string]$Servicio,
        [string]$Directorio
    )

    $usuario = "svc_$($Servicio.ToLower())"

    $chars    = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%"
    $password = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    $secPwd   = ConvertTo-SecureString $password -AsPlainText -Force

    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        New-LocalUser `
            -Name $usuario `
            -Password $secPwd `
            -PasswordNeverExpires `
            -UserMayNotChangePassword `
            -Description "Cuenta de servicio para $Servicio" `
            | Out-Null
        Write-Host "Usuario $usuario creado." -ForegroundColor Green
    } else {
        Write-Host "Usuario $usuario ya existe." -ForegroundColor Yellow
    }

    $hostname     = $env:COMPUTERNAME
    $usuarioLocal = "$hostname\$usuario"

    Aplicar-ACL-Segura -Directorio $Directorio -UsuarioLocal $usuarioLocal
}