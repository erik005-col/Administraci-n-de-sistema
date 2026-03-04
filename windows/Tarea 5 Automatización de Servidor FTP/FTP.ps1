#requires -RunAsAdministrator
Import-Module WebAdministration -ErrorAction Stop

function Mostrar-Menu-FTP {

    $siteName = "Default FTP Site"
    $ftpRoot  = "C:\inetpub\ftproot"
    $continuarFTP = $true

    do {
        Clear-Host
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host "       ADMINISTRACION FTP WINDOWS     "
        Write-Host "======================================"
        Write-Host "1) Instalacion y Configuracion Inicial"
        Write-Host "2) Creacion Masiva de Usuarios"
        Write-Host "3) Cambiar Usuario de Grupo"
        Write-Host "4) Ver Estado del Servicio FTP"
        Write-Host "5) Ver Usuarios FTP"
        Write-Host "6) Eliminar Usuario"
        Write-Host "7) Salir"
        $op = Read-Host "Seleccione una opcion"

        switch ($op) {

            "1" {

                Install-WindowsFeature Web-Server,Web-FTP-Server -IncludeManagementTools | Out-Null

                    # Crear estructura
                    New-Item -Path $ftpRoot -ItemType Directory -Force | Out-Null
                    New-Item -Path "$ftpRoot\publica" -ItemType Directory -Force | Out-Null
                    New-Item -Path "$ftpRoot\reprobados" -ItemType Directory -Force | Out-Null
                    New-Item -Path "$ftpRoot\recursadores" -ItemType Directory -Force | Out-Null

                    foreach ($g in @("reprobados","recursadores")) {
                        if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
                            New-LocalGroup -Name $g | Out-Null
                        }
                    }

                    if (Test-Path "IIS:\Sites\$siteName") {
                        Remove-WebSite $siteName
                    }

                    New-WebFtpSite -Name $siteName -Port 21 -PhysicalPath $ftpRoot -Force

                    # SSL opcional
                    Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName `
                        -Filter "system.ftpServer/security/ssl" -Name controlChannelPolicy -Value "SslAllow"
                    Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName `
                        -Filter "system.ftpServer/security/ssl" -Name dataChannelPolicy -Value "SslAllow"

                    # Autenticación
                    Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName `
                        -Filter "system.ftpServer/security/authentication/anonymousAuthentication" -Name enabled -Value $true
                    Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName `
                        -Filter "system.ftpServer/security/authentication/basicAuthentication" -Name enabled -Value $true

                    # Sin aislamiento
                    Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName `
                        -Filter "system.ftpServer/userIsolation" -Name mode -Value "None"

                    # Limpiar reglas
                    Clear-WebConfiguration -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/authorization"

                    # Reglas de autorización
                    Add-WebConfiguration -PSPath "IIS:\" -Location $siteName `
                        -Filter "system.ftpServer/security/authorization" -Value @{accessType="Allow";users="IUSR";permissions="Read"}
                    Add-WebConfiguration -PSPath "IIS:\" -Location $siteName `
                        -Filter "system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="reprobados";permissions="Read,Write"}
                    Add-WebConfiguration -PSPath "IIS:\" -Location $siteName `
                        -Filter "system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="recursadores";permissions="Read,Write"}

                    # Permisos NTFS
                    icacls "$ftpRoot\publica" /grant "IUSR:(OI)(CI)(R)" /T | Out-Null
                    icacls "$ftpRoot\publica" /grant "Users:(OI)(CI)(M)" /T | Out-Null
                    icacls "$ftpRoot\reprobados" /grant "reprobados:(OI)(CI)(M)" /T | Out-Null
                    icacls "$ftpRoot\recursadores" /grant "recursadores:(OI)(CI)(M)" /T | Out-Null

                    netsh advfirewall firewall add rule name="FTP Server 21" dir=in action=allow protocol=TCP localport=21 | Out-Null

                    iisreset | Out-Null
                }

            "2" {

                $n = Read-Host "Numero de usuarios a crear"

                for ($i=1; $i -le $n; $i++) {

                    $user = Read-Host "Nombre de usuario"
                    $pass = Read-Host "Contrasena" -AsSecureString
                    $grupo = Read-Host "Grupo (reprobados/recursadores)"

                    try {
                        New-LocalUser -Name $user -Password $pass -FullName "Usuario FTP $user" -ErrorAction Stop
                    }
                    catch {
                        Write-Host "Error creando usuario." -ForegroundColor Red
                        continue
                    }

                    Add-LocalGroupMember -Group $grupo -Member $user -ErrorAction SilentlyContinue | Out-Null

                    $userRoot = "$ftpRoot\$user"
                    New-Item -ItemType Directory -Path $userRoot -Force | Out-Null
                    icacls $userRoot /grant "${user}:(OI)(CI)(M)" /T | Out-Null

                    Write-Host "Usuario $user creado correctamente." -ForegroundColor Green
                }

                Pause
            }

            "3" {

                $user = Read-Host "Usuario a mover"
                $nuevo = Read-Host "Nuevo grupo (reprobados/recursadores)"

                Remove-LocalGroupMember -Group "reprobados" -Member $user -ErrorAction SilentlyContinue
                Remove-LocalGroupMember -Group "recursadores" -Member $user -ErrorAction SilentlyContinue
                Add-LocalGroupMember -Group $nuevo -Member $user -ErrorAction SilentlyContinue

                Write-Host "Usuario movido correctamente." -ForegroundColor Cyan
                Pause
            }

            "4" {

                $svc = Get-Service ftpsvc
                Write-Host "Servicio FTP: $($svc.Status)" -ForegroundColor Yellow
                Pause
            }

            "5" {

                Get-LocalUser | Where-Object { $_.Name -notmatch "Administrator|Guest|DefaultAccount" } |
                Select-Object Name, Enabled
                Pause
            }

            "6" {

                $user = Read-Host "Nombre del usuario a eliminar"

                if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
                    Write-Host "El usuario no existe." -ForegroundColor Red
                    Pause
                    break
                }

                Remove-LocalGroupMember -Group "reprobados" -Member $user -ErrorAction SilentlyContinue
                Remove-LocalGroupMember -Group "recursadores" -Member $user -ErrorAction SilentlyContinue

                $userFolder = "$ftpRoot\$user"
                if (Test-Path $userFolder) {
                    Remove-Item $userFolder -Recurse -Force
                }

                Remove-LocalUser -Name $user

                Write-Host "Usuario eliminado correctamente." -ForegroundColor Green
                Pause
            }

            "7" {
                $continuarFTP = $false
            }

            default {
                Write-Host "Opcion invalida" -ForegroundColor Red
                Start-Sleep 1
            }
        }

    } while ($continuarFTP)
}

Mostrar-Menu-FTP