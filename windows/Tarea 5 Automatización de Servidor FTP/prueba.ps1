# ============================================================
# ADMINISTRADOR SERVIDOR FTP - VERSION PROFESIONAL
# Windows Server 2016 / 2019 / 2022
# ============================================================

Import-Module ServerManager
Import-Module WebAdministration

$ftpRoot="C:\FTP"
$ftpSite="FTP_SERVER"
$logFile="C:\FTP\ftp_log.txt"

# ------------------------------------------------------------
# INSTALAR FTP
# ------------------------------------------------------------

function Instalar-FTP {

Write-Host "Instalando IIS + FTP..."

$features=@(
"Web-Server",
"Web-FTP-Server",
"Web-FTP-Service",
"Web-FTP-Ext"
)

foreach($f in $features){

$estado = Get-WindowsFeature $f

if(!$estado.Installed){

Write-Host "Instalando $f ..."
Install-WindowsFeature $f -IncludeManagementTools

}
else{

Write-Host "$f ya esta instalado"

}

}

Start-Service W3SVC -ErrorAction SilentlyContinue
Start-Service ftpsvc -ErrorAction SilentlyContinue

Set-Service ftpsvc -StartupType Automatic

Write-Host "FTP instalado correctamente"

Log "FTP instalado"

}

# ------------------------------------------------------------
# LOG
# ------------------------------------------------------------

function Log {

param($msg)

$fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Crear carpeta si no existe
if (!(Test-Path $ftpRoot)) {
    New-Item -Path $ftpRoot -ItemType Directory -Force | Out-Null
}

# Crear archivo log si no existe
if (!(Test-Path $logFile)) {
    New-Item -Path $logFile -ItemType File -Force | Out-Null
}

Add-Content $logFile "$fecha - $msg"

}



# ------------------------------------------------------------
# FIREWALL
# ------------------------------------------------------------

function Configurar-Firewall {

New-NetFirewallRule `
-DisplayName "FTP 21" `
-Direction Inbound `
-Protocol TCP `
-LocalPort 21 `
-Action Allow `
-ErrorAction SilentlyContinue

New-NetFirewallRule `
-DisplayName "FTP Passive" `
-Direction Inbound `
-Protocol TCP `
-LocalPort 50000-51000 `
-Action Allow `
-ErrorAction SilentlyContinue

Write-Host "Firewall configurado"

Log "Firewall configurado"

}

# ------------------------------------------------------------
# CREAR GRUPOS
# ------------------------------------------------------------

function Crear-Grupos {

$grupos=@("reprobados","recursadores","ftpusuarios")

foreach($g in $grupos){

if(!(Get-LocalGroup $g -ErrorAction SilentlyContinue)){

New-LocalGroup $g

Write-Host "Grupo $g creado"

}

}

Log "Grupos creados"

}

# ------------------------------------------------------------
# ESTRUCTURA
# ------------------------------------------------------------

function Crear-Estructura {

New-Item $ftpRoot -ItemType Directory -Force

New-Item "$ftpRoot\general" -ItemType Directory -Force
New-Item "$ftpRoot\reprobados" -ItemType Directory -Force
New-Item "$ftpRoot\recursadores" -ItemType Directory -Force

New-Item "$ftpRoot\Data" -ItemType Directory -Force
New-Item "$ftpRoot\Data\Usuarios" -ItemType Directory -Force

New-Item "$ftpRoot\LocalUser" -ItemType Directory -Force
New-Item "$ftpRoot\LocalUser\Public" -ItemType Directory -Force

cmd /c mklink /J "$ftpRoot\LocalUser\Public\general" "$ftpRoot\general"

Write-Host "Estructura creada"

Log "Estructura FTP creada"

}

# ------------------------------------------------------------
# PERMISOS
# ------------------------------------------------------------

