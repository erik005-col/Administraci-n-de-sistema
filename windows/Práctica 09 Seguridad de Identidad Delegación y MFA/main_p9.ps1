# ============================================================
#  main_p9.ps1 - Menu principal de la Practica 9
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#  Version  : 2.0
#
#  Practica 09: Seguridad de Identidad, Delegacion y MFA
#
#  ORDEN DE EJECUCION RECOMENDADO:
#    1 -> Configurar Password Policies (FGPP)
#    3 -> Crear administradores delegados
#    4 -> Delegar permisos en OUs
#    5 -> Configurar bloqueo de cuentas
#    6 -> Configurar auditoria
#    2 -> Verificar politica de un usuario (para comprobar)
# ============================================================

# Importar funciones
. "$PSScriptRoot\funciones_p9.ps1"

# Verificar ejecucion como Administrador
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  ERROR: Debes ejecutar este script como Administrador." -ForegroundColor Red
    Write-Host "  Clic derecho en PowerShell -> Ejecutar como administrador." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# Bucle principal
do {
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | PRACTICA 9 - SEGURIDAD DE IDENTIDAD      |" -ForegroundColor Cyan
    Write-Host "  | practica8.local  |  192.168.1.202        |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  1. Configurar Password Policies (FGPP)  |" -ForegroundColor White
    Write-Host "  |  2. Verificar politica de un usuario     |" -ForegroundColor White
    Write-Host "  |  3. Crear administradores delegados      |" -ForegroundColor White
    Write-Host "  |  4. Configurar delegacion en OUs         |" -ForegroundColor White
    Write-Host "  |  5. Configurar bloqueo de cuentas (GPO)  |" -ForegroundColor White
    Write-Host "  |  6. Configurar auditoria de seguridad    |" -ForegroundColor White
    Write-Host "  |  7. Ver cuentas bloqueadas               |" -ForegroundColor White
    Write-Host "  |  8. Desbloquear cuenta de usuario        |" -ForegroundColor White
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  0. Salir                                |" -ForegroundColor Yellow
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $opcion = Read-Host "  Selecciona una opcion"

    switch ($opcion) {
        "1" { Configurar-PasswordPolicies }
        "2" { Verificar-PasswordPolicy    }
        "3" { Crear-AdminesDelegados      }
        "4" { Configurar-Delegacion       }
        "5" { Configurar-AccountLockout   }
        "6" { Configurar-Auditoria        }
        "7" { Ver-CuentasBloqueadas       }
        "8" { Desbloquear-Cuenta          }
        "0" { Write-Host "`n  Saliendo...`n" -ForegroundColor Yellow }
        default {
            Write-Host ""
            Write-Host "  Opcion invalida. Elige entre 0 y 8." -ForegroundColor Red
        }
    }

    if ($opcion -ne "0") {
        Write-Host ""
        Write-Host "  Presiona ENTER para volver al menu..." -ForegroundColor DarkGray
        Read-Host | Out-Null
    }

} while ($opcion -ne "0")
