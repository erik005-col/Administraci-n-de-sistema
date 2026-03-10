Import-Module WebAdministration

############################
# VALIDACION INPUT
############################

function Validate-Input {
    param($input)

    if ([string]::IsNullOrWhiteSpace($input)) {
        Write-Host "Entrada vacia"
        return $false
    }

    if ($input -match "[^0-9]") {
        Write-Host "Solo numeros permitidos"
        return $false
    }

    return $true
}

############################
# VALIDACION PUERTO
############################

function Validate-Port {
    param($port)

    if ($port -notmatch '^[0-9]+$') {
        Write-Host "Puerto invalido"
        return $false
    }

    $port=[int]$port

    if ($port -lt 1024 -or $port -gt 65535) {
        Write-Host "Puerto fuera de rango"
        return $false
    }

    $reserved = @(21,22,23,25,53,110,135,139,443)

    if ($reserved -contains $port) {
        Write-Host "Puerto reservado"
        return $false
    }

    return $true
}

############################
# PUERTO EN USO
############################

function Test-PortAvailability {
    param($port)

    $test = Test-NetConnection -ComputerName localhost -Port $port -WarningAction SilentlyContinue

    if ($test.TcpTestSucceeded) {
        Write-Host "Puerto ya en uso"
        return $false
    }

    return $true
}

############################
# CONSULTA VERSIONES (CHOCOLATEY)
############################

function Get-ApacheVersions {

    Check-Chocolatey

    $versions = choco search apache-httpd --all | `
    Select-String "apache-httpd" | `
    ForEach-Object { ($_ -split ' ')[1] }

    return $versions
}

function Get-NginxVersions {

    Check-Chocolatey

    $versions = choco search nginx --all | `
    Select-String "nginx" | `
    ForEach-Object { ($_ -split ' ')[1] }

    return $versions
}

############################
# IIS
############################

function Install-IIS {

    Write-Host "Instalando IIS..."

    Install-WindowsFeature `
    -Name Web-Server `
    -IncludeManagementTools
}

function Set-IISPort {

    param($port)

    Remove-WebBinding `
    -Name "Default Web Site" `
    -Protocol "http" `
    -Port 80 `
    -ErrorAction SilentlyContinue

    New-WebBinding `
    -Name "Default Web Site" `
    -Protocol http `
    -Port $port
    iisreset
}

############################
# APACHE
############################

function Install-Apache {

    param($version)

    Check-Chocolatey

    choco install apache-httpd `
    --version=$version `
    -y
}

function Set-ApachePort {

    param($port)

    $conf="C:\tools\Apache24\conf\httpd.conf"

    if (Test-Path $conf) {

        (Get-Content $conf) `
        -replace "Listen 80","Listen $port" `
        -replace "ServerName localhost:80","ServerName localhost:$port" `
        | Set-Content $conf

        Restart-Service Apache24 -ErrorAction SilentlyContinue
    }
}

############################
# NGINX
############################

function Install-Nginx {

    param($version)

    Check-Chocolatey

    choco install nginx `
    --version=$version `
    -y
}

function Set-NginxPort {

    param($port)

    $conf="C:\tools\nginx\conf\nginx.conf"

    if (Test-Path $conf) {

        (Get-Content $conf) `
        -replace "listen 80","listen $port" `
        | Set-Content $conf

        Stop-Process -Name nginx -ErrorAction SilentlyContinue
        Start-Process "C:\tools\nginx\nginx.exe"
    }
}

############################
# FIREWALL
############################

function Open-FirewallPort {

    param($port)

    New-NetFirewallRule `
    -DisplayName "HTTP-Custom-$port" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $port `
    -Action Allow `
    -Profile Any `
    -ErrorAction SilentlyContinue
}

############################
# INDEX.HTML PERSONALIZADO
############################

function Create-IndexPage {

    param($server,$version,$port)

    $path="C:\inetpub\wwwroot\index.html"

    if ($server -eq "Apache") {
        $path="C:\tools\Apache24\htdocs\index.html"
    }

    if ($server -eq "Nginx") {
        $path="C:\tools\nginx\html\index.html"
    }

    $dir = Split-Path $path

    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force
    }

$content=@"
<html>
<head>
<title>Servidor HTTP</title>
</head>

<body>

<h1>Servidor: $server</h1>
<h2>Version: $version</h2>
<h3>Puerto: $port</h3>

</body>
</html>
"@

    Set-Content $path $content -Force
}

############################
# USUARIO DE SERVICIO
############################

function Create-ServiceUser {

$password = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

if (!(Get-LocalUser -Name "websvc" -ErrorAction SilentlyContinue)) {

New-LocalUser `
-Name "websvc" `
-Password $password `
-FullName "HTTP Service User"
}
}

############################
# PERMISOS
############################

function Set-WebPermissions {

$path="C:\inetpub\wwwroot"

if (Test-Path $path) {

icacls $path /inheritance:r
icacls $path /grant "websvc:(OI)(CI)RX"
}
}

############################
# SEGURIDAD IIS
############################

function Secure-IISHeaders {

Remove-WebConfigurationProperty `
-pspath 'MACHINE/WEBROOT/APPHOST' `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-AtElement @{name='X-Powered-By'} `
-ErrorAction SilentlyContinue

Set-WebConfigurationProperty `
-Filter system.webServer/security/requestFiltering `
-Name removeServerHeader `
-Value True `
-PSPath IIS:\
}

function Set-IISSecurityHeaders {

Add-WebConfigurationProperty `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-value @{name='X-Frame-Options';value='SAMEORIGIN'} `
-ErrorAction SilentlyContinue

Add-WebConfigurationProperty `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-value @{name='X-Content-Type-Options';value='nosniff'} `
-ErrorAction SilentlyContinue
}

############################
# BLOQUEAR METODOS PELIGROSOS
############################

function Block-DangerousMethods {

Add-WebConfiguration `
-Filter "/system.webServer/security/requestFiltering/verbs" `
-Value @{verb="TRACE";allowed="false"} `
-PSPath IIS:\ `
-ErrorAction SilentlyContinue
}

############################
# CHOCOLATEY
############################

function Check-Chocolatey {

if (!(Get-Command choco -ErrorAction SilentlyContinue)) {

Write-Host "Instalando Chocolatey..."

Set-ExecutionPolicy Bypass -Scope Process -Force

[System.Net.ServicePointManager]::SecurityProtocol =
[System.Net.ServicePointManager]::SecurityProtocol -bor 3072

iex ((New-Object System.Net.WebClient).DownloadString(
'https://community.chocolatey.org/install.ps1'))
}
}

############################
# VALIDAR IIS
############################

function Check-IIS {

$feature = Get-WindowsFeature -Name Web-Server

if (!($feature.Installed)) {

Install-IIS
}
}