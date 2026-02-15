#!/bin/bash

# =========================================================
# GESTOR DHCP PRO - KEA DHCP (LINUX)
# =========================================================

# Variables Globales
RESPALDO_IP=""
RESPALDO_MASK=""
INTERFAZ="enp0s8"
CONF_KEA="/etc/kea/kea-dhcp4.conf"

# Colores para la terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# ================= FUNCIONES DE APOYO =================

validar_ip(){
    local ip=$1
    local expresionRegular="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    if ! [[ $ip =~ $expresionRegular ]]; then return 1; fi

    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    for octeto in $o1 $o2 $o3 $o4; do
        if ((octeto < 0 || octeto > 255)); then return 1; fi
    done

    if [[ "$ip" == "0.0.0.0" || "$ip" == "127.0.0.1" ]]; then return 1; fi
    return 0
}

pedir_ip() {
    local mensaje=$1
    local opcional=$2
    while true; do
        read -p "$mensaje: " ip
        if [[ -z "$ip" && "$opcional" == "true" ]]; then
            echo ""
            return
        fi
        if validar_ip "$ip"; then
            echo "$ip"
            return
        else
            echo -e "${RED}¡Error! IP inválida.${NC}" >&2
        fi
    done
}

# ================= FUNCIONES DE RED =================

cambiar_ip_servidor() {
    local nueva_ip=$1
    
    # Respaldo de la IP actual
    RESPALDO_IP=$(ip -4 addr show $INTERFAZ | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    RESPALDO_MASK=$(ip -4 addr show $INTERFAZ | grep -oP '(?<=inet\s\d+(\.\d+){3}/)\d+' | head -n 1)

    echo -e "${GRAY}[!] Respaldo guardado de $INTERFAZ: $RESPALDO_IP/$RESPALDO_MASK${NC}"
    echo -e "${YELLOW}[!] Configurando IP estática $nueva_ip en $INTERFAZ...${NC}"
    
    sudo ip addr flush dev $INTERFAZ
    sudo ip addr add "$nueva_ip/24" dev $INTERFAZ
    sudo ip link set $INTERFAZ up
    
    echo -e "${GREEN}OK: IP asignada correctamente.${NC}"
}

restaurar_ip_original() {
    if [ -z "$RESPALDO_IP" ]; then
        echo -e "${YELLOW}No hay datos de respaldo.${NC}"
        return
    fi
    echo -e "${CYAN}[!] Restaurando $INTERFAZ a $RESPALDO_IP/$RESPALDO_MASK...${NC}"
    sudo ip addr flush dev $INTERFAZ
    sudo ip addr add "$RESPALDO_IP/$RESPALDO_MASK" dev $INTERFAZ
    echo -e "${GREEN}OK: Servidor restaurado.${NC}"
    RESPALDO_IP=""
}

# ================= MODULOS DHCP =================

instalar_kea(){
    echo -e "\nVerificando Kea DHCP..."
    if rpm -q kea &>/dev/null; then
        echo -e "${YELLOW}Kea ya está instalado.${NC}"
        read -p "¿Desea reinstalarlo? (s/n): " opcion
        if [[ "$opcion" =~ ^[Ss]$ ]]; then
            sudo dnf reinstall -y kea
        fi
    else
        echo "Instalando KEA DHCP..."
        sudo dnf install -y kea
    fi
}

configurar_dhcp() {
    clear
    echo -e "${CYAN}===== CONFIGURACION DE KEA DHCP ($INTERFAZ) =====${NC}"
    
    # Listar interfaces para que el usuario elija bien
    ip -o link show | awk -F': ' '{print " - " $2}'
    read -p ">> Confirmar Interfaz (ej: enp0s8): " INTERFAZ

    if ! ip link show "$INTERFAZ" &> /dev/null; then
        echo -e "${RED}Error: La interfaz no existe.${NC}"
        return 1
    fi

    local ip_servidor=$(pedir_ip "IP del Servidor (Esta máquina)")
    local ip_inicio=$(pedir_ip "IP Inicial del Rango")
    local ip_fin=$(pedir_ip "IP Final del Rango")
    local gateway=$(pedir_ip "Gateway (Opcional)" "true")
    local dns=$(pedir_ip "DNS (Opcional)" "true")
    local lease=$(read -p "Tiempo de Concesión (segundos, defecto 4000): " res; echo ${res:-4000})

    cambiar_ip_servidor "$ip_servidor"

    local red_base=$(echo $ip_servidor | cut -d. -f1-3).0

    # Generar configuración en formato JSON (Kea Style)
    sudo bash -c "cat > $CONF_KEA" <<EOF
{
"Dhcp4": {
    "interfaces-config": {
        "interfaces": [ "$INTERFAZ" ]
    },
    "lease-database": {
        "type": "memfile",
        "persist": true,
        "name": "/var/lib/kea/kea-leases4.csv",
        "lfc-interval": 3600
    },
    "valid-lifetime": $lease,
    "subnet4": [
        {
            "subnet": "$red_base/24",
            "pools": [ { "pool": "$ip_inicio - $ip_fin" } ],
            "option-data": [
                { "name": "routers", "data": "$gateway" },
                { "name": "domain-name-servers", "data": "$dns" }
            ]
        }
    ]
}
}
EOF

    echo -e "${YELLOW}Reiniciando Kea DHCP...${NC}"
    sudo systemctl enable kea-dhcp4
    sudo systemctl restart kea-dhcp4
    
    if systemctl is-active --quiet kea-dhcp4; then
        echo -e "${GREEN}[OK] DHCP configurado y activo.${NC}"
    else
        echo -e "${RED}[ERROR] El servicio no arrancó. Revisa la config en $CONF_KEA${NC}"
    fi
}

# ================= MENU PRINCIPAL =================

while true; do
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}    GESTOR KEA DHCP - FEDORA/CENTOS       ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo "1. Instalar Kea DHCP"
    echo "2. Configurar Ámbito y Red"
    echo "3. Verificar Estado"
    echo "4. Ver Clientes (Leases)"
    echo "5. Ver IP actual de $INTERFAZ"
    echo "6. Restaurar IP Original"
    echo "7. Salir"
    echo "=========================================="
    read -p "Seleccione: " opcion

    case $opcion in
        1) instalar_kea ;;
        2) configurar_dhcp ;;
        3) sudo systemctl status kea-dhcp4 --no-pager ;;
        4) 
            echo "Concesiones actuales (CSV):"
            [ -f /var/lib/kea/kea-leases4.csv ] && sudo cat /var/lib/kea/kea-leases4.csv || echo "Sin clientes aún."
            ;;
        5) ip addr show $INTERFAZ ;;
        6) restaurar_ip_original ;;
        7) exit 0 ;;
        *) echo "Opción no válida." ;;
    esac
    read -p "Presione Enter para continuar..."
done