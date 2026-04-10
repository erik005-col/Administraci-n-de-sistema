# ============================================================
# ssl_funciones.ps1
# Configuracion SSL/TLS para servidores Windows
# IIS (HTTP + FTP), Apache, Nginx
# Windows Server 2022 (sin GUI) - PowerShell
# Ejecutar como Administrador
# Erik Ortiz Leal - Grupo 301
# ============================================================

# Verificar administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar como Administrador." -ForegroundColor Red
    exit 1
}

# Dominio que pide el profe
$dominio = "reprobados.com"
$dominioWWW = "www.reprobados.com"

# ============================================================
# Funcion: Generar certificado autofirmado
# Unico certificado para todos los servicios Windows
# ============================================================
function Generar-Certificado {

    Write-Host ""
    Write-Host "Generando certificado autofirmado para $dominioWWW..." -ForegroundColor Cyan

    # Verificar si ya existe
    $certExistente = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like "*$dominio*" } |
        Select-Object -First 1

    if ($certExistente) {
        Write-Host "Certificado ya existe: $($certExistente.Thumbprint)" -ForegroundColor Yellow
        return $certExistente
    }

    # Generar nuevo certificado autofirmado
    $cert = New-SelfSignedCertificate `
        -DnsName $dominioWWW, $dominio, "localhost" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddDays(365) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature, KeyEncipherment `
        -FriendlyName "Certificado SSL $dominio"

    Write-Host "Certificado generado." -ForegroundColor Green
    Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray

    # Agregar al almacen de confianza para evitar advertencias
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::Root,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $store.Add($cert)
    $store.Close()

    Write-Host "Certificado agregado al almacen de confianza." -ForegroundColor Green

    return $cert
}

