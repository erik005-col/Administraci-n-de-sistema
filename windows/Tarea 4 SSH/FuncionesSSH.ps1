# ===============================
#   MODULO SSH - WINDOWS SERVER
# ===============================

function Install-SSHService {
    Write-Host "Iniciando configuracion de SSH..." -ForegroundColor Cyan

    $ssh = Get-Service -Name sshd -ErrorAction SilentlyContinue

    # 1. Intentar instalacion si no existe
    if (-not $ssh) {
        Write-Host "OpenSSH no detectado. Intentando instalacion local..." -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
        
        $ssh = Get-Service -Name sshd -ErrorAction SilentlyContinue
        if (-not $ssh) {
            Write-Host "ERROR: No se pudo instalar automaticamente. Instale via Server Manager (ISO)." -ForegroundColor Red
            return
        }
    }

    # 2. Iniciar y configurar servicio
    Write-Host "Arrancando servicio sshd..." -ForegroundColor Yellow
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic

    # 3. Habilitar Autenticacion por Contraseña (Evita 'Permission denied')
    $configPath = "$env:ProgramData\ssh\sshd_config"
    if (Test-Path $configPath) {
        (Get-Content $configPath) -replace '#PasswordAuthentication yes', 'PasswordAuthentication yes' | Set-Content $configPath
        Restart-Service sshd
        Write-Host "Configuracion de autenticacion actualizada." -ForegroundColor Green
    }

    # 4. Gestion avanzada del Firewall (Puerto 22)
    $firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    
    if (!$firewallRule) {
        Write-Host "Creando nueva regla de Firewall para puerto 22..." -ForegroundColor Yellow
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    } else {
        Write-Host "Habilitando regla de Firewall existente..." -ForegroundColor Yellow
        Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    }

    # Detectar la IP actual para informar al usuario
    $currentIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" }).IPAddress | Select-Object -First 1
    
    Write-Host "----------------------------------------------"
    Write-Host "SSH LISTO PARA CONEXION" -ForegroundColor Green
    Write-Host "IP Actual detectada: $currentIP" -ForegroundColor Cyan
    Write-Host "Comando: ssh Administrador@$currentIP" -ForegroundColor Yellow
    Write-Host "----------------------------------------------"