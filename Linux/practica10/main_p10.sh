#!/bin/bash
# Archivo: main_p10.sh
# Práctica 10 - Virtualización con Docker

# Verificar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    echo "============================================================"
    echo " ERROR: Este script requiere privilegios administrativos."
    echo " Ejecuta: sudo bash main_p10.sh"
    echo "============================================================"
    exit 1
fi

# Cargar funciones
if [ -f "./funciones_p10.sh" ]; then
    source ./funciones_p10.sh
else
    echo "ERROR: No se encontró funciones_p10.sh en el directorio actual."
    exit 1
fi

# Menú principal
while true; do
    clear
    echo "=========================================================="
    echo "   Práctica 10: Virtualización Nativa y Contenedores"
    echo "=========================================================="
    echo " 1. Validar e Instalar Dependencias (Docker, Compose)"
    echo " 2. Preparar Estructura de Carpetas y Red (infra_red)"
    echo " 3. Generar Archivos de Configuración Web (Dockerfile)"
    echo " 4. Desplegar Contenedores (Web, BD, FTP)"
    echo " 5. Gestionar Respaldos de Base de Datos (pg_dump + cron)"
    echo " 6. Ejecutar Protocolo de Pruebas (Validación)"
    echo " 7. Gestionar Infraestructura (detener / reiniciar / limpiar)"
    echo ""
    echo " 0. Salir"
    echo "=========================================================="
    read -p " Selecciona una opción: " opcion

    case $opcion in
        1) instalar_dependencias ;;
        2) preparar_entorno_docker ;;
        3) generar_archivos_configuracion ;;
        4) desplegar_contenedores ;;
        5) respaldar_base_datos ;;
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
