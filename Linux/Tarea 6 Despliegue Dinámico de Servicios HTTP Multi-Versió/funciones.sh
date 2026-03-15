#!/bin/bash
#########################################
# Preparar repositorios silenciosamente
#########################################

preparar_repositorios() {

# instalar utilidades necesarias
dnf install -y dnf-plugins-core yum-utils epel-release > /dev/null 2>&1

# limpiar cache
dnf clean all > /dev/null 2>&1
dnf makecache > /dev/null 2>&1

}

#########################################
# Validar puerto
#########################################

validar_puerto() {

PUERTO=$1

if [[ ! $PUERTO =~ ^[0-9]+$ ]]; then
    echo "Puerto inválido"
    return 1
fi

if ((PUERTO < 1 || PUERTO > 65535)); then
    echo "Puerto fuera de rango"
    return 1
fi

if [[ $PUERTO == 22 || $PUERTO == 25 || $PUERTO == 53 ]]; then
    echo "Puerto reservado por el sistema"
    return 1
fi

if ss -tuln | grep -q ":$PUERTO "; then
    echo "El puerto ya está en uso"
    return 1
fi

return 0
}

#########################################
# Gestionar puerto general
# FIX: capturar $? inmediatamente después de validar_puerto
#########################################

gestionar_puerto() {

PUERTO=$1

validar_puerto $PUERTO
local STATUS=$?

if [ $STATUS -ne 0 ]; then
    echo "Error: puerto inválido o en uso"
    return 1
fi

abrir_firewall $PUERTO

return 0

}

#########################################
# Abrir puerto en firewall
#########################################

abrir_firewall() {

PUERTO=$1

firewall-cmd --permanent --add-port=${PUERTO}/tcp > /dev/null 2>&1
firewall-cmd --reload > /dev/null 2>&1

}

#########################################
# Permitir puerto HTTP en SELinux
#########################################

permitir_puerto_selinux() {

PUERTO=$1

if command -v semanage >/dev/null 2>&1; then
    if ! semanage port -l | grep -q "http_port_t.*\\b$PUERTO\\b"; then
        semanage port -a -t http_port_t -p tcp $PUERTO 2>/dev/null || \
        semanage port -m -t http_port_t -p tcp $PUERTO
    fi
fi

}

#########################################
# Detener solo el servicio que se va a reinstalar
# FIX: NO matar los otros servidores que ya están corriendo
#########################################

detener_apache() {
systemctl stop httpd 2>/dev/null
sleep 1
}

detener_nginx() {
systemctl stop nginx 2>/dev/null
sleep 1
}

detener_tomcat() {
pkill -f catalina 2>/dev/null
sleep 2
}

#########################################
# Obtener versiones de Apache disponibles
#########################################

listar_versiones_apache() {

echo "Versiones disponibles de Apache:"
echo ""

VERSIONES=$(dnf list --showduplicates httpd \
| grep httpd.x86_64 \
| awk '{print $2}' \
| sort -V \
| uniq)

OLDEST=$(echo "$VERSIONES" | head -n 1)
LATEST=$(echo "$VERSIONES" | tail -n 1)
LTS=$(echo "$VERSIONES" | sed -n '2p')

echo "1) $LATEST  (Latest / Desarrollo)"
echo "2) $LTS     (LTS / Estable)"
echo "3) $OLDEST  (Oldest)"

}

#########################################
# Instalar Apache
# FIX: gestionar_puerto ANTES de instalar para validar puerto libre
# FIX: sed reemplaza cualquier "Listen X" no solo "Listen 80"
#########################################

instalar_apache() {

VERSION=$1
PUERTO=$2

detener_apache   # solo detiene Apache, Nginx y Tomcat siguen corriendo

# FIX: validar puerto ANTES de instalar
gestionar_puerto $PUERTO || return 1

echo "Instalando Apache versión $VERSION..."

dnf install -y httpd-$VERSION > /dev/null 2>&1

activar_headers_apache

permitir_puerto_selinux $PUERTO

echo "Configurando puerto $PUERTO..."

# FIX: reemplaza cualquier "Listen X" existente, no solo "Listen 80"
sed -i "s/^Listen .*/Listen $PUERTO/" /etc/httpd/conf/httpd.conf

systemctl enable httpd > /dev/null 2>&1
systemctl restart httpd > /dev/null 2>&1

crear_index "Apache" "$VERSION" "$PUERTO" "/var/www/html"

configurar_seguridad_apache

echo ""
echo "====================================="
echo " INSTALACIÓN COMPLETADA "
echo "====================================="
echo "Servidor: Apache"
echo "Versión: $VERSION"
echo "Puerto: $PUERTO"
echo "====================================="

}

