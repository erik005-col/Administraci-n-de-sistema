#!/bin/bash
# ==============================================================
# Archivo: main_p11.sh
# Práctica 11 — Infraestructura como Código (IaC)
# Orquestación multicapa con Docker Compose
# ==============================================================

# Verificar privilegios root
if [ "$EUID" -ne 0 ]; then
    echo "============================================================"
    echo " ERROR: Este script requiere privilegios administrativos."
    echo " Ejecuta: sudo bash main_p11.sh"
    echo "============================================================"
    exit 1
fi

# Cargar funciones
if [ -f "./funciones11.sh" ]; then
    source ./funciones11.sh
else
    echo "ERROR: No se encontró funciones_p11.sh en el directorio actual."
    exit 1
fi

# Menú principal
while true; do
    clear
    echo "=========================================================="
    echo "   Práctica 11: Infraestructura como Código (IaC)"
    echo "   Orquestación Multicapa con Docker Compose"
    echo "=========================================================="
    echo " 1. Validar e Instalar Dependencias (Docker, SSH)"
    echo " 2. Preparar Estructura de Carpetas y .env"
    echo " 3. Generar Archivos de Configuración (Compose, nginx)"
    echo " 4. Desplegar Infraestructura Completa"
    echo " 5. Configurar Firewall (bloquear puertos internos)"
    echo " 6. Ejecutar Protocolo de Pruebas (Validación P11)"
    echo " 7. Gestionar Infraestructura (detener/reiniciar/limpiar)"
    echo ""
    echo " 0. Salir"
    echo "=========================================================="
    read -p " Selecciona una opción: " opcion

    case $opcion in
        1) instalar_dependencias ;;
        2) preparar_entorno_docker ;;
        3) generar_archivos_configuracion ;;
        4) desplegar_contenedores ;;
        5) configurar_firewall ;;
        6) menu_pruebas ;;
        7) limpiar_infraestructura ;;
        0)
            echo "Saliendo. ¡Hasta luego!"
            exit 0
            ;;
        *)
            echo "Opción no válida."
            sleep 2
            ;;
    esac
done