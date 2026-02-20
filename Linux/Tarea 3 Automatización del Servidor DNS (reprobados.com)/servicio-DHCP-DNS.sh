#!/bin/bash

# --- VARIABLES GLOBALES PARA COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- FUNCIONES DE VALIDACION Y UTILIDADES ---

ip_to_int() {
    local IFS=.
    read -r i1 i2 i3 i4 <<< "$1"
    echo $(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
}

validar_formato_ip() {
    if [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    return 1
}

validar_ip_utilizable() {
    local IP=$1
    if ! validar_formato_ip "$IP"; then return 1; fi
    IFS='.' read -r o1 o2 o3 o4 <<< "$IP"
    for octeto in $o1 $o2 $o3 $o4; do
        if [ "$octeto" -lt 0 ] || [ "$octeto" -gt 255 ]; then return 1; fi
    done
    if [ "$IP" == "0.0.0.0" ]; then echo "Error: IP 0.0.0.0 no válida"; return 1; fi
    if [ "$IP" == "127.0.0.1" ]; then echo "Error: Localhost no permitido"; return 1; fi
    if [ "$o4" -eq 0 ]; then echo "Error: IP de Red (.0)"; return 1; fi
    if [ "$o4" -eq 255 ]; then echo "Error: IP de Broadcast (.255)"; return 1; fi
    return 0
}

# --- 1. GESTIÓN DHCP (KEA) ---

estado_servicio() {
    while true; do
        clear
        echo "----------------------------------------"
        echo "        ESTADO DEL SERVICIO DHCP"
        echo "----------------------------------------"
        if ! rpm -q kea &> /dev/null; then
            echo -e "${RED}[!] El paquete 'kea' NO está instalado.${NC}"
            read -p "Presione Enter para volver..."
            return
        fi
        if systemctl is-active --quiet kea-dhcp4; then
            echo -e "Estado Actual: ${GREEN}ACTIVO (Running)${NC}"
            echo "----------------------------------------"
            echo " [1] Detener el servicio"
            echo " [2] Reiniciar el servicio"
            echo " [3] Volver al menú principal"
        else
            echo -e "Estado Actual: ${RED}DETENIDO (Stopped)${NC}"
            echo "----------------------------------------"
            echo " [1] Iniciar el servicio"
            echo " [3] Volver al menú principal"
        fi
        read -p "Seleccione una opción: " sub_opcion
        case $sub_opcion in
            1)
                if systemctl is-active --quiet kea-dhcp4; then systemctl stop kea-dhcp4; else systemctl start kea-dhcp4; fi
                sleep 1 ;;
            2) systemctl restart kea-dhcp4; sleep 1 ;;
            3) return ;;
        esac
    done
}

instalar_servicio() {
    echo "Instalando Kea DHCP..."
    dnf install -y epel-release &> /dev/null
    dnf install -y kea &> /dev/null
    [ $? -eq 0 ] && echo -e "${GREEN}Instalado.${NC}" || echo -e "${RED}Falló.${NC}"
    read -p "Presione Enter..."
}

configurar_servicio() {
    clear
    echo "=== CONFIGURACION DHCP ==="
    ip -o link show | awk -F': ' '{print " - " $2}'
    read -p "1. Adaptador de red: " INTERFAZ
    read -p "2. Nombre del Ámbito: " SCOPE_NAME
    while true; do
        read -p "3. IP Servidor (Estatica): " IP_INICIO
        if validar_ip_utilizable "$IP_INICIO"; then break; fi
    done
    
    PREFIX=$(echo "$IP_INICIO" | cut -d'.' -f1-3)
    POOL_START="$PREFIX.$(( $(echo "$IP_INICIO" | cut -d'.' -f4) + 1 ))"
    
    read -p "4. Rango final ($PREFIX.X): " IP_FIN
    read -p "5. Gateway (Enter para omitir): " GATEWAY
    read -p "6. DNS (Enter para omitir): " DNS_SERVER
    read -p "7. Tiempo Concesión: " LEASE_TIME

    # Configurar IP en la interfaz
    ip addr flush dev "$INTERFAZ"
    ip addr add "$IP_INICIO/24" dev "$INTERFAZ"
    ip link set "$INTERFAZ" up

    # Crear Configuración Kea
    OPTIONS=""
    [ -n "$GATEWAY" ] && OPTIONS="{ \"name\": \"routers\", \"data\": \"$GATEWAY\" }"
    [ -n "$DNS_SERVER" ] && [ -n "$OPTIONS" ] && OPTIONS="$OPTIONS, "
    [ -n "$DNS_SERVER" ] && OPTIONS="$OPTIONS { \"name\": \"domain-name-servers\", \"data\": \"$DNS_SERVER\" }"

    cat <<EOF > /etc/kea/kea-dhcp4.conf
{
"Dhcp4": {
    "interfaces-config": { "interfaces": [ "$INTERFAZ" ] },
    "lease-database": { "type": "memfile", "persist": true, "name": "/var/lib/kea/kea-leases4.csv" },
    "valid-lifetime": $LEASE_TIME,
    "subnet4": [
        {
            "id": 1, "subnet": "$PREFIX.0/24",
            "pools": [ { "pool": "$POOL_START - $IP_FIN" } ],
            "option-data": [ $OPTIONS ]
        }
    ]
}}
EOF
    systemctl restart kea-dhcp4
    echo -e "${GREEN}Configurado.${NC}"
    read -p "Enter..."
}