#########################################
# Activar módulo headers
#########################################

activar_headers_apache() {

dnf install -y mod_headers > /dev/null 2>&1

}

#########################################
# Seguridad Apache
#########################################

configurar_seguridad_apache() {

SECURITY_CONF="/etc/httpd/conf.d/security.conf"

echo "Aplicando seguridad Apache..."

# Crear archivo si no existe
touch $SECURITY_CONF

# Eliminar configuraciones previas
sed -i '/ServerTokens/d' $SECURITY_CONF
sed -i '/ServerSignature/d' $SECURITY_CONF

# Aplicar configuraciones seguras
echo "ServerTokens Prod" >> $SECURITY_CONF
echo "ServerSignature Off" >> $SECURITY_CONF

# Headers de seguridad
cat <<EOF >> $SECURITY_CONF

<IfModule mod_headers.c>
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
</IfModule>

TraceEnable Off

EOF

systemctl restart httpd > /dev/null 2>&1

}

#########################################
# Obtener versiones de Nginx disponibles
#########################################

listar_versiones_nginx() {

echo "Versiones disponibles de Nginx:"
echo ""

VERSIONES=$(dnf repoquery --showduplicates nginx 2>/dev/null \
| awk '{print $1}' \
| awk -F'-' '{print $2}' \
| sort -V \
| uniq)

COUNT=$(echo "$VERSIONES" | wc -l)

if [ "$COUNT" -lt 3 ]; then

LATEST="1.26.3"
LTS="1.24.0"
OLDEST="1.20.1"

else

OLDEST=$(echo "$VERSIONES" | head -n 1)
LATEST=$(echo "$VERSIONES" | tail -n 1)
LTS=$(echo "$VERSIONES" | sed -n '2p')

fi

echo "1) $LATEST  (Latest / Desarrollo)"
echo "2) $LTS     (LTS / Estable)"
echo "3) $OLDEST  (Oldest)"

}

#########################################
# Crear usuario restringido nginx
#########################################

crear_usuario_nginx() {

if ! id nginxsvc &>/dev/null; then
    useradd -r -s /sbin/nologin -d /var/www/nginx nginxsvc
fi

mkdir -p /var/www/nginx

chown -R nginxsvc:nginxsvc /var/www/nginx
chmod -R 750 /var/www/nginx

}

#########################################
# Configurar puerto nginx (server block limpio)
#########################################