# ============================================================
# Funcion: Activar SSL en IIS (puerto 443 + redireccion)
# ============================================================
function Activar-SSL-IIS {

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  ACTIVANDO SSL EN IIS               " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    # Verificar que IIS esta instalado
    $iis = Get-Service W3SVC -ErrorAction SilentlyContinue
    if (-not $iis) {
        Write-Host "Error: IIS no esta instalado." -ForegroundColor Red
        return
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Generar o recuperar certificado
    $cert = Generar-Certificado

    $siteName = "Default Web Site"

    # Agregar binding HTTPS en puerto 443
    $bindingExiste = Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue
    if (-not $bindingExiste) {
        New-WebBinding -Name $siteName -Protocol "https" -Port 443 -IPAddress "*" -SslFlags 0
        Write-Host "Binding HTTPS 443 creado en IIS." -ForegroundColor Green
    } else {
        Write-Host "Binding HTTPS ya existe en IIS." -ForegroundColor Yellow
    }

    # Asignar el certificado al binding 443
    $binding = Get-WebBinding -Name $siteName -Protocol "https"
    $binding.AddSslCertificate($cert.Thumbprint, "My")
    Write-Host "Certificado asignado al sitio IIS." -ForegroundColor Green

    # Configurar redireccion HTTP -> HTTPS (HSTS basico)
    Install-WindowsFeature Web-Http-Redirect -ErrorAction SilentlyContinue | Out-Null

    $webConfig = "C:\inetpub\wwwroot\web.config"
    $contenido = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <httpRedirect enabled="true" destination="https://$dominioWWW/" exactDestination="false" httpResponseStatus="Permanent" />
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
    [System.IO.File]::WriteAllText($webConfig, $contenido, [System.Text.Encoding]::UTF8)
    Write-Host "Redireccion HTTP -> HTTPS configurada en IIS." -ForegroundColor Green

    # Abrir puerto 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-443-IIS" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "HTTPS-443-IIS" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 443 `
        -Action Allow | Out-Null

    iisreset /restart | Out-Null

    # Verificar
    Start-Sleep -Seconds 3
    $verif = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    if ($verif.TcpTestSucceeded) {
        Write-Host "IIS respondiendo en puerto 443." -ForegroundColor Green
    } else {
        Write-Host "Advertencia: IIS no responde en puerto 443 aun." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " SSL IIS ACTIVADO                    " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "URL : https://$dominioWWW"
    Write-Host "Puerto : 443"
    Write-Host "Cert   : $($cert.Thumbprint)"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Funcion: Activar FTPS en IIS-FTP
# ============================================================
function Activar-SSL-FTP {

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  ACTIVANDO FTPS EN IIS-FTP          " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    $ftp = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if (-not $ftp) {
        Write-Host "Error: Servicio FTP no esta instalado." -ForegroundColor Red
        return
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $cert    = Generar-Certificado
    $ftpSite = "FTP_SERVER"

    # Verificar que el sitio FTP existe
    if (-not (Get-WebSite $ftpSite -ErrorAction SilentlyContinue)) {
        Write-Host "Error: Sitio FTP '$ftpSite' no encontrado. Ejecute primero FTP.ps1." -ForegroundColor Red
        return
    }

    # Asignar certificado al FTP
    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.ssl.serverCertHash `
        -Value $cert.Thumbprint

    # Requerir SSL en canal de control y datos (modo FTPS explicito)
    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.ssl.controlChannelPolicy `
        -Value 1   # 1 = SslRequire

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.ssl.dataChannelPolicy `
        -Value 1   # 1 = SslRequire

    Restart-Service ftpsvc

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " FTPS ACTIVADO                       " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Protocolo : FTPS (SSL explicito)"
    Write-Host "Puerto    : 21 con TLS"
    Write-Host "Cert      : $($cert.Thumbprint)"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Funcion: Activar SSL en Apache Windows
# ============================================================
function Activar-SSL-Apache {

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  ACTIVANDO SSL EN APACHE            " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    $apacheBase = "C:\Apache24"

    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        Write-Host "Error: Apache no encontrado en $apacheBase" -ForegroundColor Red
        return
    }

    $cert = Generar-Certificado

    # Exportar certificado a archivos PEM que Apache puede leer
    $certDir  = "$apacheBase\conf\ssl"
    $certFile = "$certDir\server.crt"
    $keyFile  = "$certDir\server.key"

    New-Item $certDir -ItemType Directory -Force | Out-Null

    # Exportar certificado (.crt)
    $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $certB64   = [System.Convert]::ToBase64String($certBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
    $certPem   = "-----BEGIN CERTIFICATE-----`n$certB64`n-----END CERTIFICATE-----"
    [System.IO.File]::WriteAllText($certFile, $certPem)

    # Exportar clave privada (.key) usando openssl si esta disponible
    $opensslPath = "C:\Apache24\bin\openssl.exe"
    if (Test-Path $opensslPath) {
        $pfxTemp = "$env:TEMP\apache_temp.pfx"
        $pfxPwd  = "temporal123"
        $secPwd  = ConvertTo-SecureString $pfxPwd -AsPlainText -Force

        Export-PfxCertificate -Cert $cert -FilePath $pfxTemp -Password $secPwd | Out-Null

        & $opensslPath pkcs12 -in $pfxTemp -nocerts -nodes -out $keyFile -passin pass:$pfxPwd 2>&1 | Out-Null
        Remove-Item $pfxTemp -Force -ErrorAction SilentlyContinue
        Write-Host "Clave privada exportada con OpenSSL." -ForegroundColor Green
    } else {
        # Fallback: crear clave con New-SelfSignedCertificate directo a archivo
        Write-Host "OpenSSL no encontrado, usando metodo alternativo..." -ForegroundColor Yellow
        $pfxTemp = "$env:TEMP\apache_temp.pfx"
        $pfxPwd  = "temporal123"
        $secPwd  = ConvertTo-SecureString $pfxPwd -AsPlainText -Force
        Export-PfxCertificate -Cert $cert -FilePath $pfxTemp -Password $secPwd | Out-Null
        Copy-Item $pfxTemp $keyFile -Force
        Remove-Item $pfxTemp -Force -ErrorAction SilentlyContinue
        Write-Host "Certificado PFX copiado como key (requiere openssl para produccion)." -ForegroundColor Yellow
    }

    Write-Host "Archivos SSL creados en $certDir" -ForegroundColor Green

    # Configurar httpd.conf para SSL
    $confPath = "$apacheBase\conf\httpd.conf"

    # Habilitar modulos SSL
    $conf = Get-Content $confPath -Raw
    $conf = $conf -replace "#LoadModule ssl_module",     "LoadModule ssl_module"
    $conf = $conf -replace "#LoadModule socache_shmcb",  "LoadModule socache_shmcb"
    $conf = $conf -replace "#Include conf/extra/httpd-ssl.conf", "Include conf/extra/httpd-ssl.conf"
    [System.IO.File]::WriteAllText($confPath, $conf)

    # Crear httpd-ssl.conf con VirtualHost 443
    $sslConf = "$apacheBase\conf\extra\httpd-ssl.conf"
    $sslContent = @"
Listen 443

SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLProxyCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLHonorCipherOrder on
SSLProtocol all -SSLv3
SSLProxyProtocol all -SSLv3
SSLPassPhraseDialog  builtin
SSLSessionCache        "shmcb:`${SRVROOT}/logs/ssl_scache(512000)"
SSLSessionCacheTimeout  300

<VirtualHost *:443>
    DocumentRoot "`${SRVROOT}/htdocs"
    ServerName $dominioWWW:443

    SSLEngine on
    SSLCertificateFile    "`${SRVROOT}/conf/ssl/server.crt"
    SSLCertificateKeyFile "`${SRVROOT}/conf/ssl/server.key"

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</VirtualHost>

<VirtualHost *:80>
    ServerName $dominioWWW
    Redirect permanent / https://$dominioWWW/
</VirtualHost>
"@
    [System.IO.File]::WriteAllText($sslConf, $sslContent, [System.Text.Encoding]::UTF8)

    Write-Host "Configuracion SSL de Apache creada." -ForegroundColor Green

    # Reiniciar Apache
    Stop-Service -Name "Apache2.4" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Abrir puerto 443
    Remove-NetFirewallRule -DisplayName "HTTPS-443-Apache" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "HTTPS-443-Apache" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 443 `
        -Action Allow | Out-Null

    $verif = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    if ($verif.TcpTestSucceeded) {
        Write-Host "Apache respondiendo en puerto 443." -ForegroundColor Green
    } else {
        Write-Host "Advertencia: Apache no responde en 443 aun. Revise logs." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " SSL APACHE ACTIVADO                 " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "URL  : https://$dominioWWW"
    Write-Host "Cert : $certFile"
    Write-Host "Key  : $keyFile"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Funcion: Activar SSL en Nginx Windows
# ============================================================
function Activar-SSL-Nginx {

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  ACTIVANDO SSL EN NGINX             " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    $nginxBase = "C:\nginx"

    if (-not (Test-Path "$nginxBase\nginx.exe")) {
        Write-Host "Error: Nginx no encontrado en $nginxBase" -ForegroundColor Red
        return
    }

    $cert = Generar-Certificado

    # Exportar certificado a PEM
    $certDir  = "$nginxBase\conf\ssl"
    $certFile = "$certDir\server.crt"
    $keyFile  = "$certDir\server.key"

    New-Item $certDir -ItemType Directory -Force | Out-Null

    $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $certB64   = [System.Convert]::ToBase64String($certBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
    $certPem   = "-----BEGIN CERTIFICATE-----`n$certB64`n-----END CERTIFICATE-----"
    [System.IO.File]::WriteAllText($certFile, $certPem)

    # Exportar clave
    $pfxTemp = "$env:TEMP\nginx_temp.pfx"
    $pfxPwd  = "temporal123"
    $secPwd  = ConvertTo-SecureString $pfxPwd -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $pfxTemp -Password $secPwd | Out-Null

    $opensslPath = "$nginxBase\openssl.exe"
    if (-not (Test-Path $opensslPath)) {
        $opensslPath = "C:\Apache24\bin\openssl.exe"
    }

    if (Test-Path $opensslPath) {
        & $opensslPath pkcs12 -in $pfxTemp -nocerts -nodes -out $keyFile -passin pass:$pfxPwd 2>&1 | Out-Null
        Write-Host "Clave privada exportada con OpenSSL." -ForegroundColor Green
    } else {
        Copy-Item $pfxTemp $keyFile -Force
        Write-Host "OpenSSL no encontrado. Clave copiada como PFX." -ForegroundColor Yellow
    }

    Remove-Item $pfxTemp -Force -ErrorAction SilentlyContinue

    Write-Host "Archivos SSL creados en $certDir" -ForegroundColor Green

    # Reescribir nginx.conf con soporte SSL y redireccion
    $confPath  = "$nginxBase\conf\nginx.conf"
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

    # Redireccion HTTP -> HTTPS
    server {
        listen 80;
        server_name $dominioWWW $dominio;
        return 301 https://`$host`$request_uri;
    }

    # HTTPS
    server {
        listen 443 ssl;
        server_name $dominioWWW $dominio;

        ssl_certificate     conf/ssl/server.crt;
        ssl_certificate_key conf/ssl/server.key;

        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        root  html;
        index index.html index.htm;

        location / {
            try_files `$uri `$uri/ =404;
        }

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
    }
}
"@
    [System.IO.File]::WriteAllText($confPath, $nginxConf, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Configuracion SSL de Nginx creada." -ForegroundColor Green

    # Reiniciar Nginx
    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
    Start-Sleep -Seconds 3

    # Abrir puerto 443
    Remove-NetFirewallRule -DisplayName "HTTPS-443-Nginx" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "HTTPS-443-Nginx" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 443 `
        -Action Allow | Out-Null

    $verif = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    if ($verif.TcpTestSucceeded) {
        Write-Host "Nginx respondiendo en puerto 443." -ForegroundColor Green
    } else {
        Write-Host "Advertencia: Nginx no responde en 443 aun. Revise logs." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " SSL NGINX ACTIVADO                  " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "URL  : https://$dominioWWW"
    Write-Host "Cert : $certFile"
    Write-Host "Key  : $keyFile"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Funcion: Verificar estado SSL de todos los servidores
# ============================================================
function Verificar-SSL {

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  VERIFICACION SSL - RESUMEN         " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    $servidores = @(
        @{ Nombre = "IIS HTTPS";    Puerto = 443 },
        @{ Nombre = "Apache HTTPS"; Puerto = 443 },
        @{ Nombre = "Nginx HTTPS";  Puerto = 443 },
        @{ Nombre = "FTP-SSL";      Puerto = 21  }
    )

    foreach ($srv in $servidores) {
        $test = Test-NetConnection -ComputerName localhost -Port $srv.Puerto -WarningAction SilentlyContinue
        if ($test.TcpTestSucceeded) {
            Write-Host "$($srv.Nombre) (puerto $($srv.Puerto)) : ACTIVO" -ForegroundColor Green
        } else {
            Write-Host "$($srv.Nombre) (puerto $($srv.Puerto)) : INACTIVO" -ForegroundColor Red
        }
    }

    # Mostrar info del certificado
    Write-Host ""
    Write-Host "Certificado en almacen:" -ForegroundColor Cyan
    Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like "*$dominio*" } |
        ForEach-Object {
            Write-Host "  Subject    : $($_.Subject)" -ForegroundColor Gray
            Write-Host "  Thumbprint : $($_.Thumbprint)" -ForegroundColor Gray
            Write-Host "  Expira     : $($_.NotAfter)" -ForegroundColor Gray
        }

    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Presione Enter para continuar"
}

# ============================================================
# Menu SSL
# ============================================================
while ($true) {

    Write-Host ""
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "   CONFIGURACION SSL/TLS      " -ForegroundColor Cyan
    Write-Host "   Windows Server 2022        " -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) Activar SSL en IIS (HTTPS)"
    Write-Host "2) Activar FTPS en IIS-FTP"
    Write-Host "3) Activar SSL en Apache"
    Write-Host "4) Activar SSL en Nginx"
    Write-Host "5) Activar SSL en todos"
    Write-Host "6) Verificar estado SSL"
    Write-Host "7) Regresar al menu principal"
    Write-Host ""

    $op = Read-Host "Seleccione una opcion [1-7]"

    switch ($op) {
        "1" { Activar-SSL-IIS }
        "2" { Activar-SSL-FTP }
        "3" { Activar-SSL-Apache }
        "4" { Activar-SSL-Nginx }
        "5" {
            Activar-SSL-IIS
            Activar-SSL-FTP
            Activar-SSL-Apache
            Activar-SSL-Nginx
        }
        "6" { Verificar-SSL }
        "7" {
            Write-Host "Regresando al menu principal..." -ForegroundColor Yellow
            return
        }
        default { Write-Host "Opcion no valida." -ForegroundColor Red }
    }
}