# ============================================================
#  main_p8.ps1 - Menu principal de la Practica 8
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
# ============================================================

# Importar todas las funciones
. "$PSScriptRoot\funciones_p8.ps1"

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
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |        PRACTICA 8 - ACTIVE DIRECTORY     |" -ForegroundColor Cyan
    Write-Host "  |        practica8.local | 192.168.1.202   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  1. Instalar dependencias                |" -ForegroundColor White
    Write-Host "  |  2. Promover servidor a Domain Controller|" -ForegroundColor White
    Write-Host "  |  3. Crear OUs y usuarios desde CSV       |" -ForegroundColor White
    Write-Host "  |  4. Configurar horarios de acceso        |" -ForegroundColor White
    Write-Host "  |  5. Configurar cuotas FSRM               |" -ForegroundColor White
    Write-Host "  |  6. Configurar apantallamiento FSRM      |" -ForegroundColor White
    Write-Host "  |  7. Configurar AppLocker                 |" -ForegroundColor White
    Write-Host "  |  8. Crear usuario dinamicamente          |" -ForegroundColor White
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  0. Salir                                |" -ForegroundColor Yellow
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $opcion = Read-Host "  Selecciona una opcion"

    switch ($opcion) {
        "1" { Instalar-Dependencias }
        "2" { Promover-DomainController }
        "3" { Crear-OUsYUsuarios }
        "4" { Configurar-Horarios }
        "5" { Configurar-CuotasFSRM }
        "6" { Configurar-Apantallamiento }
        "7" { Configurar-AppLocker }
        "8" { Crear-UsuarioDinamico }
        "0" { Write-Host "`n  Saliendo...`n" -ForegroundColor Yellow }
        default { Write-Host "`n  Opcion invalida, intenta de nuevo." -ForegroundColor Red; pause }
    }

} while ($opcion -ne "0")