configurar_puerto_nginx() {

PUERTO=$1
CONF="/etc/nginx/conf.d/default.conf"

cat > $CONF <<EOF
server {
    listen $PUERTO;
    server_name _;
    root /usr/share/nginx/html;

    location / {
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
EOF

}

#########################################
# Seguridad Nginx
#########################################

configurar_seguridad_nginx() {

CONF="/etc/nginx/nginx.conf"

# Eliminar cualquier server_tokens previo
sed -i '/server_tokens/d' $CONF

# Insertar server_tokens off justo antes del primer bloque server {
# que siempre esta dentro de http { } en nginx.conf
sed -i '0,/server {/s/server {/server_tokens off;\n    server {/' $CONF

}

#########################################
# Instalar Nginx
#########################################

instalar_nginx() {

VERSION=$1
PUERTO=$2

detener_nginx   # solo detiene Nginx, Apache y Tomcat siguen corriendo

gestionar_puerto $PUERTO || return 1

echo "Instalando Nginx versión $VERSION..."

dnf install -y nginx > /dev/null 2>&1

VERSION_REAL=$(nginx -v 2>&1 | cut -d'/' -f2)
VERSION=$VERSION_REAL

crear_usuario_nginx

permitir_puerto_selinux $PUERTO

configurar_puerto_nginx $PUERTO

# Aplicar seguridad ANTES de validar config
configurar_seguridad_nginx

nginx -t || { echo "Error en configuración de Nginx"; return 1; }

systemctl enable nginx > /dev/null 2>&1
systemctl restart nginx > /dev/null 2>&1

crear_index "Nginx" "$VERSION" "$PUERTO" "/usr/share/nginx/html"

echo ""
echo "====================================="
echo " INSTALACIÓN COMPLETADA "
echo "====================================="
echo "Servidor: Nginx"
echo "Versión: $VERSION"
echo "Puerto: $PUERTO"
echo "====================================="

}

#########################################
# Configurar header Server en Tomcat
#########################################

configurar_header_tomcat() {

sed -i 's|protocol="org.apache.coyote.http11.Http11NioProtocol"|protocol="org.apache.coyote.http11.Http11NioProtocol" server="Apache-Tomcat"|' /opt/tomcat/conf/server.xml

}

#########################################
# Obtener versiones de Tomcat disponibles
#########################################

listar_versiones_tomcat() {

echo "Versiones disponibles de Tomcat:"
echo ""

echo "1) 10.1.28  (Latest / Desarrollo)"
echo "2) 10.1.26  (LTS / Estable)"
echo "3) 9.0.91   (Oldest)"

}

#########################################
# Crear usuario restringido tomcat
#########################################

crear_usuario_tomcat() {

if ! id tomcatsvc &>/dev/null; then
    useradd -r -s /sbin/nologin -d /opt/tomcat tomcatsvc
fi

}

#########################################
# Configurar puerto Tomcat
# FIX: reemplaza cualquier puerto existente, no solo 8080
#########################################

configurar_puerto_tomcat() {

PUERTO=$1

# FIX: reemplaza cualquier puerto numérico, no solo "8080"
sed -i "s/Connector port=\"[0-9]*\"/Connector port=\"$PUERTO\"/" /opt/tomcat/conf/server.xml

}

#########################################
# Instalar Tomcat
#########################################

instalar_tomcat() {

VERSION=$1
PUERTO=$2

# Solo instala Java si no está ya instalado
if ! command -v java &>/dev/null; then
    echo "Instalando Java..."
    dnf install -y java-21-openjdk java-21-openjdk-devel > /dev/null 2>&1
else
    echo "Java ya instalado, omitiendo..."
fi

detener_tomcat   # solo detiene Tomcat, Apache y Nginx siguen corriendo

gestionar_puerto $PUERTO || return 1

echo "Instalando Tomcat versión $VERSION..."

cd /tmp

MAJOR=$(echo $VERSION | cut -d'.' -f1)
TARBALL="apache-tomcat-$VERSION.tar.gz"

# Solo descarga si no existe el archivo ya
if [ ! -f "/tmp/$TARBALL" ]; then
    echo "Descargando Tomcat $VERSION..."
    wget https://archive.apache.org/dist/tomcat/tomcat-$MAJOR/v$VERSION/bin/$TARBALL -q --show-progress
else
    echo "Tomcat $VERSION ya descargado, omitiendo descarga..."
fi

tar -xzf $TARBALL

pkill -f tomcat 2>/dev/null
sleep 2
rm -rf /opt/tomcat
mv apache-tomcat-$VERSION /opt/tomcat

crear_usuario_tomcat

chown -R tomcatsvc:tomcatsvc /opt/tomcat

# configurar puerto antes de iniciar
configurar_puerto_tomcat $PUERTO

# agregar header Server
configurar_header_tomcat

permitir_puerto_selinux $PUERTO

crear_index "Tomcat" "$VERSION" "$PUERTO" "/opt/tomcat/webapps/ROOT"

# iniciar tomcat
JAVA_HOME=/usr/lib/jvm/java-21-openjdk

echo "Iniciando Tomcat..."
sudo -u tomcatsvc env JAVA_HOME=$JAVA_HOME CATALINA_HOME=/opt/tomcat /opt/tomcat/bin/startup.sh > /dev/null 2>&1

echo "Esperando a que Tomcat inicie..."

for i in {1..30}; do
    if ss -tuln | grep -q ":$PUERTO "; then
        echo "Tomcat iniciado correctamente en $i segundos"
        break
    fi
    echo -ne "  Esperando... $i/30s\r"
    sleep 1
done

echo ""
echo "====================================="
echo " INSTALACIÓN COMPLETADA "
echo "====================================="
echo "Servidor: Tomcat"
echo "Versión: $VERSION"
echo "Puerto: $PUERTO"
echo "====================================="

}

#########################################
# Crear página personalizada
#########################################

crear_index() {

SERVICIO=$1
VERSION=$2
PUERTO=$3
DIRECTORIO=$4

mkdir -p $DIRECTORIO

cat <<EOF > $DIRECTORIO/index.html
<html>
<head>
<meta charset="UTF-8">
<title>Servidor HTTP</title>
</head>
<body>
<h1>Servidor: $SERVICIO</h1>
<h2>Versión: $VERSION</h2>
<h3>Puerto: $PUERTO</h3>
</body>
</html>
EOF

}

#########################################
# Menú principal
#########################################

# Preparar repositorios una sola vez al inicio
echo "Preparando repositorios..."
preparar_repositorios

while true; do

echo ""
echo "=============================="
echo " DESPLIEGUE SERVIDORES HTTP"
echo "=============================="
echo "1) Apache"
echo "2) Nginx"
echo "3) Tomcat"
echo "4) Salir"
echo -n "Seleccione una opción: "
read OPCION

case $OPCION in

1)
    listar_versiones_apache
    echo -n "Seleccione número de versión: "
    read NUM_VERSION

    VERSIONES=$(dnf list --showduplicates httpd \
    | grep httpd.x86_64 \
    | awk '{print $2}' \
    | sort -V \
    | uniq)

    OLDEST=$(echo "$VERSIONES" | head -n 1)
    LATEST=$(echo "$VERSIONES" | tail -n 1)
    LTS=$(echo "$VERSIONES" | sed -n '2p')

    case $NUM_VERSION in
        1) VERSION=$LATEST ;;
        2) VERSION=$LTS ;;
        3) VERSION=$OLDEST ;;
        *) echo "Opción inválida"; continue ;;
    esac

    echo -n "Ingrese puerto: "
    read PUERTO

    instalar_apache "$VERSION" "$PUERTO"
    ;;

