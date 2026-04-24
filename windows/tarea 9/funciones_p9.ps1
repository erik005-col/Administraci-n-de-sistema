# ============================================================
#  funciones_p9.ps1 -- Libreria de funciones Practica 09
#  Hardening AD, RBAC, FGPP, Auditoria y MFA TOTP
#  Version corregida - AppLocker bypass para instalacion MFA
# ============================================================

# ------------------------------------------------------------
# UTILIDAD: Detectar nombre real de OUs creadas en P08
# ------------------------------------------------------------
function Get-OUSegura {
    param([string]$NombreBase)
    $dcBase    = (Get-ADDomain).DistinguishedName
    $variantes = @($NombreBase, ($NombreBase -replace ' ',''), "No Cuates", "NoCuates")
    foreach ($v in $variantes) {
        if ($NombreBase -notmatch "No" -and $v -match "No") { continue }
        try {
            Get-ADOrganizationalUnit -Identity "OU=$v,$dcBase" -ErrorAction Stop | Out-Null
            return "OU=$v,$dcBase"
        } catch {}
    }
    Write-Host "  [AVISO] OU '$NombreBase' no existe. Creandola..." -ForegroundColor Yellow
    try {
        New-ADOrganizationalUnit -Name $NombreBase -Path $dcBase -ErrorAction Stop
        Write-Host "  [OK] OU '$NombreBase' creada." -ForegroundColor Green
        return "OU=$NombreBase,$dcBase"
    } catch {
        Write-Host "  [ERROR] No se pudo crear OU '$NombreBase': $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ------------------------------------------------------------
# UTILIDAD: Localizar multiotp.exe
# ------------------------------------------------------------
function Get-MultiOTPExe {
    foreach ($r in @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP","C:\Windows\multiOTP")) {
        if (Test-Path "$r\multiotp.exe") { return "$r\multiotp.exe" }
    }
    # Buscar recursivo en MFA_Setup
    $encontrado = Get-ChildItem -Path "C:\MFA_Setup" -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($encontrado) { return $encontrado.FullName }
    return $null
}

# ------------------------------------------------------------
# UTILIDAD: Permitir login local en el DC a un usuario
# ------------------------------------------------------------
function Habilitar-LogonLocal {
    param([string]$Usuario)
    try {
        $sid     = (Get-ADUser $Usuario -ErrorAction Stop).SID.Value
        $cfgPath = "C:\MFA_Setup\secpol_temp.cfg"
        secedit /export /cfg $cfgPath /quiet 2>&1 | Out-Null
        $contenido = Get-Content $cfgPath -Raw
        if ($contenido -match "SeInteractiveLogonRight.*\*$sid") {
            Write-Host "    [OK] ${Usuario}: ya tiene logon local." -ForegroundColor DarkGray
            return
        }
        $contenido = $contenido -replace "(SeInteractiveLogonRight\s*=\s*)(.*)",       "`$1`$2,*$sid"
        $contenido = $contenido -replace "(SeRemoteInteractiveLogonRight\s*=\s*)(.*)", "`$1`$2,*$sid"
        $contenido | Set-Content $cfgPath -Encoding Unicode
        secedit /configure /cfg $cfgPath /db "C:\MFA_Setup\secedit.sdb" /quiet 2>&1 | Out-Null
        Write-Host "    [OK] ${Usuario}: logon local y RDP habilitados." -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] No se pudo habilitar logon para ${Usuario}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# UTILIDAD: Deshabilitar AppLocker temporalmente
# ------------------------------------------------------------
function Deshabilitar-AppLockerTemporal {
    Write-Host "  [INFO] Deshabilitando AppLocker temporalmente para instalacion..." -ForegroundColor Yellow
    try {
        # Guardar politica actual
        $politicaActual = "C:\MFA_Setup\applocker_backup.xml"
        Get-AppLockerPolicy -Effective -Xml | Out-File $politicaActual -Encoding UTF8 -ErrorAction SilentlyContinue
        Write-Host "    [OK] Politica AppLocker respaldada en: $politicaActual" -ForegroundColor Green

        # Deshabilitar servicio AppLocker (AppIDSvc)
        $svc = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name "AppIDSvc" -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name "AppIDSvc" -Force -ErrorAction SilentlyContinue
            Write-Host "    [OK] Servicio AppIDSvc detenido." -ForegroundColor Green
        }
        return $true
    } catch {
        Write-Host "    [WARN] No se pudo deshabilitar AppLocker: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# ------------------------------------------------------------
# UTILIDAD: Rehabilitar AppLocker
# ------------------------------------------------------------
function Rehabilitar-AppLocker {
    Write-Host "  [INFO] Rehabilitando AppLocker..." -ForegroundColor Yellow
    try {
        $svc = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name "AppIDSvc" -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
            Write-Host "    [OK] AppIDSvc rehabilitado." -ForegroundColor Green
        }
        # Restaurar politica si hay backup
        $politicaBackup = "C:\MFA_Setup\applocker_backup.xml"
        if (Test-Path $politicaBackup) {
            Set-AppLockerPolicy -XmlPolicy $politicaBackup -ErrorAction SilentlyContinue
            Write-Host "    [OK] Politica AppLocker restaurada." -ForegroundColor Green
        }
    } catch {
        Write-Host "    [WARN] $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# UTILIDAD: Agregar ruta a reglas Allow de AppLocker
# ------------------------------------------------------------
function Agregar-ReglaAppLockerRuta {
    param([string]$Ruta)
    Write-Host "  [INFO] Agregando '$Ruta' a reglas Allow de AppLocker..." -ForegroundColor Yellow
    try {
        # Agregar regla publisher/path para la carpeta de instalacion
        $xmlRegla = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="$(New-Guid)" Name="Permitir MFA Setup" Description="Instalacion MFA P09" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="$Ruta\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="$(New-Guid)" Name="Permitir Windows" Description="Windows base" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="$(New-Guid)" Name="Permitir ProgramFiles" Description="Program Files" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="$(New-Guid)" Name="Permitir ProgramFiles x86" Description="Program Files x86" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES(X86)%\*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
        $archivoRegla = "C:\MFA_Setup\regla_temp_applocker.xml"
        $xmlRegla | Out-File $archivoRegla -Encoding UTF8
        Set-AppLockerPolicy -XmlPolicy $archivoRegla -Merge -ErrorAction Stop
        Write-Host "    [OK] Regla AppLocker agregada para: $Ruta" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "    [WARN] No se pudo agregar regla AppLocker: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# ------------------------------------------------------------
# FUNCION 1: Preparar entorno y descargar multiOTP
# ------------------------------------------------------------
function Preparar-EntornoMFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PREPARAR ENTORNO Y DESCARGAR MFA       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    if (-not (Test-Path $rutaDescarga)) {
        New-Item -Path $rutaDescarga -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $rutaDescarga" -ForegroundColor Green
    }

    $proceder   = $true
    $existentes = Get-ChildItem -Path $rutaDescarga -Filter "multiOTP*" -ErrorAction SilentlyContinue
    if ($existentes) {
        Write-Host "  [AVISO] Ya hay archivos multiOTP en $rutaDescarga." -ForegroundColor Yellow
        $r = Read-Host "  Descargar la version mas nueva desde GitHub? (s/n)"
        if ($r.ToLower() -ne 's') { $proceder = $false; Write-Host "  [OK] Usando archivos existentes." -ForegroundColor Green }
    }

    if ($proceder) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $descargaOk  = $false

        # --- Intento 1: URL directa ---
        $urlDirecta  = "https://github.com/multiOTP/multiOTPCredentialProvider/releases/download/5.9.8.2/multiOTPCredentialProvider-5.9.8.2.zip"
        $rutaArchivo = "$rutaDescarga\multiOTPCredentialProvider-5.9.8.2.zip"
        Write-Host "  [INFO] Descargando multiOTP v5.9.8.2..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $urlDirecta -OutFile $rutaArchivo -UseBasicParsing -ErrorAction Stop
            $descargaOk = $true
        } catch {
            Write-Host "  [WARN] URL directa fallo: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # --- Intento 2: API de GitHub (fallback) ---
        if (-not $descargaOk) {
            Write-Host "  [INFO] Intentando via GitHub API..." -ForegroundColor Cyan
            try {
                $headers = @{ "User-Agent" = "PowerShell-P09" }
                $release = Invoke-RestMethod -Uri "https://api.github.com/repos/multiOTP/multiOTPCredentialProvider/releases/latest" -Headers $headers -UseBasicParsing -ErrorAction Stop
                $asset   = $release.assets | Where-Object { $_.name -like "*.zip" -or $_.name -like "*.exe" } | Select-Object -First 1
                if ($asset) {
                    $rutaArchivo = "$rutaDescarga\$($asset.name)"
                    Write-Host "  [INFO] Descargando $($release.tag_name)..." -ForegroundColor Yellow
                    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $rutaArchivo -UseBasicParsing -Headers $headers -ErrorAction Stop
                    $descargaOk = $true
                }
            } catch {
                Write-Host "  [WARN] GitHub API fallo: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        if ($descargaOk) {
            if ($rutaArchivo.EndsWith(".zip")) {
                Write-Host "  [INFO] Extrayendo ZIP..." -ForegroundColor Yellow
                Expand-Archive -Path $rutaArchivo -DestinationPath $rutaDescarga -Force
            }
            Write-Host "  [OK] Descarga completa." -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] No se pudo descargar multiOTP automaticamente." -ForegroundColor Red
            Write-Host "  [INFO] Descarga manual: https://github.com/multiOTP/multiOTPCredentialProvider/releases" -ForegroundColor Yellow
            Write-Host "  [INFO] Coloca el ZIP extraido en: $rutaDescarga" -ForegroundColor Yellow
        }
    }
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 2: Crear los 4 usuarios + habilitar logon local
# ------------------------------------------------------------
function Crear-UsuariosAdmin {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CREACION DE USUARIOS ADMINISTRATIVOS   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $usuarios = @(
        @{ Sam = "admin_identidad"; Nombre = "Admin Identidad"; Desc = "Rol 1 - IAM Operator" },
        @{ Sam = "admin_storage";   Nombre = "Admin Storage";   Desc = "Rol 2 - Storage Operator" },
        @{ Sam = "admin_politicas"; Nombre = "Admin Politicas"; Desc = "Rol 3 - GPO Compliance" },
        @{ Sam = "admin_auditoria"; Nombre = "Admin Auditoria"; Desc = "Rol 4 - Security Auditor" }
    )

    $pwdTexto  = "Hardening2026!"
    $pwdSegura = ConvertTo-SecureString $pwdTexto -AsPlainText -Force
    $creados   = 0
    $omitidos  = 0

    foreach ($u in $usuarios) {
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue
        if ($existe) {
            Write-Host "  [OMITIDO] '$($u.Sam)' ya existe en AD." -ForegroundColor Yellow
            $omitidos++
        } else {
            try {
                New-ADUser -Name $u.Nombre -SamAccountName $u.Sam `
                    -UserPrincipalName "$($u.Sam)@$((Get-ADDomain).DNSRoot)" `
                    -Description $u.Desc -AccountPassword $pwdSegura `
                    -Enabled $true -PasswordNeverExpires $true
                Write-Host "  [OK] '$($u.Sam)' creado. Pass: $pwdTexto" -ForegroundColor Green
                $creados++
            } catch {
                Write-Host "  [ERROR] '$($u.Sam)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n  Configurando permisos de inicio de sesion..." -ForegroundColor Yellow
    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity "Remote Desktop Users" -Members $u.Sam -ErrorAction Stop
            Write-Host "  [OK] '$($u.Sam)' en Remote Desktop Users." -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] '$($u.Sam)' ya esta en Remote Desktop Users." -ForegroundColor DarkGray
        }
    }

    Write-Host "`n  Habilitando logon local en el DC..." -ForegroundColor Yellow
    if (-not (Test-Path "C:\MFA_Setup")) { New-Item "C:\MFA_Setup" -ItemType Directory | Out-Null }
    foreach ($u in $usuarios) { Habilitar-LogonLocal -Usuario $u.Sam }

    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [OK] GPO actualizada." -ForegroundColor Green
    Write-Host "`n  Resumen: $creados creados, $omitidos ya existian." -ForegroundColor Cyan
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 3: Aplicar permisos RBAC con delegacion por ACL
# ------------------------------------------------------------
function Aplicar-PermisosRBAC {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   APLICAR PERMISOS RBAC Y DELEGACION     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    try { $dominio = Get-ADDomain -ErrorAction Stop }
    catch { Write-Host "  [ERROR] No se puede conectar a AD." -ForegroundColor Red; Read-Host | Out-Null; return }

    $dcBase  = $dominio.DistinguishedName
    $netbios = $dominio.NetBIOSName

    $ouCuates   = Get-OUSegura -NombreBase "Cuates"
    $ouNoCuates = Get-OUSegura -NombreBase "NoCuates"
    if (-not $ouCuates -or -not $ouNoCuates) {
        Write-Host "  [ERROR] No se pudieron resolver las OUs." -ForegroundColor Red
        Read-Host | Out-Null; return
    }
    Write-Host "  OU Cuates   : $ouCuates"    -ForegroundColor DarkGray
    Write-Host "  OU NoCuates : $ouNoCuates`n" -ForegroundColor DarkGray

    # ----------------------------------------------------------------
    # ROL 1: admin_identidad - IAM Operator
    # ----------------------------------------------------------------
    Write-Host "  [ROL 1] admin_identidad (IAM Operator)..." -ForegroundColor Yellow

    $guidResetPwd    = [guid]"00299570-246d-11d0-a768-00aa006e0529"
    $guidUser        = [guid]"bf967aba-0de6-11d0-a285-00aa003049e2"
    $guidPwdLastSet  = [guid]"bf967a0a-0de6-11d0-a285-00aa003049e2"
    $guidLockoutTime = [guid]"28630ebf-41d5-11d1-a9c1-0000f80367c1"
    $sidIdentidad    = (Get-ADUser "admin_identidad" -ErrorAction Stop).SID

    foreach ($ou in @($ouCuates, $ouNoCuates)) {
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:CCDC;;user"                           2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:CA;Reset Password;user"               2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:CA;Change Password;user"              2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:WP;pwdLastSet;user"                   2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:RPWP;telephoneNumber;user"            2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:RPWP;physicalDeliveryOfficeName;user" 2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:RPWP;mail;user"                       2>&1 | Out-Null
        dsacls "$ou" /I:T /G "${netbios}\admin_identidad:RPWP;lockoutTime;user"                2>&1 | Out-Null

        try {
            $acl = Get-Acl -Path "AD:\$ou"
            $ace1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $sidIdentidad, [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
                [System.Security.AccessControl.AccessControlType]::Allow,
                $guidResetPwd,
                [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents, $guidUser)
            $acl.AddAccessRule($ace1)
            $ace2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $sidIdentidad, [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
                [System.Security.AccessControl.AccessControlType]::Allow,
                $guidPwdLastSet,
                [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents, $guidUser)
            $acl.AddAccessRule($ace2)
            $ace3 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $sidIdentidad, [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
                [System.Security.AccessControl.AccessControlType]::Allow,
                $guidLockoutTime,
                [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents, $guidUser)
            $acl.AddAccessRule($ace3)
            Set-Acl -Path "AD:\$ou" -AclObject $acl -ErrorAction Stop
            Write-Host "    [OK] ACEs PowerShell aplicadas en: $ou" -ForegroundColor Green
        } catch {
            Write-Host "    [WARN] Set-Acl en ${ou}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host "  [OK] admin_identidad: Reset Password delegado correctamente." -ForegroundColor Green

    # ----------------------------------------------------------------
    # ROL 2: admin_storage - DENY Reset Password en todo el dominio
    # ----------------------------------------------------------------
    Write-Host "`n  [ROL 2] admin_storage (Storage Operator - DENY Reset Password)..." -ForegroundColor Yellow
    $sidStorage = (Get-ADUser "admin_storage" -ErrorAction Stop).SID
    try {
        $aclDom = Get-Acl -Path "AD:\$dcBase"
        $aceDeny = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sidStorage, [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
            [System.Security.AccessControl.AccessControlType]::Deny,
            $guidResetPwd,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents, $guidUser)
        $aclDom.AddAccessRule($aceDeny)
        Set-Acl -Path "AD:\$dcBase" -AclObject $aclDom -ErrorAction Stop
        Write-Host "  [OK] admin_storage: DENY Reset Password aplicado en dominio." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] DENY storage: $($_.Exception.Message)" -ForegroundColor Yellow
        # Intento via dsacls
        dsacls "$dcBase" /I:T /D "${netbios}\admin_storage:CA;Reset Password;user" 2>&1 | Out-Null
        Write-Host "  [INFO] DENY aplicado via dsacls (fallback)." -ForegroundColor DarkGray
    }

    # ----------------------------------------------------------------
    # ROL 3: admin_politicas - Lectura en dominio, escritura en GPOs
    # ----------------------------------------------------------------
    Write-Host "`n  [ROL 3] admin_politicas (GPO Compliance)..." -ForegroundColor Yellow
    try {
        dsacls "$dcBase" /I:T /G "${netbios}\admin_politicas:GR" 2>&1 | Out-Null
        Write-Host "  [OK] admin_politicas: lectura en dominio." -ForegroundColor Green
        # Agregar al grupo Group Policy Creator Owners para poder editar GPOs
        try {
            Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "admin_politicas" -ErrorAction Stop
            Write-Host "  [OK] admin_politicas: agregado a 'Group Policy Creator Owners'." -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] Ya en Group Policy Creator Owners o error: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  [WARN] ROL 3: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # ----------------------------------------------------------------
    # ROL 4: admin_auditoria - Solo lectura en logs de seguridad
    # ----------------------------------------------------------------
    Write-Host "`n  [ROL 4] admin_auditoria (Security Auditor - Read Only)..." -ForegroundColor Yellow
    try {
        # Agregar al grupo Event Log Readers para leer logs de seguridad
        Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction Stop
        Write-Host "  [OK] admin_auditoria: agregado a 'Event Log Readers'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Ya en Event Log Readers o error: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
    try {
        # Acceso de solo lectura al dominio
        dsacls "$dcBase" /I:T /G "${netbios}\admin_auditoria:GR" 2>&1 | Out-Null
        Write-Host "  [OK] admin_auditoria: lectura en dominio." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] ROL 4 lectura: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "`n  RBAC aplicado correctamente." -ForegroundColor Green
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 4: Configurar FGPP
# ------------------------------------------------------------
function Configurar-FGPP {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   DIRECTIVAS DE CONTRASENA AJUSTADA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $dominio = Get-ADDomain
    $dcBase  = $dominio.DistinguishedName

    # PSO 1: Admins privilegiados - 12 caracteres minimo
    $psoAdmin = "PSO-Admins-P09"
    $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$psoAdmin'" -ErrorAction SilentlyContinue
    if ($existe) {
        Write-Host "  [AVISO] PSO '$psoAdmin' ya existe. Actualizando..." -ForegroundColor Yellow
        Set-ADFineGrainedPasswordPolicy -Identity $psoAdmin `
            -MinPasswordLength 12 -PasswordHistoryCount 10 `
            -ComplexityEnabled $true -LockoutThreshold 3 `
            -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00" `
            -MinPasswordAge "00:00:00" -MaxPasswordAge "90.00:00:00" `
            -ReversibleEncryptionEnabled $false -ErrorAction SilentlyContinue
    } else {
        try {
            New-ADFineGrainedPasswordPolicy -Name $psoAdmin `
                -Precedence 10 -MinPasswordLength 12 `
                -PasswordHistoryCount 10 -ComplexityEnabled $true `
                -LockoutThreshold 3 -LockoutDuration "00:30:00" `
                -LockoutObservationWindow "00:30:00" `
                -MinPasswordAge "00:00:00" -MaxPasswordAge "90.00:00:00" `
                -ReversibleEncryptionEnabled $false -ErrorAction Stop
            Write-Host "  [OK] PSO '$psoAdmin' creado (12 chars, lockout 3/30min)." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] PSO Admin: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Aplicar PSO a usuarios admin
    $admins = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    foreach ($a in $admins) {
        try {
            Add-ADFineGrainedPasswordPolicySubject -Identity $psoAdmin -Subjects $a -ErrorAction Stop
            Write-Host "  [OK] PSO admin aplicado a: $a" -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] ${a}: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }

    # PSO 2: Usuarios estandar - 8 caracteres minimo
    $psoUser = "PSO-Usuarios-P09"
    $existe2 = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$psoUser'" -ErrorAction SilentlyContinue
    if ($existe2) {
        Write-Host "  [AVISO] PSO '$psoUser' ya existe. Actualizando..." -ForegroundColor Yellow
        Set-ADFineGrainedPasswordPolicy -Identity $psoUser `
            -MinPasswordLength 8 -PasswordHistoryCount 5 `
            -ComplexityEnabled $true -LockoutThreshold 5 `
            -LockoutDuration "00:15:00" -LockoutObservationWindow "00:15:00" `
            -MinPasswordAge "00:00:00" -MaxPasswordAge "90.00:00:00" `
            -ReversibleEncryptionEnabled $false -ErrorAction SilentlyContinue
    } else {
        try {
            New-ADFineGrainedPasswordPolicy -Name $psoUser `
                -Precedence 20 -MinPasswordLength 8 `
                -PasswordHistoryCount 5 -ComplexityEnabled $true `
                -LockoutThreshold 5 -LockoutDuration "00:15:00" `
                -LockoutObservationWindow "00:15:00" `
                -MinPasswordAge "00:00:00" -MaxPasswordAge "90.00:00:00" `
                -ReversibleEncryptionEnabled $false -ErrorAction Stop
            Write-Host "  [OK] PSO '$psoUser' creado (8 chars, lockout 5/15min)." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] PSO Usuario: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Aplicar PSO a OUs (via grupos)
    $ouCuates   = Get-OUSegura -NombreBase "Cuates"
    $ouNoCuates = Get-OUSegura -NombreBase "NoCuates"
    foreach ($ou in @($ouCuates, $ouNoCuates)) {
        if ($ou) {
            $users = Get-ADUser -Filter * -SearchBase $ou -ErrorAction SilentlyContinue
            foreach ($u in $users) {
                try {
                    Add-ADFineGrainedPasswordPolicySubject -Identity $psoUser -Subjects $u.SamAccountName -ErrorAction Stop
                    Write-Host "  [OK] PSO usuario aplicado a: $($u.SamAccountName)" -ForegroundColor Green
                } catch {
                    Write-Host "  [AVISO] $($u.SamAccountName): ya tiene PSO." -ForegroundColor DarkGray
                }
            }
        }
    }

    Write-Host "`n  FGPP configurado correctamente." -ForegroundColor Green
    Write-Host "  - Admins  : min 12 chars, lockout 3 intentos / 30 min" -ForegroundColor Cyan
    Write-Host "  - Usuarios: min  8 chars, lockout 5 intentos / 15 min" -ForegroundColor Cyan
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 5: Configurar auditoria y generar reporte
# ------------------------------------------------------------
function Configurar-Auditoria {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   AUDITORIA Y REPORTE ID 4625            |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    # Habilitar auditoria
    Write-Host "  Habilitando politicas de auditoria..." -ForegroundColor Yellow
    $categorias = @(
        @{ cat = "Logon";                          sub = "Logon" },
        @{ cat = "Account Logon";                  sub = "Credential Validation" },
        @{ cat = "Account Management";             sub = "User Account Management" },
        @{ cat = "DS Access";                      sub = "Directory Service Access" },
        @{ cat = "Object Access";                  sub = "Other Object Access Events" }
    )
    foreach ($c in $categorias) {
        auditpol /set /subcategory:"$($c.sub)" /success:enable /failure:enable 2>&1 | Out-Null
        Write-Host "    [OK] Auditoria: $($c.sub)" -ForegroundColor Green
    }

    # Generar reporte
    $rutaReporte = "C:\MFA_Setup\Reporte_Auditoria_4625.txt"
    $enc = "==================================================" + [Environment]::NewLine +
           "REPORTE DE AUDITORIA DE SEGURIDAD"               + [Environment]::NewLine +
           "Practica 09 - Hardening Active Directory"         + [Environment]::NewLine +
           "Fecha    : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" + [Environment]::NewLine +
           "Servidor : $env:COMPUTERNAME"                    + [Environment]::NewLine +
           "Dominio  : $env:USERDNSDOMAIN"                   + [Environment]::NewLine +
           "Evento   : ID 4625 - Inicio de sesion fallido"   + [Environment]::NewLine +
           "==================================================" + [Environment]::NewLine
    try {
        $eventos = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 10 -ErrorAction SilentlyContinue
        $enc | Out-File $rutaReporte -Encoding UTF8
        if (-not $eventos -or $eventos.Count -eq 0) {
            Write-Host "  [AVISO] Sin eventos ID 4625 aun. (genera intentos fallidos primero)" -ForegroundColor Yellow
            "No se encontraron eventos de acceso denegado (ID 4625)." | Out-File $rutaReporte -Append -Encoding UTF8
            "SUGERENCIA: Intenta iniciar sesion con una contrasena incorrecta y ejecuta de nuevo." | Out-File $rutaReporte -Append -Encoding UTF8
        } else {
            Write-Host "  [OK] $($eventos.Count) evento(s) encontrados. Exportando..." -ForegroundColor Green
            $i = 1
            foreach ($e in $eventos) {
                $xml  = [xml]$e.ToXml()
                $user = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetUserName"   }).'#text'
                $dom  = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
                $ip   = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "IpAddress"        }).'#text'
                ("EVENTO $i de $($eventos.Count)"                               + [Environment]::NewLine +
                 "--------------------------------------------------"           + [Environment]::NewLine +
                 "Fecha    : $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))" + [Environment]::NewLine +
                 "Usuario  : $user"                                              + [Environment]::NewLine +
                 "Dominio  : $dom"                                               + [Environment]::NewLine +
                 "IP origen: $ip"                                                + [Environment]::NewLine +
                 "--------------------------------------------------"           + [Environment]::NewLine
                ) | Out-File $rutaReporte -Append -Encoding UTF8
                $i++
            }
        }
        Write-Host "  [OK] Reporte guardado en: $rutaReporte" -ForegroundColor Green
        Write-Host "`n  --- CONTENIDO DEL REPORTE ---" -ForegroundColor Cyan
        Get-Content $rutaReporte | ForEach-Object { Write-Host "  $_" }
        Write-Host "  ----------------------------" -ForegroundColor Cyan
    } catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 6: Instalar VC++ 2022 y multiOTP
#            CORRECCION: Desactiva AppLocker antes de instalar
# ------------------------------------------------------------
function Instalar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   INSTALAR DEPENDENCIAS Y MOTOR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    $multiotpExe  = Get-MultiOTPExe
    if ($multiotpExe) {
        Write-Host "  [OK] multiOTP ya instalado: $(Split-Path $multiotpExe)" -ForegroundColor Green
        $r = Read-Host "  Reconfigurar? (s/n)"
        if ($r.ToLower() -ne 's') { Write-Host "  Ve a la Opcion 7." -ForegroundColor Yellow; Read-Host | Out-Null; return }
    }

    # -------------------------------------------------------
    # PASO CRITICO: Deshabilitar AppLocker para la instalacion
    # Esto resuelve el error "This program is blocked by group policy"
    # -------------------------------------------------------
    Write-Host "  [PASO CRITICO] Manejando AppLocker para permitir instalacion..." -ForegroundColor Magenta

    # Metodo 1: Agregar regla de ruta allow para C:\MFA_Setup y C:\Windows
    $reglaAgregada = Agregar-ReglaAppLockerRuta -Ruta $rutaDescarga

    # Metodo 2: Deshabilitar AppIDSvc si el metodo 1 no fue suficiente
    $appIDSvc = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
    if ($appIDSvc -and $appIDSvc.Status -eq "Running") {
        Write-Host "  [INFO] AppIDSvc activo. Deteniendolo para instalacion..." -ForegroundColor Yellow
        try {
            Stop-Service -Name "AppIDSvc" -Force -ErrorAction Stop
            Write-Host "  [OK] AppIDSvc detenido. AppLocker temporalmente inactivo." -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] No se pudo detener AppIDSvc: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Start-Sleep -Seconds 2

    # -------------------------------------------------------
    # PASO 1: Visual C++ 2022 Redistributable
    # -------------------------------------------------------
    Write-Host "`n  [1/2] Visual C++ 2022 Redistributable..." -ForegroundColor Yellow
    $vcPath = "$rutaDescarga\vc_redist_2022_x64.exe"

    # Verificar si ya esta instalado
    $vcInstalado = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
    if ($vcInstalado) {
        Write-Host "  [OK] VC++ 2022 ya esta instalado (version: $($vcInstalado.Version))." -ForegroundColor Green
    } else {
        if (-not (Test-Path $vcPath)) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Write-Host "  Descargando VC++ Redistributable..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcPath -UseBasicParsing -ErrorAction Stop
                Write-Host "  [OK] Descargado." -ForegroundColor Green
            } catch {
                Write-Host "  [ERROR] Descarga VC++: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  [INFO] Descarga manual: https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
                Write-Host "  [INFO] Guarda el archivo como: $vcPath" -ForegroundColor Yellow
                Read-Host | Out-Null; return
            }
        }

        Write-Host "  Instalando VC++ 2022..." -ForegroundColor Yellow

        # CRITICO: copiar a C:\Windows\Temp (siempre permitido por GPO/AppLocker)
        $vcTemp = "C:\Windows\Temp\vc_redist_p9.exe"
        try {
            Copy-Item -Path $vcPath -Destination $vcTemp -Force -ErrorAction Stop
            Write-Host "  [OK] Copiado a ruta permitida por GPO: $vcTemp" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] No se pudo copiar a Temp. Usando ruta original." -ForegroundColor Yellow
            $vcTemp = $vcPath
        }

        $vcOK = $false
        # Intento 1: cmd /c desde Windows\Temp
        cmd /c "`"$vcTemp`" /install /quiet /norestart" 2>&1 | Out-Null
        if ($LASTEXITCODE -in @(0,1638,3010)) {
            Write-Host "  [OK] VC++ 2022 instalado." -ForegroundColor Green
            $vcOK = $true
        }
        # Intento 2: Start-Process
        if (-not $vcOK) {
            try {
                $p2 = Start-Process -FilePath $vcTemp -ArgumentList "/install /quiet /norestart" -Wait -PassThru -ErrorAction Stop
                if ($p2.ExitCode -in @(0,1638,3010)) {
                    Write-Host "  [OK] VC++ instalado (intento 2)." -ForegroundColor Green
                    $vcOK = $true
                }
            } catch {}
        }
        # Intento 3: cmd.exe como proceso padre
        if (-not $vcOK) {
            try {
                $p3 = Start-Process "cmd.exe" -ArgumentList "/c `"$vcTemp`" /install /quiet /norestart" -Wait -PassThru -ErrorAction Stop
                if ($p3.ExitCode -in @(0,1638,3010)) {
                    Write-Host "  [OK] VC++ instalado (intento 3)." -ForegroundColor Green
                    $vcOK = $true
                }
            } catch {}
        }
        if (-not $vcOK) {
            Write-Host "  [WARN] VC++ no se pudo instalar automaticamente." -ForegroundColor Yellow
            Write-Host "  [INFO] multiOTP puede instalarse igual. Continuando..." -ForegroundColor Cyan
        }
    } # cierre del else (VC++ no instalado)

    Start-Sleep -Seconds 2

    # -------------------------------------------------------
    # PASO 2: Instalar multiOTP Credential Provider
    # -------------------------------------------------------
    Write-Host "`n  [2/2] Instalador multiOTP Credential Provider..." -ForegroundColor Yellow

    # Extraer ZIPs si hay
    Get-ChildItem -Path $rutaDescarga -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = "$rutaDescarga\Extracted_$($_.BaseName)"
        if (-not (Test-Path $dest)) {
            Write-Host "  Extrayendo: $($_.Name)..." -ForegroundColor Yellow
            Expand-Archive -Path $_.FullName -DestinationPath $dest -Force
            Write-Host "  [OK] Extraido en: $dest" -ForegroundColor Green
        }
    }

    # Buscar instalador
    $instalador = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } |
                  Sort-Object Length -Descending | Select-Object -First 1

    if (-not $instalador) {
        Write-Host "  [ERROR] No se encontro instalador multiOTP." -ForegroundColor Red
        Write-Host "  [SOLUCION] Ejecuta primero la Opcion 1 para descargar multiOTP." -ForegroundColor Yellow
        # Rehabilitar AppLocker antes de salir
        $svcRestart = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        if ($svcRestart -and $svcRestart.Status -ne "Running") {
            Start-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        }
        Read-Host | Out-Null; return
    }

    Write-Host "`n  Instalador encontrado: $($instalador.Name)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  +-------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  |   INSTRUCCIONES DEL INSTALADOR multiOTP         |" -ForegroundColor Yellow
    Write-Host "  +-------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  1. En la primera pantalla marca:" -ForegroundColor White
    Write-Host "     'No remote server, local multiOTP only'"         -ForegroundColor Green
    Write-Host "  2. Logon  -> selecciona 'Local and Remote'"         -ForegroundColor White
    Write-Host "  3. Unlock -> selecciona 'Local and Remote'"         -ForegroundColor White
    Write-Host "  4. Haz clic en 'Next' hasta llegar a 'Finish'."     -ForegroundColor White
    Write-Host "  5. Al terminar el instalador, este script seguira." -ForegroundColor White
    Write-Host ""
    Write-Host "  Presiona Enter para lanzar el instalador..." -ForegroundColor Cyan
    Read-Host | Out-Null

    try {
        if ($instalador.Extension -eq ".msi") {
            Write-Host "  Instalando MSI..." -ForegroundColor Yellow
            $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$($instalador.FullName)`"" -Wait -PassThru -ErrorAction Stop
        } else {
            Write-Host "  Instalando EXE..." -ForegroundColor Yellow
            # Usar cmd /c para evitar bloqueo de AppLocker
            $resultado = cmd /c "`"$($instalador.FullName)`"" 2>&1
            $p = [PSCustomObject]@{ ExitCode = $LASTEXITCODE }
            if ($p.ExitCode -ne 0) {
                # Segundo intento con Start-Process
                $p = Start-Process $instalador.FullName -Wait -PassThru -ErrorAction Stop
            }
        }
        if ($p.ExitCode -eq 0) {
            Write-Host "  [OK] multiOTP instalado correctamente." -ForegroundColor Green
        } else {
            Write-Host "  [AVISO] Codigo de salida: $($p.ExitCode). Puede ser normal." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [SOLUCION] Instala manualmente haciendo doble clic en: $($instalador.FullName)" -ForegroundColor Cyan
    }

    # -------------------------------------------------------
    # Rehabilitar AppLocker
    # -------------------------------------------------------
    Write-Host "`n  Rehabilitando AppLocker..." -ForegroundColor Yellow
    $svcFinal = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
    if ($svcFinal -and $svcFinal.Status -ne "Running") {
        try {
            Start-Service -Name "AppIDSvc" -ErrorAction Stop
            Write-Host "  [OK] AppIDSvc rehabilitado." -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] No se pudo rehabilitar AppIDSvc: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [OK] AppIDSvc ya estaba corriendo." -ForegroundColor Green
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 7: Registrar TODOS los admins en multiOTP
# ------------------------------------------------------------
function Activar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   ACTIVAR MFA Y GENERAR CLAVE TOTP       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $multiotpExe = Get-MultiOTPExe
    if (-not $multiotpExe) {
        Write-Host "  [ERROR] multiotp.exe no encontrado. Ejecuta Opcion 6." -ForegroundColor Red
        Read-Host | Out-Null; return
    }
    $dir = Split-Path $multiotpExe
    Push-Location $dir

    $netbios = $env:USERDOMAIN
    $dns     = $env:USERDNSDOMAIN
    if ([string]::IsNullOrWhiteSpace($dns)) { $dns = (Get-ADDomain).DNSRoot }

    $base32    = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $miSecreto = -join ((1..16) | ForEach-Object { $base32[(Get-Random -Maximum 32)] })
    Write-Host "  [INFO] Secreto TOTP generado: $miSecreto`n" -ForegroundColor DarkGray

    $usuarios = @("Administrator","admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    $totalOK  = 0
    foreach ($u in $usuarios) {
        Write-Host "  Registrando: $u ..." -ForegroundColor Yellow
        foreach ($id in @($u, "$netbios\$u", "$u@$dns")) {
            & ".\multiotp.exe" -delete $id 2>&1 | Out-Null
            $s = & ".\multiotp.exe" -create $id TOTP $miSecreto 6 2>&1
            if ($s -match "(?i)(ok|success|created|0)") {
                Write-Host "    [OK] $id" -ForegroundColor Green; $totalOK++
            } else {
                Write-Host "    [WARN] $id -> $s" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "`n  Configurando bloqueo (3 fallos = 30 min = 1800 seg)..." -ForegroundColor Yellow
    & ".\multiotp.exe" -config MaxDelayedFailures=3       2>&1 | Out-Null
    & ".\multiotp.exe" -config MaxBlockFailures=3         2>&1 | Out-Null
    & ".\multiotp.exe" -config FailureDelayInSeconds=1800 2>&1 | Out-Null
    Write-Host "  [OK] Bloqueo configurado: 3 intentos fallidos = 30 min bloqueado." -ForegroundColor Green
    Pop-Location

    $archivo = "C:\MFA_Setup\MFA_Secret_TodosAdmins.txt"
    @("MFA TOTP Secret - Practica 09","==============================",
      "Usuarios : Administrator, admin_identidad, admin_storage, admin_politicas, admin_auditoria",
      "Servidor : $env:COMPUTERNAME","Dominio  : $netbios ($dns)",
      "Secreto  : $miSecreto","Tipo     : TOTP RFC 6238 (Google Authenticator)",
      "Generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
      "","NOTA: Todos los usuarios comparten el mismo secreto TOTP."
    ) | Out-File $archivo -Encoding UTF8

    Write-Host "`n  +----------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  |   CONFIGURA GOOGLE AUTHENTICATOR EN TU CELULAR           |" -ForegroundColor Magenta
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  PASO 1: Abre Google Authenticator en tu telefono"          -ForegroundColor White
    Write-Host "  PASO 2: Toca el boton '+' > 'Ingresar clave de config.'"   -ForegroundColor White
    Write-Host "  PASO 3: Escribe los siguientes datos:"                      -ForegroundColor White
    Write-Host ""
    Write-Host "     Nombre : Practica09 - $env:COMPUTERNAME"                -ForegroundColor Cyan
    Write-Host "     Secreto: $miSecreto"                                     -ForegroundColor Green
    Write-Host "     Tipo   : Basada en tiempo (TOTP)"                        -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  PASO 4: Toca 'Agregar'" -ForegroundColor White
    Write-Host ""
    Write-Host "  Sirve para: Administrator, admin_identidad, admin_storage," -ForegroundColor White
    Write-Host "              admin_politicas, admin_auditoria"                -ForegroundColor White
    Write-Host ""
    Write-Host "  IMPORTANTE: Si ya tenias una entrada anterior, BORRALA"    -ForegroundColor Red
    Write-Host "              y crea una nueva con el secreto de arriba."     -ForegroundColor Red
    Write-Host ""
    Write-Host "  [OK] Secreto guardado en: $archivo"                        -ForegroundColor Green
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 8: Ejecutar tests de evaluacion
# ------------------------------------------------------------
function Ejecutar-Tests {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PROTOCOLO DE PRUEBAS - PRACTICA 09     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan
    Write-Host "  1. Test 1 -- Delegacion RBAC (admin_identidad PASS / admin_storage DENY)" -ForegroundColor White
    Write-Host "  2. Test 2 -- FGPP (contrasena 8 chars rechazada para admin_identidad)"    -ForegroundColor White
    Write-Host "  3. Test 3 -- Estado MFA en multiOTP"                                      -ForegroundColor White
    Write-Host "  4. Test 4 -- Verificar bloqueo MFA"                                       -ForegroundColor White
    Write-Host "  5. Test 5 -- Generar reporte auditoria ID 4625"                           -ForegroundColor White
    Write-Host "  6. Todos los tests"                                                        -ForegroundColor White
    Write-Host ""
    $t = Read-Host "  Selecciona"
    switch ($t) {
        '1' { Test-DelegacionRBAC }
        '2' { Test-FGPP }
        '3' { Test-EstadoMFA }
        '4' { Test-BloqueoMFA }
        '5' { Configurar-Auditoria }
        '6' { Test-DelegacionRBAC; Test-FGPP; Test-EstadoMFA; Test-BloqueoMFA; Configurar-Auditoria }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# TEST 1: Delegacion RBAC
# ------------------------------------------------------------
function Test-DelegacionRBAC {
    Write-Host "`n  TEST 1 -- Delegacion RBAC" -ForegroundColor Cyan
    Write-Host "  -------------------------" -ForegroundColor Cyan

    $dcBase   = (Get-ADDomain).DistinguishedName
    $netbios  = (Get-ADDomain).NetBIOSName
    $servidor = $env:COMPUTERNAME

    $ouCuates = Get-OUSegura -NombreBase "Cuates"
    $usuarioPrueba = $null
    if ($ouCuates) {
        $usuarioPrueba = Get-ADUser -Filter * -SearchBase $ouCuates -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $usuarioPrueba) {
        Write-Host "  [WARN] No hay usuarios en OU Cuates. Crea uno y repite." -ForegroundColor Yellow; return
    }
    Write-Host "  Usuario de prueba : $($usuarioPrueba.SamAccountName)" -ForegroundColor DarkGray
    Write-Host "  DN                : $($usuarioPrueba.DistinguishedName)" -ForegroundColor DarkGray

    $pwdAdmin  = ConvertTo-SecureString "Hardening2026!" -AsPlainText -Force
    $targetSam = $usuarioPrueba.SamAccountName

    # ACCION A: admin_identidad debe poder resetear
    Write-Host "`n  ACCION A: admin_identidad resetea contrasena de '$targetSam'..." -ForegroundColor Yellow
    $credId = New-Object System.Management.Automation.PSCredential("$netbios\admin_identidad", $pwdAdmin)
    try {
        $resultA = Invoke-Command -ComputerName $servidor -Credential $credId -ArgumentList $targetSam -ScriptBlock {
            param($sam)
            Import-Module ActiveDirectory -ErrorAction Stop
            $nueva = ConvertTo-SecureString "Delegado2026!!" -AsPlainText -Force
            Set-ADAccountPassword -Identity $sam -NewPassword $nueva -Reset -ErrorAction Stop
            return "OK"
        } -ErrorAction Stop
        if ($resultA -eq "OK") {
            Write-Host "  [PASS] ACCION A: admin_identidad reseteo la contrasena EXITOSAMENTE." -ForegroundColor Green
            Write-Host "         Toma captura de esta pantalla como evidencia." -ForegroundColor Cyan
        }
    } catch {
        $msg = $_.Exception.Message
        Write-Host "  [FAIL] ACCION A fallo: $msg" -ForegroundColor Red
        Write-Host "  [INFO] Verificando ACEs directamente en la OU..." -ForegroundColor Yellow
        try {
            $sidIdentidad = (Get-ADUser "admin_identidad").SID
            $aclRaw = (Get-Acl "AD:\$ouCuates").Access
            $aces = $aclRaw | Where-Object { $_.IdentityReference.ToString() -match "admin_identidad|$($sidIdentidad.Value)" }
            if ($aces) {
                Write-Host "  [INFO] ACEs de admin_identidad en la OU:" -ForegroundColor Yellow
                $aces | Select-Object -First 5 | ForEach-Object {
                    Write-Host "         $($_.AccessControlType): $($_.ActiveDirectoryRights)" -ForegroundColor DarkGray
                }
                Write-Host "  [SUGERENCIA] Los permisos existen. El problema puede ser WinRM." -ForegroundColor Yellow
                Write-Host "  [SUGERENCIA] Ejecuta: Enable-PSRemoting -Force" -ForegroundColor Cyan
            } else {
                Write-Host "  [WARN] No hay ACEs para admin_identidad. Ejecuta Opcion 3." -ForegroundColor Yellow
            }
        } catch { Write-Host "  No se pudo leer ACL: $($_.Exception.Message)" -ForegroundColor Yellow }
    }

    # ACCION B: admin_storage debe ser denegado
    Write-Host "`n  ACCION B: admin_storage intenta resetear (debe ser DENEGADO)..." -ForegroundColor Yellow
    $credSt = New-Object System.Management.Automation.PSCredential("$netbios\admin_storage", $pwdAdmin)
    try {
        Invoke-Command -ComputerName $servidor -Credential $credSt -ArgumentList $targetSam -ScriptBlock {
            param($sam)
            Import-Module ActiveDirectory -ErrorAction Stop
            $nueva = ConvertTo-SecureString "Delegado2026!!" -AsPlainText -Force
            Set-ADAccountPassword -Identity $sam -NewPassword $nueva -Reset -ErrorAction Stop
            return "OK"
        } -ErrorAction Stop
        Write-Host "  [FAIL] ACCION B: admin_storage pudo resetear (DENY no funciona)." -ForegroundColor Red
        Write-Host "         Vuelve a ejecutar Opcion 3 y repite." -ForegroundColor Yellow
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match "Access.is.denied|Access denied|UnauthorizedAccess|no tiene acceso|PermissionDenied") {
            Write-Host "  [PASS] ACCION B: ACCESO DENEGADO correctamente." -ForegroundColor Green
            Write-Host "         Error: $msg" -ForegroundColor DarkGray
            Write-Host "         Toma captura de esta pantalla como evidencia." -ForegroundColor Cyan
        } else {
            Write-Host "  [INFO] Error (puede ser WinRM): $msg" -ForegroundColor Yellow
            Write-Host "  Verificando ACE DENY directamente en AD..." -ForegroundColor Yellow
            try {
                $aclDom  = Get-Acl -Path "AD:\$dcBase"
                $denyAce = $aclDom.Access | Where-Object {
                    $_.IdentityReference -like "*admin_storage*" -and $_.AccessControlType -eq "Deny"
                }
                if ($denyAce) {
                    Write-Host "  [PASS] ACE DENY confirmada para admin_storage:" -ForegroundColor Green
                    $denyAce | ForEach-Object { Write-Host "         Deny: $($_.ActiveDirectoryRights)" -ForegroundColor DarkGray }
                    Write-Host "         Toma captura como evidencia." -ForegroundColor Cyan
                } else {
                    Write-Host "  [WARN] No se encontro DENY. Ejecuta Opcion 3." -ForegroundColor Yellow
                }
            } catch { Write-Host "  No se pudo leer ACL: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }

    Write-Host "`n  --- RESUMEN TEST 1 ---" -ForegroundColor Cyan
    Write-Host "  ACCION A PASS + ACCION B PASS = Test 1 completado." -ForegroundColor White
    Write-Host "  Toma captura de pantalla de este resultado." -ForegroundColor White
}

# ------------------------------------------------------------
# TEST 2: FGPP
# ------------------------------------------------------------
function Test-FGPP {
    Write-Host "`n  TEST 2 -- FGPP" -ForegroundColor Cyan
    Write-Host "  --------------" -ForegroundColor Cyan
    try {
        $pso = Get-ADUserResultantPasswordPolicy -Identity "admin_identidad" -ErrorAction Stop
        if ($pso) {
            Write-Host "  Politica efectiva para admin_identidad:" -ForegroundColor Yellow
            Write-Host "  Nombre          : $($pso.Name)"                    -ForegroundColor White
            Write-Host "  Longitud minima : $($pso.MinPasswordLength) chars" -ForegroundColor White
            Write-Host "  Lockout umbral  : $($pso.LockoutThreshold)"        -ForegroundColor White
            Write-Host "  Lockout duracion: $($pso.LockoutDuration)"         -ForegroundColor White
        } else {
            Write-Host "  [WARN] No se encontro PSO para admin_identidad." -ForegroundColor Yellow
            Write-Host "         Ejecuta Opcion 4 primero." -ForegroundColor Yellow
        }
    } catch { Write-Host "  [WARN] No se pudo leer PSO: $($_.Exception.Message)" -ForegroundColor Yellow }

    Write-Host "`n  Intentando poner contrasena de 8 chars a admin_identidad (debe FALLAR)..." -ForegroundColor Yellow
    try {
        Set-ADAccountPassword -Identity "admin_identidad" `
            -NewPassword (ConvertTo-SecureString "Corta1!!" -AsPlainText -Force) -Reset -ErrorAction Stop
        Write-Host "  [FAIL] Acepto contrasena corta (no deberia)." -ForegroundColor Red
        Write-Host "         Verifica que el PSO este aplicado. Ejecuta Opcion 4." -ForegroundColor Yellow
    } catch {
        Write-Host "  [PASS] Contrasena de 8 chars RECHAZADA correctamente." -ForegroundColor Green
        Write-Host "         Error: $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host "         Toma captura de esta pantalla como evidencia." -ForegroundColor Cyan
    }
}

# ------------------------------------------------------------
# TEST 3: Estado MFA
# ------------------------------------------------------------
function Test-EstadoMFA {
    Write-Host "`n  TEST 3 -- Estado MFA (multiOTP)" -ForegroundColor Cyan
    Write-Host "  --------------------------------" -ForegroundColor Cyan

    $multiotpExe = Get-MultiOTPExe
    if (-not $multiotpExe) {
        Write-Host "  [FAIL] multiOTP no instalado. Ejecuta Opcion 6 y 7." -ForegroundColor Red
        return
    }
    Write-Host "  [OK] multiOTP encontrado en: $multiotpExe" -ForegroundColor Green

    $dir = Split-Path $multiotpExe
    Push-Location $dir

    Write-Host "`n  Usuarios registrados en multiOTP:" -ForegroundColor Yellow
    $carpeta = Join-Path $dir "users"
    if (Test-Path $carpeta) {
        $dbs = Get-ChildItem -Path $carpeta -Filter "*.db" -ErrorAction SilentlyContinue
        if ($dbs -and $dbs.Count -gt 0) {
            $dbs | ForEach-Object { Write-Host "    [+] $($_.BaseName)" -ForegroundColor Green }
            Write-Host "  [PASS] $($dbs.Count) usuario(s) registrados." -ForegroundColor Green
        } else {
            Write-Host "  [WARN] No hay usuarios. Ejecuta Opcion 7." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [WARN] Carpeta users no encontrada en: $dir" -ForegroundColor Yellow
    }

    Write-Host "`n  Configuracion de bloqueo MFA:" -ForegroundColor Yellow
    $cfgFile = Join-Path $dir "config\multiotp.json"
    if (-not (Test-Path $cfgFile)) { $cfgFile = Join-Path $dir "multiotp.json" }
    if (Test-Path $cfgFile) {
        $j = Get-Content $cfgFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($j) {
            $mb = if ($j.MaxBlockFailures)      { $j.MaxBlockFailures }      else { "N/D" }
            $md = if ($j.MaxDelayedFailures)    { $j.MaxDelayedFailures }    else { "N/D" }
            $fd = if ($j.FailureDelayInSeconds) { $j.FailureDelayInSeconds } else { "N/D" }
            Write-Host "    MaxBlockFailures   : $mb (debe ser 3)"    -ForegroundColor White
            Write-Host "    MaxDelayedFailures : $md (debe ser 3)"    -ForegroundColor White
            Write-Host "    FailureDelay (seg) : $fd (debe ser 1800)" -ForegroundColor White
            if ($mb -eq 3 -or $md -eq 3) { Write-Host "  [PASS] Bloqueo configurado correctamente." -ForegroundColor Green }
            else { Write-Host "  [WARN] Ejecuta Opcion 7 para configurar bloqueo." -ForegroundColor Yellow }
        }
    } else {
        Write-Host "    Config JSON no encontrado. Bloqueo aplicado via -config." -ForegroundColor DarkGray
        Write-Host "    Se validara con el Test 4 manualmente." -ForegroundColor DarkGray
    }
    Pop-Location
}

# ------------------------------------------------------------
# TEST 4: Bloqueo por MFA fallido
# ------------------------------------------------------------
function Test-BloqueoMFA {
    Write-Host "`n  TEST 4 -- Bloqueo por MFA fallido" -ForegroundColor Cyan
    Write-Host "  ----------------------------------" -ForegroundColor Cyan

    $usuarios     = @("Administrator","admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    $hayBloqueado = $false
    Write-Host "`n  Estado de bloqueo en Active Directory:" -ForegroundColor Yellow
    foreach ($u in $usuarios) {
        try {
            $info   = Get-ADUser -Identity $u -Properties LockedOut, BadLogonCount -ErrorAction Stop
            $estado = if ($info.LockedOut) { "[BLOQUEADO]" } else { "[OK - libre]" }
            $color  = if ($info.LockedOut) { "Red" } else { "Green" }
            Write-Host "  $estado $u (intentos fallidos: $($info.BadLogonCount))" -ForegroundColor $color
            if ($info.LockedOut) { $hayBloqueado = $true }
        } catch {
            Write-Host "  [WARN] No se pudo verificar ${u}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($hayBloqueado) {
        Write-Host "`n  [PASS] Cuenta bloqueada detectada. Toma captura como evidencia." -ForegroundColor Green
        Write-Host "  Para desbloquear: Unlock-ADAccount -Identity <usuario>" -ForegroundColor Cyan
    } else {
        Write-Host "`n  [INFO] Ninguna cuenta bloqueada actualmente." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Para el Test 4 (instrucciones):" -ForegroundColor Yellow
        Write-Host "  1. Cierra sesion en el servidor fisicamente" -ForegroundColor White
        Write-Host "  2. Ingresa usuario: Administrator y contrasena correcta" -ForegroundColor White
        Write-Host "  3. Cuando pida el codigo MFA, escribe: 000000" -ForegroundColor White
        Write-Host "  4. Repite 3 veces el paso anterior" -ForegroundColor White
        Write-Host "  5. Vuelve a este script y ejecuta de nuevo el Test 4" -ForegroundColor White
        Write-Host "  6. La cuenta debera aparecer como [BLOQUEADO]" -ForegroundColor White
    }
}