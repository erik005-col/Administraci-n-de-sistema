# ===============================
#   MAIN - PUNTO DE ENTRADA
# ===============================

# Cargar módulos externos
. .\FuncionesBase.ps1
. .\FuncionesDHCP.ps1
. .\FuncionesDNS.ps1
. .\FuncionesSSH.ps1

# ===============================
#   MENÚ PRINCIPAL
# ===============================

do {
    Clear-Host
    Write-Host "======================================" -ForegroundColor Green
    Write-Host "   SISTEMA DE ADMINISTRACION DE RED   " -ForegroundColor Green
    Write-Host "======================================" -ForegroundColor Green
    Write-Host "1) Gestionar DHCP"
    Write-Host "2) Gestionar DNS"
    Write-Host "3) Instalar y Configurar SSH"
    Write-Host "4) Salir"
    Write-Host "======================================"

    $op = Read-Host "Seleccione una opcion"

    switch ($op) {

        "1" { Mostrar-Menu-DHCP }

        "2" { Mostrar-Menu-DNS }

        "3" { 
            Install-SSHService
            Pause
        }

        "4" { exit }

        default {
            Write-Host "Opcion invalida." -ForegroundColor Red
            Start-Sleep 1
        }
    }

} while ($true)