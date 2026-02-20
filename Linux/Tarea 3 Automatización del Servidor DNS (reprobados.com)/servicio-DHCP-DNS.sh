#!/bin/bash
# --- VARIABLES GLOBALES PARA COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
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

# --- 1. ESTADO DEL SERVICIO ---
estado_servicio() {
    while true; do
        clear
        echo "----------------------------------------"
        echo "        ESTADO DEL SERVICIO DHCP"
        echo "----------------------------------------"

        if ! rpm -q kea &> /dev/null; then
            echo -e "${RED}[!] El paquete 'kea' NO está instalado.${NC}"
            echo "Por favor, use la opción 2 para instalarlo."
            read -p "Presione Enter para volver..."
            return
        fi

        # Verificamos estado y mostramos opciones dinámicas
        if systemctl is-active --quiet kea-dhcp4; then
            echo -e "Estado Actual: ${GREEN}ACTIVO (Running)${NC}"
            systemctl status kea-dhcp4 --no-pager | grep "Active:"
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

        echo "----------------------------------------"
        read -p "Seleccione una opción: " sub_opcion

        case $sub_opcion in
            1)
                if systemctl is-active --quiet kea-dhcp4; then
                    echo -e "${RED}Deteniendo servicio KEA...${NC}"
                    systemctl stop kea-dhcp4
                else
                    echo -e "${GREEN}Iniciando servicio KEA...${NC}"
                    systemctl start kea-dhcp4
                fi
                sleep 1.5
                ;;
            2)
                if systemctl is-active --quiet kea-dhcp4; then
                    echo -e "${GREEN}Reiniciando servicio KEA...${NC}"
                    systemctl restart kea-dhcp4
                    sleep 1.5
                else
                    echo "El servicio no está activo, no se puede reiniciar."
                    sleep 1.5
                fi
                ;;
            3)
                return ;;
            *)
                echo "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

# --- 2. INSTALACION (SILENCIOSA) ---
instalar_servicio() {
    echo "----------------------------------------"
    echo "        INSTALACIÓN DEL SERVICIO"
    echo "----------------------------------------"

    if rpm -q kea &> /dev/null; then
        echo "El servicio ya está instalado."
        read -p "Presione Enter..."
        return
    fi

    echo "Iniciando instalación desatendida... Por favor espere."
    
    (
        dnf install -y epel-release oracle-epel-release-el10
        dnf install -y kea
    ) &> /dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[EXITO] Instalación completada correctamente.${NC}"
    else
        echo -e "${RED}[ERROR] La instalación falló.${NC}"
    fi
    read -p "Presione Enter..."
}

