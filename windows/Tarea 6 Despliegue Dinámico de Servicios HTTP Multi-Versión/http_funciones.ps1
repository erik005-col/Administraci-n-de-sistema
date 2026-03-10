# -------------------------------
# VALIDAR PUERTO
# -------------------------------

function Solicitar-Puerto {

$PUERTO = Read-Host "Ingrese puerto (ej: 8080, 8888)"

if($PUERTO -notmatch '^[0-9]+$'){
Write-Host "Puerto invalido"
return Solicitar-Puerto
}

if([int]$PUERTO -lt 1024){
Write-Host "No se permiten puertos reservados (<1024)"
return Solicitar-Puerto
}

$ocupado = Test-NetConnection -ComputerName localhost -Port $PUERTO

if($ocupado.TcpTestSucceeded){
Write-Host "El puerto ya esta en uso"
return Solicitar-Puerto
}

return $PUERTO

}

# -------------------------------
# CONFIGURAR FIREWALL
# -------------------------------

function Configurar-Firewall($PUERTO){
if (-not (Get-NetFirewallRule -DisplayName "HTTP-Custom-${PUERTO}" -ErrorAction SilentlyContinue)) {

New-NetFirewallRule `
-DisplayName "HTTP-Custom-${PUERTO}" `
-Direction Inbound `
-Protocol TCP `
-LocalPort $PUERTO `
-Action Allow

}

}

# -------------------------------
# CREAR INDEX WEB
# -------------------------------

function Crear-Index($ruta,$servidor,$version,$puerto){

$contenido = @"
<html>
<head>
<title>Servidor HTTP</title>
</head>

<body>
<h1>Servidor: $servidor</h1>
<h2>Version: $version</h2>
<h3>Puerto: $puerto</h3>
</body>

</html>
"@

$contenido | Out-File "$ruta\index.html" -Encoding utf8

}

# -------------------------------
# IIS
# -------------------------------

function Instalar-IIS {

Write-Host "Instalando IIS..."

if ((Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole).State -ne "Enabled") {

Enable-WindowsOptionalFeature `
-Online `
-FeatureName IIS-WebServerRole `
-All `
-NoRestart

}

$PUERTO = Solicitar-Puerto

Cambiar-Puerto-IIS $PUERTO

Configurar-Firewall $PUERTO

$version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp").VersionString

Crear-Index "C:\inetpub\wwwroot" "IIS" $version $PUERTO

Configurar-Seguridad-IIS

Write-Host "IIS instalado correctamente"

}

# -------------------------------
# CAMBIAR PUERTO IIS
# -------------------------------

function Cambiar-Puerto-IIS($PUERTO){

Import-Module WebAdministration

# eliminar binding puerto 80
Remove-WebBinding -Name "Default Web Site" -Protocol "http" -Port 80 -ErrorAction SilentlyContinue

# crear binding nuevo
New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $PUERTO -IPAddress "*"

Restart-Service W3SVC

}
# -------------------------------
# SEGURIDAD IIS
# -------------------------------

function Configurar-Seguridad-IIS {

Import-Module WebAdministration

Remove-WebConfigurationProperty `
-pspath 'MACHINE/WEBROOT/APPHOST' `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-atElement @{name='X-Powered-By'}

Add-WebConfigurationProperty `
-pspath 'MACHINE/WEBROOT/APPHOST' `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-value @{name='X-Frame-Options';value='SAMEORIGIN'}

Add-WebConfigurationProperty `
-pspath 'MACHINE/WEBROOT/APPHOST' `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-value @{name='X-Content-Type-Options';value='nosniff'}

}


# -------------------------------
# CONSULTAR VERSIONES APACHE
# -------------------------------

function Obtener-Versiones-Apache {
    Write-Host "=============================="
    Write-Host "Versiones disponibles Apache"
    Write-Host "=============================="
  $versiones = choco list apache-httpd --all | `
   Where-Object {$_ -match "apache-httpd"} | `
   ForEach-Object { ($_ -split " ")[1] }

return $versiones

}


# -------------------------------
# INSTALAR APACHE
# -------------------------------

function Instalar-Apache {

Obtener-Versiones-Apache

$version = Read-Host "Seleccione la version a instalar"

$PUERTO = Solicitar-Puerto

Write-Host "Instalando Apache version $version..."

choco install apache-httpd --version=$version -y

Configurar-Puerto-Apache $PUERTO

Configurar-Firewall $PUERTO

Crear-Index "C:\tools\Apache24\htdocs" "Apache" $version $PUERTO

}
# -------------------------------
# CAMBIAR PUERTO APACHE
# -------------------------------

function Configurar-Puerto-Apache($PUERTO){

$config = "C:\tools\Apache24\conf\httpd.conf"

(Get-Content $config) `
-replace "Listen 80","Listen $PUERTO" |
Set-Content $config


Restart-Service Apache2.4 -ErrorAction SilentlyContinue

}

# -------------------------------
# CONSULTAR VERSIONES NGINX
# -------------------------------

function Obtener-Versiones-Nginx {

Write-Host "Versiones disponibles Nginx:"
winget show nginx

}

# -------------------------------
# INSTALAR NGINX
# -------------------------------

function Instalar-Nginx {

Obtener-Versiones-Nginx

$PUERTO = Solicitar-Puerto

Write-Host "Instalando Nginx..."

winget install nginx --silent

Start-Sleep 5

Configurar-Puerto-Nginx $PUERTO

Configurar-Firewall $PUERTO

Crear-Index "C:\nginx\html" "Nginx" "Latest" $PUERTO

}

# -------------------------------
# CAMBIAR PUERTO NGINX
# -------------------------------

function Configurar-Puerto-Nginx($PUERTO){

$config = "C:\nginx\conf\nginx.conf"

if(Test-Path $config){

(Get-Content $config) `
-replace "listen 80","listen $PUERTO" |
Set-Content $config

Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue
Start-Process "C:\nginx\nginx.exe"

}

}