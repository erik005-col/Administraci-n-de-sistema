
. "$PSScriptRoot\http_funciones.ps1"
function Show-MainMenu {

    Clear-Host
    Write-Host "======================================="
    Write-Host "   SISTEMA AUTOMATIZADO DE SERVIDORES"
    Write-Host "======================================="
    Write-Host "1) Instalar IIS (Obligatorio)"
    Write-Host "2) Instalar Apache HTTP Server"
    Write-Host "3) Instalar Nginx"
    Write-Host "4) Consultar versiones disponibles"
    Write-Host "5) Salir"
    Write-Host "======================================="

}

while ($true) {

    Show-MainMenu

    $opcion = (Read-Host "Seleccione una opcion").Trim()

    if (!(Validate-Input $opcion)) {
        Write-Host "Entrada invalida"
        Start-Sleep 2
        continue
    }

    switch ($opcion) {

        "1" {

            $puerto = (Read-Host "Ingrese puerto").Trim()

            if (Validate-Port $puerto -and Test-PortAvailability $puerto) {

                Install-IIS
                Set-IISPort $puerto
                Open-FirewallPort $puerto
                Create-IndexPage "IIS" "Default" $puerto
                Secure-IISHeaders
                Set-IISSecurityHeaders
                Block-DangerousMethods

            }

            Pause
        }

        "2" {

            Write-Host "Versiones disponibles de Apache:"
            $versions = Get-ApacheVersions
            $versions

            $version = Read-Host "Seleccione version"
            $puerto = (Read-Host "Ingrese puerto").Trim()

            if (Validate-Port $puerto -and Test-PortAvailability $puerto) {

                Install-Apache $version
                Set-ApachePort $puerto
                Open-FirewallPort $puerto
                Create-IndexPage "Apache" $version $puerto
                Create-ServiceUser
                Set-WebPermissions

            }

            Pause
        }

        "3" {

            Write-Host "Versiones disponibles de Nginx:"
            $versions = Get-NginxVersions
            $versions

            $version = Read-Host "Seleccione version"
            $puerto = (Read-Host "Ingrese puerto").Trim()

            if (Validate-Port $puerto -and Test-PortAvailability $puerto) {

                Install-Nginx $version
                Set-NginxPort $puerto
                Open-FirewallPort $puerto
                Create-IndexPage "Nginx" $version $puerto
                Create-ServiceUser
                Set-WebPermissions

            }

            Pause
        }

        "4" {

            Write-Host "1) Apache"
            Write-Host "2) Nginx"

            $sub = Read-Host "Seleccione opcion"

            if ($sub -eq "1") {
                Get-ApacheVersions
            }
            elseif ($sub -eq "2") {
                Get-NginxVersions
            }

            Pause
        }

        "5" {

            Write-Host "Saliendo..."
            break

        }

        default {

            Write-Host "Opcion invalida"
            Start-Sleep 2

        }

    }

}