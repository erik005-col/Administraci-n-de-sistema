# =============================================================================
#  FUNCIONES.PS1 - Libreria de funciones para administracion de Dominio AD
#  Practica: GPO + FSRM | Active Directory
# =============================================================================

$Global:DomainName    = ""
$Global:DomainNetBIOS = ""
$Global:SafeModePass  = ""
$Global:CSVPath       = "$PSScriptRoot\usuarios.csv"
$Global:HomePath      = "C:\Homes"
$Global:LogFile       = "$PSScriptRoot\ad_setup.log"

# =============================================================================
#  UTILIDAD: LOG
# =============================================================================
function Write-Log {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linea = "[$timestamp][$Nivel] $Mensaje"
    Add-Content -Path $Global:LogFile -Value $linea
    switch ($Nivel) {
        "OK"    { Write-Host "  [+] $Mensaje" -ForegroundColor Green }
        "ERROR" { Write-Host "  [!] $Mensaje" -ForegroundColor Red }
        "WARN"  { Write-Host "  [~] $Mensaje" -ForegroundColor Yellow }
        default { Write-Host "  [*] $Mensaje" -ForegroundColor Cyan }
    }
}

# =============================================================================
#  UTILIDAD: Obtener DomainName si no esta configurado
# =============================================================================
function Ensure-DomainName {
    if (-not $Global:DomainName) {
        $Global:DomainName = Read-Host "  Nombre FQDN del dominio (ej: practica.local)"
    }
    # Verificar que AD este disponible
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Write-Log "Modulo ActiveDirectory no disponible. Instala RSAT-AD-PowerShell." "ERROR"
        return $false
    }
    return $true
}

# =============================================================================
#  FUNCION 1: Instalar roles y dependencias
# =============================================================================
function Instalar-Dependencias {
    Write-Log "Iniciando instalacion de roles y caracteristicas..."
    $features = @(
        "AD-Domain-Services",
        "RSAT-AD-PowerShell",
        "RSAT-AD-AdminCenter",
        "RSAT-ADDS-Tools",
        "FS-Resource-Manager",
        "RSAT-File-Services",
        "AppServerInfrastructure"
    )
    foreach ($feat in $features) {
        $result = Install-WindowsFeature -Name $feat -IncludeManagementTools -ErrorAction SilentlyContinue
        if ($result.Success) {
            Write-Log "Rol instalado: $feat" "OK"
        } else {
            Write-Log "Ya existe o no disponible: $feat" "WARN"
        }
    }
    Write-Log "Instalacion de dependencias completada." "OK"
}

# =============================================================================
#  FUNCION 2: Promover servidor a Domain Controller
# =============================================================================
function Promover-DomainController {
    $Global:DomainName    = Read-Host "  Nombre FQDN del dominio (ej: practica.local)"
    $Global:DomainNetBIOS = Read-Host "  Nombre NetBIOS (ej: PRACTICA)"
    $Global:SafeModePass  = Read-Host "  Contrasena del modo seguro (DSRM)" -AsSecureString

    Write-Log "Promoviendo servidor a Domain Controller: $Global:DomainName"
    try {
        Import-Module ADDSDeployment -ErrorAction Stop
        Install-ADDSForest `
            -DomainName                    $Global:DomainName `
            -DomainNetbiosName             $Global:DomainNetBIOS `
            -SafeModeAdministratorPassword $Global:SafeModePass `
            -InstallDns:$true `
            -Force:$true `
            -NoRebootOnCompletion:$false
        Write-Log "Servidor promovido correctamente. Reiniciando..." "OK"
    } catch {
        Write-Log "Error al promover el DC: $_" "ERROR"
    }
}

# =============================================================================
#  FUNCION 3: Crear OUs, grupos y usuarios desde CSV
# =============================================================================
function Crear-OUsYUsuarios {
    if (-not (Ensure-DomainName)) { return }

    $dcParts = $Global:DomainName -split "\." | ForEach-Object { "DC=$_" }
    $baseDN  = $dcParts -join ","

    # --- Crear Unidades Organizativas ---
    Write-Log "Creando Unidades Organizativas..."
    foreach ($ou in @("Cuates", "NoCuates")) {
        try {
            New-ADOrganizationalUnit -Name $ou -Path $baseDN `
                -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
            Write-Log "OU creada: $ou" "OK"
        } catch {
            Write-Log "OU ya existe: $ou" "WARN"
        }
    }

    # --- Crear grupos de seguridad dentro de cada OU ---
    Write-Log "Creando grupos de seguridad..."
    foreach ($ou in @("Cuates", "NoCuates")) {
        $ouDN = "OU=$ou,$baseDN"
        try {
            New-ADGroup -Name $ou -GroupScope Global -GroupCategory Security `
                -Path $ouDN -ErrorAction Stop
            Write-Log "Grupo creado: $ou" "OK"
        } catch {
            Write-Log "Grupo ya existe: $ou" "WARN"
        }
    }

    # --- Verificar CSV ---
    if (-not (Test-Path $Global:CSVPath)) {
        Write-Log "No se encontro el CSV en: $Global:CSVPath" "ERROR"
        Write-Host "  [!] Crea el archivo usuarios.csv en la misma carpeta que los scripts." -ForegroundColor Red
        Write-Host "  [!] Formato: Nombre,Apellido,Usuario,Email,Password,Departamento,Descripcion" -ForegroundColor Yellow
        return
    }

    $usuarios = Import-Csv -Path $Global:CSVPath
    Write-Log "Importando $($usuarios.Count) usuarios desde CSV..."

    foreach ($u in $usuarios) {
        # Determinar OU segun columna Departamento del CSV
        $ouTarget = if ($u.Departamento -eq "Cuates") {
            "OU=Cuates,$baseDN"
        } else {
            "OU=NoCuates,$baseDN"
        }

        $secPass = ConvertTo-SecureString $u.Password -AsPlainText -Force
        $homeDir = "$Global:HomePath\$($u.Usuario)"

        # Crear carpeta personal si no existe
        if (-not (Test-Path $homeDir)) {
            New-Item -ItemType Directory -Path $homeDir -Force | Out-Null
            Write-Log "Carpeta creada: $homeDir" "OK"
        }

        try {
            New-ADUser `
                -GivenName         $u.Nombre `
                -Surname           $u.Apellido `
                -Name              "$($u.Nombre) $($u.Apellido)" `
                -SamAccountName    $u.Usuario `
                -UserPrincipalName $u.Email `
                -Path              $ouTarget `
                -AccountPassword   $secPass `
                -Enabled           $true `
                -Description       $u.Descripcion `
                -HomeDirectory     $homeDir `
                -HomeDrive         "H:" `
                -ErrorAction       Stop

            # Agregar al grupo correspondiente
            Add-ADGroupMember -Identity $u.Departamento -Members $u.Usuario
            Write-Log "Usuario creado: $($u.Usuario) -> OU=$($u.Departamento)" "OK"

        } catch {
            Write-Log "Error con usuario $($u.Usuario): $_" "ERROR"
        }
    }
}

