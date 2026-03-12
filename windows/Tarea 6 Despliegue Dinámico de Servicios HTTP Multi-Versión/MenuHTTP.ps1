

. "$PSScriptRoot\http_funciones.ps1"

# ============================================================
# main.ps1
# Menu principal - Despliegue de servidores HTTP en Windows
# Windows Server 2019 Core (sin GUI) - PowerShell
# Ejecutar como Administrador
# ============================================================

# Verificar que se ejecuta como Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar este script como Administrador." -ForegroundColor Red
    exit 1
}

# Cargar funciones
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptDir\funciones.ps1"

# ============================================================
# Funcion auxiliar: leer opcion validada (sin caracteres especiales)
# ============================================================
function Leer-Opcion {
    param(
        [string]$Prompt,
        [string[]]$Validas
    )

    while ($true) {
        Write-Host $Prompt -NoNewline
        $input = Read-Host

        # Validar que no sea nulo ni tenga caracteres especiales
        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "Entrada invalida. Intente de nuevo." -ForegroundColor Red
            continue
        }
        if ($input -match '[^\w\d\s\.\-]') {
            Write-Host "Caracter especial no permitido." -ForegroundColor Red
            continue
        }
        if ($Validas -and ($Validas -notcontains $input.Trim())) {
            Write-Host "Opcion no valida. Opciones validas: $($Validas -join ', ')" -ForegroundColor Red
            continue
        }

        return $input.Trim()
    }
}

# ============================================================
# Funcion auxiliar: leer puerto con validacion
# ============================================================
function Leer-Puerto {

    while ($true) {
        Write-Host "Ingrese el puerto de escucha: " -NoNewline
        $input = Read-Host

        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "Puerto no puede estar vacio." -ForegroundColor Red
            continue
        }

        if ($input -notmatch '^\d+$') {
            Write-Host "El puerto debe ser un numero entero." -ForegroundColor Red
            continue
        }

        $resultado = Validar-Puerto -Puerto $input
        if ($resultado) {
            return [int]$input
        }
        # Si Validar-Puerto falla ya imprime el mensaje de error
    }
}

# ============================================================
# Funcion auxiliar: resolver version segun seleccion
# ============================================================
function Resolver-Version {
    param(
        [string]$Seleccion,
        [string]$Latest,
        [string]$Lts,
        [string]$Oldest
    )

    switch ($Seleccion) {
        "1" { return $Latest }
        "2" { return $Lts    }
        "3" { return $Oldest }
    }
}

# ============================================================
# Bucle principal del menu
# ============================================================
while ($true) {

    Write-Host ""
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "  DESPLIEGUE SERVIDORES HTTP  " -ForegroundColor Cyan
    Write-Host "    Windows Server 2019       " -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) IIS (Internet Information Services) - Obligatorio"
    Write-Host "2) Apache HTTP Server (Win64)"
    Write-Host "3) Nginx para Windows"
    Write-Host "4) Salir"
    Write-Host ""

    $opcion = Leer-Opcion -Prompt "Seleccione una opcion [1-4]: " -Validas @("1","2","3","4")

    switch ($opcion) {

        # --------------------------------------------------
        # IIS
        # --------------------------------------------------
        "1" {
            Listar-Versiones-IIS

            $verNum = Leer-Opcion -Prompt "Seleccione numero de version [1-2]: " -Validas @("1","2")

            # IIS version es la del sistema, ambas opciones retornan la misma
            $version = "10.0"

            $puerto = Leer-Puerto

            Instalar-IIS -Version $version -Puerto $puerto
        }

        # --------------------------------------------------
        # Apache Win64
        # --------------------------------------------------
        "2" {
            Listar-Versiones-Apache

            $verNum = Leer-Opcion -Prompt "Seleccione numero de version [1-3]: " -Validas @("1","2","3")

            $version = Resolver-Version `
                -Seleccion $verNum `
                -Latest  $global:APACHE_LATEST `
                -Lts     $global:APACHE_LTS `
                -Oldest  $global:APACHE_OLDEST

            $puerto = Leer-Puerto

            Instalar-Apache -Version $version -Puerto $puerto
        }

        # --------------------------------------------------
        # Nginx Windows
        # --------------------------------------------------
        "3" {
            Listar-Versiones-Nginx

            $verNum = Leer-Opcion -Prompt "Seleccione numero de version [1-3]: " -Validas @("1","2","3")

            $version = Resolver-Version `
                -Seleccion $verNum `
                -Latest  $global:NGINX_LATEST `
                -Lts     $global:NGINX_LTS `
                -Oldest  $global:NGINX_OLDEST

            $puerto = Leer-Puerto

            Instalar-Nginx -Version $version -Puerto $puerto
        }

        # --------------------------------------------------
        # Salir
        # --------------------------------------------------
        "4" {
            Write-Host "Saliendo..." -ForegroundColor Yellow
            exit 0
        }

    }

}