# ===============================
#   MAIN - PUNTO DE ENTRADA
# ===============================

. "$PSScriptRoot\FuncionesBase.ps1"
. "$PSScriptRoot\FuncionesDHCP.ps1"
. "$PSScriptRoot\FuncionesDNS.ps1"
. "$PSScriptRoot\FuncionesSSH.ps1"

  $continuar = $true

do {
    Clear-Host
    Write-Host "======================================" -ForegroundColor Green
    Write-Host "   SISTEMA DE ADMINISTRACION DE RED   "
    Write-Host "======================================"
    Write-Host "1) Gestionar DHCP"
    Write-Host "2) Gestionar DNS"
    Write-Host "3) Instalar y Configurar SSH"
    Write-Host "4) Salir"

    $op = Read-Host "Seleccione una opcion"
     

    switch ($op) {

        "1" { Mostrar-Menu-DHCP }

        "2" { Mostrar-Menu-DNS }

        "3" { Instalar-SSH }

        "4" {$continuar = $false }

        default {
            Write-Host "Opcion invalida." -ForegroundColor Red
            Start-Sleep 1
        }
    }

} while ($continuar)