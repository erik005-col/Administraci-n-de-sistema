#!/bin/bash
# =====================================================
# SISTEMA DE ADMINISTRACION DE RED MODULAR
# =====================================================

# Cargar bibliotecas
source ./funciones_util.sh
source ./funciones_dhcp.sh
source ./funciones_dns.sh
source ./funciones_ssh.sh

# Validaciones iniciales
verificar_root
preparar_entorno
escribir_log "Sistema iniciado por el usuario $USER"

BOLD='\033[1m'

while true; do
    clear
    echo -e "${BOLD}SISTEMA DE ADMINISTRACION DE RED MODULAR${NC}"
    echo "1) Gestionar SSH (Acceso Remoto)"
    echo "2) Gestionar DHCP (Kea)"
    echo "3) Gestionar DNS (Bind)"
    echo "4) Salir"
    echo "----------------------------------------"
    read -p "Seleccione: " op
    case $op in
        1) menu_ssh ;;
        2) menu_dhcp ;;
        3) menu_dns ;;
        4) escribir_log "Sistema cerrado"; exit 0 ;;
        *) msg_error "Opción inválida" ;;
    esac
done