# --- 4. CONFIGURACION DHCP ---
configurar_servicio() {
    clear
    echo "========================================"
    echo "   CONFIGURACION DE DHCP"
    echo "========================================"

    if ! rpm -q kea &> /dev/null; then
        echo "Error: Instale el servicio primero."
        read -p "Enter..."
        return
    fi

    echo "Interfaces disponibles:"
    ip -o link show | awk -F': ' '{print " - " $2}'
    echo "----------------------------------------"
    
    while true; do
        read -p "1. Adaptador de red: " INTERFAZ
        if ip link show "$INTERFAZ" &> /dev/null; then break; fi
        echo -e "${RED}   [!] La interfaz no existe.${NC}"
    done

    if command -v nmcli &> /dev/null; then
        nmcli device set "$INTERFAZ" managed no &> /dev/null
    fi

    read -p "2. Nombre del Ámbito: " SCOPE_NAME

    # --- RANGO INICIAL (IP DEL SERVIDOR) ---
    while true; do
        read -p "3. Rango inicial (IP Servidor): " IP_INICIO
        # Validamos usando la nueva lógica
        if validar_ip_utilizable "$IP_INICIO"; then break; fi
        echo -e "${RED}   [!] IP inválida o reservada.${NC}"
    done

    PREFIX=$(echo "$IP_INICIO" | cut -d'.' -f1-3)
    LAST_OCTET=$(echo "$IP_INICIO" | cut -d'.' -f4)
    
    POOL_START_OCTET=$((LAST_OCTET + 1))
    POOL_START="$PREFIX.$POOL_START_OCTET"
    SUBNET="$PREFIX.0"

    # --- RANGO FINAL ---
    while true; do
        read -p "4. Rango final ($PREFIX.X): " IP_FIN
        
        if ! validar_ip_utilizable "$IP_FIN"; then 
            echo -e "${RED}   [!] IP inválida.${NC}"; continue
        fi

        PREFIX_FIN=$(echo "$IP_FIN" | cut -d'.' -f1-3)
        if [ "$PREFIX" != "$PREFIX_FIN" ]; then
            echo -e "${RED}   [!] La IP debe estar en el segmento $PREFIX.x${NC}"; continue
        fi

        INT_POOL_START=$(ip_to_int "$POOL_START")
        INT_FIN=$(ip_to_int "$IP_FIN")

        if [ $INT_POOL_START -le $INT_FIN ]; then
            break
        else
            echo -e "${RED}   [!] Error: El rango final debe ser mayor o igual a $POOL_START.${NC}"
        fi
    done

    # --- GATEWAY (MODIFICADO) ---
    while true; do
        read -p "5. Gateway (Enter para omitir): " GATEWAY
        
        # Opción 1: Usuario presiona Enter (vacío) -> Se permite y sale del bucle
        if [ -z "$GATEWAY" ]; then 
            break 
        fi
        
        # Opción 2: Usuario ingresa algo -> Se valida IP y Segmento
        if validar_ip_utilizable "$GATEWAY"; then
            GW_PREFIX=$(echo "$GATEWAY" | cut -d'.' -f1-3)
            if [ "$GW_PREFIX" == "$PREFIX" ]; then
                break
            else
                echo -e "${RED}   [!] El Gateway debe pertenecer a la red $PREFIX.x${NC}"
            fi
        else
            echo -e "${RED}   [!] IP inválida.${NC}"
        fi
    done

    read -p "6. DNS (Enter para omitir): " DNS_SERVER
    if [ -n "$DNS_SERVER" ] && ! validar_formato_ip "$DNS_SERVER"; then
        echo "   [!] DNS inválido, se omitirá."
        DNS_SERVER=""
    fi

    while true; do
        read -p "7. Tiempo de concesión (segundos): " LEASE_TIME
        if [[ "$LEASE_TIME" =~ ^[0-9]+$ ]]; then break; fi
        echo -e "${RED}   [!] Debe ser un número entero.${NC}"
    done

    # --- RESUMEN ---
    clear
    echo "========================================"
    echo "        RESUMEN DE CONFIGURACIÓN"
    echo "========================================"
    echo "1- Adaptador de red:    $INTERFAZ"
    echo "2- Nombre del ambito:   $SCOPE_NAME"
    echo "3- Rango inicial (srv): $IP_INICIO"
    echo "4- Rango final:         $IP_FIN"
    echo "   -> Pool DHCP real:   $POOL_START a $IP_FIN"
    
    if [ -z "$GATEWAY" ]; then
        echo "5- GateWay:             (Ninguno)"
    else
        echo "5- GateWay:             $GATEWAY"
    fi

    echo "6- DNS:                 $DNS_SERVER"
    echo "7- Tiempo de concesión: $LEASE_TIME"
    echo "========================================"
    read -p "Confirmar configuración (S/N): " CONFIRM
    
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo "Configuración cancelada."
        return
    fi

    echo "Configurando IP estática en $INTERFAZ..."
    sudo ip link set "$INTERFAZ" down
    sudo ip addr flush dev "$INTERFAZ"
    sudo ip addr add "$IP_INICIO/24" dev "$INTERFAZ"
    sudo ip link set "$INTERFAZ" up
    sleep 2

    echo "Generando archivo de configuración Kea..."
    
    OPTIONS_BLOCK=""
    # Solo agrega la opción routers si GATEWAY no está vacío
    if [ -n "$GATEWAY" ]; then OPTIONS_BLOCK="$OPTIONS_BLOCK { \"name\": \"routers\", \"data\": \"$GATEWAY\" },"; fi
    
    if [ -n "$DNS_SERVER" ]; then OPTIONS_BLOCK="$OPTIONS_BLOCK { \"name\": \"domain-name-servers\", \"data\": \"$DNS_SERVER\" },"; fi
    OPTIONS_BLOCK=$(echo "$OPTIONS_BLOCK" | sed 's/,$//')

    [ -f /etc/kea/kea-dhcp4.conf ] && cp /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.bak

    cat <<EOF > /etc/kea/kea-dhcp4.conf
{
    "Dhcp4": {
        "interfaces-config": { "interfaces": [ "$INTERFAZ" ] },
        "lease-database": {
            "type": "memfile",
            "persist": true,
            "name": "/var/lib/kea/kea-leases4.csv"
        },
        "valid-lifetime": $LEASE_TIME,
        "max-valid-lifetime": $(($LEASE_TIME * 2)),
        "subnet4": [
            {
                "id": 1,
                "subnet": "$SUBNET/24",
                "user-context": { "name": "$SCOPE_NAME" }, 
                "pools": [ { "pool": "$POOL_START - $IP_FIN" } ],
                "option-data": [ $OPTIONS_BLOCK ]
            }
        ]
    }
}
EOF

    echo "Reiniciando servicio..."
    firewall-cmd --add-service=dhcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null
    systemctl restart kea-dhcp4
    
    if systemctl is-active --quiet kea-dhcp4; then
        echo -e "${GREEN}[EXITO] Servicio configurado y activo.${NC}"
    else
        echo -e "${RED}[ERROR] Kea no pudo iniciar.${NC}"
    fi
    read -p "Presione Enter..."
}