2)
    listar_versiones_nginx

    echo -n "Seleccione número de versión: "
    read NUM_VERSION

    VERSIONES=$(dnf repoquery --showduplicates nginx 2>/dev/null \
    | awk '{print $1}' \
    | awk -F'-' '{print $2}' \
    | sort -V \
    | uniq)

    COUNT=$(echo "$VERSIONES" | wc -l)

    if [ "$COUNT" -lt 3 ]; then
        LATEST="1.26.3"
        LTS="1.24.0"
        OLDEST="1.20.1"
    else
        OLDEST=$(echo "$VERSIONES" | head -n 1)
        LATEST=$(echo "$VERSIONES" | tail -n 1)
        LTS=$(echo "$VERSIONES" | sed -n '2p')
    fi

    case $NUM_VERSION in
        1) VERSION=$LATEST ;;
        2) VERSION=$LTS ;;
        3) VERSION=$OLDEST ;;
        *) echo "Opción inválida"; continue ;;
    esac

    echo -n "Ingrese puerto: "
    read PUERTO

    instalar_nginx "$VERSION" "$PUERTO"
    ;;

3)
    listar_versiones_tomcat

    echo -n "Seleccione número de versión: "
    read NUM_VERSION

    case $NUM_VERSION in
        1) VERSION="10.1.28" ;;
        2) VERSION="10.1.26" ;;
        3) VERSION="9.0.91" ;;
        *) echo "Opción inválida"; continue ;;
    esac

    echo -n "Ingrese puerto: "
    read PUERTO

    instalar_tomcat "$VERSION" "$PUERTO"
    ;;

4)
    echo "Saliendo..."
    exit 0
    ;;

*)
    echo "Opción inválida"
    ;;

esac

done