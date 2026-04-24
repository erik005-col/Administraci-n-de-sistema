# ============================================================
#  unir_windows.ps1 - Une el cliente Windows 10 al dominio
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#
#  INSTRUCCIONES:
#  1. Copia este script al cliente Windows 10
#  2. Abre PowerShell como Administrador
#  3. Ejecuta: powershell -ExecutionPolicy Bypass -File unir_windows.ps1
# ============================================================

# Verificar que se ejecuta como Administrador
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  ERROR: Debes ejecutar este script como Administrador." -ForegroundColor Red
    Write-Host ""
    exit 1
}

Clear-Host
Write-Host ""
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host "  |     UNIR WINDOWS 10 AL DOMINIO           |" -ForegroundColor Cyan
Write-Host "  |     practica8.local | 192.168.1.202      |" -ForegroundColor Cyan
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ""

# --- Verificar conectividad con el servidor ---
Write-Host "  Verificando conectividad con el servidor..." -ForegroundColor Yellow
Write-Host ""

$ping = Test-Connection -ComputerName 192.168.1.202 -Count 2 -Quiet
if (-not $ping) {
    Write-Host "  [ERROR] No se puede contactar al servidor 192.168.1.202" -ForegroundColor Red
    Write-Host "  Verifica que:" -ForegroundColor Yellow
    Write-Host "    - El servidor este encendido" -ForegroundColor Yellow
    Write-Host "    - El adaptador red_sistemas este activo" -ForegroundColor Yellow
    Write-Host "    - Las IPs estaticas esten bien configuradas" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
Write-Host "  [OK] Servidor alcanzable." -ForegroundColor Green

# --- Configurar DNS apuntando al servidor ---
Write-Host ""
Write-Host "  Configurando DNS para apuntar al servidor AD..." -ForegroundColor Yellow

# Buscar el adaptador con IP 192.168.1.200
$adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
    $ip = Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ip.IPAddress -eq "192.168.1.200") { $_ }
}

if ($adaptador) {
    Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses "192.168.1.202"
    Write-Host "  [OK] DNS configurado en adaptador: $($adaptador.Name)" -ForegroundColor Green
} else {
    Write-Host "  [AVISO] No se encontro el adaptador con IP 192.168.1.200." -ForegroundColor Yellow
    Write-Host "  Configurando DNS en todos los adaptadores activos..." -ForegroundColor Yellow
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses "192.168.1.202"
    }
}

# --- Verificar que el dominio es resolvible ---
Write-Host ""
Write-Host "  Verificando resolucion del dominio practica8.local..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

$resolucion = Resolve-DnsName practica8.local -ErrorAction SilentlyContinue
if (-not $resolucion) {
    Write-Host "  [ERROR] No se puede resolver practica8.local." -ForegroundColor Red
    Write-Host "  Verifica que el DNS del servidor este funcionando." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
Write-Host "  [OK] Dominio practica8.local resuelto correctamente." -ForegroundColor Green

# --- Mostrar estado actual ---
Write-Host ""
Write-Host "  Estado actual de esta maquina:" -ForegroundColor White
$nombreActual  = $env:COMPUTERNAME
$dominioActual = (Get-WmiObject Win32_ComputerSystem).Domain
Write-Host "    Nombre     : $nombreActual" -ForegroundColor Cyan
Write-Host "    Dominio    : $dominioActual" -ForegroundColor Cyan
Write-Host ""

# Verificar si ya esta en el dominio
if ($dominioActual -eq "practica8.local") {
    Write-Host "  [INFO] Esta maquina ya pertenece a practica8.local." -ForegroundColor Yellow
    Write-Host "  No es necesario unirla de nuevo." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# --- Confirmar y pedir credenciales ---
Write-Host "  Se unira esta maquina al dominio practica8.local." -ForegroundColor White
Write-Host "  Se reiniciara automaticamente al finalizar." -ForegroundColor Red
Write-Host ""

$confirmar = Read-Host "  Deseas continuar? (s/n)"
if ($confirmar -ne "s") {
    Write-Host ""
    Write-Host "  Operacion cancelada." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "  Ingresa las credenciales del Administrador del dominio." -ForegroundColor Yellow
Write-Host "  (Usuario: Administrator o PRACTICA8\Administrator)" -ForegroundColor White
Write-Host ""

$credencial = Get-Credential -Message "Credenciales del dominio practica8.local" -UserName "PRACTICA8\Administrator"

# --- Unir al dominio ---
Write-Host ""
Write-Host "  Uniendo al dominio practica8.local..." -ForegroundColor Cyan

try {
    Add-Computer `
        -DomainName "practica8.local" `
        -Credential $credencial `
        -Restart `
        -Force

    Write-Host "  [OK] Maquina unida al dominio. Reiniciando..." -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host "  [ERROR] No se pudo unir al dominio." -ForegroundColor Red
    Write-Host "  Detalle: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Causas comunes:" -ForegroundColor Yellow
    Write-Host "    - Credenciales incorrectas" -ForegroundColor Yellow
    Write-Host "    - El servidor no esta disponible" -ForegroundColor Yellow
    Write-Host "    - El DNS no apunta al servidor AD" -ForegroundColor Yellow
    Write-Host ""
}