function Permisos {

# ROOT
icacls $ftpRoot /inheritance:r
icacls $ftpRoot /grant "Administrators:(OI)(CI)F"
icacls $ftpRoot /grant "SYSTEM:(OI)(CI)F"
icacls $ftpRoot /grant "IUSR:(RX)"

# GENERAL
icacls "$ftpRoot\general" /inheritance:r
icacls "$ftpRoot\general" /grant "Administrators:(OI)(CI)F"
icacls "$ftpRoot\general" /grant "SYSTEM:(OI)(CI)F"
icacls "$ftpRoot\general" /grant "ftpusuarios:(OI)(CI)M"
icacls "$ftpRoot\general" /grant "IUSR:(OI)(CI)RX"

# REPROBADOS
icacls "$ftpRoot\reprobados" /inheritance:r
icacls "$ftpRoot\reprobados" /grant "Administrators:(OI)(CI)F"
icacls "$ftpRoot\reprobados" /grant "SYSTEM:(OI)(CI)F"
icacls "$ftpRoot\reprobados" /grant "reprobados:(OI)(CI)M"

# RECURSADORES
icacls "$ftpRoot\recursadores" /inheritance:r
icacls "$ftpRoot\recursadores" /grant "Administrators:(OI)(CI)F"
icacls "$ftpRoot\recursadores" /grant "SYSTEM:(OI)(CI)F"
icacls "$ftpRoot\recursadores" /grant "recursadores:(OI)(CI)M"

}

# ------------------------------------------------------------
# CONFIGURAR FTP
# ------------------------------------------------------------

function Configurar-FTP {

if(Get-WebSite $ftpSite -ErrorAction SilentlyContinue){

Remove-WebSite $ftpSite

}

New-WebFtpSite `
-Name $ftpSite `
-Port 21 `
-PhysicalPath $ftpRoot `
-Force

# DESACTIVAR SSL (ARREGLA ERROR 534)
Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.security.ssl.controlChannelPolicy `
-Value 0

Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.security.ssl.dataChannelPolicy `
-Value 0

Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.userIsolation.mode `
-Value 3

Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.security.authentication.anonymousAuthentication.enabled `
-Value $true

Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.security.authentication.basicAuthentication.enabled `
-Value $true

Clear-WebConfiguration `
-Filter system.ftpServer/security/authorization `
-PSPath IIS:\ `
-Location $ftpSite

Add-WebConfiguration `
-Filter system.ftpServer/security/authorization `
-PSPath IIS:\ `
-Location $ftpSite `
-Value @{accessType="Allow";users="?";permissions="Read"}

Add-WebConfiguration `
-Filter system.ftpServer/security/authorization `
-PSPath IIS:\ `
-Location $ftpSite `
-Value @{accessType="Allow";roles="ftpusuarios";permissions="Read,Write"}

Restart-Service ftpsvc
iisreset

Write-Host "FTP configurado"

Log "FTP configurado"

}



# ------------------------------------------------------------
# CREAR USUARIO
# ------------------------------------------------------------

function Crear-Usuario {
    $cantidad=Read-Host "¿Cuantos usuarios desea crear?"

for($i=1;$i -le $cantidad;$i++){

Write-Host ""
Write-Host "Creando usuario $i de $cantidad"

$usuario=Read-Host "Usuario"
$pass=Read-Host "Contraseña" -AsSecureString
$grupo=Read-Host "Grupo (reprobados/recursadores)"

if($grupo -ne "reprobados" -and $grupo -ne "recursadores"){

Write-Host "Grupo inválido"
continue

}

if(Get-LocalUser $usuario -ErrorAction SilentlyContinue){

Write-Host "El usuario ya existe"
continue

}

New-LocalUser $usuario -Password $pass

Add-LocalGroupMember $grupo -Member $usuario
Add-LocalGroupMember "ftpusuarios" -Member $usuario

$userHome="$ftpRoot\LocalUser\$usuario"

New-Item $userHome -ItemType Directory -Force
New-Item "$ftpRoot\Data\Usuarios\$usuario" -ItemType Directory -Force

cmd /c mklink /J "$userHome\general" "$ftpRoot\general"
cmd /c mklink /J "$userHome\$grupo" "$ftpRoot\$grupo"
cmd /c mklink /J "$userHome\$usuario" "$ftpRoot\Data\Usuarios\$usuario"

icacls "$ftpRoot\Data\Usuarios\$usuario" /grant "${usuario}:(OI)(CI)F"

}

Restart-Service ftpsvc

Write-Host "Usuarios creados correctamente"

}




