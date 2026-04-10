# =============================================================================
#  MENU.PS1 - Interfaz principal de administracion de Dominio AD
#  Practica: GPO + FSRM | Active Directory
#  Requiere: funciones.ps1 en el mismo directorio
# =============================================================================

# Verificar privilegios de administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  [!] Este script requiere privilegios de Administrador." -ForegroundColor Red
    Write-Host "  [!] Ejecuta PowerShell como Administrador e intenta de nuevo." -ForegroundColor Red
    Write-Host ""
    Read-Host "Presiona ENTER para salir"
    exit
}

# Importar funciones
$funcionesPath = "$PSScriptRoot\funciones.ps1"
if (-not (Test-Path $funcionesPath)) {
    Write-Host ""
    Write-Host "  [!] No se encontro funciones.ps1" -ForegroundColor Red
    Write-Host "  [!] Ruta buscada: $funcionesPath" -ForegroundColor Red
    Write-Host "  [!] Asegurate de tener funciones.ps1 en la misma carpeta que menu.ps1" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Presiona ENTER para salir"
    exit
}

try {
    . $funcionesPath
    Write-Host "  [+] funciones.ps1 cargado correctamente." -ForegroundColor Green
    Start-Sleep -Seconds 1
} catch {
    Write-Host ""
    Write-Host "  [!] Error al cargar funciones.ps1: $_" -ForegroundColor Red
    Write-Host "  [!] Verifica que el archivo no este corrupto." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Presiona ENTER para salir"
    exit
}

# =============================================================================
#  FUNCIONES DE UI
# =============================================================================

function Show-Clear {
    [System.Console]::Clear()
}

function Write-Top {
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
}

function Write-Bottom {
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
}

function Write-Div {
    Write-Host "  |----------------------------------------------------------|" -ForegroundColor DarkGray
}

function Write-Empty {
    Write-Host "  |                                                          |" -ForegroundColor DarkCyan
}

function Write-Row {
    param(
        [string]$texto,
        [string]$color = "White"
    )
    $max = 58
    if ($texto.Length -gt $max) { $texto = $texto.Substring(0, $max) }
    $pad = $max - $texto.Length
    Write-Host "  | " -ForegroundColor DarkCyan -NoNewline
    Write-Host $texto -ForegroundColor $color -NoNewline
    Write-Host (" " * $pad) -NoNewline
    Write-Host " |" -ForegroundColor DarkCyan
}

function Write-Option {
    param(
        [string]$num,
        [string]$label,
        [string]$hint = ""
    )
    $inner  = " [" + $num + "]  " + $label
    $maxInner = 58
    $hintPad  = $maxInner - $inner.Length - $hint.Length
    if ($hintPad -lt 1) { $hintPad = 1 }

    Write-Host "  |" -ForegroundColor DarkCyan -NoNewline
    Write-Host " [" -ForegroundColor DarkGray -NoNewline
    Write-Host $num -ForegroundColor Cyan -NoNewline
    Write-Host "]  " -ForegroundColor DarkGray -NoNewline
    Write-Host $label -ForegroundColor White -NoNewline
    Write-Host (" " * $hintPad) -NoNewline
    Write-Host $hint -ForegroundColor DarkGray -NoNewline
    Write-Host " |" -ForegroundColor DarkCyan
}

