# ============================================================
# http_funciones.ps1
# Funciones para despliegue de servidores HTTP en Windows
# Windows Server 2022 (sin GUI) - PowerShell
# Ejecutar como Administrador
# ============================================================
 
# ============================================================
# Validar puerto
# ============================================================
function Validar-Puerto {
    param([string]$Puerto)
 
    if ($Puerto -notmatch '^\d+$') {
        Write-Host "Error: El puerto debe ser un numero entero." -ForegroundColor Red
        return $false
    }
 
    $p = [int]$Puerto
 
    if ($p -lt 1 -or $p -gt 65535) {
        Write-Host "Error: Puerto fuera de rango (1-65535)." -ForegroundColor Red
        return $false
    }
 
    $reservados = @(22, 25, 53, 3389, 445, 135, 139)
    if ($reservados -contains $p) {
        Write-Host "Error: Puerto $p reservado por el sistema." -ForegroundColor Red
        return $false
    }
 
    $enUso = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
    if ($enUso.TcpTestSucceeded) {
        Write-Host "Error: El puerto $p ya esta en uso." -ForegroundColor Red
        return $false
    }
 
    return $true
}
 
# ============================================================
# Abrir puerto en firewall y cerrar puertos por defecto libres
# ============================================================
function Gestionar-Firewall {
    param([int]$Puerto)
 
    Write-Host "Configurando firewall para puerto $Puerto..." -ForegroundColor Cyan
 
    Remove-NetFirewallRule -DisplayName "HTTP-Custom" -ErrorAction SilentlyContinue
 
    New-NetFirewallRule `
        -DisplayName "HTTP-Custom" `
        -Direction Inbound `
        -LocalPort $Puerto `
        -Protocol TCP `
        -Action Allow `
        | Out-Null
 
    if ($Puerto -ne 80) {
        $puerto80 = Test-NetConnection -ComputerName localhost -Port 80 -WarningAction SilentlyContinue
        if (-not $puerto80.TcpTestSucceeded) {
            Remove-NetFirewallRule -DisplayName "HTTP-Default-80" -ErrorAction SilentlyContinue
            New-NetFirewallRule `
                -DisplayName "HTTP-Default-80" `
                -Direction Inbound `
                -LocalPort 80 `
                -Protocol TCP `
                -Action Block `
                | Out-Null
            Write-Host "Puerto 80 bloqueado (no en uso)." -ForegroundColor Yellow
        }
    }
 
    Write-Host "Firewall configurado." -ForegroundColor Green
}
 
# ============================================================
# Verificar winget
# ============================================================
function Verificar-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    return $false
}
 
# ============================================================
# Resolucion de nombres de cuentas por SID (independiente del idioma)
# ============================================================
function Obtener-NombreCuenta {
    param([string]$Sid)
    try {
        $obj = New-Object System.Security.Principal.SecurityIdentifier($Sid)
        return $obj.Translate([System.Security.Principal.NTAccount]).Value
    } catch {
        return $null
    }
}
 
# ============================================================
# Verificar e instalar Chocolatey si no esta presente
# ============================================================
function Asegurar-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) { return $true }
 
    Write-Host "Instalando Chocolatey (gestor de paquetes)..." -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "Chocolatey instalado correctamente." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "No se pudo instalar Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}
 
# ============================================================
# Descargar archivo usando BITS con fallback a WebClient
# ============================================================
function Descargar-Archivo {
    param(
        [string]$Url,
        [string]$Destino
    )
 
    if (Test-Path $Destino) { Remove-Item $Destino -Force }
 
    Write-Host "Descargando desde $Url..." -ForegroundColor Cyan
 
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $Url -Destination $Destino -ErrorAction Stop
        Write-Host "Descarga completada via BITS." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "BITS fallo, intentando WebClient..." -ForegroundColor Yellow
    }
 
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "curl/7.68.0")
        $wc.DownloadFile($Url, $Destino)
        Write-Host "Descarga completada via WebClient." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "WebClient fallo, intentando Invoke-WebRequest..." -ForegroundColor Yellow
    }
 
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destino -UseBasicParsing -UserAgent "curl/7.68.0" -ErrorAction Stop
        Write-Host "Descarga completada via Invoke-WebRequest." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "Error: No se pudo descargar el archivo. Verifique la conexion a internet." -ForegroundColor Red
        return $false
    }
}
 
