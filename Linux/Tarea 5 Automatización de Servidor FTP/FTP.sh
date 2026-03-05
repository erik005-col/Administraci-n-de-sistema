#!/bin/bash

# --- VALIDACIÓN DE ROOT ---
if [[ $EUID -ne 0 ]]; then
  echo "Error: Este script debe ejecutarse como root (sudo)."
  exit 1
fi

# --- VARIABLES GLOBALES ---
CONF="/etc/vsftpd/vsftpd.conf"
RAIZ_FTP="/ftp"

# --- FUNCIONES DE SOPORTE ---
configurar_firewall(){
    if systemctl is-active --quiet firewalld; then
       firewall-cmd --permanent --add-service=ftp
       firewall-cmd --permanent --add-port=40000-40100/tcp
       firewall-cmd --reload
       echo "Firewall configurado."
    fi
}

configurar_selinux(){
    if command -v getenforce &>/dev/null; then
        setsebool -P ftpd_full_access 1 2>/dev/null
        echo "SELinux ajustado."
    fi
}

# --- OPCIONES DEL MENÚ ---

instalar_ftp(){
    echo "Instalando vsftpd..."
    dnf install -y vsftpd > /dev/null 2>&1
    systemctl enable --now vsftpd
    configurar_firewall
    configurar_selinux
    echo "Servicio instalado y activo."
}

configurar_vsftpd(){
    cp -n "$CONF" "$CONF.bak"
    cat <<EOF > "$CONF"
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
anon_root=$RAIZ_FTP
listen=NO
listen_ipv6=YES
pam_service_name=vsftpd
userlist_enable=YES
EOF
    systemctl restart vsftpd
    echo "Archivo vsftpd.conf optimizado."
}

crear_estructura_base(){
    mkdir -p "$RAIZ_FTP"/{general,reprobados,recursadores}
    groupadd -f reprobados
    groupadd -f recursadores
    groupadd -f ftpusuarios

    # Permisos Raíz
    chown root:root "$RAIZ_FTP"
    chmod 755 "$RAIZ_FTP"

    # Carpeta General (Lectura anónima, escritura para logueados)
    chown root:ftpusuarios "$RAIZ_FTP/general"
    chmod 775 "$RAIZ_FTP/general"

    # Carpetas de Grupo
    chown root:reprobados "$RAIZ_FTP/reprobados"
    chown root:recursadores "$RAIZ_FTP/recursadores"
    chmod 2770 "$RAIZ_FTP/reprobados"
    chmod 2770 "$RAIZ_FTP/recursadores"
    
    echo "Estructura y grupos creados."
}

crear_usuarios_masivo(){
    read -p "¿Cuántos usuarios registrar?: " n
    for (( i=1; i<=n; i++ )); do
        echo -e "\n--- Usuario $i ---"
        read -p "Nombre: " nombre
        read -s -p "Password: " pass; echo
        read -p "Grupo (reprobados/recursadores): " grupo

        if [[ "$grupo" != "reprobados" && "$grupo" != "recursadores" ]]; then
            echo "Grupo no válido, saltando..."
            continue
        fi

        # Crear usuario con Home apuntando a la raíz FTP
        # -d define el directorio, -M no crea /home/usuario tradicional
        useradd -d "$RAIZ_FTP" -s /sbin/nologin -G "$grupo,ftpusuarios" "$nombre"
        echo "$nombre:$pass" | chpasswd

        # Carpeta Personal
        mkdir -p "$RAIZ_FTP/$nombre"
        chown "$nombre":"$grupo" "$RAIZ_FTP/$nombre"
        chmod 700 "$RAIZ_FTP/$nombre"
        
        echo "Usuario $nombre configurado."
    done
}

cambiar_grupo(){
    read -p "Nombre del usuario: " nombre
    read -p "Nuevo grupo (reprobados/recursadores): " nuevo
    if id "$nombre" &>/dev/null; then
        # Remover de grupos viejos y asignar nuevo
        usermod -g "$nuevo" "$nombre"
        # Actualizar dueño de su carpeta personal
        chown "$nombre":"$nuevo" "$RAIZ_FTP/$nombre"
        echo "Usuario movido a $nuevo."
    else
        echo "Usuario no existe."
    fi
}

eliminar_usuario(){
    read -p "Usuario a eliminar: " nombre
    if id "$nombre" &>/dev/null; then
        userdel "$nombre"
        rm -rf "$RAIZ_FTP/$nombre"
        echo "Usuario y su carpeta personal eliminados."
    else
        echo "No existe el usuario."
    fi
}

ver_usuarios(){
    echo -e "\n--- Usuarios en Grupos FTP ---"
    echo "REPROBADOS:"
    getent group reprobados | cut -d: -f4
    echo "RECURSADORES:"
    getent group recursadores | cut -d: -f4
}

# --- MENÚ PRINCIPAL ---
while true; do
    echo -e "\n*****************************************"
    echo "* SISTEMA DE GESTIÓN FTP (LINUX)      *"
    echo "*****************************************"
    echo "1) Instalación y Configuración Inicial"
    echo "2) Crear Estructura y Grupos"
    echo "3) Creación Masiva de Usuarios"
    echo "4) Cambiar Usuario de Grupo"
    echo "5) Ver Estado del Servicio FTP"
    echo "6) Ver Usuarios FTP"
    echo "7) Eliminar Usuario"
    echo "0) Salir"
    read -p "Seleccione opción: " opt

    case $opt in
        1) instalar_ftp; configurar_vsftpd ;;
        2) crear_estructura_base ;;
        3) crear_usuarios_masivo ;;
        4) cambiar_grupo ;;
        5) systemctl status vsftpd ;;
        6) ver_usuarios ;;
        7) eliminar_usuario ;;
        0) break ;;
        *) echo "Opción no válida." ;;
    esac
done