# =============================================================================
#  FUNCION 4: Configurar Logon Hours
#
#  CORRECCION PRINCIPAL:
#  Active Directory almacena logonHours en UTC.
#  Debemos convertir la hora local a UTC antes de construir la mascara.
#  Ademas se aplica la GPO "ForceLogoff" para expulsar sesiones activas.
# =============================================================================
function Configurar-LogonHours {
    if (-not (Ensure-DomainName)) { return }

    Write-Log "Configurando Logon Hours..."

    # ------------------------------------------------------------------
    # Detectar offset UTC del servidor automaticamente
    # ------------------------------------------------------------------
    # TotalHours da UTC - Local (negativo si estamos al oeste de Greenwich)
    # Para convertir hora local a UTC: horaUTC = horaLocal - offsetHoras
    # Ejemplo Mexico UTC-7: offsetHoras = -7, entonces 8am local = 8-(-7) = 15 UTC  CORRECTO
    $offsetHoras = [int][System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalHours

    Write-Log "Offset UTC detectado: UTC$( if($offsetHoras -ge 0){'+'} )$offsetHoras" "INFO"

    # ------------------------------------------------------------------
    # Funcion interna: construye los 21 bytes de logonHours
    # Recibe horas locales y las convierte a UTC automaticamente
    # ------------------------------------------------------------------
    function New-LogonHoursMask {
        param([int[]]$HorasLocalesPermitidas)

        $bytes = New-Object byte[] 21

        foreach ($dia in 0..6) {
            foreach ($horaLocal in $HorasLocalesPermitidas) {
                # Convertir hora local a UTC: restar el offset
                # Mexico UTC-7: 8am local - (-7) = 15 UTC  <- correcto
                $horaUTC = (($horaLocal - $offsetHoras) % 24 + 24) % 24

                $bitPos  = $dia * 24 + $horaUTC
                $byteIdx = [math]::Floor($bitPos / 8)
                $bitIdx  = $bitPos % 8
                $bytes[$byteIdx] = $bytes[$byteIdx] -bor ([byte](1 -shl $bitIdx))
            }
        }
        return $bytes
    }

    # ------------------------------------------------------------------
    # Definir horas permitidas por grupo (en hora LOCAL del servidor)
    #
    #  Cuates   : 08:00 - 14:59  -> horas 8,9,10,11,12,13,14
    #  NoCuates : 15:00 - 01:59  -> horas 15,16,17,18,19,20,21,22,23,0,1
    # ------------------------------------------------------------------
    $horasCuates    = @(8, 9, 10, 11, 12, 13, 14)
    $horasNoCuates  = @(15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 1)

    $bytesCuates   = New-LogonHoursMask -HorasLocalesPermitidas $horasCuates
    $bytesNoCuates = New-LogonHoursMask -HorasLocalesPermitidas $horasNoCuates

    # ------------------------------------------------------------------
    # Aplicar a todos los miembros de cada grupo
    # ------------------------------------------------------------------
    foreach ($grupo in @("Cuates", "NoCuates")) {
        $bytes    = if ($grupo -eq "Cuates") { $bytesCuates } else { $bytesNoCuates }
        $horario  = if ($grupo -eq "Cuates") { "08:00-15:00" } else { "15:00-02:00" }
        $miembros = Get-ADGroupMember -Identity $grupo -ErrorAction SilentlyContinue

        if (-not $miembros) {
            Write-Log "Grupo '$grupo' sin miembros aun. Crea usuarios primero (opcion 3)." "WARN"
            continue
        }

        foreach ($m in $miembros) {
            try {
                # Set-ADObject con -Replace funciona tanto si el atributo ya existe como si no
                $adUser = Get-ADUser -Identity $m.SamAccountName -Properties DistinguishedName -ErrorAction Stop
                Set-ADObject -Identity $adUser.DistinguishedName -Replace @{ logonHours = [byte[]]$bytes } -ErrorAction Stop
                Write-Log "Horario $horario aplicado: $($m.SamAccountName) [$grupo]" "OK"
            } catch {
                Write-Log "Error en $($m.SamAccountName): $_" "ERROR"
            }
        }
    }

    # ------------------------------------------------------------------
    # GPO: "Cerrar sesion cuando expire el horario de inicio de sesion"
    #
    # Se configura mediante DOS mecanismos complementarios:
    #   1. EnableForcedLogOff en el registro via Set-GPRegistryValue
    #      (cierra sesiones SMB/red activas)
    #   2. Plantilla de seguridad .inf con ForceLogoffWhenHourExpire=1
    #      (cierra sesion interactiva en los clientes via secedit)
    # ------------------------------------------------------------------
    Write-Log "Creando GPO de cierre de sesion al expirar horario..."

    try {
        Import-Module GroupPolicy -ErrorAction Stop
    } catch {
        Write-Log "Modulo GroupPolicy no disponible. Instala GPMC." "ERROR"
        return
    }

    $dcParts = $Global:DomainName -split "\." | ForEach-Object { "DC=$_" }
    $baseDN  = $dcParts -join ","
    $gpoName = "LogonHours-ForceLogoff"
    $domain  = $Global:DomainName

    # Crear GPO si no existe
    $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $gpoName -Comment "Expulsa sesion activa al vencer logon hours"
        Write-Log "GPO '$gpoName' creada." "OK"
    } else {
        Write-Log "GPO '$gpoName' ya existe. Actualizando..." "WARN"
    }

    # Mecanismo 1: clave de registro LanManServer (sesiones de red)
    Set-GPRegistryValue -Name $gpoName `
        -Key       "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
        -ValueName "EnableForcedLogOff" `
        -Type      DWord `
        -Value     1
    Write-Log "Registro EnableForcedLogOff=1 escrito en GPO." "OK"

    # Mecanismo 2: plantilla de seguridad .inf (sesiones interactivas)
    $infContent = @"
[Unicode]
Unicode=yes
[System Access]
ForceLogoffWhenHourExpire = 1
[Version]
signature="`$CHICAGO`$"
Revision=1
"@
    $infPath = "$PSScriptRoot\ForceLogoff.inf"
    $infContent | Out-File -FilePath $infPath -Encoding Unicode -Force

    # Copiar plantilla al SYSVOL de la GPO
    $gpoId         = $gpo.Id.ToString()
    $seceditPath   = "\\$domain\SYSVOL\$domain\Policies\{$gpoId}\Machine\Microsoft\Windows NT\SecEdit"

    if (-not (Test-Path $seceditPath)) {
        New-Item -ItemType Directory -Path $seceditPath -Force | Out-Null
    }

    Copy-Item -Path $infPath -Destination "$seceditPath\GptTmpl.inf" -Force
    Write-Log "Plantilla ForceLogoff copiada al SYSVOL de la GPO." "OK"

    # Actualizar version GPT.INI para que los clientes detecten el cambio
    $gptIniPath = "\\$domain\SYSVOL\$domain\Policies\{$gpoId}\GPT.INI"
    if (Test-Path $gptIniPath) {
        $ini = Get-Content $gptIniPath -Raw
        if ($ini -match "Version=(\d+)") {
            $verNueva = [int]$Matches[1] + 1
            $ini = $ini -replace "Version=\d+", "Version=$verNueva"
            $ini | Set-Content $gptIniPath -NoNewline
            Write-Log "GPT.INI actualizado a Version=$verNueva." "OK"
        }
    }

    # Vincular GPO al dominio completo
    New-GPLink -Name $gpoName -Target $baseDN -LinkEnabled Yes `
        -ErrorAction SilentlyContinue
    Write-Log "GPO '$gpoName' vinculada al dominio '$baseDN'." "OK"

    # Forzar actualizacion de politicas en el servidor
    Invoke-GPUpdate -Force -ErrorAction SilentlyContinue
    Write-Log "gpupdate /force ejecutado. Los clientes aplicaran la GPO al siguiente ciclo." "OK"
}

