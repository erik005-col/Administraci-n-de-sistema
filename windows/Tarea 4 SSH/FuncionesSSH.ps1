# ===============================
#   MODULO SSH - WINDOWS SERVER
# ===============================

function Install-SSHService {

  $ssh = Get-Service -Name sshd -ErrorAction SilentlyContinue

    if (-not $ssh) {
        Write-Host "OpenSSH no está instalado. Instálelo desde Server Manager si no hay internet." -ForegroundColor Red
        return
    }

    Start-Service sshd
    Set-Service -Name sshd -StartupType Automatic

    if (-not (Get-NetFirewallRule -DisplayName "SSH-Port-22" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -DisplayName "SSH-Port-22" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 22 `
            -Action Allow
    }

    Write-Host "SSH configurado correctamente." -ForegroundColor Green
}