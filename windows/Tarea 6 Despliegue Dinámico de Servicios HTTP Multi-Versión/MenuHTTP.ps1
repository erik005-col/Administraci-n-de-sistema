
. "$PSScriptRoot\http_funciones.ps1"

function Show-MainMenu {

    Clear-Host

    Write-Host "================================="
    Write-Host " SISTEMA AUTOMATIZADO DE SERVIDORES"
    Write-Host "================================="
    Write-Host "1) Instalar IIS (Obligatorio)"
    Write-Host "2) Instalar Apache HTTP Server"
    Write-Host "3) Instalar Nginx"
    Write-Host "4) Consultar versiones disponibles"
    Write-Host "5) Salir"
}

Check-IIS
Check-Chocolatey

while ($true) {

    Show-MainMenu

    $option = Read-Host "Seleccione una opcion"

    if (!(Validate-Input $option)) {
        Write-Host "Opcion invalida"
        pause
        continue
    }

    switch ($option) {

        1 { Install-IISMenu }

        2 { Install-ApacheMenu }

        3 { Install-NginxMenu }

        4 { Show-VersionsMenu }

        5 {
            Write-Host "Saliendo..."
            break
        }

        default {
            Write-Host "Opcion incorrecta"
        }
    }

    pause
}