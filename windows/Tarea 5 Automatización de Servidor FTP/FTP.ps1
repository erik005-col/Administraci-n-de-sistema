function Mostrar-Menu-FTP {
    $continuarFTP = $true
    do {
        Clear-Host
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host "       ADMINISTRACION FTP WINDOWS     "
        Write-Host "======================================"
        Write-Host "1) Instalacion y Configuracion Inicial"
        Write-Host "2) Creacion Masiva de Usuarios"
        Write-Host "3) Cambiar Usuario de Grupo"
        Write-Host "4) Volver al Menu Principal"
        
        $op = Read-Host "Seleccione una opcion"

        switch ($op) {
            "1" {
                Write-Host "Instalando roles de FTP..." -ForegroundColor Yellow
                Install-WindowsFeature Web-FTP-Server, Web-Mgmt-Console -IncludeManagementTools | Out-Null
                
                # Crear grupos
                foreach ($g in @("reprobados", "recursadores")) {
                    if (!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) { 
                        New-LocalGroup -Name $g 
                    }
                }

                # Configurar Directorio Raiz
                $ftpRoot = "C:\inetpub\ftproot"
                if (!(Test-Path "$ftpRoot\general")) { 
                    New-Item -Path "$ftpRoot\general" -ItemType Directory -Force | Out-Null
                }
                
                # Regla de autorizacion anonima (Solo Lectura)
                Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Name "." -Value @{accessType="Allow";users="?";roles="";permissions="Read"}
                
                Write-Host "Configuracion inicial completada." -ForegroundColor Green
                Pause
            }

            "2" {
                $ftpRoot = "C:\inetpub\ftproot"
                $n = Read-Host "Numero de usuarios a crear"
                
                for ($i=1; $i -le $n; $i++) {
                    $user = Read-Host "Nombre de usuario $i"
                    $pass = Read-Host "Contrasena para $user" -AsSecureString
                    $grupo = Read-Host "Grupo (reprobados/recursadores)"

                    # Crear usuario y grupo
                    New-LocalUser -Name $user -Password $pass -FullName "Usuario FTP $user" | Out-Null
                    Add-LocalGroupMember -Group $grupo -Member $user | Out-Null

                    # Carpetas segmentadas
                    $uPath = "$ftpRoot\$user"
                    New-Item -ItemType Directory -Path "$uPath\general", "$uPath\$grupo", "$uPath\$user" -Force | Out-Null

                    # Permisos NTFS (ACLs)
                    $acl = Get-Acl $uPath
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user,"Modify","Allow")
                    $acl.SetAccessRule($rule)
                    Set-Acl $uPath $acl

                    Write-Host "Usuario $user configurado." -ForegroundColor Green
                }
                Pause
            }

            "3" {
                $user = Read-Host "Nombre del usuario a mover"
                $nuevoG = Read-Host "Nuevo grupo (reprobados/recursadores)"
                # Lógica de cambio simplificada
                Add-LocalGroupMember -Group $nuevoG -Member $user
                Write-Host "Usuario movido a $nuevoG." -ForegroundColor Cyan
                Pause
            }

            "4" {
                $continuarFTP = $false
            }

            default {
                Write-Host "Opcion no valida." -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($continuarFTP)
}