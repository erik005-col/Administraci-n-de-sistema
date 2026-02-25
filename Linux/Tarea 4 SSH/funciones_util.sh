#!/bin/bash
# --- VARIABLES GLOBALES PARA COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' 

LOG_FILE="/var/log/admin_red.log"

# --- FUNCIONES DE UTILIDAD ---

verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[!] Error: Este script debe ejecutarse como root (sudo).${NC}"
        exit 1
    fi
}

preparar_entorno() {
    # Evitar conflictos con servicios por defecto en máquinas limpias
    systemctl stop dnsmasq &> /dev/null
    systemctl disable dnsmasq &> /dev/null
    mkdir -p /etc/kea/ /var/lib/kea/
}

escribir_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

msg_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    sleep 2
}

# --- VALIDACIONES DE IP ---

ip_to_int() {
    local IFS=.
    read -r i1 i2 i3 i4 <<< "$1"
    echo $(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
}

validar_formato_ip() {
    if [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    return 1
}

# Función ajustada: Permite 127.x.x.x excepto .1, .0 y .255
validar_ip_utilizable() {
    local IP=$1
    
    # 1. Validar formato básico x.x.x.x
    if ! validar_formato_ip "$IP"; then return 1; fi

    # 2. Desglosar octetos
    IFS='.' read -r o1 o2 o3 o4 <<< "$IP"

    # 3. Validaciones de rango numérico (0-255)
    for octeto in $o1 $o2 $o3 $o4; do
        if [ "$octeto" -lt 0 ] || [ "$octeto" -gt 255 ]; then return 1; fi
    done

    # 4. Validar IPs Reservadas Específicas
    
    # Bloquear 0.0.0.0
    if [ "$IP" == "0.0.0.0" ]; then echo "Error: IP 0.0.0.0 no válida"; return 1; fi
    
    # Bloquear Localhost exacto
    if [ "$IP" == "127.0.0.1" ]; then echo "Error: Localhost (127.0.0.1) no permitido como servidor"; return 1; fi

    # 5. Reglas generales de Red y Broadcast (.0 y .255)
    if [ "$o4" -eq 0 ]; then echo "Error: IP de Red (termina en .0)"; return 1; fi
    if [ "$o4" -eq 255 ]; then echo "Error: IP de Broadcast (termina en .255)"; return 1; fi

    return 0
}