#!/bin/bash
BASE_DIR="/srv/ftp"
PUBLIC_DIR="$BASE_DIR/general"
GROUPS=("reprobados" "recursadores")


intalar_ftp() {
    echo =============================================
    echo          "Instalación de FTP"               
    echo =============================================


    apt update -y
    apt install -y vsftpd

    mkdir -p $BASE_DIR
    mkdir -p $PUBLIC_DIR

    chmod 755 $PUBLIC_DIR

    for g in "${GROUPS[@]}"; do
        groupadd -f $g
        mkdir -p $BASE_DIR/$g
        chgrp $g $BASE_DIR/$g
        chmod 770 $BASE_DIR/$g
    done

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

    echo "---------------------------------------------" 
    echo "Servicio instalado, configurado y corriendo. "
    echo "---------------------------------------------" 
}


crear usuario_ftp() {
    echo =============================================
    echo            "Instalación de vsftpd "            
    echo =============================================

    apt update -y
    apt install -y vsftpd

    read -p "¿Cuántos usuarios FTP desea crear? : " num_users

    for ((i=1; i<=3; i++)); do
        echo "--------------usuarios------------------------------"
        read -p "Ingrese el nombre del usuario FTP: " username
        read -s -p "Ingrese la contraseña para el usuario FTP: " password
        read -s -p "Confirme la contraseña: " password_confirm
        read -p "Grupo (reprobados/recursadores)"grupo_op
        echo

        useradd -m $username
        echo "$username:$password" | chpasswd

        echo "Usuario FTP '$username' creado exitosamente."  
    donde 
        if [[ "$grupo_op" == "reprobados" ]]; then
            usermod -aG reprobados $username
            chown $username:reprobados $BASE_DIR/reprobados
        elif [[ "$grupo_op" == "recursadores" ]]; then
            usermod -aG recursadores $username
            chown $username:recursadores $BASE_DIR/recursadores
        else
            echo "Grupo no válido. El usuario se ha creado sin asignar a un grupo específico."
        fi

        echo "---------------------------------------------"
    done


}

cambiar_grupo() {
    read -p "Usuario a modificar: " user
    echo "Nuevo grupo:"
    select grp in "${GROUPS[@]}"; do
        break
    done

    usermod -G $grp $user
    chown $user:$grp $BASE_DIR/$user
    echo "Grupo actualizado."
}




while true; do
    echo "Seleccione una opción:"
    echo "1) Instalar FTP"
    echo "2) crear usuario FTP"
    echo "3) cambiar usuario de grupo"
    echo "4) Salir"
    read -p "Opción: " opcion

    case $opcion in
        1)
            intalar-FTP
            ;;
        2)
            crear_usuario_ftp
            ;;
        3)
            cambiar_grupo
            ;;
        4)
            echo "Saliendo..."
            exit 0
            ;;      
        *)
            echo "Opción no válida. Intente nuevamente."
            ;;
    esac
done 