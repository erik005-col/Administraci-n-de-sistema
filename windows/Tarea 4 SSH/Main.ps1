# ===============================
#   MAIN - PUNTO DE ENTRADA
# ===============================

# Cargar módulos externos
. "$PSScriptRoot\FuncionesBase.ps1"
. "$PSScriptRoot\FuncionesDHCP.ps1"
. "$PSScriptRoot\FuncionesDNS.ps1"
. "$PSScriptRoot\FuncionesSSH.ps1"
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
           

        }

        "4" { exit }

        default {
            Write-Host "Opcion invalida." -ForegroundColor Red
            Start-Sleep 1
        }
    }

} while ($true)