#!/bin/bash

BASE_DIR="/srv/ftp"
PUBLIC_DIR="$BASE_DIR/general"
GROUPS="reprobados recursadores"

if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse como root."
    echo "Use: sudo ./FTP.sh"
    exit 1
fi

instalar_ftp() {


    echo "============================================="
    echo "Configuracion de Entorno FTP"
    echo "============================================="

    dnf install -y vsftpd

    mkdir -p "$BASE_DIR"

    # Crear grupos directamente (sin variable)
    for g in reprobados recursadores; do
        if getent group "$g" > /dev/null; then
            echo "Grupo $g ya existe."
        else
            echo "Creando grupo $g..."
            groupadd "$g"
        fi
    done

    mkdir -p "$PUBLIC_DIR"
    chmod 755 "$PUBLIC_DIR"
    chown root:root "$PUBLIC_DIR"

    for g in reprobados recursadores; do
        mkdir -p "$BASE_DIR/$g"
        chown root:"$g" "$BASE_DIR/$g"
        chmod 775 "$BASE_DIR/$g"
    done

    systemctl restart vsftpd
    systemctl enable vsftpd

    echo "Entorno configurado correctamente."
crear_usuario_ftp() {

    read -p "Cuantos usuarios desea crear?: " num_users

    for ((i=1; i<=num_users; i++)); do

        echo "--------- Registro de Usuario $i ---------"

        read -p "Nombre de usuario: " username
        read -s -p "Contrasena: " password; echo
        read -p "Grupo (reprobados/recursadores): " grupo_op

        if ! getent group "$grupo_op" > /dev/null; then
            echo "El grupo $grupo_op no existe."
            continue
        fi

        if id "$username" &>/dev/null; then
            echo "Usuario $username ya existe."
        else
            useradd -d "$BASE_DIR/$username" -s /sbin/nologin "$username"
            echo "$username:$password" | chpasswd
        fi

        usermod -aG "$grupo_op" "$username"

        USER_HOME="$BASE_DIR/$username"
        mkdir -p "$USER_HOME"
        chown "$username:$username" "$USER_HOME"
        chmod 755 "$USER_HOME"

        mkdir -p "$USER_HOME/general"
        mkdir -p "$USER_HOME/$grupo_op"
        mkdir -p "$USER_HOME/$username"

        mountpoint -q "$USER_HOME/general" || mount --bind "$PUBLIC_DIR" "$USER_HOME/general"
        mountpoint -q "$USER_HOME/$grupo_op" || mount --bind "$BASE_DIR/$grupo_op" "$USER_HOME/$grupo_op"

        chown -R "$username:$username" "$USER_HOME/$username"
        chmod 700 "$USER_HOME/$username"

        echo "Usuario $username creado correctamente."
    done
}

cambiar_grupo() {

    read -p "Usuario a modificar: " user

    if ! id "$user" &>/dev/null; then
        echo "Usuario no existe."
        return
    fi

    echo "Seleccione nuevo grupo:"
    select nuevo_grupo in $GROUPS; do
        if [ -n "$nuevo_grupo" ]; then

            for g in $GROUPS; do
                gpasswd -d "$user" "$g" 2>/dev/null
                if mountpoint -q "$BASE_DIR/$user/$g"; then
                    umount "$BASE_DIR/$user/$g"
                    rmdir "$BASE_DIR/$user/$g"
                fi
            done

            usermod -aG "$nuevo_grupo" "$user"

            mkdir -p "$BASE_DIR/$user/$nuevo_grupo"
            mount --bind "$BASE_DIR/$nuevo_grupo" "$BASE_DIR/$user/$nuevo_grupo"

            echo "Usuario movido a $nuevo_grupo."
            break
        else
            echo "Opcion invalida."
        fi
    done
}

while true; do
    echo ""
    echo "MENU DE ADMINISTRACION FTP"
    echo "1) Instalar y Configurar Entorno"
    echo "2) Crear usuarios"
    echo "3) Cambiar usuario de grupo"
    echo "4) Salir"

    read -p "Opcion: " opcion

    case $opcion in
        1) instalar_ftp ;;
        2) crear_usuario_ftp ;;
        3) cambiar_grupo ;;
        4) exit 0 ;;
        *) echo "Opcion invalida" ;;
    esac
done