# ============================================================
# menuFTPHTTP.ps1
# Orquestador principal - Practica 7
# Erik Ortiz Leal - Grupo 301
# Windows Server 2022 (sin GUI) - PowerShell
# Ejecutar como Administrador
# ============================================================

# Verificar administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar como Administrador." -ForegroundColor Red
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Cargar funciones HTTP puras (sin menu)
. "$scriptDir\http_funciones.ps1"

# ============================================================
# Funcion: Instalar servicio desde repositorio FTP privado
# Cubre el 35% de la rubrica - cliente FTP dinamico
# ============================================================
function Instalar-DesdeFTP {

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  INSTALAR DESDE REPOSITORIO FTP     " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    # Pedir datos de conexion al FTP
    $ftpIP   = Read-Host "IP del servidor FTP"
    $ftpUser = Read-Host "Usuario FTP"
    $ftpPass = Read-Host "Contrasena FTP"

    $ftpBase = "ftp://$ftpIP/http/Windows"

    Write-Host ""
    Write-Host "Conectando al repositorio FTP..." -ForegroundColor Cyan

    # Listar carpetas de servicios disponibles en /http/Windows/
    try {
        $credencial = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
        $request    = [System.Net.WebRequest]::Create($ftpBase + "/")
        $request.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.Credentials = $credencial

        $response = $request.GetResponse()
        $reader   = New-Object System.IO.StreamReader($response.GetResponseStream())
        $lista    = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()

        $servicios = ($lista -split "`n") | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }

        if ($servicios.Count -eq 0) {
            Write-Host "No se encontraron servicios en el repositorio." -ForegroundColor Red
            return
        }

    } catch {
        Write-Host "Error: No se pudo conectar al FTP. Verifique IP, usuario y contrasena." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Gray
        return
    }

    # Mostrar servicios disponibles
    Write-Host ""
    Write-Host "Servicios disponibles en el repositorio:" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $servicios.Count; $i++) {
        Write-Host "$($i+1)) $($servicios[$i])"
    }
    Write-Host ""

    $selServicio = Read-Host "Seleccione numero de servicio"
    $indice      = [int]$selServicio - 1

    if ($indice -lt 0 -or $indice -ge $servicios.Count) {
        Write-Host "Seleccion invalida." -ForegroundColor Red
        return
    }

    $servicioElegido = $servicios[$indice]
    $rutaServicio    = "$ftpBase/$servicioElegido"

    Write-Host ""
    Write-Host "Listando archivos en $servicioElegido..." -ForegroundColor Cyan

    # Listar archivos binarios dentro de la carpeta del servicio
    try {
        $request2    = [System.Net.WebRequest]::Create($rutaServicio + "/")
        $request2.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request2.Credentials = $credencial

        $response2 = $request2.GetResponse()
        $reader2   = New-Object System.IO.StreamReader($response2.GetResponseStream())
        $lista2    = $reader2.ReadToEnd()
        $reader2.Close()
        $response2.Close()

        # Solo mostrar binarios, no los .sha256
        $archivos = ($lista2 -split "`n") |
            Where-Object { $_.Trim() -ne "" -and $_ -notmatch "\.sha256$" } |
            ForEach-Object { $_.Trim() }

        if ($archivos.Count -eq 0) {
            Write-Host "No se encontraron instaladores en esta carpeta." -ForegroundColor Red
            return
        }

    } catch {
        Write-Host "Error al listar archivos del servicio." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Gray
        return
    }

    # Mostrar archivos disponibles
    Write-Host ""
    Write-Host "Instaladores disponibles:" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $archivos.Count; $i++) {
        Write-Host "$($i+1)) $($archivos[$i])"
    }
    Write-Host ""

    $selArchivo   = Read-Host "Seleccione numero de instalador"
    $indiceArch   = [int]$selArchivo - 1

    if ($indiceArch -lt 0 -or $indiceArch -ge $archivos.Count) {
        Write-Host "Seleccion invalida." -ForegroundColor Red
        return
    }

    $archivoElegido = $archivos[$indiceArch]
    $urlBinario     = "$rutaServicio/$archivoElegido"
    $urlHash        = "$rutaServicio/$archivoElegido.sha256"
    $destBinario    = "$env:TEMP\$archivoElegido"
    $destHash       = "$env:TEMP\$archivoElegido.sha256"

    # Descargar el instalador desde FTP
    Write-Host ""
    Write-Host "Descargando $archivoElegido..." -ForegroundColor Cyan

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Credentials = $credencial
        $wc.DownloadFile($urlBinario, $destBinario)
        Write-Host "Instalador descargado." -ForegroundColor Green
    } catch {
        Write-Host "Error al descargar el instalador." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Gray
        return
    }

    # Descargar el archivo .sha256
    Write-Host "Descargando hash de verificacion..." -ForegroundColor Cyan

    try {
        $wc.DownloadFile($urlHash, $destHash)
        Write-Host "Hash descargado." -ForegroundColor Green
    } catch {
        Write-Host "Error al descargar el archivo .sha256." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Gray
        return
    }

    # ============================================================
    # Verificar integridad SHA256 - 15% de la rubrica
    # ============================================================
    Write-Host ""
    Write-Host "Verificando integridad del archivo..." -ForegroundColor Cyan

    $hashLocal    = (Get-FileHash $destBinario -Algorithm SHA256).Hash.ToUpper()
    $hashEsperado = (Get-Content $destHash -Raw).Trim().ToUpper()

    # El archivo .sha256 puede contener solo el hash o "HASH  nombre_archivo"
    # Extraer solo el hash (primeros 64 caracteres)
    if ($hashEsperado.Length -gt 64) {
        $hashEsperado = ($hashEsperado -split "\s+")[0]
    }

    Write-Host "Hash local   : $hashLocal" -ForegroundColor Gray
    Write-Host "Hash servidor: $hashEsperado" -ForegroundColor Gray

    if ($hashLocal -ne $hashEsperado) {
        Write-Host ""
        Write-Host "ERROR: El archivo esta corrupto. Los hashes no coinciden." -ForegroundColor Red
        Write-Host "Instalacion cancelada." -ForegroundColor Red
        Remove-Item $destBinario -Force -ErrorAction SilentlyContinue
        Remove-Item $destHash    -Force -ErrorAction SilentlyContinue
        return
    }

    Write-Host "Integridad verificada correctamente." -ForegroundColor Green

    # ============================================================
    # Instalar el servicio descargado
    # ============================================================
    Write-Host ""
    Write-Host "Instalando $archivoElegido..." -ForegroundColor Cyan

    $extension = [System.IO.Path]::GetExtension($archivoElegido).ToLower()

    switch ($extension) {
        ".msi" {
            Start-Process msiexec.exe -ArgumentList "/i `"$destBinario`" /quiet /norestart" -Wait
            Write-Host "Instalacion MSI completada." -ForegroundColor Green
        }
        ".exe" {
            Start-Process $destBinario -ArgumentList "/S" -Wait
            Write-Host "Instalacion EXE completada." -ForegroundColor Green
        }
        ".zip" {
            $carpetaDestino = "C:\$([System.IO.Path]::GetFileNameWithoutExtension($archivoElegido))"
            Expand-Archive -Path $destBinario -DestinationPath $carpetaDestino -Force
            Write-Host "ZIP extraido en: $carpetaDestino" -ForegroundColor Green
        }
        default {
            Write-Host "Tipo de archivo no reconocido: $extension" -ForegroundColor Yellow
        }
    }

    # Limpiar temporales
    Remove-Item $destBinario -Force -ErrorAction SilentlyContinue
    Remove-Item $destHash    -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION DESDE FTP COMPLETADA    " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servicio : $servicioElegido"
    Write-Host "Archivo  : $archivoElegido"
    Write-Host "Hash     : OK"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Funcion: Ver estado de los servidores instalados
# ============================================================
function Ver-EstadoServidores {

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  ESTADO DE SERVIDORES               " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    # IIS
    $iis = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($iis) {
        $color = if ($iis.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "IIS (W3SVC)   : $($iis.Status)" -ForegroundColor $color
    } else {
        Write-Host "IIS (W3SVC)   : No instalado" -ForegroundColor Gray
    }

    # FTP
    $ftp = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($ftp) {
        $color = if ($ftp.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "FTP (ftpsvc)  : $($ftp.Status)" -ForegroundColor $color
    } else {
        Write-Host "FTP (ftpsvc)  : No instalado" -ForegroundColor Gray
    }

    # Apache
    $apache = Get-Service Apache2.4 -ErrorAction SilentlyContinue
    if ($apache) {
        $color = if ($apache.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "Apache        : $($apache.Status)" -ForegroundColor $color
    } else {
        Write-Host "Apache        : No instalado" -ForegroundColor Gray
    }

    # Nginx
    $nginx = Get-Process nginx -ErrorAction SilentlyContinue
    if ($nginx) {
        Write-Host "Nginx         : Running" -ForegroundColor Green
    } else {
        Write-Host "Nginx         : No esta corriendo" -ForegroundColor Gray
    }

    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Presione Enter para continuar"
}

# ============================================================
# Menu principal
# ============================================================
while ($true) {

    Write-Host ""
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "   ADMINISTRADOR PRINCIPAL    " -ForegroundColor Cyan
    Write-Host "   Windows Server 2022        " -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) Gestionar servidores HTTP"
    Write-Host "2) Gestionar servidor FTP"
    Write-Host "3) Instalar servicio desde FTP"
    Write-Host "4) Activar SSL/TLS"
    Write-Host "5) Ver estado de servidores"
    Write-Host "6) Salir"
    Write-Host ""

    $op = Read-Host "Seleccione una opcion [1-6]"

    switch ($op) {
        "1" { & "$scriptDir\main.ps1" }
        "2" { & "$scriptDir\FTP.ps1" }
        "3" { Instalar-DesdeFTP }
        "4" { & "$scriptDir\ssl_funciones.ps1" }
        "5" { Ver-EstadoServidores }
        "6" { Write-Host "Saliendo..." -ForegroundColor Yellow; exit 0 }
        default { Write-Host "Opcion no valida." -ForegroundColor Red }
    }
}