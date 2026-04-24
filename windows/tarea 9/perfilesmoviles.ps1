# ============================================================
#  PERFILES MOVILES - Configuracion completa
#  Ejecutar como: Administrator en el servidor
# ============================================================

Write-Host "`n[PERFILES MOVILES] Iniciando configuracion..." -ForegroundColor Cyan

# ---- CONFIGURACION ----
$servidorNombre = $env:COMPUTERNAME
$rutaPerfiles   = "C:\PerfilesMoviles"
$compartido     = "Perfiles$"
$dominio        = (Get-ADDomain).NetBIOSName

# ---- PASO 1: Crear carpeta en el servidor ----
Write-Host "`n[PASO 1] Creando carpeta de perfiles..." -ForegroundColor Yellow

if (-not (Test-Path $rutaPerfiles)) {
    New-Item -Path $rutaPerfiles -ItemType Directory | Out-Null
    Write-Host "[OK] Carpeta creada: $rutaPerfiles" -ForegroundColor Green
} else {
    Write-Host "[OK] Carpeta ya existe: $rutaPerfiles" -ForegroundColor DarkGray
}

# ---- PASO 2: Compartir la carpeta ----
Write-Host "`n[PASO 2] Compartiendo carpeta..." -ForegroundColor Yellow

$shareExiste = Get-SmbShare -Name $compartido -ErrorAction SilentlyContinue
if (-not $shareExiste) {
    New-SmbShare -Name $compartido -Path $rutaPerfiles `
        -FullAccess "Authenticated Users" -ErrorAction Stop
    Write-Host "[OK] Carpeta compartida como: \\$servidorNombre\$compartido" -ForegroundColor Green
} else {
    Write-Host "[OK] Ya esta compartida: \\$servidorNombre\$compartido" -ForegroundColor DarkGray
}

# ---- PASO 3: Permisos NTFS correctos ----
Write-Host "`n[PASO 3] Configurando permisos NTFS..." -ForegroundColor Yellow

$acl = Get-Acl $rutaPerfiles

# Quitar herencia
$acl.SetAccessRuleProtection($true, $false)

# Agregar permisos
$permisos = @(
    @{ Usuario = "SYSTEM";               Permiso = "FullControl" },
    @{ Usuario = "Administrators";       Permiso = "FullControl" },
    @{ Usuario = "Authenticated Users";  Permiso = "Modify" }
)

foreach ($p in $permisos) {
    $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $p.Usuario, $p.Permiso, "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($regla)
    Write-Host "[OK] Permiso agregado: $($p.Usuario) - $($p.Permiso)" -ForegroundColor Green
}

Set-Acl -Path $rutaPerfiles -AclObject $acl
Write-Host "[OK] Permisos NTFS aplicados." -ForegroundColor Green

# ---- PASO 4: Configurar perfil movil en cada usuario del dominio ----
Write-Host "`n[PASO 4] Configurando perfil movil en usuarios AD..." -ForegroundColor Yellow

# Obtener todos los usuarios habilitados del dominio
$usuarios = Get-ADUser -Filter { Enabled -eq $true } -Properties ProfilePath |
    Where-Object { $_.SamAccountName -ne "Administrator" -and 
                   $_.SamAccountName -notlike "krbtgt*" -and
                   $_.SamAccountName -notlike "Guest*" }

$configurados = 0
foreach ($u in $usuarios) {
    $rutaPerfil = "\\$servidorNombre\$compartido\$($u.SamAccountName)"
    
    try {
        Set-ADUser -Identity $u.SamAccountName -ProfilePath $rutaPerfil -ErrorAction Stop
        Write-Host "[OK] $($u.SamAccountName) -> $rutaPerfil" -ForegroundColor Green
        $configurados++
    } catch {
        Write-Host "[ERROR] $($u.SamAccountName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n[INFO] $configurados usuarios configurados con perfil movil." -ForegroundColor Cyan

# ---- PASO 5: Verificar configuracion ----
Write-Host "`n[PASO 5] Verificando configuracion..." -ForegroundColor Yellow

Get-ADUser -Filter { Enabled -eq $true } -Properties ProfilePath |
    Where-Object { $_.ProfilePath -ne $null -and $_.ProfilePath -ne "" } |
    Select-Object SamAccountName, ProfilePath |
    Format-Table -AutoSize

Write-Host "`n[INFO] Ruta de perfiles: \\$servidorNombre\$compartido" -ForegroundColor Cyan
Write-Host "[INFO] Cuando el usuario inicie sesion en el cliente se creara automaticamente" -ForegroundColor Cyan
Write-Host "       la carpeta con extension V6 en: $rutaPerfiles" -ForegroundColor Cyan
Write-Host "`n[EVIDENCIA] Perfiles Moviles: CONFIGURADOS CORRECTAMENTE" -ForegroundColor Green