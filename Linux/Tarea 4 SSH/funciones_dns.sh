#!/bin/bash
# =====================================================
# DNS - CORREGIDO
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
            3) return ;;
            *) echo "Opción no válida."; sleep 1 ;;
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


nuevo_dominio() {
    read -p "Ingrese el nombre del dominio (ej: cocacola.com): " DOMINIO
    if [ -z "$DOMINIO" ]; then
        echo "Dominio inválido."; sleep 2; return
    fi

    # Verificar si ya existe en named.conf
    if grep -q "zone \"$DOMINIO\"" /etc/named.conf; then
        echo "El dominio ya existe."; sleep 2; return
    fi

    # Función para instalar el servicio DNS
    while true; do
        read -p "Ingrese la dirección IP para el dominio: " IP_DOMINIO
        if [[ $IP_DOMINIO =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            break
        else
            echo "Formato de IP inválido."
        fi
    done

    ZONA_FILE="/var/named/$DOMINIO.zone"

    echo "Creando zona DNS..."

    # Agregamos la zona al final de named.conf
    cat <<EOF >> /etc/named.conf
zone "$DOMINIO" IN {
    type master;
    file "$ZONA_FILE";
};
EOF

    # Crear el archivo de zona
    cat <<EOF > $ZONA_FILE
\$TTL 86400
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
        $(date +%Y%m%d%H)
        3600
        1800
        604800
        86400 )

@       IN  NS      ns1.$DOMINIO.
ns1     IN  A       $IP_DOMINIO
@       IN  A       $IP_DOMINIO
www     IN  A       $IP_DOMINIO
EOF

    chown named:named $ZONA_FILE
    chmod 640 $ZONA_FILE
    
    # IMPORTANTE: Aplicar contexto SELinux para que BIND pueda leerlo
    restorecon -v $ZONA_FILE &> /dev/null

    systemctl restart named

    if systemctl is-active --quiet named; then
        echo "[EXITO] Dominio $DOMINIO creado correctamente."

    else
        echo "[ERROR] named no pudo iniciar. Verifique named.conf."
    fi

    read -p "Enter..."
}

#Función para borrar un dominio
borrar_dominio() {

    read -p "Ingrese el dominio a eliminar: " DOMINIO
    ZONA_FILE="/var/named/$DOMINIO.zone"

    if ! grep -q "zone \"$DOMINIO\"" /etc/named.conf; then
        echo "El dominio no existe."; sleep 2; return
    fi

    # Eliminar bloque de zona de forma segura
    sed -i "/zone \"$DOMINIO\"/,/};/d" /etc/named.conf

    # Eliminar archivo de zona
    rm -f $ZONA_FILE

    systemctl restart named

    echo -e "${GREEN}Dominio eliminado correctamente.${NC}"
    read -p "Enter..."
}

consultar_dominio() {
    clear
    DOMINIOS=($(grep -oP 'zone\s+"\K[^"]+' /etc/named.conf))

    if [ ${#DOMINIOS[@]} -eq 0 ]; then
        echo "No hay dominios configurados."; read -p "Enter..."; return
    fi

    echo "Dominios disponibles:"
    for i in "${!DOMINIOS[@]}"; do
        echo "$((i+1))) ${DOMINIOS[$i]}"
    done

    read -p "Seleccione un dominio: " opcion
    if ! [[ "$opcion" =~ ^[0-9]+$ ]] || [ "$opcion" -lt 1 ] || [ "$opcion" -gt ${#DOMINIOS[@]} ]; then
        echo "Selección inválida."; sleep 2; return
    fi

    DOMINIO_SELECCIONADO=${DOMINIOS[$((opcion-1))]}
    
    clear
    echo "========================================"
    echo "Dominio seleccionado: $DOMINIO_SELECCIONADO"
    echo "========================================"

    dig @localhost +short "$DOMINIO_SELECCIONADO"
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
    sudo rm -f /var/lib/kea/kea-leases4.csv
    sudo systemctl start kea-dhcp4
     
    # Limpia DNS (Bind)
    echo "2. Vaciando caché de BIND DNS..."
    sudo rndc flush || sudo systemctl restart named
    
    echo "3. Limpiando caché del sistema Linux..."
    sudo resolvectl flush-caches &> /dev/null || echo "Resolvectl no disponible."
    
    echo -e "\n${GREEN}[OK] Caché de servicios limpia correctamente.${NC}"
    
    read -p "Presione Enter para volver..."
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
        echo "6) Limpiar Sistema"
        echo "7) Volver"
        read -p "Seleccione: " op
        case $op in
            1) estado_dns ;;
            2) instalar_dns ;;
            3) nuevo_dominio ;;
            4) borrar_dominio ;;
            5) consultar_dominio ;;
            6) limpiar_sistema ;;
            7) break ;;
            *) echo "Opción no válida"; sleep 1 ;;
        esac
    done
}