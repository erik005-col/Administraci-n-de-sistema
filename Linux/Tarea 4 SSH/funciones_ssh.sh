#!/bin/bash

instalar_ssh() {
    echo "Configurando entorno para acceso remoto SSH..."
    dnf install -y openssh-server &> /dev/null
    
    systemctl enable sshd
    systemctl start sshd
    
    # Firewall
    firewall-cmd --permanent --add-service=ssh &> /dev/null
    firewall-cmd --reload &> /dev/null
    
    escribir_log "Servicio SSH instalado y configurado."
    echo -e "${GREEN}[OK] SSH listo. Ya puede conectar desde su cliente.${NC}"
    read -p "Presione Enter..."
}

menu_ssh() {
    while true; do
        clear
        echo -e "${CYAN}--- GESTIÓN SSH ---${NC}"
        echo "1. Instalar y Habilitar SSH"
        echo "2. Verificar Estado"
        echo "3. Volver"
        read -p "Opción: " osh
        case $osh in
            1) instalar_ssh ;;
            2) systemctl status sshd --no-pager; read -p "Enter..." ;;
            3) break ;;
        esac
    done
}