monitorear_servicio() {
    watch -n 2 "cat /var/lib/kea/kea-leases4.csv"
}

# --- 2. GESTIÓN DNS (BIND) ---

estado_dns() {
    if systemctl is-active --quiet named; then
        echo -e "${GREEN}DNS Corriendo${NC}"
        read -p "1) Detener 2) Reiniciar 3) Salir: " op
        case $op in
            1) systemctl stop named ;;
            2) systemctl restart named ;;
        esac
    else
        echo -e "${RED}DNS Detenido${NC}"
        read -p "1) Iniciar 3) Salir: " op
        [ "$op" == "1" ] && systemctl start named
    fi
}

instalar_dns() {
    dnf install -y bind bind-utils &> /dev/null
    systemctl enable --now named
    echo -e "${GREEN}BIND Instalado.${NC}"
    read -p "Enter..."
}

nuevo_dominio() {
    read -p "Dominio (ej: miempresa.com): " DOMINIO
    read -p "Interfaz para IP: " INTERFAZ_DNS
    IP_SRV=$(ip -4 addr show "$INTERFAZ_DNS" | grep inet | awk '{print $2}' | cut -d/ -f1)
    ZONA="/var/named/$DOMINIO.zone"

    echo "zone \"$DOMINIO\" IN { type master; file \"$ZONA\"; };" >> /etc/named.conf

    cat <<EOF > $ZONA
\$TTL 86400
@ IN SOA ns1.$DOMINIO. admin.$DOMINIO. ( 2026021701 3600 1800 604800 86400 )
@ IN NS ns1.$DOMINIO.
ns1 IN A $IP_SRV
www IN A $IP_SRV
EOF
    chown named:named $ZONA
    systemctl restart named
    echo -e "${GREEN}Dominio creado.${NC}"
    read -p "Enter..."
}

borrar_dominio() {
    read -p "Dominio a borrar: " DOMINIO
    sed -i "/zone \"$DOMINIO\"/,/};/d" /etc/named.conf
    rm -f "/var/named/$DOMINIO.zone"
    systemctl restart named
    echo "Borrado."
    read -p "Enter..."
}

consultar_dominio() {
    grep "zone" /etc/named.conf
    read -p "Dominio a consultar: " DOM
    dig @localhost +short "$DOM"
    read -p "Enter..."
}

limpiar_sistema() {
    systemctl stop kea-dhcp4
    rm -f /var/lib/kea/kea-leases4.csv
    systemctl start kea-dhcp4
    rndc flush
    echo -e "${GREEN}Caché limpia.${NC}"
    read -p "Enter..."
}

# --- MENUS ---

menu_dhcp() {
    while true; do
        clear
        echo -e "${CYAN}--- GESTOR DHCP ---${NC}"
        echo "1. Estado | 2. Instalar | 3. Configurar | 4. Monitorear | 5. Volver"
        read -p "Opción: " op
        case $op in 1) estado_servicio ;; 2) instalar_servicio ;; 3) configurar_servicio ;; 4) monitorear_servicio ;; 5) break ;; esac
    done
}

menu_dns() {
    while true; do
        clear
        echo -e "${MAGENTA}--- GESTOR DNS ---${NC}"
        echo "1. Estado | 2. Instalar | 3. Nuevo | 4. Borrar | 5. Consultar | 6. Volver"
        read -p "Opción: " op
        case $op in 1) estado_dns ;; 2) instalar_dns ;; 3) nuevo_dominio ;; 4) borrar_dominio ;; 5) consultar_dominio ;; 6) break ;; esac
    done
}

# --- MENU GLOBAL ---

while true; do
    clear
    echo -e "${BOLD}SISTEMA DE ADMINISTRACION DE RED${NC}"
    echo "1) Gestionar DHCP"
    echo "2) Gestionar DNS"
    echo "3) Limpiar Caché"
    echo "4) Salir"
    read -p "Seleccione: " op
    case $op in
        1) menu_dhcp ;;
        2) menu_dns ;;
        3) limpiar_sistema ;;
        4) exit 0 ;;
        *) echo "Opción inválida" ; sleep 1 ;;
    esac
done