# --- 5. MONITOREO ---
monitorear_servicio() {
    LEASE_FILE="/var/lib/kea/kea-leases4.csv"
    
    watch -n 2 -t "
      echo '==========================================================================';
      echo '                   ESTADO DEL SERVICIO DHCP';
      echo '==========================================================================';
      if systemctl is-active --quiet kea-dhcp4; then echo 'Estado: ACTIVO'; else echo 'Estado: INACTIVO'; fi
      echo '--------------------------------------------------------------------------';
      echo 'Clientes Conectados:';
      printf '%-20s | %-20s | %-30s\n' 'DIRECCION IP' 'MAC ADDRESS' 'HOSTNAME';
      echo '---------------------|----------------------|-----------------------------';
      
      if [ -f $LEASE_FILE ]; then
         tail -n +2 $LEASE_FILE | awk -F, '{printf \"%-20s | %-20s | %-30s\n\", \$1, \$2, \$9}'
      else
         echo '             Sin base de datos de concesiones...'
      fi
    "
}

# =====================================================
# DNS
# =====================================================

estado_dns() {
    while true; do
        clear
        echo "========================================"
        echo "        ESTADO DEL SERVICIO DNS"
        echo "========================================"

        if ! rpm -q bind &> /dev/null; then
            echo -e "${RED}[!] El paquete 'bind' no está instalado.${NC}"
            echo "Use la opción de instalar servicio primero."
            read -p "Presione Enter..."
            return
        fi

        if systemctl is-active --quiet named; then
            echo -e "Estado actual: ${GREEN}ACTIVO (Running)${NC}"
            systemctl status named --no-pager | grep Active
            echo "----------------------------------------"
            echo "1) Detener servicio"
            echo "2) Reiniciar servicio"
            echo "3) Volver al menú DNS"
        else
            echo -e "Estado actual: ${RED}INACTIVO (Stopped)${NC}"
            echo "----------------------------------------"
            echo "1) Iniciar servicio"
            echo "3) Volver al menú DNS"
        fi

        echo "----------------------------------------"
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                if systemctl is-active --quiet named; then
                    echo "Deteniendo servicio..."
                    systemctl stop named
                else
                    echo "Iniciando servicio..."
                    systemctl start named
                fi
                sleep 2
                ;;
            2)
                if systemctl is-active --quiet named; then
                    echo "Reiniciando servicio..."
                    systemctl restart named
                    sleep 2
                else
                    echo "El servicio está detenido. No se puede reiniciar."
                    sleep 2
                fi
                ;;
            3)
                return
                ;;
            *)
                echo "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

