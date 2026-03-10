# Cargar archivo de funciones
. "$PSScriptRoot\http_funciones.ps1"

$continuar = $true

do {

Write-Host "=============================="
Write-Host "  Aprovisionamiento HTTP"
Write-Host "=============================="
Write-Host "1) IIS (Obligatorio)"
Write-Host "2) Apache Win64"
Write-Host "3) Nginx Windows"
Write-Host "4) Salir"
Write-Host "=============================="

$opcion = Read-Host "Seleccione una opcion"

switch ($opcion) {

"1" { Instalar-IIS }

"2" { Instalar-Apache }

"3" { Instalar-Nginx }

"4" { 
Write-Host "Saliendo..."
$continuar = $false
}

default {
Write-Host "Opcion invalida" -ForegroundColor Red
}
  
}

} while ($continuar)