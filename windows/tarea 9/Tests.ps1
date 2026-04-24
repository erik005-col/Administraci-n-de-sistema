# ============================================================
#  TEST 2 - FGPP: Directiva de Contraseña Ajustada
#  Sesion iniciada como: Administrator
# ============================================================

Write-Host "`n[TEST 2 - FGPP] Iniciando prueba..." -ForegroundColor Cyan

$usuario = Read-Host "Ingresa el usuario a probar (ej: admin_identidad)"

# INTENTO 1 - Contraseña corta (debe FALLAR)
Write-Host "`n[INTENTO 1] Escribe una contrasena corta de 8 caracteres" -ForegroundColor Yellow
$passCorta = Read-Host "Contrasena corta"

try {
    Set-ADAccountPassword -Identity $usuario `
        -NewPassword (ConvertTo-SecureString $passCorta -AsPlainText -Force) `
        -Reset -ErrorAction Stop

    Write-Host "[ADVERTENCIA] Fue aceptada - revisar FGPP" -ForegroundColor Yellow
}
catch {
    Write-Host "[RECHAZADA] Contrasena corta rechazada correctamente" -ForegroundColor Red
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[EVIDENCIA] Test 2: FGPP funcionando correctamente" -ForegroundColor Green
}

# INTENTO 2 - Contraseña larga (debe PASAR)
Write-Host "`n[INTENTO 2] Escribe una contrasena de 12 o mas caracteres" -ForegroundColor Yellow
$passLarga = Read-Host "Contrasena larga"

try {
    Set-ADAccountPassword -Identity $usuario `
        -NewPassword (ConvertTo-SecureString $passLarga -AsPlainText -Force) `
        -Reset -ErrorAction Stop

    Write-Host "[OK] Contrasena aceptada correctamente" -ForegroundColor Green
    Write-Host "[EVIDENCIA] Test 2: FGPP aplica minimo de 12 caracteres" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}

# Mostrar política aplicada
Write-Host "`n[INFO] Politica FGPP aplicada a: $usuario" -ForegroundColor Cyan
Get-ADUserResultantPasswordPolicy -Identity $usuario |
    Select-Object Name, MinPasswordLength, ComplexityEnabled