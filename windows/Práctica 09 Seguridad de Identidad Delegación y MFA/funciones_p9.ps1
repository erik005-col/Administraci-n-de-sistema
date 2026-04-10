# ============================================================
#  funciones_p9.ps1 - Libreria de funciones para la Practica 9
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#  Version  : 2.0 (corregida y robusta)
#
#  Practica 09: Seguridad de Identidad, Delegacion y MFA
# ============================================================


# ------------------------------------------------------------
# HELPER INTERNO: Importar modulos necesarios de forma segura
# ------------------------------------------------------------
function Asegurar-Modulos {
    $modulosRequeridos = @("ActiveDirectory", "GroupPolicy")
    foreach ($mod in $modulosRequeridos) {
        if (-not (Get-Module -Name $mod -ErrorAction SilentlyContinue)) {
            try {
                Import-Module $mod -ErrorAction Stop
            } catch {
                Write-Host "  [AVISO] No se pudo importar el modulo '$mod': $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}


# ------------------------------------------------------------
# FUNCION 1: Configurar Fine-Grained Password Policies (FGPP)
# Cuates    -> minimo 10 caracteres, historial 5,  prioridad 10
# NoCuates  -> minimo 14 caracteres, historial 10, prioridad 20
# NOTA: FGPP requiere nivel funcional Windows Server 2008+
# ------------------------------------------------------------
function Configurar-PasswordPolicies {

    Asegurar-Modulos

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |  FINE-GRAINED PASSWORD POLICIES (FGPP)   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Se crearan dos politicas de contrasena:" -ForegroundColor White
    Write-Host "    - Cuates   : min 10 car, historial 5,  bloqueo 5/30min" -ForegroundColor Green
    Write-Host "    - NoCuates : min 14 car, historial 10, bloqueo 3/60min" -ForegroundColor Yellow
    Write-Host ""

    # Verificar conexion al dominio
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Host "  Dominio    : $($domain.DNSRoot)" -ForegroundColor Cyan
        Write-Host "  Nivel func : $($domain.DomainMode)" -ForegroundColor Cyan
        Write-Host ""
    } catch {
        Write-Host "  [ERROR] No se puede contactar con el dominio: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Verificar que los grupos existen
    foreach ($grupo in @("Cuates", "NoCuates")) {
        $g = Get-ADGroup -Filter "Name -eq '$grupo'" -ErrorAction SilentlyContinue
        if (-not $g) {
            Write-Host "  [ERROR] El grupo '$grupo' no existe en AD." -ForegroundColor Red
            Write-Host "         Asegurate de haber ejecutado la Practica 8 primero." -ForegroundColor Yellow
            return
        }
    }

    $confirmar = Read-Host "  Confirmas la configuracion? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    $politicas = @(
        @{
            Nombre      = "PSO-Cuates"
            Precedencia = 10
            MinLongitud = 10
            Historial   = 5
            Intentos    = 5
            Duracion    = "00:30:00"
            Ventana     = "00:30:00"
            MaxEdad     = "60.00:00:00"
            Grupo       = "Cuates"
        },
        @{
            Nombre      = "PSO-NoCuates"
            Precedencia = 20
            MinLongitud = 14
            Historial   = 10
            Intentos    = 3
            Duracion    = "01:00:00"
            Ventana     = "01:00:00"
            MaxEdad     = "30.00:00:00"
            Grupo       = "NoCuates"
        }
    )

    $i = 1
    foreach ($pol in $politicas) {
        Write-Host "  [$i/$($politicas.Count)] Configurando '$($pol.Nombre)'..." -ForegroundColor Yellow
        try {
            # Si ya existe, eliminar sujetos primero y luego la politica
            $existente = Get-ADFineGrainedPasswordPolicy -Identity $pol.Nombre -ErrorAction SilentlyContinue
            if ($existente) {
                $sujetos = Get-ADFineGrainedPasswordPolicySubject -Identity $pol.Nombre -ErrorAction SilentlyContinue
                if ($sujetos) {
                    Remove-ADFineGrainedPasswordPolicySubject `
                        -Identity $pol.Nombre -Subjects $sujetos `
                        -Confirm:$false -ErrorAction SilentlyContinue
                }
                Remove-ADFineGrainedPasswordPolicy -Identity $pol.Nombre -Confirm:$false -ErrorAction Stop
                Write-Host "    [INFO] Politica anterior eliminada para recrearla limpia." -ForegroundColor Yellow
            }

            New-ADFineGrainedPasswordPolicy `
                -Name                     $pol.Nombre      `
                -Precedence               $pol.Precedencia `
                -MinPasswordLength        $pol.MinLongitud `
                -PasswordHistoryCount     $pol.Historial   `
                -ComplexityEnabled        $true            `
                -LockoutThreshold         $pol.Intentos    `
                -LockoutDuration          $pol.Duracion    `
                -LockoutObservationWindow $pol.Ventana     `
                -MinPasswordAge           "1.00:00:00"     `
                -MaxPasswordAge           $pol.MaxEdad     `
                -ReversibleEncryptionEnabled      $false   `
                -ProtectedFromAccidentalDeletion  $false   `
                -ErrorAction Stop

            Add-ADFineGrainedPasswordPolicySubject `
                -Identity $pol.Nombre `
                -Subjects  $pol.Grupo `
                -ErrorAction Stop

            Write-Host "    [OK] '$($pol.Nombre)' creada y vinculada al grupo '$($pol.Grupo)'." -ForegroundColor Green

        } catch {
            Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
        $i++
        Write-Host ""
    }

    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | RESUMEN DE POLITICAS CREADAS             |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | PSO-Cuates    (Prioridad 10)              |" -ForegroundColor Green
    Write-Host "  |   Min longitud : 10 caracteres           |" -ForegroundColor White
    Write-Host "  |   Historial    : 5 contrasenas           |" -ForegroundColor White
    Write-Host "  |   Bloqueo      : 5 intentos / 30 min     |" -ForegroundColor White
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | PSO-NoCuates  (Prioridad 20)              |" -ForegroundColor Yellow
    Write-Host "  |   Min longitud : 14 caracteres           |" -ForegroundColor White
    Write-Host "  |   Historial    : 10 contrasenas          |" -ForegroundColor White
    Write-Host "  |   Bloqueo      : 3 intentos / 60 min     |" -ForegroundColor White
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 2: Verificar FGPP aplicada a un usuario
# ------------------------------------------------------------
function Verificar-PasswordPolicy {

    Asegurar-Modulos

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    VERIFICAR POLITICA DE UN USUARIO      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $usuario = Read-Host "  Ingresa el SamAccountName del usuario"

    if ([string]::IsNullOrWhiteSpace($usuario)) {
        Write-Host "  [ERROR] No ingresaste ningun nombre." -ForegroundColor Red
        Write-Host ""
        return
    }

    try {
        $userObj = Get-ADUser -Identity $usuario -ErrorAction Stop
        Write-Host ""
        Write-Host "  Usuario encontrado: $($userObj.Name)" -ForegroundColor Cyan

        $pso = Get-ADUserResultantPasswordPolicy -Identity $usuario -ErrorAction SilentlyContinue
        if ($pso) {
            Write-Host ""
            Write-Host "  Politica FGPP efectiva:" -ForegroundColor Green
            Write-Host "    Nombre PSO          : $($pso.Name)"                 -ForegroundColor White
            Write-Host "    Min longitud        : $($pso.MinPasswordLength)"    -ForegroundColor White
            Write-Host "    Historial           : $($pso.PasswordHistoryCount)" -ForegroundColor White
            Write-Host "    Bloqueo (intentos)  : $($pso.LockoutThreshold)"     -ForegroundColor White
            Write-Host "    Duracion bloqueo    : $($pso.LockoutDuration)"      -ForegroundColor White
            Write-Host "    Complejidad         : $($pso.ComplexityEnabled)"    -ForegroundColor White
        } else {
            Write-Host ""
            Write-Host "  '$usuario' NO tiene PSO asignada." -ForegroundColor Yellow
            Write-Host "  Usa la politica predeterminada del dominio." -ForegroundColor Yellow
        }
    } catch {
        Write-Host ""
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 3: Crear administradores delegados
# admin_cuates   -> OU=Cuates
# admin_nocuates -> OU=NoCuates
# ------------------------------------------------------------
function Crear-AdminesDelegados {

    Asegurar-Modulos

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CREAR ADMINISTRADORES DELEGADOS        |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Se crearan:" -ForegroundColor White
    Write-Host "    - admin_cuates   en OU=Cuates"   -ForegroundColor Green
    Write-Host "    - admin_nocuates en OU=NoCuates" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Estos usuarios NO seran Domain Admins." -ForegroundColor Cyan
    Write-Host ""

    $dcBase = "DC=practica8,DC=local"

    # Verificar que las OUs existen
    $ouCuatesObj   = Get-ADOrganizationalUnit -Filter "Name -eq 'Cuates'"   -ErrorAction SilentlyContinue
    $ouNoCuatesObj = Get-ADOrganizationalUnit -Filter "Name -eq 'NoCuates'" -ErrorAction SilentlyContinue

    if (-not $ouCuatesObj) {
        Write-Host "  [ERROR] La OU 'Cuates' no existe. Ejecuta primero la Practica 8." -ForegroundColor Red
        return
    }
    if (-not $ouNoCuatesObj) {
        Write-Host "  [ERROR] La OU 'NoCuates' no existe. Ejecuta primero la Practica 8." -ForegroundColor Red
        return
    }

    $pwdAdmin  = Read-Host "  Ingresa la contrasena para los admins delegados" -AsSecureString
    $confirmar = Read-Host "  Confirmas la creacion? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    $admins = @(
        @{ SAM = "admin_cuates";   Nombre = "Admin Cuates";   OU = "Cuates"   },
        @{ SAM = "admin_nocuates"; Nombre = "Admin NoCuates"; OU = "NoCuates" }
    )

    foreach ($adm in $admins) {
        Write-Host "  Procesando '$($adm.SAM)'..." -ForegroundColor Yellow
        try {
            $existente = Get-ADUser -Filter "SamAccountName -eq '$($adm.SAM)'" -ErrorAction SilentlyContinue
            if ($existente) {
                Write-Host "  [INFO] '$($adm.SAM)' ya existe. Se omite la creacion." -ForegroundColor Yellow
            } else {
                New-ADUser `
                    -Name                  $adm.Nombre `
                    -SamAccountName        $adm.SAM `
                    -UserPrincipalName     "$($adm.SAM)@practica8.local" `
                    -Path                  "OU=$($adm.OU),$dcBase" `
                    -AccountPassword       $pwdAdmin `
                    -Enabled               $true `
                    -PasswordNeverExpires  $true `
                    -ChangePasswordAtLogon $false `
                    -Description           "Administrador delegado OU=$($adm.OU)" `
                    -ErrorAction Stop

                Write-Host "  [OK] '$($adm.SAM)' creado en OU=$($adm.OU)." -ForegroundColor Green
            }
        } catch {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | ADMINS CREADOS                           |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | admin_cuates   -> OU=Cuates              |" -ForegroundColor Green
    Write-Host "  | admin_nocuates -> OU=NoCuates            |" -ForegroundColor Yellow
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Siguiente: Opcion 4 -> Delegacion        |" -ForegroundColor White
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 4: Delegacion de Control en OUs via dsacls.exe
# dsacls es nativo en cualquier Windows Server DC
# No requiere modulos adicionales ni trucos de ACL
# ------------------------------------------------------------
function Configurar-Delegacion {

    Asegurar-Modulos

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |       DELEGACION DE CONTROL EN OUs       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Permisos que se delegaran:" -ForegroundColor White
    Write-Host "    - Crear y eliminar objetos de usuario" -ForegroundColor White
    Write-Host "    - Leer y modificar propiedades de usuario" -ForegroundColor White
    Write-Host "    - Resetear contrasenas" -ForegroundColor White
    Write-Host "    - Habilitar/Deshabilitar cuentas" -ForegroundColor White
    Write-Host ""

    $dominio = "practica8.local"
    $dcBase  = "DC=practica8,DC=local"

    # Verificar que los admins existen
    foreach ($sam in @("admin_cuates", "admin_nocuates")) {
        $u = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
        if (-not $u) {
            Write-Host "  [ERROR] El usuario '$sam' no existe." -ForegroundColor Red
            Write-Host "         Ejecuta primero la Opcion 3 (Crear administradores delegados)." -ForegroundColor Yellow
            return
        }
    }

    $confirmar = Read-Host "  Confirmas la delegacion? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    $delegaciones = @(
        @{ Admin = "admin_cuates";   OU = "Cuates"   },
        @{ Admin = "admin_nocuates"; OU = "NoCuates" }
    )

    foreach ($del in $delegaciones) {
        $ouDN   = "OU=$($del.OU),$dcBase"
        $cuenta = "$dominio\$($del.Admin)"

        Write-Host "  [$($del.Admin)] Delegando en OU=$($del.OU)..." -ForegroundColor Yellow

        # Permiso 1: Crear y eliminar objetos usuario en la OU (hereda hacia abajo)
        $null = dsacls $ouDN /I:T /G "${cuenta}:CCDC;user" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] Crear/Eliminar usuarios" -ForegroundColor Green
        } else {
            Write-Host "    [AVISO] Crear/Eliminar: puede ya existir o requerir permisos adicionales" -ForegroundColor Yellow
        }

        # Permiso 2: Leer/Escribir todas las propiedades en objetos usuario descendientes
        $null = dsacls $ouDN /I:S /G "${cuenta}:RPWP;user" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] Leer/Escribir propiedades" -ForegroundColor Green
        } else {
            Write-Host "    [AVISO] Propiedades: puede ya existir o requerir permisos adicionales" -ForegroundColor Yellow
        }

        # Permiso 3: Extended Right - Reset Password
        $null = dsacls $ouDN /I:S /G "${cuenta}:CA;Reset Password;user" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] Resetear contrasenas" -ForegroundColor Green
        } else {
            Write-Host "    [AVISO] Reset Password: puede ya existir" -ForegroundColor Yellow
        }

        # Permiso 4: Escribir userAccountControl (habilitar/deshabilitar)
        $null = dsacls $ouDN /I:S /G "${cuenta}:WP;userAccountControl;user" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] Habilitar/Deshabilitar cuentas" -ForegroundColor Green
        } else {
            Write-Host "    [AVISO] userAccountControl: puede ya existir" -ForegroundColor Yellow
        }

        Write-Host ""
    }

    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | DELEGACION COMPLETADA                    |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | admin_cuates   -> permisos en OU=Cuates  |" -ForegroundColor Green
    Write-Host "  | admin_nocuates -> permisos en OU=NoCuates|" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 5: Configurar Account Lockout (GPO + secedit)
# Usa la ruta local de SYSVOL (C:\Windows\SYSVOL\...)
# con fallback a secedit directo si falla la ruta
# ------------------------------------------------------------
function Configurar-AccountLockout {

    Asegurar-Modulos

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR BLOQUEO DE CUENTAS          |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Configuracion que se aplicara:" -ForegroundColor White
    Write-Host "    - Bloqueo tras    : 5 intentos fallidos"  -ForegroundColor White
    Write-Host "    - Duracion bloqueo: 30 minutos"           -ForegroundColor White
    Write-Host "    - Ventana reset   : 30 minutos"           -ForegroundColor White
    Write-Host "    - Min contrasena  : 8 caracteres"         -ForegroundColor White
    Write-Host "    - Complejidad     : Habilitada"           -ForegroundColor White
    Write-Host ""

    $confirmar = Read-Host "  Confirmas la configuracion? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""
    $nombreGPO = "P9-AccountLockout"

    # PASO 1: Crear o recuperar GPO
    Write-Host "  [1/4] Creando GPO '$nombreGPO'..." -ForegroundColor Yellow
    $gpo = $null
    try {
        $gpo = Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $nombreGPO -ErrorAction Stop
            Write-Host "  [OK] GPO creada. GUID: $($gpo.Id)" -ForegroundColor Green
        } else {
            Write-Host "  [INFO] GPO ya existe. GUID: $($gpo.Id)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] No se pudo crear la GPO: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # PASO 2: Escribir plantilla de seguridad en SYSVOL
    Write-Host ""
    Write-Host "  [2/4] Escribiendo plantilla de seguridad..." -ForegroundColor Yellow

    $contenidoInf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MinimumPasswordAge = 1
MaximumPasswordAge = 60
MinimumPasswordLength = 8
PasswordComplexity = 1
PasswordHistorySize = 5
LockoutBadCount = 5
ResetLockoutCount = 30
LockoutDuration = 30
"@

    # Intentar ruta local de SYSVOL (mas confiable que UNC en el propio DC)
    $gpoGuidUpper = "{$($gpo.Id.ToString().ToUpper())}"
    $sysvolBase   = "C:\Windows\SYSVOL\sysvol\practica8.local\Policies"
    $gpoPath      = "$sysvolBase\$gpoGuidUpper\Machine\Microsoft\Windows NT\SecEdit"
    $infEscrito   = $false

    if (Test-Path $sysvolBase) {
        try {
            if (-not (Test-Path $gpoPath)) {
                New-Item -ItemType Directory -Path $gpoPath -Force -ErrorAction Stop | Out-Null
            }
            $contenidoInf | Out-File -FilePath "$gpoPath\GptTmpl.inf" -Encoding Unicode -Force -ErrorAction Stop

            # Actualizar o crear GPT.INI para que el DC reconozca la version
            $gptIni = "$sysvolBase\$gpoGuidUpper\GPT.INI"
            if (Test-Path $gptIni) {
                $txt = Get-Content $gptIni -Raw
                if ($txt -match "Version=(\d+)") {
                    $txt = $txt -replace "Version=\d+", "Version=$([int]$Matches[1] + 1)"
                    $txt | Out-File $gptIni -Encoding ASCII -Force
                }
            } else {
                "[General]`r`nVersion=1`r`n" | Out-File $gptIni -Encoding ASCII -Force
            }

            Write-Host "  [OK] Plantilla escrita en SYSVOL local." -ForegroundColor Green
            $infEscrito = $true
        } catch {
            Write-Host "  [AVISO] No se pudo escribir en SYSVOL: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Si no se pudo escribir en SYSVOL, aplicar directamente con secedit
    if (-not $infEscrito) {
        Write-Host "  Aplicando politica directamente via secedit..." -ForegroundColor Yellow
        try {
            $tmpInf = Join-Path $env:TEMP "p9_lockout.inf"
            $tmpDB  = Join-Path $env:TEMP "p9_secedit.sdb"
            $contenidoInf | Out-File -FilePath $tmpInf -Encoding Unicode -Force
            $null = secedit /configure /db $tmpDB /cfg $tmpInf /overwrite /quiet 2>&1
            Remove-Item $tmpInf -ErrorAction SilentlyContinue
            Remove-Item $tmpDB  -ErrorAction SilentlyContinue
            Write-Host "  [OK] Politica aplicada via secedit." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] secedit: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # PASO 3: Vincular GPO al dominio
    Write-Host ""
    Write-Host "  [3/4] Vinculando GPO al dominio..." -ForegroundColor Yellow
    try {
        $herencia = Get-GPInheritance -Target "DC=practica8,DC=local" -ErrorAction Stop
        $links    = $herencia.GpoLinks
        $yaVinculada = ($links -and ($links | Where-Object { $_.DisplayName -eq $nombreGPO }))

        if (-not $yaVinculada) {
            New-GPLink -Name $nombreGPO -Target "DC=practica8,DC=local" -LinkEnabled Yes -ErrorAction Stop | Out-Null
            Write-Host "  [OK] GPO vinculada al dominio." -ForegroundColor Green
        } else {
            Write-Host "  [INFO] GPO ya estaba vinculada." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [AVISO] $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # PASO 4: Forzar actualizacion
    Write-Host ""
    Write-Host "  [4/4] gpupdate /force..." -ForegroundColor Yellow
    $null = gpupdate /force 2>&1
    Write-Host "  [OK] gpupdate /force completado." -ForegroundColor Green

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | BLOQUEO DE CUENTAS CONFIGURADO           |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Intentos fallidos    : 5                 |" -ForegroundColor White
    Write-Host "  | Duracion del bloqueo : 30 minutos        |" -ForegroundColor White
    Write-Host "  | Ventana observacion  : 30 minutos        |" -ForegroundColor White
    Write-Host "  | Min contrasena       : 8 caracteres      |" -ForegroundColor White
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 6: Configurar Auditoria de eventos
# Usa GUIDs de subcategoria (funciona en cualquier idioma)
# ------------------------------------------------------------
function Configurar-Auditoria {

    Asegurar-Modulos

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |      CONFIGURAR AUDITORIA DE SEGURIDAD   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Se auditaran (exito y fallo):" -ForegroundColor White
    Write-Host "    - Inicios y cierres de sesion"      -ForegroundColor White
    Write-Host "    - Bloqueo de cuentas"               -ForegroundColor White
    Write-Host "    - Gestion de cuentas de usuario"    -ForegroundColor White
    Write-Host "    - Acceso a sistema de archivos"     -ForegroundColor White
    Write-Host "    - Cambios en politica de auditoria" -ForegroundColor White
    Write-Host ""

    $confirmar = Read-Host "  Confirmas la configuracion? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "  [1/3] Configurando auditoria local via GUIDs (independiente del idioma)..." -ForegroundColor Yellow

    # GUIDs de subcategoria de auditoria - estandar de Microsoft, no cambian con el idioma
    $subcategorias = @(
        @{ GUID = "{0CCE9215-69AE-11D9-BED3-505054503030}"; Nombre = "Logon"                     },
        @{ GUID = "{0CCE9216-69AE-11D9-BED3-505054503030}"; Nombre = "Logoff"                    },
        @{ GUID = "{0CCE9217-69AE-11D9-BED3-505054503030}"; Nombre = "Account Lockout"           },
        @{ GUID = "{0CCE9235-69AE-11D9-BED3-505054503030}"; Nombre = "Other Logon/Logoff Events" },
        @{ GUID = "{0CCE9224-69AE-11D9-BED3-505054503030}"; Nombre = "User Account Management"   },
        @{ GUID = "{0CCE9225-69AE-11D9-BED3-505054503030}"; Nombre = "Computer Account Mgmt"    },
        @{ GUID = "{0CCE922B-69AE-11D9-BED3-505054503030}"; Nombre = "File System"               },
        @{ GUID = "{0CCE922F-69AE-11D9-BED3-505054503030}"; Nombre = "Audit Policy Change"       }
    )

    $errores = 0
    foreach ($sub in $subcategorias) {
        $null = auditpol /set /subcategory:$($sub.GUID) /success:enable /failure:enable 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] $($sub.Nombre)" -ForegroundColor Green
        } else {
            Write-Host "    [AVISO] $($sub.Nombre)" -ForegroundColor Yellow
            $errores++
        }
    }

    if ($errores -eq 0) {
        Write-Host "  [OK] Auditoria local configurada sin errores." -ForegroundColor Green
    } else {
        Write-Host "  [AVISO] $errores categoria(s) con advertencias (no critico)." -ForegroundColor Yellow
    }

    # Crear GPO de auditoria
    Write-Host ""
    Write-Host "  [2/3] Creando GPO de auditoria..." -ForegroundColor Yellow
    $nombreGPO = "P9-Auditoria-Seguridad"
    $gpo = $null
    try {
        $gpo = Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $nombreGPO -ErrorAction Stop
            Write-Host "  [OK] GPO '$nombreGPO' creada." -ForegroundColor Green
        } else {
            Write-Host "  [INFO] GPO '$nombreGPO' ya existe." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    # Vincular GPO
    Write-Host ""
    Write-Host "  [3/3] Vinculando GPO al dominio..." -ForegroundColor Yellow
    if ($gpo) {
        try {
            $herencia = Get-GPInheritance -Target "DC=practica8,DC=local" -ErrorAction Stop
            $links    = $herencia.GpoLinks
            $yaVinculada = ($links -and ($links | Where-Object { $_.DisplayName -eq $nombreGPO }))

            if (-not $yaVinculada) {
                New-GPLink -Name $nombreGPO -Target "DC=practica8,DC=local" -LinkEnabled Yes -ErrorAction Stop | Out-Null
                Write-Host "  [OK] GPO vinculada al dominio." -ForegroundColor Green
            } else {
                Write-Host "  [INFO] GPO ya estaba vinculada." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [AVISO] $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $null = gpupdate /force 2>&1
    Write-Host "  [OK] gpupdate /force completado." -ForegroundColor Green

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | AUDITORIA CONFIGURADA                    |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Ver en: Visor de Eventos -> Seguridad    |" -ForegroundColor White
    Write-Host "  | ID 4624 = Login exitoso                  |" -ForegroundColor Green
    Write-Host "  | ID 4625 = Login fallido (captura para    |" -ForegroundColor Red
    Write-Host "  |           evidencias del documento)      |" -ForegroundColor Red
    Write-Host "  | ID 4740 = Cuenta bloqueada               |" -ForegroundColor Red
    Write-Host "  | ID 4722 = Cuenta de usuario habilitada   |" -ForegroundColor White
    Write-Host "  | ID 4723 = Cambio de contrasena           |" -ForegroundColor White
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 7: Ver cuentas bloqueadas en el dominio
# ------------------------------------------------------------
function Ver-CuentasBloqueadas {

    Asegurar-Modulos

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |      CUENTAS BLOQUEADAS EN EL DOMINIO    |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $bloqueadas = @(Search-ADAccount -LockedOut -UsersOnly -ErrorAction Stop)

        if ($bloqueadas.Count -gt 0) {
            Write-Host "  Cuentas bloqueadas encontradas: $($bloqueadas.Count)" -ForegroundColor Red
            Write-Host ""

            foreach ($cuenta in $bloqueadas) {
                try {
                    $user = Get-ADUser -Identity $cuenta.SamAccountName `
                                -Properties BadLogonCount, BadPasswordTime, LockedOut `
                                -ErrorAction Stop
                    Write-Host "  -> $($user.SamAccountName)" -ForegroundColor Yellow
                    Write-Host "     Nombre          : $($user.Name)"          -ForegroundColor White
                    Write-Host "     Intentos fallidos: $($user.BadLogonCount)" -ForegroundColor White
                    if ($user.BadPasswordTime) {
                        Write-Host "     Ultimo intento  : $($user.BadPasswordTime)" -ForegroundColor White
                    }
                    Write-Host ""
                } catch {
                    Write-Host "  -> $($cuenta.SamAccountName) [sin detalles]" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "  No hay cuentas bloqueadas en este momento." -ForegroundColor Green
            Write-Host ""
        }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
    }

    Write-Host "  Usa la Opcion 8 para desbloquear una cuenta." -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 8: Desbloquear cuenta de usuario
# ------------------------------------------------------------
function Desbloquear-Cuenta {

    Asegurar-Modulos

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |         DESBLOQUEAR CUENTA DE USUARIO    |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $usuario = Read-Host "  Ingresa el SamAccountName a desbloquear"

    if ([string]::IsNullOrWhiteSpace($usuario)) {
        Write-Host ""
        Write-Host "  [ERROR] No ingresaste ningun nombre de usuario." -ForegroundColor Red
        Write-Host ""
        return
    }

    try {
        $user = Get-ADUser -Identity $usuario -Properties LockedOut -ErrorAction Stop

        Write-Host ""
        Write-Host "  Usuario encontrado: $($user.Name)" -ForegroundColor Cyan

        if ($user.LockedOut) {
            Unlock-ADAccount -Identity $usuario -ErrorAction Stop
            Write-Host "  [OK] Cuenta '$usuario' desbloqueada correctamente." -ForegroundColor Green
        } else {
            Write-Host "  [INFO] La cuenta '$usuario' no esta bloqueada." -ForegroundColor Yellow
        }
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Host ""
        Write-Host "  [ERROR] El usuario '$usuario' no existe en el dominio." -ForegroundColor Red
    } catch {
        Write-Host ""
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}
