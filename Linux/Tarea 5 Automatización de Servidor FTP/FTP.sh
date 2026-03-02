#!/bin/bash
BASE_DIR="/srv/ftp"
PUBLIC_DIR="$BASE_DIR/general"
GROUPS=("reprobados" "recursadores")

# 1. Función de Instalación
intalar_ftp() {
    echo "============================================="
    echo "          Instalación de FTP (DNF)           "
    echo "============================================="

    # En Oracle Linux usamos dnf
    dnf install -y vsftpd

    # Creamos directorios base si no existen
    mkdir -p $PUBLIC_DIR

    # Permisos para la carpeta pública (lectura para todos)
    chmod 755 $PUBLIC_DIR

    # Crear grupos y sus carpetas
    for g in "${GROUPS[@]}"; do
        groupadd -f $g
        mkdir -p $BASE_DIR/$g
        chgrp $g $BASE_DIR/$g
        chmod 770 $BASE_DIR/$g # Solo dueño y grupo pueden entrar
    done

    # Configuración del archivo vsftpd
    cp /etc/vsftpd.conf /etc/vsftpd.conf.bak 2>/dev/null

cat > /etc/vsftpd.conf <<EOF
listen=YES
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
anon_root=$PUBLIC_DIR
local_root=$BASE_DIR
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
EOF

    systemctl enable vsftpd
    systemctl restart vsftpd
    echo "Servicio listo."
}

# 2. Función de creación de usuarios
crear_usuario_ftp() {
    read -p "¿Cuántos usuarios desea crear?: " num_users

    # Usamos la variable que el usuario ingresó
    for ((i=1; i<=$num_users; i++)); do
        echo "--------- Registro de Usuario $i ---------"
        read -p "Nombre de usuario: " username
        read -s -p "Contraseña: " password
        echo
        read -p "Grupo (reprobados/recursadores): " grupo_op

        # Crear usuario
        useradd -m -d "$BASE_DIR/$username" -s /sbin/nologin $username
        echo "$username:$password" | chpasswd

        
        if [[ "$grupo_op" == "reprobados" || "$grupo_op" == "recursadores" ]]; then
            usermod -aG $grupo_op $username
            # IMPORTANTE: Aquí asignamos la propiedad de su carpeta personal
            chown $username:$grupo_op $BASE_DIR/$username
            chmod 700 $BASE_DIR/$username
        else
            echo "Grupo no válido."
        fi
        echo "Usuario $username creado."
    done
}

# 3. Cambiar grupo
cambiar_grupo() {
    read -p "Usuario a modificar: " user
    echo "Seleccione el nuevo grupo:"
    # Select crea un menú automático con los elementos de un array
    select grp in "${GROUPS[@]}"; do
        if [ -n "$grp" ]; then
            usermod -g $grp $user # -g cambia el grupo principal
            echo "Usuario $user ahora pertenece a $grp"
            break
        else
            echo "Opción inválida."
        fi
    done
}

# --- MENÚ PRINCIPAL ---
while true; do
    echo -e "\nMENÚ DE ADMINISTRACIÓN FTP"
    echo "1) Instalar FTP"
    echo "2) Crear usuarios"
    echo "3) Cambiar usuario de grupo"
    echo "4) Salir"
    read -p "Opción: " opcion

    case $opcion in
        1) intalar_ftp ;;
        2) crear_usuario_ftp ;;
        3) cambiar_grupo ;;
        4) exit 0 ;;
        *) echo "Inválido" ;;
    esac
done