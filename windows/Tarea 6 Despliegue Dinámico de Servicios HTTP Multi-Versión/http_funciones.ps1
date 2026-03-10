Import-Module WebAdministration
function Validate-Input {

    param($input)

    if ([string]::IsNullOrWhiteSpace($input)) {
        return $false
    }

    $input = $input.Trim()

    if ($input -notmatch '^[1-5]$') {
        return $false
    }

    return $true
}

function Validate-Port {

    param($port)

    if ($port -lt 1 -or $port -gt 65535) {
        Write-Host "Puerto invalido"
        return $false
    }

    $reserved = @(21,22,23,25,53,110,135,139,443)

    if ($reserved -contains $port) {
        Write-Host "Puerto reservado"
        return $false
    }

    return $true
}

function Test-PortAvailability {

    param($port)

    $result = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue

    if ($result) {
        Write-Host "Puerto en uso"
        return $false
    }

    return $true
}

function Get-ApacheVersions {

    choco info apache-httpd --all | Select-String "apache-httpd"
}

function Get-NginxVersions {

    choco info nginx --all | Select-String "nginx"
}

function Install-IIS {

    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All -NoRestart
}

function Set-IISPort {

    param($port)

    Remove-WebBinding -Name "Default Web Site" -Protocol "http" -Port 80 -ErrorAction SilentlyContinue

    New-WebBinding -Name "Default Web Site" -Protocol http -Port $port
}

function Install-Apache {

    param($version)

    choco install apache-httpd --version=$version -y
}

function Set-ApachePort {

    param($port)

    $conf="C:\tools\Apache24\conf\httpd.conf"

    (Get-Content $conf) -replace "Listen 80","Listen $port" | Set-Content $conf

    Restart-Service Apache2.4
}

function Install-Nginx {

    param($version)

    choco install nginx --version=$version -y
}

function Set-NginxPort {

    param($port)

    $conf="C:\tools\nginx\conf\nginx.conf"

    (Get-Content $conf) -replace "listen 80","listen $port" | Set-Content $conf
}

function Open-FirewallPort {

    param($port)

    New-NetFirewallRule -DisplayName "HTTP-Custom-$port" -LocalPort $port -Protocol TCP -Action Allow
}

function Create-IndexPage {

    param($server,$version,$port)

    $path="C:\inetpub\wwwroot\index.html"

$content = @"
<html>
<head><title>Servidor HTTP</title></head>
<body>
<h1>Servidor: $server</h1>
<h2>Version: $version</h2>
<h3>Puerto: $port</h3>
</body>
</html>
"@

    Set-Content $path $content
}

function Create-ServiceUser {

    $password = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

    New-LocalUser -Name "websvc" -Password $password -FullName "HTTP Service User" -ErrorAction SilentlyContinue
}

function Set-WebPermissions {

    $path="C:\inetpub\wwwroot"

    icacls $path /inheritance:r

    icacls $path /grant "websvc:(OI)(CI)RX"
}

function Secure-IISHeaders {

Remove-WebConfigurationProperty `
-pspath 'MACHINE/WEBROOT/APPHOST' `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-AtElement @{name='X-Powered-By'} `
-ErrorAction SilentlyContinue

}

function Set-IISSecurityHeaders {

Add-WebConfigurationProperty `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-value @{name='X-Frame-Options';value='SAMEORIGIN'}

Add-WebConfigurationProperty `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-value @{name='X-Content-Type-Options';value='nosniff'}

}

function Block-DangerousMethods {

Add-WebConfiguration `
-Filter "/system.webServer/security/requestFiltering/verbs" `
-Value @{verb="TRACE";allowed="false"} `
-PSPath IIS:\

Add-WebConfiguration `
-Filter "/system.webServer/security/requestFiltering/verbs" `
-Value @{verb="TRACK";allowed="false"} `
-PSPath IIS:\

Add-WebConfiguration `
-Filter "/system.webServer/security/requestFiltering/verbs" `
-Value @{verb="DELETE";allowed="false"} `
-PSPath IIS:\

}
function Check-Chocolatey {

    if (!(Get-Command choco -ErrorAction SilentlyContinue)) {

        Write-Host "Chocolatey no esta instalado. Instalando..."

        Set-ExecutionPolicy Bypass -Scope Process -Force

        [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    }

}
function Close-DefaultHTTPPorts {

    Remove-NetFirewallRule -DisplayName "HTTP-Default-80" -ErrorAction SilentlyContinue

    Remove-NetFirewallRule -DisplayName "HTTP-Default-443" -ErrorAction SilentlyContinue

}

function Validate-Service {

    param($service)

    $svc = Get-Service $service -ErrorAction SilentlyContinue

    if ($svc) {

        Write-Host "$service instalado correctamente"

    }
    else {

        Write-Host "Error instalando $service"

    }

}

function Restart-WebService {

    param($service)

    Restart-Service $service -ErrorAction SilentlyContinue

    Write-Host "Servicio reiniciado"

}

function Check-IIS {

    $feature = Get-WindowsFeature -Name Web-Server

    if ($feature.Installed) {

        Write-Host "IIS ya esta instalado"

    }
    else {

        Install-IIS

    }

}