# Función para instalar el servicio DNS
instalar_dns() {

    if rpm -q bind &> /dev/null; then
        echo "El servicio DNS ya está instalado."
        read -p "Enter..."
        return
    fi

    echo "Instalando BIND..."
    dnf install -y bind bind-utils &> /dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[EXITO] Instalación completada.${NC}"
        systemctl enable named &> /dev/null
        systemctl start named
    else
        echo -e "${RED}[ERROR] Falló la instalación.${NC}"
    fi

    read -p "Enter..."
}

#Función para crear un dominio
nuevo_dominio() {

    read -p "Ingrese el nombre del dominio (ej: reprobados.com): " DOMINIO

    if [ -z "$DOMINIO" ]; then
        echo "Dominio inválido."
        sleep 2
        return
    fi

    
    read -p "Ingrese la interfaz de red interna (ej: enp0s8): " INTERFAZ_DNS
    IP_SERVIDOR=$(ip -4 addr show "$INTERFAZ_DNS" | grep inet | awk '{print $2}' | cut -d/ -f1)
    ZONA_FILE="/var/named/$DOMINIO.zone"

    # Verificar si ya existe
    if grep -q "zone \"$DOMINIO\"" /etc/named.conf; then
        echo "El dominio ya existe."
        sleep 2
        return
    fi

    echo "Creando zona DNS..."

    # Agregar zona a named.conf
    cat <<EOF >> /etc/named.conf

zone "$DOMINIO" IN {
    type master;
    file "$ZONA_FILE";
};
EOF

    # Crear archivo de zona
    cat <<EOF > $ZONA_FILE
\$TTL 86400
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
        2026021701
        3600
        1800
        604800
        86400 )

@       IN  NS      ns1.$DOMINIO.
ns1     IN  A       $IP_SERVIDOR
@       IN  A       $IP_SERVIDOR
www     IN  A       $IP_SERVIDOR
EOF

    chown named:named $ZONA_FILE
    chmod 640 $ZONA_FILE

    firewall-cmd --add-service=dns --permanent &> /dev/null
    firewall-cmd --reload &> /dev/null

    systemctl restart named

    if systemctl is-active --quiet named; then
        echo -e "${GREEN}[EXITO] Dominio $DOMINIO creado correctamente.${NC}"
        echo "IP asociada: $IP_SERVIDOR"
    else
        echo -e "${RED}[ERROR] named no pudo iniciar.${NC}"
    fi

    read -p "Enter..."
}

#Función para borrar un dominio
borrar_dominio() {

    read -p "Ingrese el dominio a eliminar: " DOMINIO
    ZONA_FILE="/var/named/$DOMINIO.zone"

    if ! grep -q "zone \"$DOMINIO\"" /etc/named.conf; then
        echo "El dominio no existe."
        sleep 2
        return
    fi

    # Eliminar bloque de zona
    sed -i "/zone \"$DOMINIO\"/,/};/d" /etc/named.conf

    # Eliminar archivo de zona
    rm -f $ZONA_FILE

    systemctl restart named

    echo -e "${GREEN}Dominio eliminado correctamente.${NC}"
    read -p "Enter..."
}