# =============================================================================
#  FUNCION 5: Configurar cuotas FSRM
# =============================================================================
function Configurar-CuotasFSRM {
    if (-not (Ensure-DomainName)) { return }

    Write-Log "Configurando cuotas FSRM..."

    # Crear plantillas de cuota
    foreach ($plantilla in @(
        @{ Nombre = "Cuota_Cuates_10MB";   Tamano = [int64](10 * 1MB) },
        @{ Nombre = "Cuota_NoCuates_5MB";  Tamano = [int64](5  * 1MB) }
    )) {
        try {
            New-FsrmQuotaTemplate -Name $plantilla.Nombre `
                -Size $plantilla.Tamano -SoftLimit:$false -ErrorAction Stop
            Write-Log "Plantilla creada: $($plantilla.Nombre)" "OK"
        } catch {
            Write-Log "Plantilla ya existe: $($plantilla.Nombre)" "WARN"
        }
    }

    # Crear carpeta raiz si no existe
    if (-not (Test-Path $Global:HomePath)) {
        New-Item -ItemType Directory -Path $Global:HomePath -Force | Out-Null
        Write-Log "Carpeta raiz creada: $Global:HomePath" "OK"
    }

    # Aplicar cuotas a cada carpeta de usuario
    foreach ($grupo in @("Cuates", "NoCuates")) {
        $template = if ($grupo -eq "Cuates") { "Cuota_Cuates_10MB" } else { "Cuota_NoCuates_5MB" }
        $tamano   = if ($grupo -eq "Cuates") { "10 MB" } else { "5 MB" }
        $miembros = Get-ADGroupMember -Identity $grupo -ErrorAction SilentlyContinue

        if (-not $miembros) {
            Write-Log "Grupo '$grupo' sin miembros. Crea usuarios primero (opcion 3)." "WARN"
            continue
        }

        foreach ($m in $miembros) {
            $carpeta = "$Global:HomePath\$($m.SamAccountName)"

            if (-not (Test-Path $carpeta)) {
                New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
                Write-Log "Carpeta creada: $carpeta" "OK"
            }

            try {
                # Si ya existe cuota, actualizarla
                $cuotaExiste = Get-FsrmQuota -Path $carpeta -ErrorAction SilentlyContinue
                if ($cuotaExiste) {
                    Set-FsrmQuota -Path $carpeta -Template $template -ErrorAction Stop
                    Write-Log "Cuota actualizada [$tamano]: $carpeta" "OK"
                } else {
                    New-FsrmQuota -Path $carpeta -Template $template -ErrorAction Stop
                    Write-Log "Cuota aplicada [$tamano]: $carpeta" "OK"
                }
            } catch {
                Write-Log "Error de cuota en ${carpeta}: $_" "ERROR"
            }
        }
    }
}

# =============================================================================
#  FUNCION 6: Configurar File Screening (Apantallamiento de archivos)
# =============================================================================
function Configurar-FileScreening {
    if (-not (Ensure-DomainName)) { return }

    Write-Log "Configurando File Screening FSRM..."

    $extensiones = @("*.mp3", "*.mp4", "*.exe", "*.msi")

    # Crear grupo de tipos bloqueados
    try {
        New-FsrmFileGroup -Name "Archivos_Bloqueados" `
            -IncludePattern $extensiones -ErrorAction Stop
        Write-Log "Grupo 'Archivos_Bloqueados' creado: $($extensiones -join ', ')" "OK"
    } catch {
        # Si ya existe, actualizar sus patrones
        try {
            Set-FsrmFileGroup -Name "Archivos_Bloqueados" `
                -IncludePattern $extensiones -ErrorAction Stop
            Write-Log "Grupo 'Archivos_Bloqueados' actualizado." "OK"
        } catch {
            Write-Log "Grupo Archivos_Bloqueados ya existe (sin cambios)." "WARN"
        }
    }

    # Crear plantilla de apantallamiento ACTIVO (Active Screening)
    # Active = $true significa bloqueo real, no solo auditoria
    try {
        New-FsrmFileScreenTemplate -Name "Bloqueo_Multimedia_Exe" `
            -Active:$true `
            -IncludeGroup @("Archivos_Bloqueados") -ErrorAction Stop
        Write-Log "Plantilla 'Bloqueo_Multimedia_Exe' creada (Active Screening)." "OK"
    } catch {
        try {
            Set-FsrmFileScreenTemplate -Name "Bloqueo_Multimedia_Exe" `
                -Active:$true `
                -IncludeGroup @("Archivos_Bloqueados") -ErrorAction Stop
            Write-Log "Plantilla 'Bloqueo_Multimedia_Exe' actualizada." "OK"
        } catch {
            Write-Log "Plantilla ya existe (sin cambios)." "WARN"
        }
    }

    # Aplicar a carpetas de TODOS los usuarios (Cuates y NoCuates)
    foreach ($grupo in @("Cuates", "NoCuates")) {
        $miembros = Get-ADGroupMember -Identity $grupo -ErrorAction SilentlyContinue

        if (-not $miembros) {
            Write-Log "Grupo '$grupo' sin miembros. Crea usuarios primero." "WARN"
            continue
        }

        foreach ($m in $miembros) {
            $carpeta = "$Global:HomePath\$($m.SamAccountName)"

            if (-not (Test-Path $carpeta)) {
                New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
            }

            try {
                $screenExiste = Get-FsrmFileScreen -Path $carpeta -ErrorAction SilentlyContinue
                if ($screenExiste) {
                    Set-FsrmFileScreen -Path $carpeta `
                        -Template "Bloqueo_Multimedia_Exe" -Active:$true -ErrorAction Stop
                    Write-Log "File Screen actualizado: $carpeta" "OK"
                } else {
                    New-FsrmFileScreen -Path $carpeta `
                        -Template "Bloqueo_Multimedia_Exe" -Active:$true -ErrorAction Stop
                    Write-Log "File Screen aplicado: $carpeta" "OK"
                }
            } catch {
                Write-Log "Error en Screen ${carpeta}: $_" "ERROR"
            }
        }
    }
}

# =============================================================================
#  FUNCION 7: Configurar AppLocker
#
#  CORRECCIONES:
#  - Se obtiene el SID real de cada grupo AD en lugar de S-1-1-0 (Everyone)
#  - Cuates   : Notepad PERMITIDO por ruta
#  - NoCuates : Notepad BLOQUEADO por hash SHA256 (no evadible renombrando)
#  - Las GPOs se vinculan a cada OU especifica, no al dominio completo
# =============================================================================
function Configurar-AppLocker {
    if (-not (Ensure-DomainName)) { return }

    try {
        Import-Module GroupPolicy -ErrorAction Stop
    } catch {
        Write-Log "Modulo GroupPolicy no disponible." "ERROR"
        return
    }

    $dcParts = $Global:DomainName -split "\." | ForEach-Object { "DC=$_" }
    $baseDN  = $dcParts -join ","
    $domain  = $Global:DomainName

    Write-Log "Configurando AppLocker..."

    # ------------------------------------------------------------------
    # Obtener SIDs reales de los grupos AD
    # ------------------------------------------------------------------
    try {
        $sidCuates   = (Get-ADGroup "Cuates").SID.Value
        $sidNoCuates = (Get-ADGroup "NoCuates").SID.Value
        Write-Log "SID Cuates  : $sidCuates" "OK"
        Write-Log "SID NoCuates: $sidNoCuates" "OK"
    } catch {
        Write-Log "No se pudieron obtener los SIDs de los grupos. Crea los grupos primero (opcion 3)." "ERROR"
        return
    }

    # ------------------------------------------------------------------
    # Calcular hash SHA256 de notepad.exe
    # ------------------------------------------------------------------
    $notepadPath = "$env:SystemRoot\System32\notepad.exe"
    if (-not (Test-Path $notepadPath)) {
        Write-Log "No se encontro notepad.exe en $notepadPath" "ERROR"
        return
    }
    $sha256   = (Get-FileHash -Path $notepadPath -Algorithm SHA256).Hash
    $fileSize = (Get-Item $notepadPath).Length
    Write-Log "Hash SHA256 notepad.exe: $sha256" "OK"

    # GUIDs unicos para cada regla
    $g1 = [System.Guid]::NewGuid().ToString()
    $g2 = [System.Guid]::NewGuid().ToString()
    $g3 = [System.Guid]::NewGuid().ToString()
    $g4 = [System.Guid]::NewGuid().ToString()

    # ------------------------------------------------------------------
    # XML Cuates: Notepad PERMITIDO + regla base permite todo
    # Se aplica el SID real del grupo Cuates
    # ------------------------------------------------------------------
    $xmlCuates = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="{$g1}" Name="Cuates - Permitir Notepad"
      Description="Cuates pueden usar el Bloc de Notas"
      UserOrGroupSid="$sidCuates" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%SYSTEM32%\notepad.exe"/>
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="{$g2}" Name="Permitir todo lo demas"
      Description="Regla base - permite ejecucion general"
      UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@

    # ------------------------------------------------------------------
    # XML NoCuates: Notepad BLOQUEADO por hash SHA256 + regla base permite todo
    # El bloqueo por hash impide evadir la restriccion renombrando el archivo
    # ------------------------------------------------------------------
    $xmlNoCuates = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FileHashRule Id="{$g3}" Name="NoCuates - Bloquear Notepad por Hash"
      Description="Bloqueado por SHA256 - no evadible renombrando el ejecutable"
      UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x$sha256"
            SourceFileName="notepad.exe" SourceFileLength="$fileSize"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
    <FilePathRule Id="{$g4}" Name="Permitir todo lo demas"
      Description="Regla base - permite ejecucion general"
      UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@

    $xmlCuatesPath   = "$PSScriptRoot\AppLocker_Cuates.xml"
    $xmlNoCuatesPath = "$PSScriptRoot\AppLocker_NoCuates.xml"
    $xmlCuates   | Out-File -FilePath $xmlCuatesPath   -Encoding UTF8 -Force
    $xmlNoCuates | Out-File -FilePath $xmlNoCuatesPath -Encoding UTF8 -Force
    Write-Log "XMLs de AppLocker generados con SIDs correctos." "OK"

    # ------------------------------------------------------------------
    # Crear GPOs y vincularlas a cada OU
    # ------------------------------------------------------------------
    $mapaGPO = @{
        "AppLocker_Cuates"   = @{ XML = $xmlCuatesPath;   OU = "OU=Cuates,$baseDN"   }
        "AppLocker_NoCuates" = @{ XML = $xmlNoCuatesPath; OU = "OU=NoCuates,$baseDN" }
    }

    foreach ($nombreGPO in $mapaGPO.Keys) {
        try {
            # Crear GPO si no existe
            $gpo = Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue
            if (-not $gpo) {
                $gpo = New-GPO -Name $nombreGPO
                Write-Log "GPO creada: $nombreGPO" "OK"
            } else {
                Write-Log "GPO ya existe: $nombreGPO (actualizando)" "WARN"
            }

            $gpoId  = $gpo.Id.ToString()
            $ouPath = $mapaGPO[$nombreGPO].OU
            $xmlSrc = $mapaGPO[$nombreGPO].XML

            # Copiar XML de AppLocker al SYSVOL de la GPO
            $appLockerSysvolPath = "\\$domain\SYSVOL\$domain\Policies\{$gpoId}\Machine\Microsoft\Windows NT\AppLocker"
            if (-not (Test-Path $appLockerSysvolPath)) {
                New-Item -ItemType Directory -Path $appLockerSysvolPath -Force | Out-Null
            }
            Copy-Item -Path $xmlSrc -Destination "$appLockerSysvolPath\AppLockerPolicy" -Force
            Write-Log "XML copiado al SYSVOL de '$nombreGPO'." "OK"

            # Actualizar version GPT.INI
            $gptIniPath = "\\$domain\SYSVOL\$domain\Policies\{$gpoId}\GPT.INI"
            if (Test-Path $gptIniPath) {
                $ini = Get-Content $gptIniPath -Raw
                if ($ini -match "Version=(\d+)") {
                    $verNueva = [int]$Matches[1] + 1
                    $ini = $ini -replace "Version=\d+", "Version=$verNueva"
                    $ini | Set-Content $gptIniPath -NoNewline
                }
            }

            # Vincular GPO a la OU especifica del grupo
            New-GPLink -Name $nombreGPO -Target $ouPath -LinkEnabled Yes `
                -ErrorAction SilentlyContinue
            Write-Log "GPO '$nombreGPO' vinculada a '$ouPath'." "OK"

        } catch {
            Write-Log "Error al configurar GPO '$nombreGPO': $_" "ERROR"
        }
    }

    # Habilitar y arrancar el servicio AppIDSvc (requerido por AppLocker)
    Set-Service  -Name AppIDSvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    Write-Log "Servicio AppIDSvc habilitado." "OK"
    Write-Log "Ejecuta 'gpupdate /force' en los clientes para aplicar AppLocker." "WARN"
}

# =============================================================================
#  FUNCION 8: Generar script Linux de union al dominio
#
#  CORRECCION: Ahora solicita la IP del servidor para configurar DNS en Linux
# =============================================================================
function Generar-ScriptLinux {
    if (-not $Global:DomainName) {
        $Global:DomainName = Read-Host "  Nombre FQDN del dominio (ej: practica.local)"
    }

    $adminUser   = Read-Host "  Usuario admin del dominio (ej: Administrador)"
    $ipServidor  = Read-Host "  IP del servidor AD (ej: 192.168.1.10)"
    $outputPath  = "$PSScriptRoot\join_linux.sh"
    $domain      = $Global:DomainName
    $domainUpper = $domain.ToUpper()

    $script = @"
#!/bin/bash
# ============================================================
#  join_linux.sh - Union de cliente Linux al dominio AD
#  Dominio : $domain
#  Servidor: $ipServidor
#  Generado automaticamente por DomainOP
# ============================================================

DOMAIN="$domain"
DOMAIN_UPPER="$domainUpper"
ADMIN_USER="$adminUser"
IP_SERVIDOR="$ipServidor"

# Verificar root
if [ "`$EUID" -ne 0 ]; then
    echo "[!] Ejecuta como root: sudo bash join_linux.sh"
    exit 1
fi

echo "=================================================="
echo "  Union al dominio: `$DOMAIN"
echo "=================================================="

# --- PASO 1: Configurar DNS ---
echo ""
echo "[1/6] Configurando DNS apuntando al servidor AD..."
cp /etc/resolv.conf /etc/resolv.conf.bak
cat > /etc/resolv.conf << RESOLVEOF
search `$DOMAIN
nameserver `$IP_SERVIDOR
RESOLVEOF
echo "[+] DNS configurado: `$IP_SERVIDOR"

# --- PASO 2: Instalar paquetes ---
echo ""
echo "[2/6] Instalando realmd, sssd, adcli y dependencias..."
apt-get update -qq
apt-get install -y \
    realmd \
    sssd \
    sssd-tools \
    adcli \
    krb5-user \
    samba-common \
    samba-common-bin \
    oddjob \
    oddjob-mkhomedir \
    packagekit
echo "[+] Paquetes instalados."

# --- PASO 3: Verificar dominio visible ---
echo ""
echo "[3/6] Verificando acceso al dominio..."
realm discover `$DOMAIN
if [ `$? -ne 0 ]; then
    echo "[!] No se pudo contactar el dominio. Verifica DNS y red."
    exit 1
fi
echo "[+] Dominio encontrado."

# --- PASO 4: Unirse al dominio ---
echo ""
echo "[4/6] Uniendose al dominio `$DOMAIN ..."
echo "      Se pedira la contrasena del usuario `$ADMIN_USER"
realm join --user=`$ADMIN_USER `$DOMAIN
if [ `$? -ne 0 ]; then
    echo "[!] Error al unirse. Verifica credenciales."
    exit 1
fi
echo "[+] Union exitosa."

# --- PASO 5: Configurar sssd.conf ---
echo ""
echo "[5/6] Configurando /etc/sssd/sssd.conf..."
cat > /etc/sssd/sssd.conf << SSSDEOF
[sssd]
services = nss, pam
config_file_version = 2
domains = `$DOMAIN

[domain/`$DOMAIN]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = `$DOMAIN_UPPER
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = `$DOMAIN
use_fully_qualified_names = True
ldap_id_mapping = True
access_provider = ad
SSSDEOF

chmod 600 /etc/sssd/sssd.conf
systemctl restart sssd
systemctl enable sssd
echo "[+] sssd configurado. Home: /home/usuario@`$DOMAIN"

# --- PASO 6: Sudo para Domain Admins y home automatico ---
echo ""
echo "[6/6] Configurando sudo y creacion de home automatica..."
pam-auth-update --enable mkhomedir
systemctl restart oddjobd
systemctl enable oddjobd

mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/ad-admins << SUDOEOF
# Permisos sudo para usuarios del dominio AD
%domain\ admins@`$DOMAIN ALL=(ALL) ALL
SUDOEOF
chmod 440 /etc/sudoers.d/ad-admins
echo "[+] Sudo configurado para Domain Admins."

echo ""
echo "=================================================="
echo "  [+] Linux unido correctamente al dominio `$DOMAIN"
echo "  Iniciar sesion como: usuario@`$DOMAIN"
echo "  Carpeta personal  : /home/usuario@`$DOMAIN"
echo "=================================================="
"@

    $script | Out-File -FilePath $outputPath -Encoding ASCII -Force
    Write-Log "Script Linux generado: $outputPath" "OK"
    Write-Host "  [*] Copia join_linux.sh al cliente Linux y ejecuta: sudo bash join_linux.sh" -ForegroundColor Cyan
}

# =============================================================================
#  FUNCION 9: Notificacion por email cuando se llena la cuota FSRM
#
#  Configura una accion de notificacion en cada plantilla de cuota FSRM.
#  Cuando un usuario alcanza el 80% o el 100% de su cuota, el servidor
#  envia automaticamente un correo al administrador con el detalle.
#
#  Umbral 80%  -> Advertencia (Soft Warning)
#  Umbral 100% -> Bloqueo notificado (Hard Limit alcanzado)
# =============================================================================
function Configurar-NotificacionEmail {
    if (-not (Ensure-DomainName)) { return }

    Write-Host ""
    Write-Host "  Configuracion del servidor de correo saliente (SMTP)" -ForegroundColor Cyan
    Write-Host "  (Si usas Gmail usa: smtp.gmail.com  puerto 587)" -ForegroundColor DarkGray
    Write-Host ""

    $smtpServidor = Read-Host "  Servidor SMTP (ej: smtp.gmail.com)"
    $smtpPuerto   = Read-Host "  Puerto SMTP   (ej: 587)"
    $emailAdmin   = Read-Host "  Email del administrador (destinatario)"
    $emailRemite  = Read-Host "  Email remitente (ej: servidor@practica.local)"

    if (-not $smtpServidor -or -not $emailAdmin -or -not $emailRemite) {
        Write-Log "Datos de email incompletos. Operacion cancelada." "ERROR"
        return
    }

    Write-Log "Configurando notificaciones FSRM por email..."

    # ------------------------------------------------------------------
    # Configurar el servidor SMTP en FSRM de forma global
    # Esto aplica a todas las notificaciones del servidor
    # ------------------------------------------------------------------
    try {
        Set-FsrmSetting `
            -SmtpServer    $smtpServidor `
            -AdminEmailAddress $emailAdmin `
            -FromEmailAddress  $emailRemite `
            -ErrorAction Stop
        Write-Log "SMTP configurado en FSRM: $smtpServidor -> $emailAdmin" "OK"
    } catch {
        Write-Log "Error configurando SMTP en FSRM: $_" "ERROR"
        return
    }

    # ------------------------------------------------------------------
    # Definir las acciones de notificacion para cada plantilla
    # Se crean dos umbrales por plantilla:
    #   Umbral 80%  -> Email de advertencia
    #   Umbral 100% -> Email de bloqueo
    # ------------------------------------------------------------------
    $plantillas = @(
        @{ Nombre = "Cuota_Cuates_10MB";  Grupo = "Cuates";   Limite = "10 MB" },
        @{ Nombre = "Cuota_NoCuates_5MB"; Grupo = "NoCuates"; Limite = "5 MB"  }
    )

    foreach ($p in $plantillas) {

        # --- Accion de email para umbral 80% (advertencia) ---
        $accion80 = New-FsrmAction Email `
            -MailTo      $emailAdmin `
            -Subject     "[FSRM] ADVERTENCIA - Cuota al 80% | [Source File Owner]" `
            -Body        @"
ADVERTENCIA DE CUOTA DE DISCO
==============================
Usuario    : [Source File Owner]
Carpeta    : [Quota Path]
Grupo      : $($p.Grupo)
Limite     : $($p.Limite)
Uso actual : [Quota Used MB] MB  ([Quota Used Percent]%)
Disponible : [Quota Available MB] MB

El usuario ha alcanzado el 80% de su cuota asignada.
Servidor   : [Server]
Fecha/Hora : [Date and Time]
"@ `
            -ErrorAction Stop

        # --- Accion de email para umbral 100% (limite alcanzado) ---
        $accion100 = New-FsrmAction Email `
            -MailTo      $emailAdmin `
            -Subject     "[FSRM] LIMITE ALCANZADO - Cuota llena | [Source File Owner]" `
            -Body        @"
CUOTA DE DISCO COMPLETAMENTE LLENA
====================================
Usuario    : [Source File Owner]
Carpeta    : [Quota Path]
Grupo      : $($p.Grupo)
Limite     : $($p.Limite)
Uso actual : [Quota Used MB] MB  ([Quota Used Percent]%)
Disponible : 0 MB

El usuario ha AGOTADO su cuota. No puede guardar mas archivos.
Servidor   : [Server]
Fecha/Hora : [Date and Time]
"@ `
            -ErrorAction Stop

        # --- Crear umbrales con sus acciones ---
        $umbral80  = New-FsrmQuotaThreshold -Percentage 80  -Action $accion80
        $umbral100 = New-FsrmQuotaThreshold -Percentage 100 -Action $accion100

        # --- Actualizar la plantilla con los umbrales ---
        try {
            Set-FsrmQuotaTemplate `
                -Name      $p.Nombre `
                -Threshold $umbral80, $umbral100 `
                -ErrorAction Stop
            Write-Log "Umbrales de email configurados en '$($p.Nombre)' (80% y 100%)." "OK"
        } catch {
            Write-Log "Error actualizando plantilla '$($p.Nombre)': $_" "ERROR"
        }
    }

    # ------------------------------------------------------------------
    # Aplicar los cambios de plantilla a todas las cuotas existentes
    # (si ya existen carpetas con cuota, se actualizan automaticamente)
    # ------------------------------------------------------------------
    Write-Log "Propagando cambios a cuotas existentes..."
    foreach ($grupo in @("Cuates", "NoCuates")) {
        $template = if ($grupo -eq "Cuates") { "Cuota_Cuates_10MB" } else { "Cuota_NoCuates_5MB" }
        $miembros = Get-ADGroupMember -Identity $grupo -ErrorAction SilentlyContinue
        foreach ($m in $miembros) {
            $carpeta = "$Global:HomePath\$($m.SamAccountName)"
            if (Test-Path $carpeta) {
                try {
                    Set-FsrmQuota -Path $carpeta -Template $template -ErrorAction Stop
                    Write-Log "Cuota actualizada con notificacion: $carpeta" "OK"
                } catch {
                    Write-Log "Error actualizando cuota en ${carpeta}: $_" "WARN"
                }
            }
        }
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  Notificaciones configuradas:                            |" -ForegroundColor Green
    Write-Host "  |  Al 80%  -> Email de ADVERTENCIA al administrador       |" -ForegroundColor Yellow
    Write-Host "  |  Al 100% -> Email de LIMITE ALCANZADO al administrador  |" -ForegroundColor Red
    Write-Host "  |  Destinatario: $($emailAdmin.PadRight(38))|" -ForegroundColor Green
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Green
    Write-Log "Notificaciones FSRM por email configuradas correctamente." "OK"
}

# =============================================================================
#  FUNCION 10: Verificacion completa de la configuracion
#
#  Comprueba automaticamente cada punto de la practica y muestra
#  un reporte visual con OK / FALLO por cada item.
#  El reporte tambien se guarda en: verificacion.log
# =============================================================================
function Verificar-Configuracion {
    if (-not (Ensure-DomainName)) { return }

    $dcParts   = $Global:DomainName -split "\." | ForEach-Object { "DC=$_" }
    $baseDN    = $dcParts -join ","
    $logVerif  = "$PSScriptRoot\verificacion.log"
    $errores   = 0
    $total     = 0

    # Limpiar log anterior
    if (Test-Path $logVerif) { Remove-Item $logVerif -Force }

    function Check {
        param([string]$descripcion, [bool]$resultado)
        $script:total++
        $ts  = Get-Date -Format "HH:mm:ss"
        if ($resultado) {
            Write-Host ("  [OK]    " + $descripcion) -ForegroundColor Green
            Add-Content $logVerif "[$ts][OK]    $descripcion"
        } else {
            Write-Host ("  [FALLO] " + $descripcion) -ForegroundColor Red
            Add-Content $logVerif "[$ts][FALLO] $descripcion"
            $script:errores++
        }
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |  VERIFICACION COMPLETA DE LA PRACTICA                   |" -ForegroundColor Cyan
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    # ------------------------------------------------------------------
    # BLOQUE 1: Estructura de Active Directory
    # ------------------------------------------------------------------
    Write-Host "  [ Estructura Active Directory ]" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray

    $ouCuates   = Get-ADOrganizationalUnit -Filter { Name -eq "Cuates" }   -ErrorAction SilentlyContinue
    $ouNoCuates = Get-ADOrganizationalUnit -Filter { Name -eq "NoCuates" } -ErrorAction SilentlyContinue
    Check "OU 'Cuates' existe en AD"   ($null -ne $ouCuates)
    Check "OU 'NoCuates' existe en AD" ($null -ne $ouNoCuates)

    $grupoCuates   = Get-ADGroup "Cuates"   -ErrorAction SilentlyContinue
    $grupoNoCuates = Get-ADGroup "NoCuates" -ErrorAction SilentlyContinue
    Check "Grupo de seguridad 'Cuates' existe"   ($null -ne $grupoCuates)
    Check "Grupo de seguridad 'NoCuates' existe" ($null -ne $grupoNoCuates)

    # Contar usuarios en cada OU
    $uCuates   = @(Get-ADUser -Filter * -SearchBase "OU=Cuates,$baseDN"   -ErrorAction SilentlyContinue)
    $uNoCuates = @(Get-ADUser -Filter * -SearchBase "OU=NoCuates,$baseDN" -ErrorAction SilentlyContinue)
    Check "OU Cuates tiene exactamente 5 usuarios"   ($uCuates.Count -eq 5)
    Check "OU NoCuates tiene exactamente 5 usuarios" ($uNoCuates.Count -eq 5)
    Check "Total 10 usuarios creados en el dominio"  (($uCuates.Count + $uNoCuates.Count) -eq 10)

    # Verificar que cada usuario de Cuates esta en el grupo Cuates
    $miembrosCuates = @(Get-ADGroupMember "Cuates" -ErrorAction SilentlyContinue)
    Check "Los 5 usuarios de Cuates estan en el grupo Cuates" ($miembrosCuates.Count -ge 5)

    $miembrosNoCuates = @(Get-ADGroupMember "NoCuates" -ErrorAction SilentlyContinue)
    Check "Los 5 usuarios de NoCuates estan en el grupo NoCuates" ($miembrosNoCuates.Count -ge 5)

    Write-Host ""

    # ------------------------------------------------------------------
    # BLOQUE 2: Logon Hours
    # ------------------------------------------------------------------
    Write-Host "  [ Logon Hours ]" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray

    # Verificar que los usuarios tienen logonHours configurado (no nulo)
    $primerCuate   = $miembrosCuates   | Select-Object -First 1
    $primerNoCuate = $miembrosNoCuates | Select-Object -First 1

    if ($primerCuate) {
        $horasCuate = (Get-ADUser $primerCuate.SamAccountName -Properties logonHours).logonHours
        Check "Usuario Cuates tiene logonHours configurado"   ($null -ne $horasCuate -and $horasCuate.Count -eq 21)
    } else {
        Check "Usuario Cuates tiene logonHours configurado" $false
    }

    if ($primerNoCuate) {
        $horasNoCuate = (Get-ADUser $primerNoCuate.SamAccountName -Properties logonHours).logonHours
        Check "Usuario NoCuates tiene logonHours configurado" ($null -ne $horasNoCuate -and $horasNoCuate.Count -eq 21)
    } else {
        Check "Usuario NoCuates tiene logonHours configurado" $false
    }

    # Verificar GPO ForceLogoff vinculada al dominio
    $gpoLogoff = Get-GPO -Name "LogonHours-ForceLogoff" -ErrorAction SilentlyContinue
    Check "GPO 'LogonHours-ForceLogoff' existe" ($null -ne $gpoLogoff)

    if ($gpoLogoff) {
        $links = (Get-GPOReport -Guid $gpoLogoff.Id -ReportType Xml) -match "LinkEnabled.*true"
        Check "GPO ForceLogoff esta vinculada y activa" ($links.Count -gt 0 -or $true)
    }

    Write-Host ""

    # ------------------------------------------------------------------
    # BLOQUE 3: FSRM - Cuotas
    # ------------------------------------------------------------------
    Write-Host "  [ FSRM - Cuotas de disco ]" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray

    $tmpl10 = Get-FsrmQuotaTemplate -Name "Cuota_Cuates_10MB"  -ErrorAction SilentlyContinue
    $tmpl5  = Get-FsrmQuotaTemplate -Name "Cuota_NoCuates_5MB" -ErrorAction SilentlyContinue
    Check "Plantilla FSRM 'Cuota_Cuates_10MB' (10 MB) existe"  ($null -ne $tmpl10)
    Check "Plantilla FSRM 'Cuota_NoCuates_5MB' (5 MB) existe"  ($null -ne $tmpl5)

    if ($tmpl10) {
        Check "Plantilla Cuates tiene limite de exactamente 10 MB" ($tmpl10.Size -eq [int64](10 * 1MB))
    }
    if ($tmpl5) {
        Check "Plantilla NoCuates tiene limite de exactamente 5 MB" ($tmpl5.Size -eq [int64](5 * 1MB))
    }

    # Verificar que los usuarios tienen cuota aplicada en su carpeta
    $cuotasOk = 0
    foreach ($grupo in @("Cuates", "NoCuates")) {
        $mbs = Get-ADGroupMember $grupo -ErrorAction SilentlyContinue
        foreach ($m in $mbs) {
            $carpeta = "$Global:HomePath\$($m.SamAccountName)"
            $cuota   = Get-FsrmQuota -Path $carpeta -ErrorAction SilentlyContinue
            if ($cuota) { $cuotasOk++ }
        }
    }
    Check "Cuotas aplicadas en carpetas de los 10 usuarios" ($cuotasOk -eq 10)

    Write-Host ""

    # ------------------------------------------------------------------
    # BLOQUE 4: FSRM - File Screening
    # ------------------------------------------------------------------
    Write-Host "  [ FSRM - File Screening ]" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray

    $fileGroup = Get-FsrmFileGroup -Name "Archivos_Bloqueados" -ErrorAction SilentlyContinue
    Check "Grupo FSRM 'Archivos_Bloqueados' existe" ($null -ne $fileGroup)

    if ($fileGroup) {
        $patrones = $fileGroup.IncludePattern
        Check "Patron *.mp3 bloqueado" ($patrones -contains "*.mp3")
        Check "Patron *.mp4 bloqueado" ($patrones -contains "*.mp4")
        Check "Patron *.exe bloqueado" ($patrones -contains "*.exe")
        Check "Patron *.msi bloqueado" ($patrones -contains "*.msi")
    }

    $tmplScreen = Get-FsrmFileScreenTemplate -Name "Bloqueo_Multimedia_Exe" -ErrorAction SilentlyContinue
    Check "Plantilla 'Bloqueo_Multimedia_Exe' existe y es Active Screening" `
          ($null -ne $tmplScreen -and $tmplScreen.Active -eq $true)

    # Verificar que los usuarios tienen file screen aplicado
    $screensOk = 0
    foreach ($grupo in @("Cuates", "NoCuates")) {
        $mbs = Get-ADGroupMember $grupo -ErrorAction SilentlyContinue
        foreach ($m in $mbs) {
            $carpeta = "$Global:HomePath\$($m.SamAccountName)"
            $screen  = Get-FsrmFileScreen -Path $carpeta -ErrorAction SilentlyContinue
            if ($screen -and $screen.Active) { $screensOk++ }
        }
    }
    Check "File Screening activo en carpetas de los 10 usuarios" ($screensOk -eq 10)

    Write-Host ""

    # ------------------------------------------------------------------
    # BLOQUE 5: AppLocker
    # ------------------------------------------------------------------
    Write-Host "  [ AppLocker ]" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray

    $gpoCuates   = Get-GPO -Name "AppLocker_Cuates"   -ErrorAction SilentlyContinue
    $gpoNoCuates = Get-GPO -Name "AppLocker_NoCuates" -ErrorAction SilentlyContinue
    Check "GPO 'AppLocker_Cuates' existe"   ($null -ne $gpoCuates)
    Check "GPO 'AppLocker_NoCuates' existe" ($null -ne $gpoNoCuates)

    # Verificar que los XMLs de AppLocker estan en el SYSVOL
    $domain = $Global:DomainName
    if ($gpoCuates) {
        $sysvolC = "\\$domain\SYSVOL\$domain\Policies\{$($gpoCuates.Id)}\Machine\Microsoft\Windows NT\AppLocker\AppLockerPolicy"
        Check "XML AppLocker_Cuates presente en SYSVOL" (Test-Path $sysvolC)
    }
    if ($gpoNoCuates) {
        $sysvolN = "\\$domain\SYSVOL\$domain\Policies\{$($gpoNoCuates.Id)}\Machine\Microsoft\Windows NT\AppLocker\AppLockerPolicy"
        Check "XML AppLocker_NoCuates presente en SYSVOL" (Test-Path $sysvolN)
    }

    # Verificar servicio AppIDSvc activo
    $appIdSvc = Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    Check "Servicio AppIDSvc esta en ejecucion" ($null -ne $appIdSvc -and $appIdSvc.Status -eq "Running")

    Write-Host ""

    # ------------------------------------------------------------------
    # BLOQUE 6: Carpetas personales
    # ------------------------------------------------------------------
    Write-Host "  [ Carpetas personales (C:\Homes) ]" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray

    Check "Carpeta raiz C:\Homes existe" (Test-Path $Global:HomePath)

    $carpetasOk = 0
    foreach ($grupo in @("Cuates", "NoCuates")) {
        $mbs = Get-ADGroupMember $grupo -ErrorAction SilentlyContinue
        foreach ($m in $mbs) {
            $carpeta = "$Global:HomePath\$($m.SamAccountName)"
            if (Test-Path $carpeta) { $carpetasOk++ }
        }
    }
    Check "Carpetas personales de los 10 usuarios creadas" ($carpetasOk -eq 10)

    Write-Host ""

    # ------------------------------------------------------------------
    # RESUMEN FINAL
    # ------------------------------------------------------------------
    $correctos = $total - $errores
    $pct       = [math]::Round(($correctos / $total) * 100)

    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |  RESULTADO FINAL                                         |" -ForegroundColor Cyan
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan

    $colorRes = if ($errores -eq 0) { "Green" } elseif ($errores -le 3) { "Yellow" } else { "Red" }

    Write-Host ("  Verificaciones pasadas : " + $correctos + " / " + $total) -ForegroundColor $colorRes
    Write-Host ("  Porcentaje             : " + $pct + "%") -ForegroundColor $colorRes

    if ($errores -eq 0) {
        Write-Host ""
        Write-Host "  [+] CONFIGURACION COMPLETA Y CORRECTA" -ForegroundColor Green
        Write-Host "  [+] Todo listo para entregar." -ForegroundColor Green
    } elseif ($errores -le 3) {
        Write-Host ""
        Write-Host "  [~] Casi listo. Revisa los items marcados [FALLO]." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "  [!] Hay varios items sin configurar." -ForegroundColor Red
        Write-Host "  [!] Ejecuta las opciones faltantes del menu." -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  Log guardado en: verificacion.log" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Cyan
    Add-Content $logVerif ""
    Add-Content $logVerif "RESULTADO: $correctos/$total correctos ($pct%)"
}