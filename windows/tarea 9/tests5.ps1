# ============================================================
#  TEST 5 - REPORTE DE AUDITORIA AUTOMATIZADO
#  Ejecutar como: Administrator
# ============================================================

Write-Host "`n[TEST 5] Generando reporte de auditoria..." -ForegroundColor Cyan

$fecha      = Get-Date -Format "yyyy-MM-dd_HH-mm"
$archivoCSV = "C:\Users\Administrator\tarea 9\reporte_auditoria_$fecha.csv"
$archivoTXT = "C:\Users\Administrator\tarea 9\reporte_auditoria_$fecha.txt"

# Extraer ultimos 10 intentos de acceso denegado (Event ID 4625)
Write-Host "[INFO] Buscando eventos de acceso denegado (ID 4625)..." -ForegroundColor Yellow

try {
    $eventos = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4625
    } -MaxEvents 10 -ErrorAction Stop |
    ForEach-Object {
        $xml  = [xml]$_.ToXml()
        $data = $xml.Event.EventData.Data
        [PSCustomObject]@{
            Fecha       = $_.TimeCreated
            Usuario     = ($data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
            Dominio     = ($data | Where-Object { $_.Name -eq 'TargetDomainName' }).'#text'
            IP_Origen   = ($data | Where-Object { $_.Name -eq 'IpAddress' }).'#text'
            Razon       = ($data | Where-Object { $_.Name -eq 'FailureReason' }).'#text'
            EventoID    = $_.Id
        }
    }

    if ($eventos) {
        # Guardar CSV
        $eventos | Export-Csv -Path $archivoCSV -NoTypeInformation -Encoding UTF8
        Write-Host "[OK] CSV generado: $archivoCSV" -ForegroundColor Green

        # Guardar TXT
        $eventos | Format-Table -AutoSize | Out-String | Set-Content $archivoTXT -Encoding UTF8
        Write-Host "[OK] TXT generado: $archivoTXT" -ForegroundColor Green

        # Mostrar en pantalla
        Write-Host "`n[RESULTADO] Ultimos 10 intentos de acceso denegado:" -ForegroundColor Cyan
        $eventos | Format-Table -AutoSize

        Write-Host "[EVIDENCIA] Test 5: COMPLETADO - Archivos generados" -ForegroundColor Green
    } else {
        Write-Host "[WARN] No se encontraron eventos 4625." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red

    # Si no hay eventos 4625 buscar eventos relacionados
    Write-Host "[INFO] Buscando eventos alternativos (4624 - Logon exitoso)..." -ForegroundColor Yellow
    $eventosAlt = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id      = 4624
    } -MaxEvents 10 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, Message |
    Export-Csv -Path $archivoCSV -NoTypeInformation -Encoding UTF8

    Write-Host "[OK] Reporte alternativo generado: $archivoCSV" -ForegroundColor Green
}