function Show-Banner {
    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  |" -ForegroundColor Cyan -NoNewline
    Write-Host "   ____                        _         ___  ____          " -ForegroundColor White -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  |" -ForegroundColor Cyan -NoNewline
    Write-Host "  |  _ \  ___  _ __ ___   __ _(_)_ __   / _ \|  _ \        " -ForegroundColor Cyan -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  |" -ForegroundColor Cyan -NoNewline
    Write-Host "  | | | |/ _ \| '_ ' _ \ / _' | | '_ \ | | | | |_) |      " -ForegroundColor Cyan -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  |" -ForegroundColor Cyan -NoNewline
    Write-Host "  | |_| | (_) | | | | | | (_| | | | | || |_| |  __/        " -ForegroundColor DarkCyan -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  |" -ForegroundColor Cyan -NoNewline
    Write-Host "  |____/ \___/|_| |_| |_|\__,_|_|_| |_| \___/|_|           " -ForegroundColor DarkCyan -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  |" -ForegroundColor Cyan -NoNewline
    Write-Host "      Active Directory  *  GPO  *  FSRM  *  AppLocker       " -ForegroundColor DarkCyan -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Status {
    $hora      = Get-Date -Format "HH:mm:ss"
    $fecha     = Get-Date -Format "dd/MM/yyyy"
    $equipo    = $env:COMPUTERNAME
    $usuario   = $env:USERNAME
    $domActual = "No configurado aun"
    try { $domActual = (Get-ADDomain -ErrorAction Stop).DNSRoot } catch {}

    Write-Top
    Write-Row "  ESTADO DEL SISTEMA" "Cyan"
    Write-Div
    Write-Row ("  Equipo  : " + $equipo.PadRight(18) + "  Fecha : " + $fecha) "White"
    Write-Row ("  Usuario : " + $usuario.PadRight(18) + "  Hora  : " + $hora) "White"
    Write-Row ("  Dominio : " + $domActual) "Green"
    Write-Bottom
}

function Show-Menu {
    Show-Clear
    Show-Banner
    Show-Status
    Write-Host ""
    Write-Top
    Write-Row "  MENU PRINCIPAL  --  Administrador de Dominio AD" "Cyan"
    Write-Div
    Write-Empty
    Write-Option "1" "Instalar dependencias"           "[ Roles AD, FSRM, RSAT ]"
    Write-Empty
    Write-Option "2" "Promover a Domain Controller"    "[ ADDS Forest      ]"
    Write-Empty
    Write-Option "3" "Crear OUs y usuarios desde CSV"  "[ Cuates/NoCuates  ]"
    Write-Empty
    Write-Option "4" "Configurar Logon Hours"          "[ Horarios acceso  ]"
    Write-Empty
    Write-Option "5" "Configurar cuotas FSRM"          "[ 10MB / 5MB       ]"
    Write-Empty
    Write-Option "6" "Configurar File Screening"       "[ mp3 mp4 exe msi  ]"
    Write-Empty
    Write-Option "7" "Configurar AppLocker"            "[ Notepad x grupo  ]"
    Write-Empty
    Write-Option "8" "Generar script Linux"            "[ join_linux.sh    ]"
    Write-Empty
    Write-Option "9" "Despliegue COMPLETO (1,3 al 8)"  "[ Requiere DC listo]"
    Write-Empty
    Write-Option "10" "Notificacion email FSRM"        "[ Cuota al 80/100%]"
    Write-Empty
    Write-Option "11" "Verificar configuracion"        "[ Checklist auto   ]"
    Write-Empty
    Write-Div
    Write-Option "0" "Salir" ""
    Write-Bottom
    Write-Host ""
}

function Show-Confirm {
    param([string]$accion)
    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  |  Confirmar: " -ForegroundColor Yellow -NoNewline
    $short = $accion
    if ($short.Length -gt 44) { $short = $short.Substring(0, 44) }
    Write-Host $short -ForegroundColor White -NoNewline
    $pad = 44 - $short.Length
    if ($pad -lt 0) { $pad = 0 }
    Write-Host (" " * $pad) -NoNewline
    Write-Host "  |" -ForegroundColor Yellow
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Yellow
    $resp = Read-Host "  Continuar? (S/N)"
    return ($resp -match "^[sS]$")
}

function Show-Done {
    param([string]$msg)
    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  [OK] " -ForegroundColor Green -NoNewline
    $short = $msg
    if ($short.Length -gt 51) { $short = $short.Substring(0, 51) }
    Write-Host $short -ForegroundColor Green -NoNewline
    $pad = 51 - $short.Length
    if ($pad -lt 0) { $pad = 0 }
    Write-Host (" " * $pad) -NoNewline
    Write-Host "|" -ForegroundColor Green
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Green
    Write-Host ""
    Read-Host "  Presiona ENTER para continuar"
}

function Show-Header {
    param([string]$titulo)
    Show-Clear
    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |  " -ForegroundColor Cyan -NoNewline
    $t = $titulo.ToUpper()
    Write-Host $t -ForegroundColor White -NoNewline
    $pad = 55 - $t.Length
    if ($pad -lt 0) { $pad = 0 }
    Write-Host (" " * $pad) -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Progress {
    param([string]$msg, [int]$paso, [int]$total)
    $pct  = [math]::Round(($paso / $total) * 100)
    $fill = [math]::Round(($paso / $total) * 30)
    $bar  = ("#" * $fill) + ("-" * (30 - $fill))
    Write-Host ("`r  [$bar] $pct% - $msg     ") -ForegroundColor Cyan -NoNewline
    if ($paso -eq $total) { Write-Host "" }
}

# =============================================================================
#  LOOP PRINCIPAL DEL MENU
# =============================================================================

$run = $true

while ($run) {
    Show-Menu
    $op = Read-Host "  Selecciona una opcion"

    switch ($op) {

        "1" {
            if (Show-Confirm "Instalar roles y dependencias") {
                Show-Header "Instalando dependencias"
                Instalar-Dependencias
                Show-Done "Dependencias instaladas correctamente"
            }
        }

        "2" {
            Show-Header "Promocion a Domain Controller"
            Write-Host "  [!] ATENCION: Esta opcion reinicia el servidor." -ForegroundColor Yellow
            Write-Host "  [!] Despues del reinicio vuelve a ejecutar menu.ps1" -ForegroundColor Yellow
            Write-Host "  [!] y continua desde la opcion 3." -ForegroundColor Yellow
            Write-Host ""
            if (Show-Confirm "Promover servidor a Domain Controller (REINICIARA)") {
                Promover-DomainController
                Show-Done "Servidor promovido (el equipo se reiniciara)"
            }
        }

        "3" {
            if (Show-Confirm "Crear OUs y usuarios desde CSV") {
                Show-Header "Creando OUs y usuarios"
                Crear-OUsYUsuarios
                Show-Done "OUs y usuarios creados correctamente"
            }
        }

        "4" {
            if (Show-Confirm "Configurar horarios de acceso") {
                Show-Header "Configurando Logon Hours"
                Write-Host "  Cuates   : 08:00 - 15:00  (lunes a domingo)" -ForegroundColor Green
                Write-Host "  NoCuates : 15:00 - 02:00  (lunes a domingo)" -ForegroundColor Yellow
                Write-Host "  GPO      : ForceLogoff activo (expulsa sesion activa)" -ForegroundColor Cyan
                Write-Host ""
                Configurar-LogonHours
                Show-Done "Horarios de acceso y GPO ForceLogoff configurados"
            }
        }

        "5" {
            if (Show-Confirm "Configurar cuotas FSRM") {
                Show-Header "Configurando cuotas FSRM"
                Write-Host "  Cuates   : 10 MB por usuario (hard quota)" -ForegroundColor Green
                Write-Host "  NoCuates :  5 MB por usuario (hard quota)" -ForegroundColor Yellow
                Write-Host ""
                Configurar-CuotasFSRM
                Show-Done "Cuotas FSRM aplicadas correctamente"
            }
        }

        "6" {
            if (Show-Confirm "Configurar apantallamiento de archivos") {
                Show-Header "Configurando File Screening"
                Write-Host "  Bloqueando (Active Screening):" -ForegroundColor Red
                Write-Host "    .mp3  .mp4  (multimedia)" -ForegroundColor Red
                Write-Host "    .exe  .msi  (ejecutables)" -ForegroundColor Red
                Write-Host ""
                Configurar-FileScreening
                Show-Done "File Screening activo en todas las carpetas"
            }
        }

        "7" {
            if (Show-Confirm "Configurar AppLocker") {
                Show-Header "Configurando AppLocker"
                Write-Host "  Cuates   : Bloc de Notas PERMITIDO (por ruta)" -ForegroundColor Green
                Write-Host "  NoCuates : Bloc de Notas BLOQUEADO (por hash SHA256)" -ForegroundColor Red
                Write-Host "  GPO      : Vinculada a cada OU por separado" -ForegroundColor Cyan
                Write-Host ""
                Configurar-AppLocker
                Show-Done "AppLocker configurado por grupo"
            }
        }

        "8" {
            if (Show-Confirm "Generar script Linux de union al dominio") {
                Show-Header "Generando script Linux"
                Generar-ScriptLinux
                Show-Done "Script join_linux.sh generado en la carpeta"
            }
        }

        "9" {
            Show-Header "Despliegue automatico completo"
            Write-Host "  [!] NOTA: La opcion 2 (Promover DC) NO forma parte del" -ForegroundColor Yellow
            Write-Host "  [!] despliegue automatico porque requiere reinicio del" -ForegroundColor Yellow
            Write-Host "  [!] servidor. Asegurate de haber completado la opcion 2" -ForegroundColor Yellow
            Write-Host "  [!] y reiniciado ANTES de continuar aqui." -ForegroundColor Yellow
            Write-Host ""
            if (Show-Confirm "DESPLIEGUE COMPLETO pasos 1, 3 al 8") {

                $pasos = @(
                    @{ N = "Instalando dependencias";     F = { Instalar-Dependencias } },
                    @{ N = "Creando OUs y usuarios";      F = { Crear-OUsYUsuarios } },
                    @{ N = "Configurando Logon Hours";    F = { Configurar-LogonHours } },
                    @{ N = "Configurando cuotas FSRM";    F = { Configurar-CuotasFSRM } },
                    @{ N = "Configurando File Screening"; F = { Configurar-FileScreening } },
                    @{ N = "Configurando AppLocker";      F = { Configurar-AppLocker } },
                    @{ N = "Generando script Linux";      F = { Generar-ScriptLinux } }
                )

                $i = 0
                foreach ($p in $pasos) {
                    $i++
                    Write-Host ""
                    Write-Host "  -- Paso $i/$($pasos.Count): $($p.N)" -ForegroundColor Cyan
                    Show-Progress $p.N $i $pasos.Count
                    & $p.F
                }

                Write-Host ""
                Write-Host "  +----------------------------------------------------------+" -ForegroundColor Green
                Write-Host "  |  [+] DESPLIEGUE COMPLETADO EXITOSAMENTE                  |" -ForegroundColor Green
                Write-Host "  |  Log guardado en: ad_setup.log                           |" -ForegroundColor Green
                Write-Host "  |  Ejecuta gpupdate /force en los clientes Windows         |" -ForegroundColor Green
                Write-Host "  |  Copia join_linux.sh al cliente Linux                    |" -ForegroundColor Green
                Write-Host "  +----------------------------------------------------------+" -ForegroundColor Green
                Write-Host ""
                Read-Host "  Presiona ENTER para continuar"
            }
        }

        "10" {
            if (Show-Confirm "Configurar notificacion email al llenar cuota FSRM") {
                Show-Header "Configurando notificacion email FSRM"
                Write-Host "  Se enviara email al administrador cuando:" -ForegroundColor Cyan
                Write-Host "    80%  del limite -> Email de ADVERTENCIA" -ForegroundColor Yellow
                Write-Host "    100% del limite -> Email de LIMITE ALCANZADO" -ForegroundColor Red
                Write-Host ""
                Configurar-NotificacionEmail
                Show-Done "Notificaciones email FSRM configuradas"
            }
        }

        "11" {
            Show-Header "Verificacion completa de la practica"
            Write-Host "  Comprobando cada punto de la practica..." -ForegroundColor Cyan
            Write-Host ""
            Verificar-Configuracion
            Write-Host ""
            Read-Host "  Presiona ENTER para continuar"
        }

        "0" {
            Show-Clear
            Write-Host ""
            Write-Host "  +------------------------------------------+" -ForegroundColor DarkCyan
            Write-Host "  |                                          |" -ForegroundColor DarkCyan
            Write-Host "  |   Hasta luego, Administrador.            |" -ForegroundColor Cyan
            Write-Host "  |   Log guardado en: ad_setup.log          |" -ForegroundColor DarkGray
            Write-Host "  |                                          |" -ForegroundColor DarkCyan
            Write-Host "  +------------------------------------------+" -ForegroundColor DarkCyan
            Write-Host ""
            $run = $false
        }

        default {
            Write-Host ""
            Write-Host "  [!] Opcion no valida. Elige un numero del 0 al 11." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}
