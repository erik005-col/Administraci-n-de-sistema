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
        Write-Host "6) Salir"
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

                if (-not (Test-Path "IIS:\Sites\$siteName")) {
                    New-WebFtpSite -Name $siteName -Port 21 -PhysicalPath $ftpRoot -Force
                }

                # SSL no obligatorio
                Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/ssl" -Name controlChannelPolicy -Value "Allow"
                Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/ssl" -Name dataChannelPolicy -Value "Allow"

                # Autenticación
                Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/authentication/anonymousAuthentication" -Name enabled -Value $true
                Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/authentication/basicAuthentication" -Name enabled -Value $true

                # Sin aislamiento
                Set-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/userIsolation" -Name mode -Value "None"

                # Limpiar reglas anteriores
                Clear-WebConfiguration -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/authorization"

                # 🔹 Anónimo solo lectura
                Add-WebConfiguration -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/authorization" -Value @{accessType="Allow";users="IUSR";permissions="Read"}

                # 🔹 Grupos lectura y escritura
                Add-WebConfiguration -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="reprobados";permissions="Read,Write"}
                Add-WebConfiguration -PSPath "IIS:\" -Location $siteName -Filter "system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="recursadores";permissions="Read,Write"}

                # Permisos NTFS

                # Carpeta pública (todos leen, solo autenticados escriben vía IIS)
                icacls "$ftpRoot\publica" /grant "Users:(OI)(CI)(RX)" /T | Out-Null

                # Permisos por grupo
                icacls "$ftpRoot\reprobados" /grant "reprobados:(OI)(CI)(M)" /T | Out-Null
                icacls "$ftpRoot\recursadores" /grant "recursadores:(OI)(CI)(M)" /T | Out-Null

                netsh advfirewall firewall add rule name="FTP Server 21" dir=in action=allow protocol=TCP localport=21 | Out-Null

                iisreset | Out-Null

                Write-Host "FTP configurado correctamente para la practica." -ForegroundColor Green
                Pause
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
                            Write-Host "Error creando usuario: $($_.Exception.Message)" -ForegroundColor Red
                            continue
                        }

                        Add-LocalGroupMember -Group $grupo -Member $user -ErrorAction SilentlyContinue | Out-Null

                        # Crear carpeta personal en la raiz
                        $userRoot = "$ftpRoot\$user"
                        New-Item -ItemType Directory -Path $userRoot -Force | Out-Null

                        # Permiso total solo para el usuario
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

                Clear-Host
                Write-Host "===== ESTADO DEL SERVICIO FTP =====" -ForegroundColor Cyan

                $svc = Get-Service ftpsvc
                Write-Host ""
                Write-Host "Servicio FTP (ftpsvc): $($svc.Status)" -ForegroundColor Yellow

                $site = Get-Website -Name $siteName -ErrorAction SilentlyContinue

                if ($site) {
                    Write-Host "Sitio IIS '$siteName': $($site.State)" -ForegroundColor Yellow
                }
                else {
                    Write-Host "Sitio IIS '$siteName' no existe." -ForegroundColor Red
                }

                $port = netstat -an | Select-String ":21"

                if ($port) {
                    Write-Host "Puerto 21: LISTENING" -ForegroundColor Green
                }
                else {
                    Write-Host "Puerto 21: NO esta escuchando" -ForegroundColor Red
                }

                Pause
            }

            "5" {

                Clear-Host
                Write-Host "===== USUARIOS FTP REGISTRADOS =====" -ForegroundColor Cyan
                Write-Host ""

                $rutaBase = "$ftpRoot\LocalUser"

                $usuarios = Get-LocalUser | Where-Object {
                    $_.Name -notmatch "Administrator|DefaultAccount|Guest|WDAGUtilityAccount"
                }

                if (-not $usuarios) {
                    Write-Host "No hay usuarios creados." -ForegroundColor Yellow
                }
                else {
                    foreach ($u in $usuarios) {

                        Write-Host "Usuario: $($u.Name)" -ForegroundColor Green
                        Write-Host "Estado : $($u.Enabled)"

                        $grupos = Get-LocalGroup | Where-Object {
                            (Get-LocalGroupMember $_.Name -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -like "*$($u.Name)" })
                        }

                        if ($grupos) {
                            Write-Host "Grupo  : $($grupos.Name -join ', ')"
                        }
                        else {
                            Write-Host "Grupo  : Ninguno"
                        }

                        $ruta = "$rutaBase\$($u.Name)"

                        if (Test-Path $ruta) {
                            Write-Host "Carpeta FTP: Existe"
                        }
                        else {
                            Write-Host "Carpeta FTP: No encontrada"
                        }

                        Write-Host "-----------------------------------"
                    }
                }

                Pause
            }

            "6" {
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