# ============================================================
# IIS: Listar versiones
# ============================================================
function Listar-Versiones-IIS {
    Write-Host ""
    Write-Host "Versiones disponibles de IIS:" -ForegroundColor Cyan
    Write-Host ""
 
    $iisPath = "C:\Windows\System32\inetsrv\inetinfo.exe"
    if (Test-Path $iisPath) {
        $ver = (Get-Item $iisPath).VersionInfo.ProductVersion
    } else {
        $ver = "10.0 (Windows Server 2022)"
    }
 
    Write-Host "1) $ver  (Estable - incluida en Windows Server 2022)"
    Write-Host "2) $ver  (LTS - misma version de sistema)"
    Write-Host ""
    Write-Host "Nota: IIS se instala desde roles de Windows. La version depende del OS." -ForegroundColor Yellow
}
 
# ============================================================
# IIS: Instalar y configurar
# CORREGIDO: toma control de wwwroot antes de escribir index.html
# ============================================================
function Instalar-IIS {
    param(
        [string]$Version,
        [int]$Puerto
    )
 
    Write-Host "Instalando IIS (Internet Information Services)..." -ForegroundColor Cyan
 
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Web-Http-Redirect, Web-Http-Logging, Web-Security | Out-Null
 
    $iisPath = "C:\Windows\System32\inetsrv\inetinfo.exe"
    $Version = (Get-Item $iisPath -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
    if (-not $Version) { $Version = "10.0" }
 
    Write-Host "Configurando puerto $Puerto..." -ForegroundColor Cyan
 
    Import-Module WebAdministration -ErrorAction SilentlyContinue
 
    $siteName = "Default Web Site"
    Remove-WebBinding -Name $siteName -ErrorAction SilentlyContinue
    New-WebBinding -Name $siteName -Protocol "http" -Port $Puerto -IPAddress "*" | Out-Null
 
    # CORRECCION: tomar control de wwwroot para poder escribir index.html
    # sin esto en maquina limpia IIS bloquea el acceso al Administrador
    Write-Host "Tomando control de wwwroot..." -ForegroundColor Cyan
    takeown /f "C:\inetpub\wwwroot" /r /d s 2>&1 | Out-Null
    icacls "C:\inetpub\wwwroot" /grant "$env:USERNAME`:(OI)(CI)F" /t 2>&1 | Out-Null
 
    Crear-Index -Servicio "IIS" -Version $Version -Puerto $Puerto -Directorio "C:\inetpub\wwwroot"
 
    Configurar-Seguridad-IIS
 
    Crear-Usuario-Restringido -Servicio "IIS" -Directorio "C:\inetpub\wwwroot"
 
    iisreset /restart | Out-Null
 
    Gestionar-Firewall -Puerto $Puerto
 
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : IIS"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
    Write-Host "=====================================" -ForegroundColor Green
}
 
# ============================================================
# Seguridad IIS
# ============================================================
function Configurar-Seguridad-IIS {
 
    Import-Module WebAdministration -ErrorAction SilentlyContinue
 
    try {
        Remove-WebConfigurationProperty `
            -PSPath "IIS:\" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." `
            -AtElement @{name="X-Powered-By"} `
            -ErrorAction SilentlyContinue
    } catch {}
 
    $headers = @{
        "X-Frame-Options"        = "SAMEORIGIN"
        "X-Content-Type-Options" = "nosniff"
    }
 
    foreach ($h in $headers.GetEnumerator()) {
        try {
            Remove-WebConfigurationProperty `
                -PSPath "IIS:\" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." `
                -AtElement @{name=$h.Key} `
                -ErrorAction SilentlyContinue
 
            Add-WebConfigurationProperty `
                -PSPath "IIS:\" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." `
                -Value @{name=$h.Key; value=$h.Value}
        } catch {
            Write-Host "Advertencia: No se pudo agregar header $($h.Key)" -ForegroundColor Yellow
        }
    }
 
    try {
        Set-WebConfigurationProperty `
            -PSPath "IIS:\" `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" `
            -Value $true `
            -ErrorAction SilentlyContinue
    } catch {}
 
    $metodosBloquear = @("TRACE","TRACK","DELETE")
    foreach ($metodo in $metodosBloquear) {
        try {
            Add-WebConfigurationProperty `
                -PSPath "IIS:\" `
                -Filter "system.webServer/security/requestFiltering/verbs" `
                -Name "." `
                -Value @{verb=$metodo; allowed="false"} `
                -ErrorAction SilentlyContinue
        } catch {}
    }
 
    Write-Host "Seguridad IIS configurada." -ForegroundColor Green
}
 
# ============================================================
# Apache Win64: Listar versiones
# ============================================================
function Listar-Versiones-Apache {
 
    Write-Host ""
    Write-Host "Consultando versiones disponibles de Apache..." -ForegroundColor Cyan
 
    Asegurar-Chocolatey | Out-Null
 
    $latest = ""
    $lts    = ""
    $oldest = ""
 
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            Write-Host "Consultando repositorio de Chocolatey..." -ForegroundColor Gray
            $raw = choco search apache-httpd --all-versions --limit-output 2>&1 | Out-String
            $versiones = ($raw -split "`n") |
                Where-Object { $_ -match "^apache-httpd" } |
                ForEach-Object { ($_ -split "[|]")[1].Trim() } |
                Where-Object { $_ -match "^\d+\.\d+\.\d+$" } |
                Sort-Object { [Version]$_ } -Descending
 
            if ($versiones.Count -ge 1) { $latest = $versiones[0] }
            if ($versiones.Count -ge 2) { $lts    = $versiones[1] }
            if ($versiones.Count -ge 3) { $oldest = $versiones[$versiones.Count - 1] }
        } catch {
            Write-Host "Chocolatey no pudo listar versiones: $($_.Exception.Message)" -ForegroundColor Gray
        }
    }
 
    if (-not $latest) { $latest = "2.4.55" }
    if (-not $lts)    { $lts    = "2.4.54" }
    if (-not $oldest) { $oldest = "2.4.52" }
 
    Write-Host ""
    Write-Host "Versiones disponibles de Apache HTTP Server:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) $latest  (Latest / Desarrollo)"
    Write-Host "2) $lts     (LTS / Estable)"
    Write-Host "3) $oldest  (Oldest)"
 
    $global:APACHE_LATEST = $latest
    $global:APACHE_LTS    = $lts
    $global:APACHE_OLDEST = $oldest
}
 
