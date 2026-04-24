# ============================================================
#  TEST 1 - ACCION A: Cambio de contraseña como admin_identidad
# ============================================================

Write-Host "`n[TEST 1 - ACCION A]" -ForegroundColor Cyan

# Pedir datos al momento de ejecutar
$usuario   = Read-Host "Ingresa el nombre de usuario (ej: ecastro)"
$nuevaPass = Read-Host "Ingresa la nueva contraseña"

Write-Host "`nBuscando usuario..." -ForegroundColor Yellow

# Verificar que el usuario existe
try {
    $user = Get-ADUser -Identity $usuario -Properties DistinguishedName -ErrorAction Stop
    Write-Host "[INFO] Usuario encontrado: $($user.DistinguishedName)" -ForegroundColor Yellow

    # Cambiar contraseña
    Set-ADAccountPassword -Identity $usuario `
        -NewPassword (ConvertTo-SecureString $nuevaPass -AsPlainText -Force) `
        -Reset -ErrorAction Stop

    Write-Host "[OK] Contraseña cambiada exitosamente para: $usuario" -ForegroundColor Green
    Write-Host "[EVIDENCIA] Accion A: EXITOSA" -ForegroundColor Green

    # Mostrar estado final
    Get-ADUser -Identity $usuario -Properties PasswordLastSet |
        Select-Object Name, SamAccountName, DistinguishedName, PasswordLastSet
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}