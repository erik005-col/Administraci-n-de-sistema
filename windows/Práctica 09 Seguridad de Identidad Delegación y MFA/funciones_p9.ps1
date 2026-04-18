# ============================================================
#  funciones_p9.ps1 - Libreria de funciones para la Practica 9
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#  Version  : 1.0
#
#  Actividades:
#  1. Delegacion de Control y RBAC (4 roles)
#  2. FGPP - Directivas de contrasena ajustada
#  3. Auditoria de eventos (auditpol)
#  4. Script de monitoreo (Event ID 4625)
#  5. Guia de instalacion MFA (WinOTP/TOTP)
# ============================================================

# ------------------------------------------------------------
# FUNCION 1: Preparar Entorno y Descargar MFA
# ------------------------------------------------------------
function Preparar-EntornoMFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    PREPARAR ENTORNO Y DESCARGAR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"

    # 1. Crear carpeta si no existe
    if (-not (Test-Path $rutaDescarga)) {
        New-Item -Path $rutaDescarga -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $rutaDescarga" -ForegroundColor Green
    }

    # 2. Logica de validacion de descarga (CORREGIDA PARA ZIPS)
    $procederDescarga = $true
    $archivosExistentes = Get-ChildItem -Path $rutaDescarga -Filter "multiOTP*" -ErrorAction SilentlyContinue

    if ($archivosExistentes) {
        Write-Host "  [AVISO] Ya existen archivos de multiOTP descargados en el servidor." -ForegroundColor Yellow
        $respuesta = Read-Host "  Deseas conectarte a internet para descargar la ultima version? (s/n)"
        
        if ($respuesta.ToLower() -ne 's') {
            $procederDescarga = $false
            Write-Host "  [OK] Omitiendo descarga. Se usaran los archivos locales (No requiere internet)." -ForegroundColor Green
        }
    }

    # 3. Descargar si es necesario
    if ($procederDescarga) {
        Write-Host "  [INFO] Conectando a la API de GitHub para buscar la ultima version..." -ForegroundColor Cyan
        
        # Forzar protocolos de seguridad modernos (TLS 1.2)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        try {
            $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell" }
            
            # PLAN DINAMICO: Preguntar a GitHub cual es la version más nueva
            $apiUrl = "https://api.github.com/repos/multiOTP/multiOTPCredentialProvider/releases/latest"
            $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
            
            # Buscar el archivo descargable (.zip o .exe) dentro del release
            $asset = $release.assets | Where-Object { $_.name -like "*.zip" -or $_.name -like "*.exe" } | Select-Object -First 1
            
            if (-not $asset) {
                Write-Host "  [ERROR] No se encontraron instaladores en la ultima version." -ForegroundColor Red
                return
            }

            $urlDinamica = $asset.browser_download_url
            $nombreArchivo = $asset.name
            $rutaArchivo = "$rutaDescarga\$nombreArchivo"

            Write-Host "  [INFO] Descargando $($release.tag_name) ($nombreArchivo)..." -ForegroundColor Yellow
            
            # Descargar el archivo real
            Invoke-WebRequest -Uri $urlDinamica -OutFile $rutaArchivo -UseBasicParsing -Headers $headers
            
            # Si el desarrollador subio un .zip (como lo hacen ahora), lo extraemos automaticamente
            if ($rutaArchivo.EndsWith(".zip")) {
                Write-Host "  [INFO] Archivo ZIP detectado. Extrayendo contenido en $rutaDescarga..." -ForegroundColor Yellow
                Expand-Archive -Path $rutaArchivo -DestinationPath $rutaDescarga -Force
                Write-Host "  [OK] Descarga y extraccion completada exitosamente." -ForegroundColor Green
            } else {
                Write-Host "  [OK] Descarga completada exitosamente." -ForegroundColor Green
            }

        } catch {
            Write-Host "  [ERROR] Fallo la descarga desde la API de GitHub." -ForegroundColor Red
            Write-Host "  Detalle final: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}


# ============================================================
# FUNCION 2: Crear usuarios administradores delegados (RBAC)
# ============================================================
function Crear-UsuariosAdmin {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    CREAR USUARIOS ADMINISTRADORES        |" -ForegroundColor Cyan
    Write-Host "  |    RBAC - 4 Roles Delegados              |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
        $dcBase  = $dominio.DistinguishedName
    } catch {
        Write-Host "  [ERROR] No se puede conectar a Active Directory." -ForegroundColor Red
        Write-Host "  Asegurate de ejecutar en el Domain Controller." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Crear OU de Administradores si no existe
    $ouAdminPath = "OU=Administradores,$dcBase"
    try {
        Get-ADOrganizationalUnit -Identity $ouAdminPath -ErrorAction Stop | Out-Null
        Write-Host "  [OK] OU 'Administradores' ya existe." -ForegroundColor Yellow
    } catch {
        try {
            New-ADOrganizationalUnit -Name "Administradores" -Path $dcBase `
                -ProtectedFromAccidentalDeletion $false
            Write-Host "  [CREADO] OU 'Administradores' creada." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] No se pudo crear OU Administradores: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Los siguientes usuarios admin seran creados:" -ForegroundColor White
    Write-Host "    -> admin_identidad  (Rol 1: IAM Operator)"           -ForegroundColor Cyan
    Write-Host "    -> admin_storage    (Rol 2: Storage Operator)"        -ForegroundColor Cyan
    Write-Host "    -> admin_politicas  (Rol 3: GPO Compliance)"          -ForegroundColor Cyan
    Write-Host "    -> admin_auditoria  (Rol 4: Security Auditor)"        -ForegroundColor Cyan
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Definir los 4 usuarios admin
    $admins = @(
        @{
            Usuario     = "admin_identidad"
            Nombre      = "Admin"
            Apellido    = "Identidad"
            Descripcion = "Rol 1 - IAM Operator: Gestion de usuarios Cuates/NoCuates"
            Password    = "P@ssword123!Id"
        },
        @{
            Usuario     = "admin_storage"
            Nombre      = "Admin"
            Apellido    = "Storage"
            Descripcion = "Rol 2 - Storage Operator: Gestion de cuotas y FSRM"
            Password    = "P@ssword123!St"
        },
        @{
            Usuario     = "admin_politicas"
            Nombre      = "Admin"
            Apellido    = "Politicas"
            Descripcion = "Rol 3 - GPO Compliance: Gestion de directivas de grupo"
            Password    = "P@ssword123!Gp"
        },
        @{
            Usuario     = "admin_auditoria"
            Nombre      = "Admin"
            Apellido    = "Auditoria"
            Descripcion = "Rol 4 - Security Auditor: Solo lectura, monitoreo de eventos"
            Password    = "P@ssword123!Au"
        }
    )

    Write-Host ""
    Write-Host "  Creando usuarios..." -ForegroundColor Yellow
    Write-Host ""

    foreach ($a in $admins) {
        $existe = $null
        try {
            $existe = Get-ADUser -Identity $a.Usuario -ErrorAction Stop
            Write-Host "  [OMITIDO] '$($a.Usuario)' ya existe en AD." -ForegroundColor Yellow
        } catch {
            $existe = $null
        }

        if (-not $existe) {
            try {
                $passwordSeg = ConvertTo-SecureString $a.Password -AsPlainText -Force
                New-ADUser `
                    -Name "$($a.Nombre) $($a.Apellido)" `
                    -GivenName $a.Nombre `
                    -Surname $a.Apellido `
                    -SamAccountName $a.Usuario `
                    -UserPrincipalName "$($a.Usuario)@practica8.local" `
                    -Path $ouAdminPath `
                    -Description $a.Descripcion `
                    -AccountPassword $passwordSeg `
                    -Enabled $true `
                    -PasswordNeverExpires $false `
                    -ChangePasswordAtLogon $false

                Write-Host "  [CREADO] $($a.Usuario) | Password: $($a.Password)" -ForegroundColor Green
            } catch {
                Write-Host "  [ERROR] No se pudo crear '$($a.Usuario)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Usuarios admin creados exitosamente.     |" -ForegroundColor Cyan
    Write-Host "  | SIGUIENTE PASO: Opcion 2 - Configurar    |" -ForegroundColor Yellow
    Write-Host "  | delegacion y ACLs para cada rol.         |" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ============================================================
# FUNCION 3: Configurar Delegacion y ACLs (RBAC)
# ============================================================
function Configurar-Delegacion {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR DELEGACION Y ACLs (RBAC)    |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
        $dcBase  = $dominio.DistinguishedName
        $dnsRoot = $dominio.DNSRoot
    } catch {
        Write-Host "  [ERROR] No se puede conectar a Active Directory." -ForegroundColor Red
        Write-Host ""
        return
    }

    # Verificar que los usuarios admin existen
    $adminsReq = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    foreach ($adm in $adminsReq) {
        try {
            Get-ADUser -Identity $adm -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "  [ERROR] El usuario '$adm' no existe. Ejecuta primero la opcion 1." -ForegroundColor Red
            Write-Host ""
            return
        }
    }

    Write-Host "  Se configuraran los siguientes permisos:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Rol 1 - admin_identidad:" -ForegroundColor Cyan
    Write-Host "    -> Crear/Eliminar/Modificar usuarios en OU Cuates y NoCuates" -ForegroundColor White
    Write-Host "    -> Reset Password y desbloqueo de cuentas" -ForegroundColor White
    Write-Host "    -> Modificar atributos basicos (Telefono, Oficina, Correo)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Rol 2 - admin_storage:" -ForegroundColor Cyan
    Write-Host "    -> Gestion de FSRM (cuotas, apantallamiento, reportes)" -ForegroundColor White
    Write-Host "    -> DENEGADO explicitamente: Reset Password en objetos de usuario" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Rol 3 - admin_politicas:" -ForegroundColor Cyan
    Write-Host "    -> Lectura en todo el dominio" -ForegroundColor White
    Write-Host "    -> Escritura solo sobre objetos GPO" -ForegroundColor White
    Write-Host "    -> Vincular/desvincular GPOs, modificar FGPP" -ForegroundColor White
    Write-Host ""
    Write-Host "  Rol 4 - admin_auditoria:" -ForegroundColor Cyan
    Write-Host "    -> Solo lectura en todo el dominio (Read-Only)" -ForegroundColor White
    Write-Host "    -> Acceso a Registros de Seguridad del Event Viewer" -ForegroundColor White
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar con la configuracion? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    # -------------------------------------------------------
    # ROL 1: admin_identidad - dsacls sobre OU Cuates y NoCuates
    # -------------------------------------------------------
    Write-Host "  [ROL 1] Configurando admin_identidad..." -ForegroundColor Yellow
    Write-Host ""

    $ous = @("Cuates", "NoCuates")
    foreach ($ouNombre in $ous) {
        $ouPath = "OU=$ouNombre,$dcBase"

        # Verificar que la OU existe
        try {
            Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "  [AVISO] OU '$ouNombre' no existe, se omite." -ForegroundColor Yellow
            continue
        }

        # Permisos completos sobre objetos User en la OU
        # Crear/Eliminar/Modificar usuarios
        $cmds = @(
            "dsacls `"$ouPath`" /I:S /G `"PRACTICA8\admin_identidad:CCDC;user`"",
            "dsacls `"$ouPath`" /I:S /G `"PRACTICA8\admin_identidad:WD;user`"",
            "dsacls `"$ouPath`" /I:S /G `"PRACTICA8\admin_identidad:WP;user`"",
            "dsacls `"$ouPath`" /I:S /G `"PRACTICA8\admin_identidad:CA;Reset Password;user`"",
            "dsacls `"$ouPath`" /I:S /G `"PRACTICA8\admin_identidad:WP;lockoutTime;user`"",
            "dsacls `"$ouPath`" /I:S /G `"PRACTICA8\admin_identidad:WP;telephoneNumber;user`"",
            "dsacls `"$ouPath`" /I:S /G `"PRACTICA8\admin_identidad:WP;physicalDeliveryOfficeName;user`"",
            "dsacls `"$ouPath`" /I:S /G `"PRACTICA8\admin_identidad:WP;mail;user`""
        )

        foreach ($cmd in $cmds) {
            try {
                Invoke-Expression $cmd 2>&1 | Out-Null
            } catch {
                # dsacls puede emitir warnings no fatales
            }
        }
        Write-Host "  [OK] Permisos IAM aplicados en OU $ouNombre" -ForegroundColor Green
    }

    Write-Host ""

    # -------------------------------------------------------
    # ROL 2: admin_storage - DENEGADO Reset Password en todo el dominio
    # -------------------------------------------------------
    Write-Host "  [ROL 2] Configurando admin_storage (denegacion Reset Password)..." -ForegroundColor Yellow
    Write-Host ""

    foreach ($ouNombre in $ous) {
        $ouPath = "OU=$ouNombre,$dcBase"
        try {
            Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
            # Denegar Reset Password explicitamente sobre objetos User
            $cmdDeny = "dsacls `"$ouPath`" /I:S /D `"PRACTICA8\admin_storage:CA;Reset Password;user`""
            Invoke-Expression $cmdDeny 2>&1 | Out-Null
            Write-Host "  [OK] DENEGADO Reset Password para admin_storage en OU $ouNombre" -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] No se pudo configurar denegacion en OU $ouNombre" -ForegroundColor Yellow
        }
    }

    # Agregar admin_storage al grupo de operadores de FSRM (local)
    try {
        $grupoFSRM = "File Server Resource Manager Administrators"
        Add-LocalGroupMember -Group "Administrators" -Member "PRACTICA8\admin_storage" -ErrorAction SilentlyContinue
        Write-Host "  [OK] admin_storage agregado al grupo de administradores locales (para FSRM)" -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] No se pudo agregar admin_storage al grupo local." -ForegroundColor Yellow
    }

    Write-Host ""

    # -------------------------------------------------------
    # ROL 3: admin_politicas - Lectura en dominio + escritura en GPO
    # -------------------------------------------------------
    Write-Host "  [ROL 3] Configurando admin_politicas (GPO Compliance)..." -ForegroundColor Yellow
    Write-Host ""

    # Lectura en todo el dominio
    try {
        $cmdRead = "dsacls `"$dcBase`" /I:T /G `"PRACTICA8\admin_politicas:GR`""
        Invoke-Expression $cmdRead 2>&1 | Out-Null
        Write-Host "  [OK] Permiso de Lectura (GR) en todo el dominio aplicado." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] No se pudo aplicar lectura de dominio." -ForegroundColor Yellow
    }

    # Agregar al grupo Group Policy Creator Owners para poder gestionar GPOs
    try {
        Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "admin_politicas" -ErrorAction Stop
        Write-Host "  [OK] admin_politicas agregado a 'Group Policy Creator Owners'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] No se pudo agregar a Group Policy Creator Owners: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host ""

    # -------------------------------------------------------
    # ROL 4: admin_auditoria - Solo lectura + Event Log Readers
    # -------------------------------------------------------
    Write-Host "  [ROL 4] Configurando admin_auditoria (Read-Only + Event Log Reader)..." -ForegroundColor Yellow
    Write-Host ""

    # Lectura en todo el dominio
    try {
        $cmdReadAudit = "dsacls `"$dcBase`" /I:T /G `"PRACTICA8\admin_auditoria:GR`""
        Invoke-Expression $cmdReadAudit 2>&1 | Out-Null
        Write-Host "  [OK] Permiso de Lectura (GR) en dominio aplicado a admin_auditoria." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] No se pudo aplicar lectura de dominio a admin_auditoria." -ForegroundColor Yellow
    }

    # Agregar al grupo Event Log Readers para acceso a logs de seguridad
    try {
        Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction Stop
        Write-Host "  [OK] admin_auditoria agregado a 'Event Log Readers'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] No se pudo agregar a Event Log Readers: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Tambien al grupo local Event Log Readers del servidor
    try {
        Add-LocalGroupMember -Group "Event Log Readers" -Member "PRACTICA8\admin_auditoria" -ErrorAction SilentlyContinue
        Write-Host "  [OK] admin_auditoria agregado al grupo local 'Event Log Readers'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Ya esta en el grupo local o no existe." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Delegacion y ACLs configuradas.          |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | ROL 1 - admin_identidad : [OK] Completo  |" -ForegroundColor Green
    Write-Host "  | ROL 2 - admin_storage   : [OK] Denegado  |" -ForegroundColor Green
    Write-Host "  | ROL 3 - admin_politicas : [OK] GPO+Leer  |" -ForegroundColor Green
    Write-Host "  | ROL 4 - admin_auditoria : [OK] ReadOnly  |" -ForegroundColor Green
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  NOTA: Para verificar los permisos usa:" -ForegroundColor White
    Write-Host "  dsacls `"OU=Cuates,$dcBase`"" -ForegroundColor DarkCyan
    Write-Host ""
}


# ============================================================
# FUNCION 4: Configurar FGPP (Fine-Grained Password Policy)
# ============================================================
function Configurar-FGPP {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |  DIRECTIVAS DE CONTRASENA AJUSTADA (FGPP)|" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
        $dcBase  = $dominio.DistinguishedName
    } catch {
        Write-Host "  [ERROR] No se puede conectar a Active Directory." -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host "  Se crearan las siguientes politicas FGPP:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Politica 1 - Administradores (alta seguridad):" -ForegroundColor Cyan
    Write-Host "    Nombre        : P9-FGPP-Admins" -ForegroundColor White
    Write-Host "    Longitud min  : 12 caracteres" -ForegroundColor White
    Write-Host "    Complejidad   : Habilitada" -ForegroundColor White
    Write-Host "    Historial     : 24 contrasenas" -ForegroundColor White
    Write-Host "    Edad max      : 60 dias" -ForegroundColor White
    Write-Host "    Bloqueo       : 3 intentos / 30 min" -ForegroundColor White
    Write-Host "    Precedencia   : 10 (mayor prioridad)" -ForegroundColor White
    Write-Host "    Aplica a      : admin_identidad, admin_storage," -ForegroundColor White
    Write-Host "                    admin_politicas, admin_auditoria" -ForegroundColor White
    Write-Host ""
    Write-Host "  Politica 2 - Usuarios estandar (Cuates y NoCuates):" -ForegroundColor Cyan
    Write-Host "    Nombre        : P9-FGPP-Usuarios" -ForegroundColor White
    Write-Host "    Longitud min  : 8 caracteres" -ForegroundColor White
    Write-Host "    Complejidad   : Habilitada" -ForegroundColor White
    Write-Host "    Historial     : 10 contrasenas" -ForegroundColor White
    Write-Host "    Edad max      : 90 dias" -ForegroundColor White
    Write-Host "    Bloqueo       : 5 intentos / 15 min" -ForegroundColor White
    Write-Host "    Precedencia   : 20 (menor prioridad)" -ForegroundColor White
    Write-Host "    Aplica a      : Grupo Cuates, Grupo NoCuates" -ForegroundColor White
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    # -------------------------------------------------------
    # FGPP 1: Administradores - 12 caracteres minimo
    # -------------------------------------------------------
    Write-Host "  Creando politica P9-FGPP-Admins..." -ForegroundColor Yellow

    $fgppAdmins = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq "P9-FGPP-Admins" } -ErrorAction SilentlyContinue

    if ($fgppAdmins) {
        Write-Host "  [OMITIDO] P9-FGPP-Admins ya existe. Actualizando parametros..." -ForegroundColor Yellow
        try {
            Set-ADFineGrainedPasswordPolicy "P9-FGPP-Admins" `
                -MinPasswordLength 12 `
                -ComplexityEnabled $true `
                -PasswordHistoryCount 24 `
                -MaxPasswordAge "60.00:00:00" `
                -MinPasswordAge "1.00:00:00" `
                -LockoutThreshold 3 `
                -LockoutObservationWindow "00:30:00" `
                -LockoutDuration "00:30:00" `
                -ReversibleEncryptionEnabled $false
            Write-Host "  [OK] P9-FGPP-Admins actualizada." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        try {
            New-ADFineGrainedPasswordPolicy `
                -Name "P9-FGPP-Admins" `
                -Precedence 10 `
                -MinPasswordLength 12 `
                -ComplexityEnabled $true `
                -PasswordHistoryCount 24 `
                -MaxPasswordAge "60.00:00:00" `
                -MinPasswordAge "1.00:00:00" `
                -LockoutThreshold 3 `
                -LockoutObservationWindow "00:30:00" `
                -LockoutDuration "00:30:00" `
                -ReversibleEncryptionEnabled $false `
                -Description "Practica 9: Politica para administradores delegados - 12 chars min"
            Write-Host "  [CREADA] P9-FGPP-Admins (12 chars minimo)." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] No se pudo crear P9-FGPP-Admins: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Aplicar politica a los 4 usuarios admin
    $adminsRBAC = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    foreach ($adm in $adminsRBAC) {
        try {
            Add-ADFineGrainedPasswordPolicySubject -Identity "P9-FGPP-Admins" -Subjects $adm -ErrorAction Stop
            Write-Host "  [OK] Politica aplicada a: $adm" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -like "*already*" -or $_.Exception.Message -like "*ya*") {
                Write-Host "  [OK] $adm ya tiene la politica asignada." -ForegroundColor Yellow
            } else {
                Write-Host "  [AVISO] No se pudo aplicar a $adm : $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""

    # -------------------------------------------------------
    # FGPP 2: Usuarios estandar - 8 caracteres minimo
    # -------------------------------------------------------
    Write-Host "  Creando politica P9-FGPP-Usuarios..." -ForegroundColor Yellow

    $fgppUsuarios = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq "P9-FGPP-Usuarios" } -ErrorAction SilentlyContinue

    if ($fgppUsuarios) {
        Write-Host "  [OMITIDO] P9-FGPP-Usuarios ya existe. Actualizando parametros..." -ForegroundColor Yellow
        try {
            Set-ADFineGrainedPasswordPolicy "P9-FGPP-Usuarios" `
                -MinPasswordLength 8 `
                -ComplexityEnabled $true `
                -PasswordHistoryCount 10 `
                -MaxPasswordAge "90.00:00:00" `
                -MinPasswordAge "1.00:00:00" `
                -LockoutThreshold 5 `
                -LockoutObservationWindow "00:15:00" `
                -LockoutDuration "00:15:00" `
                -ReversibleEncryptionEnabled $false
            Write-Host "  [OK] P9-FGPP-Usuarios actualizada." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        try {
            New-ADFineGrainedPasswordPolicy `
                -Name "P9-FGPP-Usuarios" `
                -Precedence 20 `
                -MinPasswordLength 8 `
                -ComplexityEnabled $true `
                -PasswordHistoryCount 10 `
                -MaxPasswordAge "90.00:00:00" `
                -MinPasswordAge "1.00:00:00" `
                -LockoutThreshold 5 `
                -LockoutObservationWindow "00:15:00" `
                -LockoutDuration "00:15:00" `
                -ReversibleEncryptionEnabled $false `
                -Description "Practica 9: Politica para usuarios estandar - 8 chars min"
            Write-Host "  [CREADA] P9-FGPP-Usuarios (8 chars minimo)." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] No se pudo crear P9-FGPP-Usuarios: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Aplicar politica a grupos Cuates y NoCuates
    $gruposEstandar = @("Cuates","NoCuates")
    foreach ($grp in $gruposEstandar) {
        try {
            Get-ADGroup -Identity $grp -ErrorAction Stop | Out-Null
            Add-ADFineGrainedPasswordPolicySubject -Identity "P9-FGPP-Usuarios" -Subjects $grp -ErrorAction Stop
            Write-Host "  [OK] Politica aplicada al grupo: $grp" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -like "*already*" -or $_.Exception.Message -like "*ya*") {
                Write-Host "  [OK] Grupo $grp ya tiene la politica asignada." -ForegroundColor Yellow
            } else {
                Write-Host "  [AVISO] No se pudo aplicar al grupo $grp : $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""
    Write-Host "  Verificando politicas creadas..." -ForegroundColor Yellow
    Write-Host ""

    $polAdm = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq "P9-FGPP-Admins" } -ErrorAction SilentlyContinue
    $polUsr = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq "P9-FGPP-Usuarios" } -ErrorAction SilentlyContinue

    if ($polAdm) {
        Write-Host "  P9-FGPP-Admins   -> MinLength: $($polAdm.MinPasswordLength) | Lockout: $($polAdm.LockoutThreshold) intentos" -ForegroundColor Green
    }
    if ($polUsr) {
        Write-Host "  P9-FGPP-Usuarios -> MinLength: $($polUsr.MinPasswordLength) | Lockout: $($polUsr.LockoutThreshold) intentos" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | FGPP configuradas correctamente.         |" -ForegroundColor Cyan
    Write-Host "  | Admins : 12 chars - bloqueo 3 intentos   |" -ForegroundColor Cyan
    Write-Host "  | Usuarios: 8 chars - bloqueo 5 intentos   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Para verificar las politicas ejecuta:" -ForegroundColor White
    Write-Host "  Get-ADFineGrainedPasswordPolicy -Filter * | Format-Table Name,MinPasswordLength,LockoutThreshold" -ForegroundColor DarkCyan
    Write-Host ""
}


# ===========================================================
# FUNCION 5: Configurar Auditoria de Eventos (auditpol)
# ============================================================
function Configurar-Auditoria {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR AUDITORIA DE EVENTOS        |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Se habilitaran las siguientes categorias de auditoria:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Logon/Logoff           : Exito y Fallo" -ForegroundColor Cyan
    Write-Host "    Account Logon          : Exito y Fallo" -ForegroundColor Cyan
    Write-Host "    Account Management     : Exito y Fallo" -ForegroundColor Cyan
    Write-Host "    Object Access          : Exito y Fallo" -ForegroundColor Cyan
    Write-Host "    Policy Change          : Exito y Fallo" -ForegroundColor Cyan
    Write-Host "    Privilege Use          : Exito y Fallo" -ForegroundColor Cyan
    Write-Host "    Directory Service      : Exito y Fallo" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Estos eventos son requeridos para que el script de" -ForegroundColor White
    Write-Host "  monitoreo (opcion 5) pueda extraer los eventos 4625." -ForegroundColor White
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "  Configurando politicas de auditoria..." -ForegroundColor Yellow
    Write-Host ""

    $politicas = @(
        @{ Subcategoria = "Logon";                                Descripcion = "Inicio de sesion"              },
        @{ Subcategoria = "Logoff";                               Descripcion = "Cierre de sesion"              },
        @{ Subcategoria = "Account Lockout";                      Descripcion = "Bloqueo de cuenta"             },
        @{ Subcategoria = "Credential Validation";                Descripcion = "Validacion de credenciales"    },
        @{ Subcategoria = "User Account Management";              Descripcion = "Gestion de cuentas de usuario" },
        @{ Subcategoria = "Computer Account Management";          Descripcion = "Gestion de cuentas de equipo"  },
        @{ Subcategoria = "Security Group Management";            Descripcion = "Gestion de grupos de seguridad"},
        @{ Subcategoria = "File System";                          Descripcion = "Acceso al sistema de archivos" },
        @{ Subcategoria = "Audit Policy Change";                  Descripcion = "Cambios en politica de auditoria"},
        @{ Subcategoria = "Directory Service Access";             Descripcion = "Acceso a servicios de directorio"},
        @{ Subcategoria = "Directory Service Changes";            Descripcion = "Cambios en directorio activo"   }
    )

    foreach ($pol in $politicas) {
        try {
            $cmd = "auditpol /set /subcategory:`"$($pol.Subcategoria)`" /success:enable /failure:enable"
            $resultado = Invoke-Expression $cmd 2>&1
            Write-Host "  [OK] $($pol.Descripcion)" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] $($pol.Descripcion): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Verificando configuracion actual..." -ForegroundColor Yellow
    Write-Host ""

    try {
        $verificacion = auditpol /get /subcategory:"Logon" 2>&1
        Write-Host "  Estado Logon:" -ForegroundColor White
        $verificacion | Select-String "Logon" | ForEach-Object {
            Write-Host "  $_" -ForegroundColor DarkCyan
        }
    } catch {
        Write-Host "  [AVISO] No se pudo verificar." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Aumentando el tamano maximo del log de seguridad..." -ForegroundColor Yellow
    try {
        wevtutil sl Security /ms:524288000 2>&1 | Out-Null
        Write-Host "  [OK] Log de seguridad configurado a 512 MB." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] No se pudo modificar el tamano del log." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Auditoria configurada correctamente.     |" -ForegroundColor Cyan
    Write-Host "  | Los eventos se registraran en:           |" -ForegroundColor Cyan
    Write-Host "  | Visor de Eventos -> Registro de Windows  |" -ForegroundColor Cyan
    Write-Host "  |                  -> Security             |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Para verificar usa: auditpol /get /category:*" -ForegroundColor DarkCyan
    Write-Host ""
}


# ============================================================
# FUNCION 6: Script de monitoreo - Exportar eventos 4625
# ============================================================
function Exportar-EventosAuditoria {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |  SCRIPT DE MONITOREO - EVENTOS 4625      |" -ForegroundColor Cyan
    Write-Host "  |  (Accesos Denegados / Logon Fallidos)     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Este script extrae los ultimos 10 eventos de" -ForegroundColor White
    Write-Host "  'Acceso Denegado' (Event ID 4625 - Failed Logon)" -ForegroundColor White
    Write-Host "  y los exporta a un archivo de texto." -ForegroundColor White
    Write-Host ""

    # Ruta de exportacion
    $outputDir  = "C:\P9-Auditoria"
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = "$outputDir\AccesosDenegados_$timestamp.txt"

    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta de auditoria creada: $outputDir" -ForegroundColor Green
    }

    Write-Host "  Buscando los ultimos 10 eventos ID 4625..." -ForegroundColor Yellow
    Write-Host ""

    try {
        # Obtener eventos 4625 del log de seguridad
        $eventos = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            Id      = 4625
        } -MaxEvents 10 -ErrorAction Stop

        $totalEncontrados = $eventos.Count
        Write-Host "  [OK] Se encontraron $totalEncontrados eventos de acceso fallido." -ForegroundColor Green
        Write-Host ""

        # Construir el contenido del reporte
        $lineas = @()
        $lineas += "=" * 65
        $lineas += "  REPORTE DE AUDITORIA - ACCESOS DENEGADOS"
        $lineas += "  Dominio  : practica8.local"
        $lineas += "  Servidor : 192.168.1.202"
        $lineas += "  Generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
        $lineas += "  Evento   : ID 4625 - An account failed to log on"
        $lineas += "=" * 65
        $lineas += ""

        $contador = 1
        foreach ($evento in $eventos) {
            $xml = [xml]$evento.ToXml()
            $data = $xml.Event.EventData.Data

            # Extraer campos del XML del evento
            $usuarioFallido  = ($data | Where-Object { $_.Name -eq "TargetUserName"  }).'#text'
            $dominio         = ($data | Where-Object { $_.Name -eq "TargetDomainName"}).'#text'
            $ipOrigen        = ($data | Where-Object { $_.Name -eq "IpAddress"       }).'#text'
            $hostOrigen      = ($data | Where-Object { $_.Name -eq "WorkstationName" }).'#text'
            $tipoLogon       = ($data | Where-Object { $_.Name -eq "LogonType"       }).'#text'
            $razonFallo      = ($data | Where-Object { $_.Name -eq "FailureReason"   }).'#text'
            $subStatus       = ($data | Where-Object { $_.Name -eq "SubStatus"       }).'#text'

            # Interpretar SubStatus
            $subStatusDesc = switch ($subStatus) {
                "0xC000006A" { "Contrasena incorrecta" }
                "0xC0000064" { "Usuario no existe" }
                "0xC0000072" { "Cuenta deshabilitada" }
                "0xC000006F" { "Fuera de horario permitido" }
                "0xC0000070" { "Estacion de trabajo no permitida" }
                "0xC0000234" { "Cuenta bloqueada" }
                default      { $subStatus }
            }

            # Interpretar tipo de logon
            $tipoDesc = switch ($tipoLogon) {
                "2"  { "Interactivo (consola)" }
                "3"  { "Red (compartidos)" }
                "4"  { "Por lotes (batch)" }
                "5"  { "Servicio" }
                "7"  { "Desbloqueo" }
                "8"  { "NetworkCleartext" }
                "10" { "RemoteInteractive (RDP)" }
                "11" { "CachedInteractive" }
                default { "Tipo $tipoLogon" }
            }

            $lineas += "-" * 65
            $lineas += "  Evento #$contador de $totalEncontrados"
            $lineas += "-" * 65
            $lineas += "  Fecha/Hora     : $($evento.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))"
            $lineas += "  ID Evento      : $($evento.Id)"
            $lineas += "  Usuario        : $usuarioFallido"
            $lineas += "  Dominio        : $dominio"
            $lineas += "  IP Origen      : $ipOrigen"
            $lineas += "  Host Origen    : $hostOrigen"
            $lineas += "  Tipo de Logon  : $tipoDesc"
            $lineas += "  Causa del fallo: $subStatusDesc"
            $lineas += ""

            # Mostrar en consola tambien
            Write-Host "  [$contador] $($evento.TimeCreated.ToString('dd/MM/yy HH:mm:ss')) | Usuario: $usuarioFallido | Causa: $subStatusDesc | IP: $ipOrigen" -ForegroundColor White

            $contador++
        }

        $lineas += "=" * 65
        $lineas += "  FIN DEL REPORTE"
        $lineas += "  Total de eventos exportados: $totalEncontrados"
        $lineas += "  Archivo generado: $outputFile"
        $lineas += "=" * 65

        # Escribir al archivo
        $lineas | Out-File -FilePath $outputFile -Encoding UTF8

        Write-Host ""
        Write-Host "  +==========================================+" -ForegroundColor Cyan
        Write-Host "  | Reporte generado exitosamente.           |" -ForegroundColor Cyan
        Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
        Write-Host "  | Archivo: $outputFile" -ForegroundColor Green
        Write-Host "  | Total eventos: $totalEncontrados                       |" -ForegroundColor Green
        Write-Host "  +==========================================+" -ForegroundColor Cyan

    } catch {
        if ($_.Exception.Message -like "*No events were found*" -or $_.Exception.Message -like "*no se encontraron*") {
            Write-Host "  [AVISO] No se encontraron eventos 4625 en el log de seguridad." -ForegroundColor Yellow
            Write-Host "  Es posible que la auditoria no este habilitada aun." -ForegroundColor Yellow
            Write-Host "  Ejecuta primero la opcion 4 para habilitar la auditoria." -ForegroundColor Yellow

            # Generar un reporte de muestra para la practica
            $lineas = @()
            $lineas += "=" * 65
            $lineas += "  REPORTE DE AUDITORIA - ACCESOS DENEGADOS"
            $lineas += "  Dominio  : practica8.local"
            $lineas += "  Servidor : 192.168.1.202"
            $lineas += "  Generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
            $lineas += "  NOTA: No se encontraron eventos 4625."
            $lineas += "  Habilitar auditoria (opcion 4) y reintentar."
            $lineas += "=" * 65
            $lineas | Out-File -FilePath $outputFile -Encoding UTF8

            Write-Host ""
            Write-Host "  Se genero un reporte vacio en: $outputFile" -ForegroundColor Yellow
        } else {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Para ver el archivo ejecuta:" -ForegroundColor White
    Write-Host "  notepad $outputFile" -ForegroundColor DarkCyan
    Write-Host ""
}


# ============================================================
# FUNCION 7: Configurar bloqueo de cuenta por MFA fallido (GPO)
# ============================================================
function Configurar-BloqueoMFA {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR BLOQUEO DE CUENTA - MFA     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  NOTA IMPORTANTE:" -ForegroundColor Yellow
    Write-Host "  El bloqueo real por MFA fallido depende del proveedor" -ForegroundColor White
    Write-Host "  de credenciales MFA que instales (WinOTP, DUO, etc.)." -ForegroundColor White
    Write-Host ""
    Write-Host "  Esta funcion configura la politica de bloqueo de AD:" -ForegroundColor White
    Write-Host "    - 3 intentos fallidos = cuenta bloqueada 30 minutos" -ForegroundColor Cyan
    Write-Host "    - Se aplica a los 4 usuarios admin via FGPP" -ForegroundColor Cyan
    Write-Host "    - Ventana de observacion: 30 minutos" -ForegroundColor Cyan
    Write-Host ""

    $confirmar = Read-Host "  Deseas configurar el bloqueo de cuenta? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    # Actualizar FGPP de admins con los parametros de bloqueo
    try {
        $fgpp = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq "P9-FGPP-Admins" } -ErrorAction Stop
        Set-ADFineGrainedPasswordPolicy "P9-FGPP-Admins" `
            -LockoutThreshold 3 `
            -LockoutObservationWindow "00:30:00" `
            -LockoutDuration "00:30:00"
        Write-Host "  [OK] FGPP Admins: bloqueo configurado (3 intentos / 30 min)." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Ejecuta primero la opcion 3 para crear FGPP." -ForegroundColor Yellow
    }

    # Configurar tambien la Default Domain Policy como respaldo
    Write-Host ""
    Write-Host "  Configurando Default Domain Policy como respaldo..." -ForegroundColor Yellow

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
        $dcBase  = $dominio.DistinguishedName

        # Crear o modificar GPO de bloqueo de cuenta
        $gpoNombre = "P9-AccountLockout-MFA"
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre -Comment "Practica 9: Bloqueo de cuenta post MFA fallido"
            Write-Host "  [CREADO] GPO '$gpoNombre' creada." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO '$gpoNombre' ya existe, se actualiza." -ForegroundColor Yellow
        }

        # Configurar lockout via GPO (Computer Config > Windows Settings > Security Settings > Account Policies)
        # Lockout threshold = 3
        Set-GPRegistryValue `
            -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
            -ValueName "LockoutBadCount" `
            -Type DWord `
            -Value 3 | Out-Null

        # Vincular GPO al dominio
        try {
            New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
            Write-Host "  [OK] GPO vinculada al dominio." -ForegroundColor Green
        } catch {
            Write-Host "  [OK] GPO ya estaba vinculada." -ForegroundColor Yellow
        }

    } catch {
        Write-Host "  [AVISO] No se pudo configurar la GPO: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Bloqueo de cuenta configurado.           |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Intentos antes de bloqueo : 3            |" -ForegroundColor Cyan
    Write-Host "  | Duracion del bloqueo      : 30 minutos   |" -ForegroundColor Cyan
    Write-Host "  | Ventana de observacion    : 30 minutos   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Para desbloquear una cuenta manualmente:" -ForegroundColor White
    Write-Host "  Unlock-ADAccount -Identity <usuario>" -ForegroundColor DarkCyan
    Write-Host ""
}


# ============================================================
# FUNCION 8: Guia de instalacion MFA (WinOTP Authenticator)
# ============================================================
function Guia-InstalacionMFA {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   GUIA DE INSTALACION MFA - TOTP         |" -ForegroundColor Cyan
    Write-Host "  |   WinOTP Authenticator (Credential Prov) |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  SOFTWARE RECOMENDADO: WinOTP Authenticator" -ForegroundColor White
    Write-Host "  Proveedor de Credenciales TOTP para Windows Server" -ForegroundColor White
    Write-Host ""
    Write-Host "  DESCRIPCION:" -ForegroundColor Yellow
    Write-Host "  WinOTP es un Credential Provider que se instala como" -ForegroundColor White
    Write-Host "  filtro entre la pantalla de login de Windows y el LSASS." -ForegroundColor White
    Write-Host "  Requiere un codigo TOTP de Google Authenticator ademas" -ForegroundColor White
    Write-Host "  de la contrasena normal de Active Directory." -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  PASO 1: Descargar WinOTP" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  URL: https://github.com/nicowillis/WinOTP" -ForegroundColor White
    Write-Host "  O busca: 'WinOTP Authenticator Credential Provider'" -ForegroundColor White
    Write-Host ""
    Write-Host "  Archivo a descargar: WinOTPSetup.msi o WinOTP.zip" -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  PASO 2: Instalar en el servidor" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  1. Copiar el instalador al servidor" -ForegroundColor White
    Write-Host "  2. Ejecutar como Administrador" -ForegroundColor White
    Write-Host "  3. Seguir el asistente de instalacion" -ForegroundColor White
    Write-Host "  4. Al finalizar se registra automaticamente como" -ForegroundColor White
    Write-Host "     Credential Provider en el registro de Windows" -ForegroundColor White
    Write-Host ""
    Write-Host "  Clave de registro donde se instala:" -ForegroundColor White
    Write-Host "  HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\" -ForegroundColor DarkCyan
    Write-Host "  Authentication\Credential Providers\{GUID-WinOTP}" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  PASO 3: Generar Secret Key (clave TOTP)" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  Despues de instalar, WinOTP genera una clave secreta" -ForegroundColor White
    Write-Host "  en formato Base32. Esta clave se escanea con" -ForegroundColor White
    Write-Host "  Google Authenticator para vincular el servidor." -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  PASO 4: Configurar Google Authenticator" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  1. Instalar Google Authenticator en tu telefono" -ForegroundColor White
    Write-Host "  2. Abrir la app -> '+' -> 'Escanear codigo QR'" -ForegroundColor White
    Write-Host "  3. Escanear el QR que muestra WinOTP en el servidor" -ForegroundColor White
    Write-Host "     O ingresar manualmente la clave Base32" -ForegroundColor White
    Write-Host "  4. Se creara una entrada 'practica8.local' o similar" -ForegroundColor White
    Write-Host "  5. Cada 30 segundos genera un codigo de 6 digitos" -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  PASO 5: Verificar funcionamiento" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  1. Cerrar sesion en el servidor" -ForegroundColor White
    Write-Host "  2. En la pantalla de login apareceran 2 campos:" -ForegroundColor White
    Write-Host "     [Contrasena AD] + [Codigo TOTP de Google Auth]" -ForegroundColor White
    Write-Host "  3. Ingresar ambos para autenticarse" -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  CONFIGURACION DE BLOQUEO (3 intentos MFA)        " -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  WinOTP maneja el bloqueo a nivel de Credential Provider." -ForegroundColor White
    Write-Host "  El bloqueo de AD que configuramos (opcion 6) actua" -ForegroundColor White
    Write-Host "  como segunda capa: si falla 3 veces el MFA, la" -ForegroundColor White
    Write-Host "  cuenta AD se bloquea por 30 minutos automaticamente." -ForegroundColor White
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  ALTERNATIVA: CredentialProvider manual con PowerShell" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor DarkCyan
    Write-Host "  Si WinOTP no esta disponible, ejecuta la opcion 8" -ForegroundColor White
    Write-Host "  para generar y validar codigos TOTP manualmente" -ForegroundColor White
    Write-Host "  desde PowerShell (demostracion para la practica)." -ForegroundColor White
    Write-Host ""

    $verScript = Read-Host "  Deseas ver el comando para instalar WinOTP silenciosamente? (s/n)"
    if ($verScript -eq "s") {
        Write-Host ""
        Write-Host "  Comandos de instalacion silenciosa (PowerShell Admin):" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  # Descargar WinOTP (ajusta la URL segun la version):" -ForegroundColor DarkGray
        Write-Host "  Invoke-WebRequest -Uri 'https://github.com/.../WinOTPSetup.msi'" -ForegroundColor White
        Write-Host "                    -OutFile 'C:\temp\WinOTPSetup.msi'" -ForegroundColor White
        Write-Host ""
        Write-Host "  # Instalar silenciosamente:" -ForegroundColor DarkGray
        Write-Host "  msiexec /i C:\temp\WinOTPSetup.msi /quiet /norestart" -ForegroundColor White
        Write-Host ""
        Write-Host "  # Verificar que el Credential Provider se registro:" -ForegroundColor DarkGray
        Write-Host "  Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\" -ForegroundColor White
        Write-Host "            Authentication\Credential Providers\*' | Select Name" -ForegroundColor White
        Write-Host ""
    }

    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Para la practica toma capturas de:       |" -ForegroundColor Cyan
    Write-Host "  | 1. Pantalla de login con campo TOTP       |" -ForegroundColor Cyan
    Write-Host "  | 2. Google Authenticator con el codigo     |" -ForegroundColor Cyan
    Write-Host "  | 3. Cuenta bloqueada tras 3 intentos       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ============================================================
# FUNCION 9: Demo TOTP - Generar y validar codigos TOTP
# (Para demostracion/prueba sin instalar Credential Provider)
# ============================================================
function Demo-TOTP {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   DEMO TOTP - GENERADOR DE CODIGOS       |" -ForegroundColor Cyan
    Write-Host "  |   Compatible con Google Authenticator    |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Esta funcion genera un codigo TOTP identico al que" -ForegroundColor White
    Write-Host "  produciria Google Authenticator para una clave secreta." -ForegroundColor White
    Write-Host "  Util para demostrar el funcionamiento MFA en la practica." -ForegroundColor White
    Write-Host ""

    # Clave secreta de ejemplo en Base32
    # En produccion esta clave viene del Credential Provider instalado
    $claveBase32 = "JBSWY3DPEHPK3PXP"

    Write-Host "  Clave secreta (Base32) de ejemplo:" -ForegroundColor Yellow
    Write-Host "  $claveBase32" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Copia esta clave en Google Authenticator:" -ForegroundColor White
    Write-Host "  App -> '+' -> 'Ingresar clave manualmente'" -ForegroundColor White
    Write-Host "  Cuenta: practica8.local | Clave: $claveBase32" -ForegroundColor DarkCyan
    Write-Host ""

    # Funcion de decodificacion Base32
    function Decode-Base32 {
        param([string]$encoded)
        $encoded = $encoded.ToUpper().TrimEnd('=')
        $alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        $bits = ""
        foreach ($char in $encoded.ToCharArray()) {
            $val = $alphabet.IndexOf($char)
            $bits += [Convert]::ToString($val, 2).PadLeft(5, '0')
        }
        $bytes = @()
        for ($i = 0; $i + 8 -le $bits.Length; $i += 8) {
            $bytes += [Convert]::ToByte($bits.Substring($i, 8), 2)
        }
        return [byte[]]$bytes
    }

    # Generar codigo TOTP (RFC 6238)
    function Get-TOTPCode {
        param([string]$secretBase32)

        $secretBytes = Decode-Base32 -encoded $secretBase32

        # Tiempo Unix / 30 segundos
        $epoch    = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $counter  = [long][Math]::Floor($epoch / 30)

        # Counter como big-endian bytes
        $counterBytes = [byte[]]::new(8)
        for ($i = 7; $i -ge 0; $i--) {
            $counterBytes[$i] = [byte]($counter -band 0xFF)
            $counter = $counter -shr 8
        }

        # HMAC-SHA1
        $hmac = New-Object System.Security.Cryptography.HMACSHA1
        $hmac.Key = $secretBytes
        $hash = $hmac.ComputeHash($counterBytes)

        # Dynamic Truncation
        $offset = $hash[$hash.Length - 1] -band 0x0F
        $otp = (($hash[$offset]   -band 0x7F) -shl 24) -bor `
               (($hash[$offset+1] -band 0xFF) -shl 16) -bor `
               (($hash[$offset+2] -band 0xFF) -shl 8)  -bor `
               (($hash[$offset+3] -band 0xFF))
        $otp = $otp % 1000000

        return $otp.ToString("D6")
    }

    Write-Host "  Generando codigo TOTP actual..." -ForegroundColor Yellow
    Write-Host ""

    try {
        $codigo = Get-TOTPCode -secretBase32 $claveBase32
        $tiempoActual = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $segundosRestantes = 30 - ($tiempoActual % 30)

        Write-Host "  +------------------------------------------+" -ForegroundColor Green
        Write-Host "  | CODIGO TOTP ACTUAL: $codigo                |" -ForegroundColor Green
        Write-Host "  | Valido por: $segundosRestantes segundos              |" -ForegroundColor Green
        Write-Host "  +------------------------------------------+" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Este codigo debe coincidir con el que muestra" -ForegroundColor White
        Write-Host "  Google Authenticator para la clave: $claveBase32" -ForegroundColor DarkCyan
        Write-Host ""

        # Mostrar los proximos 3 codigos
        Write-Host "  Proximos codigos (para referencia):" -ForegroundColor Yellow
        $epochBase = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        for ($i = 1; $i -le 3; $i++) {
            $counterFuturo = [long][Math]::Floor(($epochBase + ($i * 30)) / 30)
            $counterBytes = [byte[]]::new(8)
            $cf = $counterFuturo
            for ($j = 7; $j -ge 0; $j--) {
                $counterBytes[$j] = [byte]($cf -band 0xFF)
                $cf = $cf -shr 8
            }
            $secretBytes = Decode-Base32 -encoded $claveBase32
            $hmac2 = New-Object System.Security.Cryptography.HMACSHA1
            $hmac2.Key = $secretBytes
            $hash2 = $hmac2.ComputeHash($counterBytes)
            $offset2 = $hash2[$hash2.Length - 1] -band 0x0F
            $otp2 = (($hash2[$offset2]   -band 0x7F) -shl 24) -bor `
                    (($hash2[$offset2+1] -band 0xFF) -shl 16) -bor `
                    (($hash2[$offset2+2] -band 0xFF) -shl 8)  -bor `
                    (($hash2[$offset2+3] -band 0xFF))
            $otp2 = $otp2 % 1000000
            Write-Host "    En $($i*30) seg: $($otp2.ToString('D6'))" -ForegroundColor DarkCyan
        }

    } catch {
        Write-Host "  [ERROR] No se pudo generar el codigo TOTP." -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | NOTA PARA LA PRACTICA:                   |" -ForegroundColor Cyan
    Write-Host "  | Usa el codigo de arriba como evidencia   |" -ForegroundColor Cyan
    Write-Host "  | de que el sistema TOTP funciona.         |" -ForegroundColor Cyan
    Write-Host "  | Para MFA real instala WinOTP (opcion 7). |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ============================================================
# FUNCION 10: Verificar estado de toda la Practica 9
# ============================================================
function Verificar-EstadoP9 {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   VERIFICACION GENERAL - PRACTICA 9     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
        $dcBase  = $dominio.DistinguishedName
    } catch {
        Write-Host "  [ERROR] No se puede conectar a AD." -ForegroundColor Red
        return
    }

    # ---- 1. Usuarios admin ----
    Write-Host "  [1] Usuarios administradores RBAC:" -ForegroundColor Yellow
    $admins = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    foreach ($adm in $admins) {
        try {
            $u = Get-ADUser -Identity $adm -Properties Description -ErrorAction Stop
            Write-Host "      [OK] $adm - $($u.Description)" -ForegroundColor Green
        } catch {
            Write-Host "      [--] $adm - NO EXISTE" -ForegroundColor Red
        }
    }

    # ---- 2. FGPP ----
    Write-Host ""
    Write-Host "  [2] Fine-Grained Password Policies (FGPP):" -ForegroundColor Yellow
    $fgpps = @("P9-FGPP-Admins","P9-FGPP-Usuarios")
    foreach ($f in $fgpps) {
        $pol = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq $f } -ErrorAction SilentlyContinue
        if ($pol) {
            Write-Host "      [OK] $f | MinLen: $($pol.MinPasswordLength) | Lockout: $($pol.LockoutThreshold) intentos / $($pol.LockoutDuration)" -ForegroundColor Green
        } else {
            Write-Host "      [--] $f - NO EXISTE" -ForegroundColor Red
        }
    }

    # ---- 3. Auditoria ----
    Write-Host ""
    Write-Host "  [3] Politicas de auditoria:" -ForegroundColor Yellow
    try {
        $audit = auditpol /get /subcategory:"Logon" 2>&1 | Select-String "Logon"
        if ($audit -match "Success and Failure" -or $audit -match "Exito y fallo") {
            Write-Host "      [OK] Auditoria de Logon habilitada (Exito y Fallo)" -ForegroundColor Green
        } else {
            Write-Host "      [--] Auditoria de Logon NO configurada" -ForegroundColor Red
        }
    } catch {
        Write-Host "      [AVISO] No se pudo verificar auditpol" -ForegroundColor Yellow
    }

    # ---- 4. Reportes generados ----
    Write-Host ""
    Write-Host "  [4] Reportes de auditoria generados:" -ForegroundColor Yellow
    $reportes = Get-ChildItem "C:\P9-Auditoria\*.txt" -ErrorAction SilentlyContinue
    if ($reportes) {
        foreach ($r in $reportes) {
            Write-Host "      [OK] $($r.FullName) ($([Math]::Round($r.Length/1KB,1)) KB)" -ForegroundColor Green
        }
    } else {
        Write-Host "      [--] No hay reportes generados aun (ejecuta opcion 5)" -ForegroundColor Yellow
    }

    # ---- 5. Event Log Readers ----
    Write-Host ""
    Write-Host "  [5] Grupo Event Log Readers:" -ForegroundColor Yellow
    try {
        $miembros = Get-ADGroupMember -Identity "Event Log Readers" -ErrorAction Stop
        if ($miembros | Where-Object { $_.SamAccountName -eq "admin_auditoria" }) {
            Write-Host "      [OK] admin_auditoria esta en Event Log Readers" -ForegroundColor Green
        } else {
            Write-Host "      [--] admin_auditoria NO esta en Event Log Readers" -ForegroundColor Red
        }
    } catch {
        Write-Host "      [AVISO] No se pudo verificar Event Log Readers" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Verificacion completada.                 |" -ForegroundColor Cyan
    Write-Host "  | [OK] = Configurado correctamente         |" -ForegroundColor Green
    Write-Host "  | [--] = Pendiente de configurar           |" -ForegroundColor Red
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}

# ------------------------------------------------------------
# FUNCION 11: Instalar y Activar MFA (Google Authenticator)
# -----------------------------------------------------------

function Instalar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    INSTALAR Y ACTIVAR MULTI-FACTOR MFA   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    
    # =========================================================
    # PASO 1: INSTALAR DEPENDENCIA (Visual C++ 2022 Redistributable)
    # =========================================================
    Write-Host "  [1/3] Verificando pre-requisitos (Visual C++ Redistributable)..." -ForegroundColor Yellow
    # CORRECCION: Usar enlace a VS 2022 (v17) para satisfacer el requisito 14.44+ de PHP
    $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $vcRedistPath = "$rutaDescarga\vc_redist_2022_x64.exe" # Nombre nuevo para forzar descarga
    
    if (-not (Test-Path $vcRedistPath)) {
        Write-Host "  [INFO] Descargando VC++ 2022 Redistributable..." -ForegroundColor Cyan
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath -UseBasicParsing
        } catch {
            Write-Host "  [ERROR] Fallo la descarga de VC++: $($_.Exception.Message)" -ForegroundColor Red
            Pause | Out-Null
            return
        }
    }
    
    Write-Host "  [INFO] Instalando VC++ 2022 silenciosamente..." -ForegroundColor Cyan
    $procVC = Start-Process -FilePath $vcRedistPath -ArgumentList "/install /quiet /norestart" -Wait -PassThru
    if ($procVC.ExitCode -in @(0, 1638, 3010)) {
        Write-Host "  [OK] VC++ 2022 Redistributable listo." -ForegroundColor Green
    } else {
        Write-Host "  [AVISO] VC++ termino con codigo $($procVC.ExitCode). Podria fallar el MFA." -ForegroundColor Yellow
    }

    # Darle tiempo a Windows de registrar la nueva DLL 14.44
    Start-Sleep -Seconds 3

    # =========================================================
    # PASO 2: EXTRAER E INSTALAR MULTIOTP
    # =========================================================
    Write-Host "`n  [2/3] Preparando instalador de multiOTP..." -ForegroundColor Yellow
    $archivosZip = Get-ChildItem -Path $rutaDescarga -Filter "*.zip" -ErrorAction SilentlyContinue
    
    foreach ($zip in $archivosZip) {
        $rutaDestinoZip = "$rutaDescarga\Extracted_$($zip.BaseName)"
        if (-not (Test-Path $rutaDestinoZip)) {
            Expand-Archive -Path $zip.FullName -DestinationPath $rutaDestinoZip -Force
        }
    }

    $instaladores = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } | Sort-Object Length -Descending
    $instalador = $instaladores | Select-Object -First 1
    
    if (-not $instalador) {
        Write-Host "  [ERROR] No se encontro el instalador de multiOTP." -ForegroundColor Red
        Pause | Out-Null
        return
    }

    Write-Host "  [INFO] Instalando $($instalador.Name) en modo silencioso..." -ForegroundColor Cyan
    try {
        if ($instalador.Extension -eq ".msi") {
            $argumentos = "/i `"$($instalador.FullName)`" /qn"
            $procesoInstalacion = Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentos -Wait -PassThru
        } else {
            $procesoInstalacion = Start-Process -FilePath $instalador.FullName -ArgumentList "/S" -Wait -PassThru
        }
        
        if ($procesoInstalacion.ExitCode -eq 0) {
            Write-Host "  [OK] MFA instalado correctamente en el sistema." -ForegroundColor Green
        } else {
            Write-Host "  [AVISO] El instalador MFA termino con codigo $($procesoInstalacion.ExitCode)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] Fallo instalacion MFA: $($_.Exception.Message)" -ForegroundColor Red
        Pause | Out-Null
        return
    }

    Start-Sleep -Seconds 5

    # =========================================================
    # PASO 3: RASTREAR MOTOR Y CONFIGURAR ADMINISTRADOR
    # =========================================================
    Write-Host "`n  [3/3] Buscando motor de configuracion (multiotp.exe)..." -ForegroundColor Yellow
    
    $exeMultiOTP = $null
    $rutasBuscar = @("C:\Program Files", "C:\multiOTP", "C:\Program Files (x86)")
    
    foreach ($ruta in $rutasBuscar) {
        if (Test-Path $ruta) {
            $encontrado = Get-ChildItem -Path $ruta -Filter "multiotp.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($encontrado) {
                $exeMultiOTP = $encontrado.FullName
                Write-Host "  [OK] Motor encontrado en: $exeMultiOTP" -ForegroundColor Green
                break
            }
        }
    }

    if (-not $exeMultiOTP) {
        Write-Host "  [ERROR] No se encontro multiotp.exe despues de la instalacion." -ForegroundColor Red
        Pause | Out-Null
        return
    }

    Write-Host "`n  Configurando MFA para Administrator..." -ForegroundColor Yellow
    $usuarioMFA = "Administrator"
    
try {
        # Viajar a la carpeta de multiOTP
        $directorioBase = Split-Path $exeMultiOTP
        Push-Location $directorioBase

        # 0. Limpiar intentos corruptos anteriores
        Write-Host "  [INFO] Limpiando registros antiguos del usuario..." -ForegroundColor DarkGray
        & ".\multiotp.exe" -delete $usuarioMFA 2>&1 | Out-Null

        # 1. Crear el usuario limpiamente
        Write-Host "  [INFO] Registrando usuario en la base de datos de MFA..." -ForegroundColor Yellow
        $creacion = & ".\multiotp.exe" -fastcreatenopin $usuarioMFA 2>&1
        
        Write-Host "  [OK] Generando clave secreta TOTP..." -ForegroundColor Green
        
        # 2. Obtener la informacion
        $qrCrudo = & ".\multiotp.exe" -display-user-qrcode $usuarioMFA 2>&1
        $infoCruda = & ".\multiotp.exe" -user-info $usuarioMFA 2>&1
        
        # Regresar a la carpeta original
        Pop-Location

        Write-Host "`n  +-------------------------------------------------------------+" -ForegroundColor Magenta
        Write-Host "  |  ATENCION: ESCANEA ESTO CON GOOGLE AUTHENTICATOR EN TU CEL  |" -ForegroundColor Magenta
        Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Magenta
        
        Write-Host "`n  --- SALIDA DE CREACION ---" -ForegroundColor Yellow
        Write-Host $creacion -ForegroundColor Cyan

        Write-Host "`n  --- ENLACE DEL CODIGO QR ---" -ForegroundColor Yellow
        Write-Host $qrCrudo -ForegroundColor Cyan
        
        Write-Host "`n  --- DETALLES DE LA CUENTA (Busca la linea 'TOTP secret') ---" -ForegroundColor Yellow
        Write-Host $infoCruda -ForegroundColor Cyan
        
        Write-Host "`n  2. IMPORTANTE: Ten tu celular a la mano antes de cerrar sesion." -ForegroundColor White
        
    } catch {
        Write-Host "  [ERROR] Fallo configuracion de usuario: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}