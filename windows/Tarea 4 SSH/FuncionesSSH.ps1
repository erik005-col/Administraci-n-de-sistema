# ===============================
#   MODULO SSH - WINDOWS SERVER
# ===============================

function Install-SSHService {

    Write-Host "Verificando OpenSSH Server..." -ForegroundColor Cyan

    $ssh = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

    if ($ssh.State -ne "Installed") {
        Write-Host "Instalando OpenSSH Server..." -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    }
    else {
        Write-Host "OpenSSH ya esta instalado." -ForegroundColor Green
    }

    Write-Host "Configurando servicio SSH..." -ForegroundColor Yellow

    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic

    Write-Host "Configurando Firewall (Puerto 22)..." -ForegroundColor Yellow

    if (-not (Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -Name "sshd" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22
    }

    Write-Host "SSH configurado correctamente." -ForegroundColor Green
}