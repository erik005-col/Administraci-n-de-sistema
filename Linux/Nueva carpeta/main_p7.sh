#!/bin/bash
# ================================================================
# main_p7_linux.sh
# Practica 7 - Infraestructura de Despliegue Seguro e Instalacion
# Hibrida (FTP/Web) - Oracle Linux Server 10.1
# ================================================================

if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root."
    exit 1
fi

source "$(dirname "$0")/funciones_p7.sh"

while true; do
    echo ""
    echo "================================================================"
    echo "  PRACTICA 7 - Despliegue Seguro e Instalacion Hibrida         "
    echo "  Oracle Linux Server 10.1 | FTP + HTTP + SSL/TLS              "
    echo "================================================================"
    echo ""
    echo "  -- SERVIDOR FTP LOCAL --"
    echo "  1) Administrar servidor FTP"
    echo "     (Instalar, configurar, crear usuarios, grupos)"
    echo ""
    echo "  -- DEPENDENCIAS --"
    echo "  2) Instalar dependencias (openssl, curl, wget)"
    echo ""
    echo "  -- REPOSITORIO FTP --"
    echo "  3) Preparar repositorio FTP"
    echo "     (Descarga RPMs/tar.gz y genera .sha256)"
    echo ""
    echo "  -- INSTALACION HIBRIDA (WEB o FTP) --"
    echo "  4) Instalar Apache"
    echo "  5) Instalar Nginx"
    echo "  6) Instalar Tomcat"
    echo ""
    echo "  -- SSL/TLS --"
    echo "  7) Activar SSL en Apache  (HTTPS puerto 443)"
    echo "  8) Activar SSL en Nginx   (HTTPS puerto 443)"
    echo "  9) Activar SSL en Tomcat  (HTTPS puerto 8443)"
    echo " 10) Activar FTPS en vsftpd"
    echo ""
    echo "  -- UTILIDADES --"
    echo " 11) Ver estado de todos los servicios"
    echo " 12) Mostrar resumen final (evidencias)"
    echo " 13) Iniciar / Detener servicios"
    echo "  0) Salir"
    echo ""
    read -p "Seleccione opcion: " OPCION

    case $OPCION in
        1)  menu_administrar_ftp ;;
        2)  instalar_dependencias ;;
        3)  preparar_repositorio_ftp ;;
        4)  flujo_instalar_servicio "Apache" ;;
        5)  flujo_instalar_servicio "Nginx" ;;
        6)  flujo_instalar_servicio "Tomcat" ;;
        7)  activar_ssl_apache ;;
        8)  activar_ssl_nginx ;;
        9)  activar_ssl_tomcat ;;
        10) activar_ftps_vsftpd ;;
        11) ver_estado_servicios ;;
        12) mostrar_resumen_final ;;
        13) gestionar_servicios_http ;;
        0)
            echo ""
            mostrar_resumen_final
            echo "Saliendo."
            exit 0
            ;;
        *)  echo "  Opcion no valida." ;;
    esac
done
