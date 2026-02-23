# ===============================
#   MODULO SSH
# ===============================

function Instalar-SSH {

    Write-Host ""
    Write-Host "Verificando estado de OpenSSH..." -ForegroundColor Cyan

    $ssh = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

    if ($ssh.State -ne "Installed") {

        Write-Host "OpenSSH no está instalado. Instalando..." -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null

        $ssh = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

        if ($ssh.State -ne "Installed") {
            Write-Host "Error al instalar OpenSSH." -ForegroundColor Red
            Read-Host "Presione ENTER para continuar"
            return
        }
    }

    Write-Host "OpenSSH instalado correctamente." -ForegroundColor Green

    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic

    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22 | Out-Null
    }

    Write-Host "-------------------------------------"
    Write-Host "SSH ACTIVO EN PUERTO 22" -ForegroundColor Green
    Write-Host "-------------------------------------"

    Read-Host "Presione ENTER para continuar"
}