# ============================================================
#  main_p9.ps1 - Menu principal de la Practica 9
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#
#  Actividades:
#  1. Delegacion de Control y RBAC
#  2. FGPP - Fine-Grained Password Policy
#  3. Auditoria de Eventos (Hardening)
#  4. Script de Monitoreo (Eventos 4625)
#  5. Bloqueo de cuenta por MFA fallido
#  6. Guia de instalacion MFA
#  7. Demo TOTP (Google Authenticator)
#  8. Verificacion general
# ============================================================

# Importar todas las funciones
. "$PSScriptRoot\funciones_p9.ps1"

# Verificar que el script se ejecuta como Administrador
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  ERROR: Debes ejecutar este script como Administrador." -ForegroundColor Red
    Write-Host "  Ejecuta PowerShell como Administrador e intenta de nuevo." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# Bucle principal del menu
do {
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |        PRACTICA 9 - SEGURIDAD AD         |" -ForegroundColor Cyan
    Write-Host "  |   Hardening, RBAC, FGPP, MFA, Auditoria  |" -ForegroundColor Cyan
    Write-Host "  |        practica8.local | 192.168.1.202   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  -- DELEGACION Y RBAC --                 |" -ForegroundColor DarkYellow
    Write-Host "  |  1. Crear usuarios admin delegados       |" -ForegroundColor White
    Write-Host "  |     (admin_identidad/storage/politicas/  |" -ForegroundColor DarkGray
    Write-Host "  |      auditoria)                          |" -ForegroundColor DarkGray
    Write-Host "  |  2. Configurar delegacion y ACLs         |" -ForegroundColor White
    Write-Host "  |     (dsacls - permisos por rol)          |" -ForegroundColor DarkGray
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  -- DIRECTIVAS DE CONTRASENA --          |" -ForegroundColor DarkYellow
    Write-Host "  |  3. Configurar FGPP                      |" -ForegroundColor White
    Write-Host "  |     (12 chars admins / 8 chars usuarios) |" -ForegroundColor DarkGray
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  -- AUDITORIA DE EVENTOS --              |" -ForegroundColor DarkYellow
    Write-Host "  |  4. Habilitar auditoria (auditpol)       |" -ForegroundColor White
    Write-Host "  |  5. Exportar eventos 4625 a .txt         |" -ForegroundColor White
    Write-Host "  |     (Script de monitoreo)                |" -ForegroundColor DarkGray
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  -- MFA / TOTP --                        |" -ForegroundColor DarkYellow
    Write-Host "  |  6. Configurar bloqueo de cuenta MFA     |" -ForegroundColor White
    Write-Host "  |     (3 intentos / 30 min lockout)        |" -ForegroundColor DarkGray
    Write-Host "  |  7. Guia de instalacion MFA (WinOTP)     |" -ForegroundColor White
    Write-Host "  |  8. Demo TOTP - Generar codigo TOTP      |" -ForegroundColor White
    Write-Host "  |     (compatible Google Authenticator)    |" -ForegroundColor DarkGray
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  -- VERIFICACION --                      |" -ForegroundColor DarkYellow
    Write-Host "  |  9. Verificar estado general P9          |" -ForegroundColor White
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  0. Salir                                |" -ForegroundColor Yellow
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ORDEN RECOMENDADO: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7" -ForegroundColor DarkYellow
    Write-Host ""

    $opcion = Read-Host "  Selecciona una opcion"

    switch ($opcion) {
	"1" { Preparar-EntornoMFA }
        "2" { Crear-UsuariosAdmin    }
        "3" { Configurar-Delegacion  }
        "4" { Configurar-FGPP        }
        "5" { Configurar-Auditoria   }
        "6" { Exportar-EventosAuditoria }
        "7" { Configurar-BloqueoMFA  }
        "8" { Guia-InstalacionMFA    }
        "9" { Demo-TOTP              }
        "10" { Verificar-EstadoP9    }
        "11" { Instalar-MFA }
        "0" { Write-Host "`n  Saliendo...`n" -ForegroundColor Yellow }
        default {
            Write-Host ""
            Write-Host "  Opcion invalida, intenta de nuevo." -ForegroundColor Red
            Write-Host ""
            pause
        }
    }

    if ($opcion -ne "0") {
        Write-Host ""
        Write-Host "  Presiona ENTER para volver al menu..." -ForegroundColor DarkGray
        Read-Host | Out-Null
    }

} while ($opcion -ne "0")