#Función para consultar un dominio
consultar_dominio() {

    clear
    echo "========================================"
    echo "         CONSULTAR DOMINIO"
    echo "========================================"

    # Obtener lista de dominios definidos
    DOMINIOS=($(grep -oP 'zone\s+"\K[^"]+' /etc/named.conf))

    if [ ${#DOMINIOS[@]} -eq 0 ]; then
        echo "No hay dominios configurados."
        read -p "Enter..."
        return
    fi

    echo "Dominios disponibles:"
    echo "----------------------------------------"

    # Mostrar lista numerada
    for i in "${!DOMINIOS[@]}"; do
        echo "$((i+1))) ${DOMINIOS[$i]}"
    done

    echo "----------------------------------------"
    read -p "Seleccione un dominio: " opcion

    # Validar selección
    if ! [[ "$opcion" =~ ^[0-9]+$ ]] || [ "$opcion" -lt 1 ] || [ "$opcion" -gt ${#DOMINIOS[@]} ]; then
        echo "Selección inválida."
        sleep 2
        return
    fi

    DOMINIO_SELECCIONADO=${DOMINIOS[$((opcion-1))]}

    clear
    echo "========================================"
    echo "Dominio seleccionado: $DOMINIO_SELECCIONADO"
    echo "========================================"

    # Mostrar IP asociada
    echo "Direccion IP asociada al dominio:"
    dig @localhost +short "$DOMINIO_SELECCIONADO"

    echo "----------------------------------------"
    read -p "Enter..."
}

limpiar_sistema() {
    clear
    echo "========================================"
    echo "       LIMPIANDO CACHÉ DE RED"
    echo "========================================"
    
    # Limpia DHCP (Kea)
    echo "1. Limpiando concesiones DHCP..."
    sudo systemctl stop kea-dhcp4 &> /dev/null
    sudo rm -f /var/lib/kea/kea-leases4.csv  # El -f evita errores si no existe
    sudo systemctl start kea-dhcp4
    
    # Limpia DNS (Bind)
    echo "2. Vaciando caché de BIND DNS..."
    sudo rndc flush || sudo systemctl restart named  # rndc flush es el comando correcto para BIND
    
    echo "3. Limpiando caché del sistema Linux..."
    sudo resolvectl flush-caches &> /dev/null || echo "Resolvectl no disponible, omitiendo..."
    
    echo -e "\n${GREEN}[OK] Caché de servicios limpia correctamente.${NC}"
    echo -e "${CYAN}Nota: Recuerda ejecutar 'ipconfig /flushdns' en tu cliente Windows.${NC}"
    read -p "Presione Enter para volver..."
}

# =====================================================
# MENUS
# =====================================================

menu_dhcp() {
while true; do
clear
echo -e "${CYAN}GESTOR DHCP${NC}"
echo "1. Verificar Estado del Servicio"
echo "2. Instalar Servicio"
echo "3. Configurar Servicio"
echo "4. Monitorear Servicio"
echo "5. Volver"
read -p "Seleccione: " op

case $op in 
1) estado_servicio ;;
2) instalar_servicio ;;
3) configurar_servicio ;;
4) monitorear_servicio ;;
5) break ;;
*) echo "Opción inválida"; sleep 1 ;;
esac

done
}

menu_dns() {
while true; do
clear
echo -e "${MAGENTA}GESTOR DNS${NC}"
echo "1) Estado"
echo "2) Instalar"
echo "3) Nuevo Dominio"
echo "4) Borrar Dominio"
echo "5) Consultar Dominio"
echo "6) Volver"
read -p "Seleccione: " op
case $op in
1) estado_dns ;;
2) instalar_dns ;;
3) nuevo_dominio ;;
4) borrar_dominio ;;
5) consultar_dominio ;;
6) break ;;
esac
done
}

# =====================================================
# MENU GLOBAL
# =====================================================

while true; do
clear
echo -e "${BOLD}SISTEMA DE ADMINISTRACION DE RED${NC}"
echo "1) Gestionar DHCP"
echo "2) Gestionar DNS"
echo "3) Limpiar Caché (DHCP/DNS)"
echo "4) Salir"
read -p "Seleccione: " op
case $op in
1) menu_dhcp ;;
2) menu_dns ;;
3) limpiar_sistema ;;
4) exit ;;
