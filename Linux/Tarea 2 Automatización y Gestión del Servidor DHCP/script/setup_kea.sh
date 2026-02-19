#!/bin/bash
# ======================================================================================
# Tarea 2: Automatizacion y Gestion del Servidor DHCP (KEA)
# Script: Automatiza la instalación, configuración y monitoreo de DHCP
# ======================================================================================

# --- VARIABLES GLOBALES PARA COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' 

# --- FUNCIONES DE VALIDACION Y UTILIDADES ---

ip_to_int() {
    local IFS=.
    read -r i1 i2 i3 i4 <<< "$1"
    echo $(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
}

validar_formato_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

validar_ip_utilizable() {
    local IP=$1
    if ! validar_formato_ip "$IP"; then return 1; fi
    IFS='.' read -r o1 o2 o3 o4 <<< "$IP"

    for octeto in $o1 $o2 $o3 $o4; do
        if [ "$octeto" -lt 0 ] || [ "$octeto" -gt 255 ]; then return 1; fi
    done

    if [ "$IP" == "0.0.0.0" ] || [ "$IP" == "127.0.0.1" ]; then return 1; fi
    if [ "$o4" -eq 0 ] || [ "$o4" -eq 255 ]; then return 1; fi
    return 0
}

# --- 1. ESTADO DEL SERVICIO (CORREGIDO) ---
estado_servicio() {
    clear
    echo "----------------------------------------"
    echo "        ESTADO DEL SERVICIO DHCP"
    echo "----------------------------------------"
    
    if systemctl is-active --quiet kea-dhcp4; then
        echo -e "Estado: ${GREEN} ● ACTIVO (EN EJECUCIÓN)${NC}"
        echo "Logs recientes:"
        journalctl -u kea-dhcp4 -n 5 --no-pager
    else
        echo -e "Estado: ${RED} ○ INACTIVO (DETENIDO)${NC}"
    fi
    echo "----------------------------------------"
    read -p "Presione Enter para volver al menú..."
}

# --- 2. INSTALACION ---
instalar_servicio() {
    clear
    echo "----------------------------------------"
    echo "        INSTALACIÓN DEL SERVICIO"
    echo "----------------------------------------"

    if rpm -q kea &> /dev/null; then
        echo "El servicio ya está instalado."
    else
        echo "Instalando... por favor espere."
        dnf install -y epel-release oracle-epel-release-el10 &> /dev/null
        if dnf install -y kea &> /dev/null; then
            echo -e "${GREEN}[EXITO] Kea se instaló correctamente.${NC}"
            systemctl enable kea-dhcp4 &>/dev/null
        else
            echo -e "${RED}[ERROR] Falló la instalación.${NC}"
        fi
    fi
    read -p "Presione Enter..."
}

# --- 3. CONFIGURACION DHCP ---
configurar_servicio() {
    clear
    echo "========================================"
    echo "    CONFIGURACION DE DHCP"
    echo "========================================"

    if ! rpm -q kea &> /dev/null; then
        echo "Error: Instale el servicio primero."; read; return
    fi

    echo "Interfaces disponibles:"
    ip -o link show | awk -F': ' '{print " - " $2}'
    
    while true; do
        read -p "1. Adaptador de red: " INTERFAZ
        if ip link show "$INTERFAZ" &> /dev/null; then break; fi
        echo -e "${RED}[!] Interfaz no válida.${NC}"
    done

    read -p "2. Nombre del Ámbito: " SCOPE_NAME

    while true; do
        read -p "3. IP Servidor (Ejem 192.168.10.20): " IP_INICIO
        if validar_ip_utilizable "$IP_INICIO"; then break; fi
        echo -e "${RED}[!] IP inválida.${NC}"
    done

    PREFIX=$(echo "$IP_INICIO" | cut -d'.' -f1-3)
    LAST_OCTET=$(echo "$IP_INICIO" | cut -d'.' -f4)
    POOL_START="$PREFIX.$((LAST_OCTET + 1))"
    SUBNET="$PREFIX.0"

    while true; do
        read -p "4. Rango final ($PREFIX.x): " IP_FIN
        if validar_ip_utilizable "$IP_FIN" && [ "$PREFIX" == "$(echo "$IP_FIN" | cut -d'.' -f1-3)" ]; then
            if [ $(ip_to_int "$POOL_START") -le $(ip_to_int "$IP_FIN") ]; then break; fi
        fi
        echo -e "${RED}[!] Rango fuera de segmento o menor al inicio.${NC}"
    done

    read -p "5. Gateway (Enter para saltar): " GATEWAY
    read -p "6. DNS (Enter para saltar): " DNS_SERVER
    read -p "7. Tiempo concesión (seg): " LEASE_TIME
    [ -z "$LEASE_TIME" ] && LEASE_TIME=3600

    # Construir bloque JSON
    OPTIONS=""
    [ -n "$GATEWAY" ] && OPTIONS+="{ \"name\": \"routers\", \"data\": \"$GATEWAY\" }"
    if [ -n "$DNS_SERVER" ]; then
        [ -n "$OPTIONS" ] && OPTIONS+=", "
        OPTIONS+="{ \"name\": \"domain-name-servers\", \"data\": \"$DNS_SERVER\" }"
    fi

    # Escribir archivo Kea
    cat <<EOF > /etc/kea/kea-dhcp4.conf
{
"Dhcp4": {
    "interfaces-config": { "interfaces": [ "$INTERFAZ" ], "dhcp-socket-type": "raw" },
    "lease-database": { "type": "memfile", "persist": true, "name": "/var/lib/kea/kea-leases4.csv" },
    "valid-lifetime": $LEASE_TIME,
    "subnet4": [
        {
            "id": 1,
            "subnet": "$SUBNET/24",
            "pools": [ { "pool": "$POOL_START - $IP_FIN" } ],
            "option-data": [ $OPTIONS ],
            "user-context": { "name": "$SCOPE_NAME" }
        }
    ]
}
}
EOF

    # Aplicar Red
    ip addr flush dev "$INTERFAZ"
    ip addr add "$IP_INICIO/24" dev "$INTERFAZ"
    ip link set "$INTERFAZ" up
    
    firewall-cmd --add-service=dhcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null
    systemctl restart kea-dhcp4
    echo -e "${GREEN}¡Configuración aplicada!${NC}"
    read -p "Enter..."
}

# --- 4. MONITOREO ---
monitorear_servicio() {
    LEASE_FILE="/var/lib/kea/kea-leases4.csv"
    watch -n 2 -t "
      echo '===================================================='
      echo '         MONITOR DE CLIENTES DHCP'
      echo '===================================================='
      printf '%-15s | %-17s | %-15s\n' 'IP' 'MAC' 'HOSTNAME'
      echo '----------------------------------------------------'
      [ -f $LEASE_FILE ] && tail -n +2 $LEASE_FILE | awk -F, '{printf \"%-15s | %-17s | %-15s\n\", \$1, \$2, \$9}'
    "
}

# --- MENU PRINCIPAL (CORREGIDO) ---
while true; do
    clear
    echo -e "${BOLD}SISTEMA DE GESTIÓN DHCP v2.0${NC}"
    echo "========================================"
    echo -e "1. ${CYAN}ESTADO${NC}     Ver operatividad"
    echo -e "2. ${CYAN}INSTALAR${NC}   Desplegar KEA"
    echo -e "3. ${CYAN}CONFIGURAR${NC} Definir Ámbito"
    echo -e "4. ${CYAN}MONITOR${NC}    Ver Clientes"
    echo -e "5. ${RED}SALIR${NC}"
    echo "========================================"
    read -p "Seleccione: " OPC
    
    case $OPC in
        1) estado_servicio ;;
        2) instalar_servicio ;;
        3) configurar_servicio ;;
        4) monitorear_servicio ;;
        5) exit 0 ;;
        *) echo "Opción inválida"; sleep 1 ;;
    esac
done