# ------------------------------------------------------------
# ELIMINAR USUARIO
# ------------------------------------------------------------

function Eliminar-Usuario {

$usuario=Read-Host "Usuario a eliminar"

Remove-LocalUser $usuario

Remove-Item "$ftpRoot\LocalUser\$usuario" -Recurse -Force -ErrorAction SilentlyContinue

Remove-Item "$ftpRoot\Data\Usuarios\$usuario" -Recurse -Force -ErrorAction SilentlyContinue

Restart-Service ftpsvc

Write-Host "Usuario eliminado"

Log "Usuario eliminado"

}

# ------------------------------------------------------------
# CAMBIAR GRUPO
# ------------------------------------------------------------

function Cambiar-Grupo {

$usuario=Read-Host "Usuario"
$grupo=Read-Host "Nuevo grupo (reprobados/recursadores)"

# quitar de grupos
Remove-LocalGroupMember -Group "reprobados" -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember -Group "recursadores" -Member $usuario -ErrorAction SilentlyContinue

# agregar nuevo
Add-LocalGroupMember -Group $grupo -Member $usuario

$userHome="$ftpRoot\LocalUser\$usuario"

# eliminar enlaces viejos
if(Test-Path "$userHome\reprobados"){Remove-Item "$userHome\reprobados" -Force}
if(Test-Path "$userHome\recursadores"){Remove-Item "$userHome\recursadores" -Force}

# crear nuevo enlace
cmd /c mklink /J "$userHome\$grupo" "$ftpRoot\$grupo"

# reiniciar IIS completo
iisreset

Write-Host "Grupo cambiado correctamente"


}

# ------------------------------------------------------------
# VER USUARIOS
# ------------------------------------------------------------

function Ver-Usuarios {

Write-Host ""
Write-Host "Usuarios FTP creados:"
Write-Host ""

Get-LocalGroupMember ftpusuarios | ForEach-Object {

$u=$_.Name.Split("\")[-1]

Write-Host "Usuario:" $u

}

}



# ------------------------------------------------------------
# REINICIAR FTP
# ------------------------------------------------------------

function Reiniciar-FTP {

Restart-Service ftpsvc

Write-Host "FTP reiniciado"

}

# ------------------------------------------------------------
# ESTADO SERVIDOR
# ------------------------------------------------------------

function Estado {

Write-Host "Servicio FTP"

Get-Service ftpsvc

Write-Host ""
Write-Host "Puerto 21"

netstat -an | find ":21"

}

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------

function Menu {

while($true){

Write-Host ""
Write-Host "========= ADMIN FTP ========="

Write-Host "1 Instalar FTP"
Write-Host "2 Firewall"
Write-Host "3 Crear Grupos"
Write-Host "4 Crear Estructura"
Write-Host "5 Permisos"
Write-Host "6 Configurar FTP"
Write-Host "7 Crear Usuario"
Write-Host "8 Eliminar Usuario"
Write-Host "9 Cambiar Grupo"
Write-Host "10 Ver Usuarios"
Write-Host "11 Estado Servidor"
Write-Host "12 Reiniciar FTP"
Write-Host "0 Salir"

$op=Read-Host "Opcion"

switch($op){

"1"{Instalar-FTP}
"2"{Configurar-Firewall}
"3"{Crear-Grupos}
"4"{Crear-Estructura}
"5"{Permisos}
"6"{Configurar-FTP}
"7"{Crear-Usuario}
"8"{Eliminar-Usuario}
"9"{Cambiar-Grupo}
"10"{Ver-Usuarios}
"11"{Estado}
"12"{Reiniciar-FTP}
"0"{break}

}

}

}

Menu         