# ============================================================
# Apache Win64: Instalar y configurar
# ============================================================
function Instalar-Apache {
    param([string]$Version, [int]$Puerto)
 
    Write-Host ""
    Write-Host "Instalando Apache HTTP Server $Version via Chocolatey..." -ForegroundColor Cyan
 
    $apacheBase = "C:\Apache24"
 
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Error: Chocolatey no disponible. Ejecute primero la opcion de listar versiones." -ForegroundColor Red
        return
    }
 
    Stop-Service -Name "Apache2.4" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "Apache"    -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
 
    if (Test-Path "$apacheBase\bin\httpd.exe") {
        Write-Host "Desinstalando version previa de Apache..." -ForegroundColor Yellow
        choco uninstall apache-httpd --yes --no-progress 2>&1 | Out-Null
        Remove-Item $apacheBase -Recurse -Force -ErrorAction SilentlyContinue
    }
 
    Write-Host "Descargando e instalando Apache $Version (puede tardar unos minutos)..." -ForegroundColor Cyan
    $chocoOut = choco install apache-httpd `
        --version $Version `
        --params "/installLocation:$apacheBase /noService" `
        --yes `
        --no-progress `
        --accept-license `
        --allow-downgrade `
        --force `
        2>&1
 
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Chocolatey fallo al instalar Apache $Version." -ForegroundColor Red
        Write-Host ($chocoOut | Select-Object -Last 5 | Out-String) -ForegroundColor Gray
        return
    }
 
    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $encontrado = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                      Select-Object -First 1
        if ($encontrado) {
            $apacheBase = Split-Path $encontrado.DirectoryName -Parent
            Write-Host "Apache encontrado en: $apacheBase" -ForegroundColor Yellow
        } else {
            Write-Host "Error: httpd.exe no encontrado tras la instalacion." -ForegroundColor Red
            return
        }
    }
 
    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $sub = Get-ChildItem $apacheBase -Directory | Where-Object { Test-Path "$($_.FullName)\bin\httpd.exe" } | Select-Object -First 1
        if ($sub) {
            $apacheBase = $sub.FullName
            Write-Host "Ajustando ruta Apache a: $apacheBase" -ForegroundColor Yellow
        }
    }
 
    $confPath  = "$apacheBase\conf\httpd.conf"
    $apacheExe = "$apacheBase\bin\httpd.exe"
 
    $versionReal = (& $apacheExe -v 2>&1) | Select-String "Apache/" |
                   ForEach-Object { ($_.ToString() -split "/")[1] -split " " | Select-Object -First 1 }
    if ($versionReal) { $Version = $versionReal.Trim() }
 
    Write-Host "Configurando puerto $Puerto en httpd.conf..." -ForegroundColor Cyan
    (Get-Content $confPath) -replace "Listen \d+", "Listen $Puerto" | Set-Content $confPath
 
    $webRoot = "$apacheBase\htdocs"
    Crear-Index -Servicio "Apache" -Version $Version -Puerto $Puerto -Directorio $webRoot
 
    Configurar-Seguridad-Apache -ApacheBase $apacheBase
 
    Crear-Usuario-Restringido -Servicio "Apache" -Directorio $webRoot
 
    $confContent = Get-Content $confPath -Raw
    if ($confContent -match 'Define SRVROOT "([^"]+)"') {
        $srvrootActual = $matches[1]
        if ($srvrootActual -ne $apacheBase) {
            Write-Host "Corrigiendo ServerRoot: $srvrootActual -> $apacheBase" -ForegroundColor Yellow
            $confContent = $confContent -replace [regex]::Escape("Define SRVROOT `"$srvrootActual`""), "Define SRVROOT `"$apacheBase`""
            [System.IO.File]::WriteAllText($confPath, $confContent)
        }
    }
 
    Write-Host "Registrando servicio Apache..." -ForegroundColor Cyan
    & "$apacheBase\bin\httpd.exe" -k install 2>&1 | Out-Null
    Start-Sleep -Seconds 2
 
    Write-Host "Iniciando servicio Apache..." -ForegroundColor Cyan
    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
 
    $escuchando = Test-NetConnection -ComputerName "127.0.0.1" -Port $Puerto -InformationLevel Quiet -ErrorAction SilentlyContinue
    if ($escuchando) {
        Write-Host "Apache escuchando en puerto $Puerto correctamente." -ForegroundColor Green
    } else {
        Write-Host "ADVERTENCIA: Apache no responde en puerto $Puerto." -ForegroundColor Yellow
        Write-Host "Revisando error.log..." -ForegroundColor Gray
        $errorLog = "$apacheBase\logs\error.log"
        if (Test-Path $errorLog) {
            Get-Content $errorLog -Tail 8 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
        & "$apacheBase\bin\httpd.exe" -k start 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        $escuchando2 = Test-NetConnection -ComputerName "127.0.0.1" -Port $Puerto -InformationLevel Quiet -ErrorAction SilentlyContinue
        if ($escuchando2) {
            Write-Host "Apache arrancado correctamente." -ForegroundColor Green
        } else {
            Write-Host "Error: Apache no pudo iniciar. Revise $errorLog" -ForegroundColor Red
        }
    }
 
    Gestionar-Firewall -Puerto $Puerto
 
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : Apache HTTP Server"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
    Write-Host "=====================================" -ForegroundColor Green
}
 
# ============================================================
# Apache: Configurar seguridad
# ============================================================
function Configurar-Seguridad-Apache {
    param([string]$ApacheBase)
 
    $secConf = "$ApacheBase\conf\extra\httpd-security.conf"
 
    @"
ServerTokens Prod
ServerSignature Off
TraceEnable Off
 
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</IfModule>
 
<Directory "`${SRVROOT}/htdocs">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>
"@ | Set-Content $secConf -Encoding UTF8
 
    $confPath = "$ApacheBase\conf\httpd.conf"
    if (-not (Select-String -Path $confPath -Pattern "httpd-security.conf" -Quiet)) {
        Add-Content $confPath "`nInclude conf/extra/httpd-security.conf"
    }
 
    (Get-Content $confPath) -replace "#LoadModule headers_module", "LoadModule headers_module" |
        Set-Content $confPath
 
    Write-Host "Seguridad Apache configurada." -ForegroundColor Green
}
 
# ============================================================
# Nginx Windows: Listar versiones
# ============================================================
function Listar-Versiones-Nginx {
 
    Write-Host ""
    Write-Host "Consultando versiones disponibles de Nginx..." -ForegroundColor Cyan
 
    $latest = "1.27.4"
    $lts    = "1.26.3"
    $oldest = "1.24.0"
 
    Write-Host ""
    Write-Host "Versiones disponibles de Nginx:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) $latest  (Latest / Desarrollo)"
    Write-Host "2) $lts     (LTS / Estable)"
    Write-Host "3) $oldest  (Oldest)"
 
    $global:NGINX_LATEST = $latest
    $global:NGINX_LTS    = $lts
    $global:NGINX_OLDEST = $oldest
}
 
# ============================================================
# Nginx Windows: Instalar y configurar
# ============================================================
function Instalar-Nginx {
    param(
        [string]$Version,
        [int]$Puerto
    )
 
    Write-Host "Instalando Nginx $Version..." -ForegroundColor Cyan
 
    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Stop-Service -Name "nginx" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
 
    $nginxBase = "C:\nginx"
 
    $versionInstalada = ""
    if (Test-Path "$nginxBase\nginx.exe") {
        $vOut = (& "$nginxBase\nginx.exe" -v 2>&1) | Out-String
        if ($vOut -match "nginx/(.+)") { $versionInstalada = $matches[1].Trim() }
    }
 
    $necesitaInstalar = (-not (Test-Path "$nginxBase\nginx.exe")) -or ($versionInstalada -ne $Version)
 
    if ($necesitaInstalar) {
        if ($versionInstalada) {
            Write-Host "Version instalada ($versionInstalada) difiere de la solicitada ($Version). Reinstalando..." -ForegroundColor Yellow
            taskkill /f /im nginx.exe 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            Remove-Item $nginxBase -Recurse -Force -ErrorAction SilentlyContinue
        }
 
        $zipName = "nginx-$Version.zip"
        $zipUrl  = "https://nginx.org/download/$zipName"
        $zipDest = "$env:TEMP\nginx.zip"
 
        $descargaOk = Descargar-Archivo -Url $zipUrl -Destino $zipDest
        if (-not $descargaOk) { return }
 
        if ((Get-Item $zipDest).Length -lt 500000) {
            Write-Host "Error: Descarga incompleta o corrupta. Intente de nuevo." -ForegroundColor Red
            Remove-Item $zipDest -Force -ErrorAction SilentlyContinue
            return
        }
 
        Write-Host "Extrayendo archivos..." -ForegroundColor Cyan
        Expand-Archive -Path $zipDest -DestinationPath "$env:TEMP\nginx_extract" -Force
        Remove-Item $zipDest -Force -ErrorAction SilentlyContinue
 
        $extractedDir = Get-ChildItem "$env:TEMP\nginx_extract" -Directory | Select-Object -First 1
        if ($extractedDir) {
            if (Test-Path $nginxBase) { Remove-Item $nginxBase -Recurse -Force }
            Move-Item $extractedDir.FullName $nginxBase
        }
        Remove-Item "$env:TEMP\nginx_extract" -Recurse -Force -ErrorAction SilentlyContinue
 
    } else {
        Write-Host "Nginx $Version ya esta instalado en $nginxBase" -ForegroundColor Green
    }
 
    if (-not (Test-Path "$nginxBase\nginx.exe")) {
        Write-Host "Error: No se encontro nginx.exe tras la instalacion." -ForegroundColor Red
        return
    }
 
    $nginxExe    = "$nginxBase\nginx.exe"
    $versionReal = (& $nginxExe -v 2>&1) | ForEach-Object { ($_.ToString() -split "/")[1] }
    if ($versionReal) { $Version = $versionReal.Trim() }
 
    $confPath = "$nginxBase\conf\nginx.conf"
    $webRoot  = "$nginxBase\html"
 
    Write-Host "Configurando puerto $Puerto..." -ForegroundColor Cyan
 
    $nginxConf = @"
worker_processes  1;
 
events {
    worker_connections  1024;
}
 
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
 
    server_tokens off;
 
    server {
        listen       $Puerto;
        server_name  _;
        root         html;
 
        location / {
            index  index.html index.htm;
        }
 
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
    }
}
"@
    [System.IO.File]::WriteAllText($confPath, $nginxConf, [System.Text.UTF8Encoding]::new($false))
 
    Crear-Index -Servicio "Nginx" -Version $Version -Puerto $Puerto -Directorio $webRoot
 
    Crear-Usuario-Restringido -Servicio "Nginx" -Directorio $webRoot
 
    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Start-Process -FilePath $nginxExe -WorkingDirectory $nginxBase -WindowStyle Hidden
    Start-Sleep -Seconds 3
 
    $escuchando = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    if ($escuchando.TcpTestSucceeded) {
        Write-Host "Nginx escuchando en puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "Advertencia: Nginx no responde en el puerto $Puerto." -ForegroundColor Yellow
        $logPath = "$nginxBase\logs\error.log"
        if (Test-Path $logPath) {
            Write-Host "Ultimas lineas del log de error:" -ForegroundColor Yellow
            Get-Content $logPath -Tail 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
        Write-Host "Reintentando inicio de Nginx..." -ForegroundColor Cyan
        & $nginxExe -p $nginxBase 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }
 
    Gestionar-Firewall -Puerto $Puerto
 
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : Nginx"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
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
<title>Servidor HTTP</title>
</head>
<body>
<h1>Servidor: $Servicio</h1>
<h2>Version: $Version</h2>
<h3>Puerto: $Puerto</h3>
</body>
</html>
"@
 
    [System.IO.File]::WriteAllText("$Directorio\index.html", $html, [System.Text.Encoding]::UTF8)
    Write-Host "index.html creado en $Directorio" -ForegroundColor Green
}
 
# ============================================================
# Crear usuario dedicado con permisos restringidos (NTFS)
# SIDs usados:
#   S-1-5-18        = NT AUTHORITY\SYSTEM  (o SISTEMA en español)
#   S-1-5-32-544    = BUILTIN\Administrators (o BUILTIN\Administradores en español)
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
    }
 
    if (Test-Path $Directorio) {
        $acl = Get-Acl $Directorio
 
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
 
        $hostname     = $env:COMPUTERNAME
        $usuarioLocal = "$hostname\$usuario"
 
        $reglaServicio = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $usuarioLocal,
            "ReadAndExecute",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
 
        $sidSystem = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
        $sidAdmins = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $cuentaSystem = $sidSystem.Translate([System.Security.Principal.NTAccount]).Value
        $cuentaAdmins = $sidAdmins.Translate([System.Security.Principal.NTAccount]).Value
 
        foreach ($cuenta in @($cuentaSystem, $cuentaAdmins)) {
            $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $cuenta,
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($regla)
        }
 
        foreach ($cuenta in @("IUSR", "IIS_IUSRS")) {
            try {
                $reglaIIS = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $cuenta,
                    "ReadAndExecute",
                    "ContainerInherit,ObjectInherit",
                    "None",
                    "Allow"
                )
                $acl.AddAccessRule($reglaIIS)
            } catch {
                Write-Host "Advertencia: No se pudo agregar $cuenta a la ACL." -ForegroundColor Yellow
            }
        }
 
        $acl.AddAccessRule($reglaServicio)
        Set-Acl $Directorio $acl
        Write-Host "Permisos NTFS aplicados en $Directorio para usuario $usuarioLocal." -ForegroundColor Green
    }
}