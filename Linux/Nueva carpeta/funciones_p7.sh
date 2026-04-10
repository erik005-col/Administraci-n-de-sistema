#!/bin/bash
# ================================================================
# funciones_p7_linux.sh
# Practica 7 - Oracle Linux Server
# Basado en funciones.sh de P6 (HTTP) + ftp.sh de P5
# Agrega: cliente FTP dinamico, repositorio FTP, SSL/TLS
# ================================================================

# ----------------------------------------------------------------
# VARIABLES GLOBALES
# ----------------------------------------------------------------
DOMINIO_SSL="www.reprobados.com"
RESUMEN_FILE="/tmp/p7_resumen.txt"
FTP_IP=""
FTP_USER=""
FTP_PASS=""
FTP_RUTA="http/Linux"

# FTP server local (igual que P5)
FTP_PUBLIC="/ftp/public"
FTP_USERS="/ftp/users"
FTP_CONF="/etc/vsftpd/vsftpd.conf"

# ================================================================
# SECCION 1 - UTILIDADES (copiadas de P6 funciones.sh)
# ================================================================

escribir_titulo() {
    local linea="============================================================"
    echo ""; echo "$linea"; echo "  $1"; echo "$linea"; echo ""
}

registrar_resumen() {
    echo "$1 | $2 | $3 | ${4:-}" >> "$RESUMEN_FILE"
}

# De P6
validar_puerto() {
    local PUERTO=$1
    if [[ ! $PUERTO =~ ^[0-9]+$ ]]; then
        echo "Puerto invalido: debe ser un numero"; return 1
    fi
    if (( PUERTO < 1 || PUERTO > 65535 )); then
        echo "Puerto fuera de rango (1-65535)"; return 1
    fi
    if [[ $PUERTO == 22 || $PUERTO == 25 || $PUERTO == 53 ]]; then
        echo "Puerto $PUERTO reservado por el sistema"; return 1
    fi
    if ss -tuln | grep -q ":$PUERTO "; then
        echo "El puerto $PUERTO ya esta en uso"
        read -p "  Usar de todas formas? [s/N]: " resp
        [[ "$resp" =~ ^[sS]$ ]] || return 1
    fi
    return 0
}

# De P6
abrir_firewall() {
    local PUERTO=$1
    echo "  Firewall: abriendo puerto $PUERTO..."
    firewall-cmd --permanent --add-port=${PUERTO}/tcp
    firewall-cmd --reload
}

cerrar_firewall() {
    firewall-cmd --permanent --remove-port=${1}/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
}

# De P6
permitir_puerto_selinux() {
    local PUERTO=$1
    if command -v semanage >/dev/null 2>&1; then
        if ! semanage port -l | grep -q "http_port_t.*\b$PUERTO\b"; then
            semanage port -a -t http_port_t -p tcp $PUERTO 2>/dev/null || \
            semanage port -m -t http_port_t -p tcp $PUERTO 2>/dev/null
        fi
    fi
}

# De P6
detener_servicios_http() {
    systemctl stop httpd 2>/dev/null && echo "  httpd detenido." || echo "  httpd no activo."
    systemctl stop nginx 2>/dev/null && echo "  nginx detenido." || echo "  nginx no activo."
}

# De P6 (crear_index)
crear_index() {
    local SERVICIO=$1 VERSION=$2 PUERTO=$3 DIRECTORIO=$4 FUENTE="${5:-WEB}"
    local FUENTE_COLOR FUENTE_ICONO
    if [[ "$FUENTE" == "FTP" ]]; then
        FUENTE_COLOR="#8e44ad"
        FUENTE_ICONO="&#128229; FTP"
    else
        FUENTE_COLOR="#27ae60"
        FUENTE_ICONO="&#127760; WEB"
    fi
    mkdir -p "$DIRECTORIO"
    cat > "$DIRECTORIO/index.html" <<HTMLEOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>$SERVICIO - P7</title>
<style>
body{font-family:Arial,sans-serif;text-align:center;margin-top:60px;background:#f4f4f4}
.card{background:#fff;border-radius:10px;padding:40px 50px;display:inline-block;box-shadow:0 4px 16px rgba(0,0,0,.15)}
h1{color:#2c3e50;margin-bottom:8px}
h2{color:#27ae60;margin:6px 0}
h3{color:#2980b9;margin:6px 0}
.fuente{display:inline-block;margin-top:18px;padding:8px 22px;border-radius:20px;
        background:$FUENTE_COLOR;color:#fff;font-size:15px;font-weight:bold;letter-spacing:1px}
.pie{margin-top:18px;color:#999;font-size:13px}
</style></head>
<body><div class="card">
<h1>&#128279; $SERVICIO</h1>
<h2>Version: $VERSION</h2>
<h3>Puerto: $PUERTO</h3>
<div class="fuente">$FUENTE_ICONO</div>
<p class="pie">Practica 7 - Infraestructura de Despliegue Seguro</p>
</div></body></html>
HTMLEOF
    echo "  index.html creado en $DIRECTORIO (fuente: $FUENTE)"
}

# ================================================================
# SECCION 2 - DEPENDENCIAS
# ================================================================

instalar_dependencias() {
    escribir_titulo "INSTALAR DEPENDENCIAS"
    dnf install -y openssl curl wget tar dnf-plugins-core \
        policycoreutils-python-utils python3-policycoreutils 2>/dev/null
    echo "  Dependencias instaladas."
    registrar_resumen "Dependencias" "Instalacion" "OK"
}

# ================================================================
# SECCION 3 - REPOSITORIO FTP
# ================================================================

generar_sha256() {
    local archivo="$1"
    local hash; hash=$(sha256sum "$archivo" | awk '{print $1}')
    echo "$hash  $(basename $archivo)" > "${archivo}.sha256"
    echo "  SHA256: $hash"
}

archivo_valido() {
    [[ -f "$1" ]] && (( $(stat -c%s "$1" 2>/dev/null || echo 0) > ${2:-100} ))
}

preparar_repositorio_ftp() {
    escribir_titulo "PREPARAR REPOSITORIO FTP"

    if [[ ! -d "$FTP_PUBLIC" ]]; then
        echo "  ERROR: $FTP_PUBLIC no existe. Ejecute opcion 1 primero."
        return 1
    fi

    local repo_base="$FTP_PUBLIC/http/Linux"
    echo "  Se crearan carpetas y se descargaran instaladores."
    read -p "  Continuar? [S/N]: " resp
    [[ "$resp" =~ ^[sS]$ ]] || return

    for svc in Apache Nginx Tomcat; do
        mkdir -p "$repo_base/$svc"
        echo "  Carpeta creada: $repo_base/$svc"
    done

    # ── APACHE via DNF ──────────────────────────────────────────
    echo ""; echo "--- Apache (via DNF) ---"
    local VERSIONES LATEST LTS OLDEST
    VERSIONES=$(dnf list --showduplicates httpd 2>/dev/null | grep "httpd.x86_64" | awk '{print $2}' | sort -V | uniq)
    LATEST=$(echo "$VERSIONES" | tail -n 1)
    LTS=$(echo "$VERSIONES" | sed -n '2p')
    OLDEST=$(echo "$VERSIONES" | head -n 1)

    mkdir -p /tmp/p7_dnl
    for entry in "latest:$LATEST" "lts:$LTS" "oldest:$OLDEST"; do
        local tag="${entry%%:*}" ver="${entry##*:}"
        local dest="$repo_base/Apache/apache_${tag}_linux.tar.gz"
        if archivo_valido "$dest" 1000; then
            echo "  Apache $tag ya existe. Omitiendo."
        elif [[ -n "$ver" ]]; then
            echo "  Descargando Apache $ver ($tag)..."
            rm -f /tmp/p7_dnl/httpd*.rpm
            dnf download "httpd-$ver" --destdir=/tmp/p7_dnl 2>/dev/null
            local f; f=$(ls /tmp/p7_dnl/httpd-[0-9]*.rpm 2>/dev/null | head -1)
            if [[ -f "$f" ]]; then
                cp "$f" "$dest" && echo "  OK: apache_${tag}_linux.tar.gz"
            else
                echo "  No se pudo descargar. Creando placeholder."
                echo "PLACEHOLDER Apache $ver $tag" > "$dest"
            fi
        fi
        archivo_valido "$dest" && generar_sha256 "$dest"
    done
    rm -rf /tmp/p7_dnl

    # ── NGINX desde nginx.org ────────────────────────────────────
    echo ""; echo "--- Nginx (nginx.org) ---"
    local BASE_URL="https://nginx.org/packages/rhel/9/x86_64/RPMS"
    for entry in "latest:1.26.3" "lts:1.24.0" "oldest:1.20.2"; do
        local tag="${entry%%:*}" ver="${entry##*:}"
        local dest="$repo_base/Nginx/nginx_${ver}_linux.tar.gz"
        if archivo_valido "$dest" 1000; then
            echo "  Nginx $ver ya existe. Omitiendo."
        else
            echo "  Descargando Nginx $ver ($tag)..."
            if curl -sSf --max-time 60 "${BASE_URL}/nginx-${ver}-1.el9.ngx.x86_64.rpm" -o "$dest" 2>/dev/null && \
               archivo_valido "$dest" 1000; then
                echo "  OK: nginx_${ver}_linux.tar.gz"
            else
                echo "  No se pudo descargar. Creando placeholder."
                echo "PLACEHOLDER Nginx $ver" > "$dest"
            fi
        fi
        generar_sha256 "$dest"
    done

    # ── TOMCAT desde archive.apache.org ─────────────────────────
    echo ""; echo "--- Tomcat (archive.apache.org) ---"
    for entry in "latest:10/v10.1.28" "lts:10/v10.1.26" "oldest:9/v9.0.91"; do
        local tag="${entry%%:*}" path="${entry##*:}"
        local ver="${path##*/v}"
        local dest="$repo_base/Tomcat/tomcat_${ver}_linux.tar.gz"
        if archivo_valido "$dest" 1000; then
            echo "  Tomcat $ver ya existe. Omitiendo."
        else
            echo "  Descargando Tomcat $ver ($tag)..."
            if curl -sSf --max-time 120 \
               "https://archive.apache.org/dist/tomcat/tomcat-${path}/bin/apache-tomcat-${ver}.tar.gz" \
               -o "$dest" 2>/dev/null && archivo_valido "$dest" 1000; then
                echo "  OK: tomcat_${ver}_linux.tar.gz"
            else
                echo "  No se pudo descargar. Creando placeholder."
                echo "PLACEHOLDER Tomcat $ver" > "$dest"
            fi
        fi
        generar_sha256 "$dest"
    done

    # Permisos
    chown -R root:ftpusuarios "$FTP_PUBLIC/http" 2>/dev/null
    chmod -R 755 "$FTP_PUBLIC/http" 2>/dev/null

    # Mount bind para usuarios FTP
    echo ""; echo "  Configurando acceso FTP al repositorio..."
    if getent group ftpusuarios &>/dev/null; then
        while IFS= read -r u; do
            [[ -z "$u" ]] && continue
            local userdir="$FTP_USERS/$u"
            if [[ -d "$userdir" ]]; then
                mkdir -p "$userdir/http"
                mountpoint -q "$userdir/http" || \
                    { mount --bind "$FTP_PUBLIC/http" "$userdir/http" && echo "  Mount bind creado para '$u'."; }
            fi
        done <<< "$(getent group ftpusuarios | cut -d: -f4 | tr ',' '\n')"
    fi

    echo ""; echo "  Repositorio listo. Archivos generados:"
    find "$repo_base" -type f | while read -r f; do
        printf "    %-55s %s\n" "${f#$repo_base/}" "$(du -sh $f 2>/dev/null | cut -f1)"
    done
    echo ""; echo "  Al conectarse por FTP, navegue a: http/Linux/"
    registrar_resumen "Repositorio-FTP" "Preparacion" "OK" "$repo_base"
}

# ================================================================
# SECCION 4 - CLIENTE FTP DINAMICO
# ================================================================

leer_credenciales_ftp() {
    echo ""; echo "--- Conexion al servidor FTP privado ---"
    if [[ -n "$FTP_IP" ]]; then
        read -p "  IP actual: '$FTP_IP' Cambiar? [S/N]: " r
        [[ "$r" =~ ^[sS]$ ]] && read -p "  IP del servidor FTP: " FTP_IP
    else
        read -p "  IP del servidor FTP: " FTP_IP
    fi
    if [[ -n "$FTP_USER" ]]; then
        read -p "  Usuario FTP (Enter = '$FTP_USER'): " u
        [[ -n "$u" ]] && FTP_USER="$u"
    else
        read -p "  Usuario FTP: " FTP_USER
    fi
    read -s -p "  Contrasena FTP: " FTP_PASS; echo ""
    echo "  Conectando como '$FTP_USER' a $FTP_IP..."
}

listar_ftp() {
    # --ssl: usa FTPS (STARTTLS) si el servidor lo requiere, -k ignora certificado autofirmado
    curl -s --max-time 15 --ssl -k --user "$FTP_USER:$FTP_PASS" "ftp://$FTP_IP/$1/" --list-only 2>/dev/null
}

descargar_ftp() {
    curl -s --max-time 120 --ssl -k --user "$FTP_USER:$FTP_PASS" "ftp://$FTP_IP/$1" -o "$2" 2>/dev/null
}

verificar_sha256() {
    local archivo="$1" sha_file="$2"
    echo ""; echo "  Verificando integridad SHA256..."
    [[ ! -f "$archivo" ]] && echo "  ERROR: Archivo no encontrado." && return 1
    if [[ ! -f "$sha_file" ]]; then
        echo "  Advertencia: .sha256 no encontrado. Continuando."; return 0
    fi
    local hash_calc hash_esp
    hash_calc=$(sha256sum "$archivo" | awk '{print $1}')
    hash_esp=$(awk '{print $1}' "$sha_file")
    echo "  Hash calculado : $hash_calc"
    echo "  Hash esperado  : $hash_esp"
    if [[ "$hash_calc" == "$hash_esp" ]]; then
        echo "  [OK] Integridad verificada."
        registrar_resumen "$(basename $archivo)" "SHA256" "OK" "Hash coincide"
        return 0
    else
        echo "  [ALERTA] Hash NO coincide."
        registrar_resumen "$(basename $archivo)" "SHA256" "ERROR" "Hash NO coincide"
        return 1
    fi
}

navegar_y_descargar_ftp() {
    local srv_forzado="${1:-}"
    leer_credenciales_ftp

    echo ""; echo "  Listando servicios en: $FTP_RUTA"
    local servicios; servicios=$(listar_ftp "$FTP_RUTA" | grep -v '\.')

    if [[ -z "$servicios" ]]; then
        echo "  ERROR: No se encontraron servicios."
        echo "    1) Verifique credenciales FTP"
        echo "    2) Ejecute opcion 3 (Preparar repositorio)"
        return 1
    fi

    local svc_elegido
    if [[ -n "$srv_forzado" ]] && echo "$servicios" | grep -qi "^${srv_forzado}$"; then
        svc_elegido="$srv_forzado"
        echo "  Servicio preseleccionado: $svc_elegido"
    else
        echo "  Servicios disponibles:"
        local i=1
        while IFS= read -r s; do echo "    $i) $s"; ((i++)); done <<< "$servicios"
        read -p "  Seleccione servicio: " sel
        svc_elegido=$(echo "$servicios" | sed -n "${sel}p")
    fi

    local ruta_svc="$FTP_RUTA/$svc_elegido"
    local instaladores; instaladores=$(listar_ftp "$ruta_svc" | grep -E '\.(rpm|tar\.gz|deb)$')

    if [[ -z "$instaladores" ]]; then
        echo "  No se encontraron instaladores en $ruta_svc."; return 1
    fi

    echo ""; echo "  Versiones disponibles para $svc_elegido:"
    local i=1
    while IFS= read -r f; do echo "    $i) $f"; ((i++)); done <<< "$instaladores"
    read -p "  Seleccione version: " sel2
    local arch_eleg; arch_eleg=$(echo "$instaladores" | sed -n "${sel2}p")
    local arch_sha="${arch_eleg}.sha256"

    local tmpdir; tmpdir=$(mktemp -d)
    echo ""; echo "  Descargando instalador desde FTP..."
    descargar_ftp "$ruta_svc/$arch_eleg" "$tmpdir/$arch_eleg"
    if [[ ! -s "$tmpdir/$arch_eleg" ]]; then
        echo "  ERROR al descargar $arch_eleg"; rm -rf "$tmpdir"; return 1
    fi
    echo "  Descargado: $arch_eleg"

    echo "  Descargando archivo .sha256..."
    descargar_ftp "$ruta_svc/$arch_sha" "$tmpdir/$arch_sha" || true

    if [[ -s "$tmpdir/$arch_sha" ]]; then
        verificar_sha256 "$tmpdir/$arch_eleg" "$tmpdir/$arch_sha"
        if [[ $? -ne 0 ]]; then
            read -p "  Continuar de todas formas? [s/N]: " r
            [[ ! "$r" =~ ^[sS]$ ]] && rm -rf "$tmpdir" && return 1
        fi
    fi

    registrar_resumen "$svc_elegido" "FTP-Descarga" "OK" "$arch_eleg"
    ARCHIVO_DESCARGADO="$tmpdir/$arch_eleg"
    SERVICIO_DESCARGADO="$svc_elegido"
    export ARCHIVO_DESCARGADO SERVICIO_DESCARGADO
    return 0
}

# ================================================================
# SECCION 5 - INSTALACION HTTP (funciones de P6)
# ================================================================

# De P6
obtener_puerto_apache() { grep -m1 "^Listen " /etc/httpd/conf/httpd.conf 2>/dev/null | awk '{print $2}'; }
obtener_puerto_nginx()  { grep -m1 "listen " /etc/nginx/conf.d/default.conf 2>/dev/null | awk '{print $2}' | tr -d ';'; }
obtener_puerto_tomcat() { grep -m1 'Connector port=' /opt/tomcat/conf/server.xml 2>/dev/null | grep -oP 'port="\K[0-9]+'; }

# De P6
activar_headers_apache() { dnf install -y mod_headers 2>/dev/null; }

# De P6
configurar_seguridad_apache() {
    local CONF="/etc/httpd/conf.d/security.conf"
    touch "$CONF"; sed -i '/ServerTokens/d; /ServerSignature/d' "$CONF"
    cat >> "$CONF" <<'SECEOF'
ServerTokens Prod
ServerSignature Off
<IfModule mod_headers.c>
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
</IfModule>
TraceEnable Off
SECEOF
    systemctl restart httpd 2>/dev/null
}

# De P6
configurar_puerto_nginx() {
    local PUERTO=$1
    mkdir -p /etc/nginx/conf.d
    cat > /etc/nginx/conf.d/default.conf <<NGXEOF
server {
    listen $PUERTO;
    server_name _;
    root /usr/share/nginx/html;
    location / { index index.html; try_files \$uri \$uri/ =404; }
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
}
NGXEOF
}

# De P6
configurar_seguridad_nginx() {
    local CONF="/etc/nginx/nginx.conf"
    [[ ! -f "$CONF" ]] && return
    sed -i '/^server_tokens/d' "$CONF"
    grep -q "server_tokens" "$CONF" && \
        sed -i "s/.*server_tokens.*/    server_tokens off;/" "$CONF" || \
        sed -i "/^http[[:space:]]*{/a\    server_tokens off;" "$CONF"
}

# ── Instalacion desde archivo descargado por FTP ─────────────────

instalar_desde_archivo() {
    local archivo="$1" servicio="$2"
    echo "  Instalando $servicio desde archivo descargado..."
    case "$servicio" in
        Apache)
            dnf install -y "$archivo" --allowerasing 2>/dev/null || \
            rpm -ivh "$archivo" 2>/dev/null || \
            dnf install -y httpd 2>/dev/null
            ;;
        Nginx)
            rpm --import https://nginx.org/keys/nginx_signing.key 2>/dev/null
            dnf install -y "$archivo" --allowerasing 2>/dev/null || \
            rpm -ivh "$archivo" 2>/dev/null || \
            dnf install -y nginx 2>/dev/null
            ;;
        Tomcat)
            local tmpdir; tmpdir=$(mktemp -d)
            tar -xzf "$archivo" -C "$tmpdir" 2>/dev/null
            local extracted; extracted=$(ls "$tmpdir" | head -1)
            pkill -f catalina 2>/dev/null; sleep 1
            rm -rf /opt/tomcat
            mv "$tmpdir/$extracted" /opt/tomcat
            rm -rf "$tmpdir"
            echo "  Tomcat extraido en /opt/tomcat"
            ;;
    esac
}

# ── APACHE (basado en P6 instalar_apache) ────────────────────────

instalar_apache_p7() {
    local VERSION=$1 PUERTO=$2 ARCHIVO="${3:-}" FUENTE="${4:-WEB}"

    # Detectar si ya esta instalado (mismo metodo que P6)
    local VERSION_INSTALADA
    VERSION_INSTALADA=$(rpm -q httpd --queryformat "%{VERSION}" 2>/dev/null)
    [[ "$VERSION_INSTALADA" == *"not installed"* ]] && VERSION_INSTALADA=""

    if [[ -n "$VERSION_INSTALADA" ]]; then
        echo "  Apache ya instalado (v$VERSION_INSTALADA)."
        local p_actual; p_actual=$(obtener_puerto_apache)
        if [[ "$p_actual" != "$PUERTO" ]]; then
            echo "  Cambiando puerto $p_actual -> $PUERTO..."
            sed -i "s/^Listen .*/Listen $PUERTO/" /etc/httpd/conf/httpd.conf
            [[ -n "$p_actual" ]] && cerrar_firewall "$p_actual"
            abrir_firewall "$PUERTO"
            permitir_puerto_selinux "$PUERTO"
            systemctl restart httpd
            registrar_resumen "Apache" "Puerto-Cambiado" "OK" "$p_actual -> $PUERTO"
            echo "  Puerto actualizado a $PUERTO."
        else
            echo "  Puerto ya configurado en $PUERTO."
        fi
        # Siempre actualizar index con la fuente actual
        crear_index "Apache" "$VERSION_INSTALADA" "$PUERTO" "/var/www/html" "$FUENTE"
        return 0
    fi

    detener_servicios_http

    if [[ -n "$ARCHIVO" && -f "$ARCHIVO" ]]; then
        instalar_desde_archivo "$ARCHIVO" "Apache"
    else
        echo "  Instalando Apache $VERSION via DNF..."
        dnf install -y "httpd-$VERSION" 2>/dev/null || dnf install -y httpd 2>/dev/null
        activar_headers_apache
    fi

    # Configurar puerto (igual que P6)
    abrir_firewall "$PUERTO"
    permitir_puerto_selinux "$PUERTO"
    sed -i "s/Listen 80/Listen $PUERTO/g" /etc/httpd/conf/httpd.conf 2>/dev/null

    local VERSION_REAL
    VERSION_REAL=$(rpm -q httpd --queryformat "%{VERSION}-%{RELEASE}" 2>/dev/null | sed 's/\.noarch$//')
    [[ -n "$VERSION_REAL" && "$VERSION_REAL" != *"not installed"* ]] && VERSION="$VERSION_REAL"

    crear_index "Apache" "$VERSION" "$PUERTO" "/var/www/html" "$FUENTE"
    configurar_seguridad_apache

    systemctl enable httpd
    systemctl restart httpd
    sleep 2

    if ss -tuln | grep -q ":$PUERTO "; then
        echo "  Apache instalado. v$VERSION | Puerto: $PUERTO | Estado: OK"
        registrar_resumen "Apache" "Instalacion" "OK" "v$VERSION puerto $PUERTO"
    else
        echo "  Apache instalado. v$VERSION | Puerto: $PUERTO | Estado: ADVERTENCIA"
        registrar_resumen "Apache" "Instalacion" "ADVERTENCIA" "No responde en $PUERTO"
    fi
}

# ── NGINX (basado en P6 instalar_nginx) ──────────────────────────

instalar_nginx_p7() {
    local VERSION=$1 PUERTO=$2 ARCHIVO="${3:-}" FUENTE="${4:-WEB}"

    # Detectar si ya esta instalado (mismo metodo que P6)
    local VERSION_INSTALADA
    VERSION_INSTALADA=$(rpm -q nginx --queryformat "%{VERSION}" 2>/dev/null)
    [[ "$VERSION_INSTALADA" == *"not installed"* ]] && VERSION_INSTALADA=""

    if [[ -n "$VERSION_INSTALADA" ]]; then
        echo "  Nginx ya instalado (v$VERSION_INSTALADA)."
        local p_actual; p_actual=$(obtener_puerto_nginx)
        if [[ "$p_actual" != "$PUERTO" ]]; then
            echo "  Cambiando puerto $p_actual -> $PUERTO..."
            configurar_puerto_nginx "$PUERTO"
            [[ -n "$p_actual" ]] && cerrar_firewall "$p_actual"
            abrir_firewall "$PUERTO"
            permitir_puerto_selinux "$PUERTO"
            systemctl restart nginx
            registrar_resumen "Nginx" "Puerto-Cambiado" "OK" "$p_actual -> $PUERTO"
            echo "  Puerto actualizado a $PUERTO."
        else
            echo "  Puerto ya configurado en $PUERTO."
        fi
        # Siempre actualizar index con la fuente actual
        crear_index "Nginx" "$VERSION_INSTALADA" "$PUERTO" "/usr/share/nginx/html" "$FUENTE"
        return 0
    fi

    detener_servicios_http
    abrir_firewall "$PUERTO"

    local INSTALADO=0

    if [[ -n "$ARCHIVO" && -f "$ARCHIVO" ]]; then
        instalar_desde_archivo "$ARCHIVO" "Nginx"
        command -v nginx &>/dev/null && INSTALADO=1
    fi

    if [[ $INSTALADO -eq 0 ]]; then
        # Mismo metodo que P6
        local BASE_URL="https://nginx.org/packages/rhel/9/x86_64/RPMS"
        local RPM_NAME="nginx-${VERSION}-1.el9.ngx.x86_64.rpm"
        echo "  Descargando $RPM_NAME desde nginx.org..."
        if curl -sSf --max-time 60 "$BASE_URL/$RPM_NAME" -o "/tmp/$RPM_NAME" 2>/dev/null; then
            rpm --import https://nginx.org/keys/nginx_signing.key 2>/dev/null
            dnf install -y "/tmp/$RPM_NAME" --allowerasing 2>/dev/null
            rm -f "/tmp/$RPM_NAME"
            command -v nginx &>/dev/null && INSTALADO=1
        fi
    fi

    if [[ $INSTALADO -eq 0 ]]; then
        echo "  Intentando via DNF como fallback..."
        dnf install -y nginx 2>/dev/null && INSTALADO=1
    fi

    [[ $INSTALADO -eq 0 ]] && { echo "  ERROR: No se pudo instalar Nginx."; return 1; }

    local VERSION_REAL; VERSION_REAL=$(nginx -v 2>&1 | cut -d'/' -f2)
    VERSION="$VERSION_REAL"

    # Corregir permisos (igual que P6)
    local NGINX_USER; NGINX_USER=$(grep -m1 "^user " /etc/nginx/nginx.conf 2>/dev/null | awk '{print $2}' | tr -d ';')
    [[ -z "$NGINX_USER" ]] && NGINX_USER="nginx"
    rm -f /run/nginx.pid; touch /run/nginx.pid
    chown "${NGINX_USER}:${NGINX_USER}" /run/nginx.pid 2>/dev/null
    restorecon /run/nginx.pid 2>/dev/null
    mkdir -p /var/log/nginx
    chown -R "${NGINX_USER}:${NGINX_USER}" /var/log/nginx
    restorecon -Rv /var/log/nginx 2>/dev/null

    permitir_puerto_selinux "$PUERTO"
    configurar_puerto_nginx "$PUERTO"
    crear_index "Nginx" "$VERSION" "$PUERTO" "/usr/share/nginx/html" "$FUENTE"
    configurar_seguridad_nginx

    nginx -t 2>/dev/null || { echo "  ERROR en config Nginx."; return 1; }
    systemctl enable nginx
    systemctl restart nginx
    sleep 2

    if ss -tuln | grep -q ":$PUERTO "; then
        echo "  Nginx instalado. v$VERSION | Puerto: $PUERTO | Estado: OK"
        registrar_resumen "Nginx" "Instalacion" "OK" "v$VERSION puerto $PUERTO"
    else
        echo "  Nginx instalado. v$VERSION | Puerto: $PUERTO | Estado: ADVERTENCIA"
        registrar_resumen "Nginx" "Instalacion" "ADVERTENCIA" "No responde en $PUERTO"
    fi
}

# ── TOMCAT (basado en P6 instalar_tomcat) ────────────────────────

instalar_tomcat_p7() {
    local VERSION=$1 PUERTO=$2 ARCHIVO="${3:-}" FUENTE="${4:-WEB}"

    # Detectar si ya esta instalado (mismo metodo que P6)
    local VERSION_INSTALADA=""
    if [[ -f /opt/tomcat/bin/startup.sh ]]; then
        VERSION_INSTALADA=$(cat /opt/tomcat/.tomcat_version 2>/dev/null)
        [[ -z "$VERSION_INSTALADA" ]] && VERSION_INSTALADA=$(grep -m1 "Apache Tomcat Version\|Tomcat/" \
            /opt/tomcat/RELEASE-NOTES 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [[ -z "$VERSION_INSTALADA" ]] && VERSION_INSTALADA=$(JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
            /opt/tomcat/bin/version.sh 2>/dev/null | grep -oP 'Server version:.*Tomcat/\K[0-9]+\.[0-9]+\.[0-9]+')
        [[ -z "$VERSION_INSTALADA" ]] && VERSION_INSTALADA="desconocida"
    fi

    if [[ -n "$VERSION_INSTALADA" ]]; then
        echo "  Tomcat ya instalado (v$VERSION_INSTALADA)."
        local p_actual; p_actual=$(obtener_puerto_tomcat)
        if [[ "$p_actual" != "$PUERTO" ]]; then
            echo "  Cambiando puerto $p_actual -> $PUERTO..."
            sed -i "s/Connector port=\"[0-9]*\"/Connector port=\"$PUERTO\"/" /opt/tomcat/conf/server.xml
            [[ -n "$p_actual" ]] && cerrar_firewall "$p_actual"
            abrir_firewall "$PUERTO"
            permitir_puerto_selinux "$PUERTO"
            pkill -f catalina 2>/dev/null; sleep 2
            sudo -u tomcatsvc env JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
                CATALINA_HOME=/opt/tomcat /opt/tomcat/bin/startup.sh
            registrar_resumen "Tomcat" "Puerto-Cambiado" "OK" "$p_actual -> $PUERTO"
            echo "  Puerto actualizado a $PUERTO."
        else
            echo "  Puerto ya configurado en $PUERTO."
        fi
        # Siempre actualizar index con la fuente actual
        crear_index "Tomcat" "$VERSION_INSTALADA" "$PUERTO" "/opt/tomcat/webapps/ROOT" "$FUENTE"
        return 0
    fi

    echo "  Instalando Java 21..."
    dnf install -y java-21-openjdk java-21-openjdk-devel 2>/dev/null

    detener_servicios_http
    abrir_firewall "$PUERTO"
    pkill -f catalina 2>/dev/null; sleep 2

    if [[ -n "$ARCHIVO" && -f "$ARCHIVO" ]]; then
        instalar_desde_archivo "$ARCHIVO" "Tomcat"
    else
        # Igual que P6: wget desde archive.apache.org
        echo "  Descargando Tomcat $VERSION..."
        local MAJOR; MAJOR=$(echo "$VERSION" | cut -d'.' -f1)
        cd /tmp
        wget -q "https://archive.apache.org/dist/tomcat/tomcat-$MAJOR/v$VERSION/bin/apache-tomcat-$VERSION.tar.gz" 2>/dev/null
        tar -xzf "apache-tomcat-$VERSION.tar.gz" 2>/dev/null
        pkill -f catalina 2>/dev/null
        rm -rf /opt/tomcat
        mv "apache-tomcat-$VERSION" /opt/tomcat 2>/dev/null
        cd - >/dev/null
    fi

    [[ ! -f /opt/tomcat/bin/startup.sh ]] && { echo "  ERROR: Tomcat no instalado."; return 1; }

    # Crear usuario (igual que P6)
    id tomcatsvc &>/dev/null || useradd -r -s /sbin/nologin -d /opt/tomcat tomcatsvc
    chown -R tomcatsvc:tomcatsvc /opt/tomcat
    echo "$VERSION" > /opt/tomcat/.tomcat_version

    # Configurar puerto y header (igual que P6)
    sed -i "s/Connector port=\"8080\"/Connector port=\"$PUERTO\"/" /opt/tomcat/conf/server.xml
    sed -i 's|protocol="org.apache.coyote.http11.Http11NioProtocol"|protocol="org.apache.coyote.http11.Http11NioProtocol" server="Apache-Tomcat"|' \
        /opt/tomcat/conf/server.xml 2>/dev/null

    permitir_puerto_selinux "$PUERTO"
    crear_index "Tomcat" "$VERSION" "$PUERTO" "/opt/tomcat/webapps/ROOT" "$FUENTE"

    # Iniciar (igual que P6)
    sudo -u tomcatsvc env JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
        CATALINA_HOME=/opt/tomcat /opt/tomcat/bin/startup.sh

    echo "  Esperando Tomcat en puerto $PUERTO..."
    for i in {1..20}; do
        ss -tuln | grep -q ":$PUERTO " && break
        echo "  Intento $i/20..."; sleep 1
    done

    if ss -tuln | grep -q ":$PUERTO "; then
        echo "  Tomcat instalado. v$VERSION | Puerto: $PUERTO | Estado: OK"
        registrar_resumen "Tomcat" "Instalacion" "OK" "v$VERSION puerto $PUERTO"
    else
        echo "  Tomcat instalado. v$VERSION | Puerto: $PUERTO | Estado: ADVERTENCIA"
        registrar_resumen "Tomcat" "Instalacion" "ADVERTENCIA" "No responde en $PUERTO"
    fi
}

# ── Flujo instalacion (WEB o FTP) ────────────────────────────────

flujo_instalar_servicio() {
    local servicio="$1"
    escribir_titulo "INSTALAR $servicio"

    echo "  Fuente de instalacion:"
    echo "    1) WEB - Repositorio oficial (DNF / descarga directa)"
    echo "    2) FTP - Repositorio privado (requiere repositorio preparado)"
    echo ""
    read -p "  Seleccione fuente [1/2]: " fuente

    local version="" archivo="" servicio_real="$servicio"

    if [[ "$fuente" == "1" ]]; then
        case $servicio in
            Apache)
                echo ""; echo "  Consultando versiones de Apache via DNF..."
                local VERSIONES; VERSIONES=$(dnf list --showduplicates httpd 2>/dev/null | grep "httpd.x86_64" | awk '{print $2}' | sort -V | uniq)
                local latest lts oldest
                latest=$(echo "$VERSIONES" | tail -n 1)
                lts=$(echo "$VERSIONES" | sed -n '2p')
                oldest=$(echo "$VERSIONES" | head -n 1)
                echo "  Versiones disponibles de Apache:"
                echo "    1) ${latest:-2.4}  (Latest / Desarrollo)"
                echo "    2) ${lts:-2.4}     (LTS / Estable)"
                echo "    3) ${oldest:-2.4}  (Oldest)"
                read -p "  Seleccione version [1-3]: " sel
                case $sel in 1) version="$latest";; 2) version="$lts";; 3) version="$oldest";; *) version="$latest";; esac
                ;;
            Nginx)
                echo ""
                local BASE_URL="https://nginx.org/packages/rhel/9/x86_64/RPMS"
                local VERSIONES_RAW n_latest n_lts n_oldest
                VERSIONES_RAW=$(curl -s --max-time 10 "$BASE_URL/" 2>/dev/null | \
                    grep -oP 'nginx-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.el9\.ngx\.x86_64\.rpm' | \
                    grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | uniq)
                n_latest=$(echo "$VERSIONES_RAW" | tail -n 1)
                n_lts=$(echo "$VERSIONES_RAW" | grep "^1\.24" | tail -n 1)
                [[ -z "$n_lts" ]] && n_lts=$(echo "$VERSIONES_RAW" | tail -n 2 | head -n 1)
                n_oldest=$(echo "$VERSIONES_RAW" | head -n 1)
                [[ -z "$n_latest" ]] && n_latest="1.26.3"
                [[ -z "$n_lts"    ]] && n_lts="1.24.0"
                [[ -z "$n_oldest" ]] && n_oldest="1.20.2"
                echo "  Versiones disponibles de Nginx:"
                echo "    1) $n_latest  (Latest / Desarrollo)"
                echo "    2) $n_lts     (LTS / Estable)"
                echo "    3) $n_oldest  (Oldest)"
                read -p "  Seleccione version [1-3]: " sel
                case $sel in 1) version="$n_latest";; 2) version="$n_lts";; 3) version="$n_oldest";; *) version="$n_latest";; esac
                ;;
            Tomcat)
                echo "  Versiones disponibles de Tomcat:"
                echo "    1) 10.1.28  (Latest / Desarrollo)"
                echo "    2) 10.1.26  (LTS / Estable)"
                echo "    3) 9.0.91   (Oldest)"
                read -p "  Seleccione version [1-3]: " sel
                case $sel in 1) version="10.1.28";; 2) version="10.1.26";; 3) version="9.0.91";; *) version="10.1.26";; esac
                ;;
        esac
    else
        navegar_y_descargar_ftp "$servicio" || { echo "  Instalacion cancelada."; return; }
        archivo="$ARCHIVO_DESCARGADO"
        servicio_real="$SERVICIO_DESCARGADO"
        fuente="FTP"
        echo "  Servicio a instalar: $servicio_real"
    fi

    local ps
    case $servicio_real in Apache) ps=8080;; Nginx) ps=8181;; Tomcat) ps=8282;; *) ps=8080;; esac
    echo ""
    read -p "  Puerto de escucha (sugerido: $ps, Enter = $ps): " puerto
    [[ -z "$puerto" ]] && puerto=$ps
    validar_puerto "$puerto" || return

    case $servicio_real in
        Apache) instalar_apache_p7 "$version" "$puerto" "$archivo" "$fuente" ;;
        Nginx)  instalar_nginx_p7  "$version" "$puerto" "$archivo" "$fuente" ;;
        Tomcat) instalar_tomcat_p7 "$version" "$puerto" "$archivo" "$fuente" ;;
        *) echo "  Servicio '$servicio_real' no reconocido." ;;
    esac
}

# ================================================================
# SECCION 6 - SSL/TLS
# ================================================================

pedir_dominio() {
    if [[ -n "$DOMINIO_SSL" ]]; then
        read -p "  Dominio actual: '$DOMINIO_SSL' Cambiar? [s/N]: " r
        [[ "$r" =~ ^[sS]$ ]] && read -p "  Nuevo dominio: " DOMINIO_SSL
    else
        read -p "  Dominio (Enter = 'www.reprobados.com'): " d
        DOMINIO_SSL="${d:-www.reprobados.com}"
    fi
}

generar_certificado_ssl() {
    local dominio="$1" ssl_dir="$2"
    mkdir -p "$ssl_dir"
    if [[ -f "$ssl_dir/server.crt" ]]; then
        local subj; subj=$(openssl x509 -subject -noout -in "$ssl_dir/server.crt" 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' | head -1)
        if [[ "$subj" == *"$dominio"* ]]; then
            echo "  Certificado para '$dominio' ya existe."
            echo "    Sujeto : CN=$subj"
            return 0
        fi
    fi
    echo "  Generando certificado autofirmado para '$dominio'..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$ssl_dir/server.key" -out "$ssl_dir/server.crt" \
        -subj "/CN=$dominio/O=Practica7/OU=SSL" 2>/dev/null
    [[ -f "$ssl_dir/server.crt" ]] || { echo "  ERROR al generar certificado."; return 1; }
    local expiry; expiry=$(openssl x509 -enddate -noout -in "$ssl_dir/server.crt" | cut -d= -f2)
    echo "  Certificado generado: CN=$dominio | Expira: $expiry"
    registrar_resumen "$dominio" "Cert-Generado" "OK" "$ssl_dir/server.crt"
}

activar_ssl_apache() {
    escribir_titulo "ACTIVAR SSL/TLS EN APACHE"
    command -v httpd &>/dev/null || { echo "  ERROR: Apache no instalado."; return 1; }
    pedir_dominio
    local dominio="$DOMINIO_SSL" ssl_dir="/etc/httpd/ssl/p7"
    generar_certificado_ssl "$dominio" "$ssl_dir" || return 1
    dnf install -y mod_ssl 2>/dev/null
    local puerto_http; puerto_http=$(obtener_puerto_apache); [[ -z "$puerto_http" ]] && puerto_http=80
    # mod_ssl instala ssl.conf con VirtualHost y Listen 443 propios
    # Deshabilitarlo completamente para que nuestro ssl_p7.conf tome precedencia
    if [[ -f /etc/httpd/conf.d/ssl.conf ]]; then
        mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.disabled
        echo "  ssl.conf de mod_ssl deshabilitado (usa ssl_p7.conf)."
    fi
    cat > /etc/httpd/conf.d/ssl_p7.conf <<SSLEOF
Listen 443 https
SSLPassPhraseDialog exec:/usr/libexec/httpd-ssl-pass-dialog
SSLSessionCache         shmcb:/run/httpd/sslcache(512000)
SSLSessionCacheTimeout  300
<VirtualHost *:443>
    ServerName $dominio
    DocumentRoot "/var/www/html"
    SSLEngine on
    SSLCertificateFile    $ssl_dir/server.crt
    SSLCertificateKeyFile $ssl_dir/server.key
    SSLProtocol all -SSLv2 -SSLv3
    SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</VirtualHost>
<VirtualHost *:$puerto_http>
    ServerName $dominio
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
SSLEOF
    abrir_firewall 443; permitir_puerto_selinux 443
    restorecon -Rv "$ssl_dir" 2>/dev/null
    systemctl restart httpd; sleep 3
    if ss -tuln | grep -q ":443 "; then
        echo "  Apache HTTPS 443: OK | Dominio: $dominio"
        registrar_resumen "Apache" "SSL-443" "OK" "Dominio: $dominio"
    else
        echo "  Apache HTTPS 443: ADVERTENCIA"
        echo "  Revisar: journalctl -xeu httpd | tail -20"
        registrar_resumen "Apache" "SSL-443" "ADVERTENCIA" "No responde en 443"
    fi
}

activar_ssl_nginx() {
    escribir_titulo "ACTIVAR SSL/TLS EN NGINX"
    command -v nginx &>/dev/null || { echo "  ERROR: Nginx no instalado."; return 1; }
    pedir_dominio
    local dominio="$DOMINIO_SSL" ssl_dir="/etc/nginx/ssl/p7"
    generar_certificado_ssl "$dominio" "$ssl_dir" || return 1
    local puerto_http; puerto_http=$(obtener_puerto_nginx)
    [[ -z "$puerto_http" || "$puerto_http" == "443" ]] && puerto_http=80
    cat > /etc/nginx/conf.d/default.conf <<NGXSSL
server {
    listen $puerto_http;
    server_name $dominio;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $dominio;
    root /usr/share/nginx/html;
    ssl_certificate     $ssl_dir/server.crt;
    ssl_certificate_key $ssl_dir/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    location / { index index.html; try_files \$uri \$uri/ =404; }
}
NGXSSL
    abrir_firewall 443; permitir_puerto_selinux 443
    restorecon -Rv "$ssl_dir" 2>/dev/null
    nginx -t 2>/dev/null || { echo "  ERROR de sintaxis en Nginx."; return 1; }
    systemctl restart nginx; sleep 3
    if ss -tuln | grep -q ":443 "; then
        echo "  Nginx HTTPS 443: OK | Dominio: $dominio"
        registrar_resumen "Nginx" "SSL-443" "OK" "Dominio: $dominio"
    else
        echo "  Nginx HTTPS 443: ADVERTENCIA"
        registrar_resumen "Nginx" "SSL-443" "ADVERTENCIA" "No responde en 443"
    fi
}

activar_ssl_tomcat() {
    escribir_titulo "ACTIVAR SSL/TLS EN TOMCAT"
    [[ -f /opt/tomcat/bin/startup.sh ]] || { echo "  ERROR: Tomcat no instalado."; return 1; }
    pedir_dominio
    local dominio="$DOMINIO_SSL" ssl_dir="/opt/tomcat/ssl"
    local keystore="$ssl_dir/keystore.p12" ks_pass="P7Tomcat2024"
    mkdir -p "$ssl_dir"
    chown -R tomcatsvc:tomcatsvc "$ssl_dir"

    local keytool_bin
    keytool_bin=$(find /usr/lib/jvm -name keytool 2>/dev/null | head -1)
    [[ -z "$keytool_bin" ]] && keytool_bin=$(command -v keytool 2>/dev/null)

    if [[ ! -f "$keystore" ]]; then
        echo "  Generando keystore para Tomcat..."
        [[ -z "$keytool_bin" ]] && { echo "  ERROR: keytool no encontrado. Instalar Java."; return 1; }
        "$keytool_bin" -genkeypair -alias tomcat -keyalg RSA -keysize 2048 -validity 365 \
            -keystore "$keystore" -storetype PKCS12 -storepass "$ks_pass" \
            -dname "CN=$dominio, O=Practica7, OU=P7-SSL" 2>/dev/null
        [[ -f "$keystore" ]] || { echo "  ERROR al generar keystore."; return 1; }
        echo "  Keystore generado."
    else
        echo "  Keystore ya existe."
    fi
    chown -R tomcatsvc:tomcatsvc "$ssl_dir"

    # Modificar server.xml con python3
    local server_xml="/opt/tomcat/conf/server.xml"
    python3 - "$server_xml" "$keystore" "$ks_pass" <<'PYEOF'
import sys, re
xml, ks, kp = sys.argv[1], sys.argv[2], sys.argv[3]
with open(xml) as f: c = f.read()

# Eliminar conector 8443 previo (con o sin SSLHostConfig)
c = re.sub(r'<Connector[^>]*port="8443".*?(?:</Connector>|/>)', '', c, flags=re.DOTALL)

# Tomcat 10+ requiere SSLHostConfig en lugar de keystoreFile en el Connector
conn = f'''    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               SSLEnabled="true" maxThreads="150" scheme="https" secure="true">
        <SSLHostConfig>
            <Certificate certificateKeystoreFile="{ks}"
                         certificateKeystorePassword="{kp}"
                         certificateKeystoreType="PKCS12"
                         type="RSA" />
        </SSLHostConfig>
    </Connector>'''

c = c.replace('</Service>', conn + '\n</Service>', 1)
with open(xml, 'w') as f: f.write(c)
print("  Conector SSL 8443 configurado en server.xml (Tomcat 10+ SSLHostConfig).")
PYEOF

    abrir_firewall 8443; permitir_puerto_selinux 8443
    # Redirigir puerto 443 -> 8443 para que Tomcat responda en https://IP sin puerto
    firewall-cmd --permanent --add-forward-port=port=443:proto=tcp:toport=8443 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    echo "  Redireccion 443 -> 8443 configurada."
    pkill -f catalina 2>/dev/null; sleep 3
    sudo -u tomcatsvc env JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
        CATALINA_HOME=/opt/tomcat /opt/tomcat/bin/startup.sh

    echo "  Esperando Tomcat en puerto 8443..."
    for i in {1..25}; do
        ss -tuln | grep -q ":8443 " && break
        echo "  Intento $i/25..."; sleep 2
    done

    if ss -tuln | grep -q ":8443 "; then
        echo "  Tomcat HTTPS 8443: OK | Dominio: $dominio"
        registrar_resumen "Tomcat" "SSL-8443" "OK" "Dominio: $dominio"
    else
        echo "  Tomcat HTTPS 8443: ADVERTENCIA"
        echo "  Revisar: tail -20 /opt/tomcat/logs/catalina.out"
        tail -5 /opt/tomcat/logs/catalina.out 2>/dev/null
        registrar_resumen "Tomcat" "SSL-8443" "ADVERTENCIA" "No responde en 8443"
    fi
}

activar_ftps_vsftpd() {
    escribir_titulo "ACTIVAR FTPS EN VSFTPD"
    systemctl is-active --quiet vsftpd 2>/dev/null || { echo "  ERROR: vsftpd no activo."; return 1; }
    pedir_dominio
    local dominio="$DOMINIO_SSL" ssl_dir="/etc/vsftpd/ssl"
    generar_certificado_ssl "$dominio" "$ssl_dir" || return 1
    local conf="$FTP_CONF"
    cp -n "$conf" "${conf}.bak_p7" 2>/dev/null
    for param in "ssl_enable=YES" "allow_anon_ssl=NO" \
        "force_local_data_ssl=YES" "force_local_logins_ssl=YES" \
        "ssl_tlsv1=YES" "ssl_sslv2=NO" "ssl_sslv3=NO" \
        "require_ssl_reuse=NO" "ssl_ciphers=HIGH" \
        "rsa_cert_file=$ssl_dir/server.crt" \
        "rsa_private_key_file=$ssl_dir/server.key"; do
        local key="${param%%=*}"
        grep -q "^${key}=" "$conf" && sed -i "s|^${key}=.*|${param}|" "$conf" || echo "$param" >> "$conf"
    done
    abrir_firewall 990
    firewall-cmd --permanent --add-service=ftps 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    command -v getenforce &>/dev/null && [[ "$(getenforce)" == "Enforcing" ]] && \
        setsebool -P ftpd_full_access 1 2>/dev/null
    restorecon -Rv "$ssl_dir" 2>/dev/null
    systemctl restart vsftpd; sleep 2
    if systemctl is-active --quiet vsftpd; then
        echo "  FTPS: OK | Dominio: $dominio"
        echo "  Verificar: openssl s_client -connect $(hostname -I | awk '{print $1}'):21 -starttls ftp"
        registrar_resumen "vsftpd" "FTPS-SSL" "OK" "Dominio: $dominio"
    else
        echo "  FTPS: ADVERTENCIA - journalctl -xeu vsftpd"
        registrar_resumen "vsftpd" "FTPS-SSL" "ADVERTENCIA" "vsftpd no inicio"
    fi
}

# ================================================================
# SECCION 7 - GESTION DE SERVICIOS
# ================================================================

gestionar_servicios_http() {
    escribir_titulo "GESTIONAR SERVICIOS HTTP"
    local a n t f
    systemctl is-active --quiet httpd  2>/dev/null && a="ACTIVO"  || a="DETENIDO"
    systemctl is-active --quiet nginx  2>/dev/null && n="ACTIVO"  || n="DETENIDO"
    pgrep -f catalina &>/dev/null      && t="ACTIVO"  || t="DETENIDO"
    systemctl is-active --quiet vsftpd 2>/dev/null && f="ACTIVO"  || f="DETENIDO"
    command -v httpd &>/dev/null || a="NO INSTALADO"
    command -v nginx &>/dev/null || n="NO INSTALADO"
    [[ ! -f /opt/tomcat/bin/startup.sh ]] && t="NO INSTALADO"
    rpm -q vsftpd &>/dev/null || f="NO INSTALADO"

    echo "  Estado:"; echo ""
    printf "    %-12s %s\n" "Apache" "$a"; printf "    %-12s %s\n" "Nginx" "$n"
    printf "    %-12s %s\n" "Tomcat" "$t"; printf "    %-12s %s\n" "vsftpd" "$f"
    echo ""
    echo "  1) Detener Apache  2) Iniciar Apache"
    echo "  3) Detener Nginx   4) Iniciar Nginx"
    echo "  5) Detener Tomcat  6) Iniciar Tomcat"
    echo "  7) Detener vsftpd  8) Iniciar vsftpd"
    echo "  9) Detener TODOS HTTP   0) Volver"
    echo ""
    read -p "  Seleccione: " op
    case $op in
        1) systemctl stop httpd  && echo "  Apache detenido." ;;
        2) systemctl start httpd && echo "  Apache iniciado." ;;
        3) systemctl stop nginx  && echo "  Nginx detenido."  ;;
        4) systemctl start nginx && echo "  Nginx iniciado."  ;;
        5) pkill -f catalina 2>/dev/null && echo "  Tomcat detenido." || echo "  No activo." ;;
        6) [[ -f /opt/tomcat/bin/startup.sh ]] && \
           sudo -u tomcatsvc env JAVA_HOME=/usr/lib/jvm/java-21-openjdk CATALINA_HOME=/opt/tomcat \
               /opt/tomcat/bin/startup.sh && echo "  Tomcat iniciado." || echo "  ERROR." ;;
        7) systemctl stop vsftpd  && echo "  vsftpd detenido." ;;
        8) systemctl start vsftpd && echo "  vsftpd iniciado." ;;
        9) systemctl stop httpd nginx 2>/dev/null; pkill -f catalina 2>/dev/null
           echo "  Todos detenidos. Use 2, 4 o 6 para iniciar uno." ;;
        0) return ;;
        *) echo "  Opcion invalida." ;;
    esac
}

# ================================================================
# SECCION 8 - ESTADO Y RESUMEN
# ================================================================

ver_estado_servicios() {
    escribir_titulo "ESTADO DE SERVICIOS"
    local pa pn pt
    pa=$(obtener_puerto_apache); [[ -z "$pa" ]] && pa=8080
    pn=$(obtener_puerto_nginx);  [[ -z "$pn" ]] && pn=8181
    pt=$(obtener_puerto_tomcat); [[ -z "$pt" ]] && pt=8282

    printf "  %-18s %-8s %s\n" "Servicio" "Puerto" "Estado"
    printf "  %-18s %-8s %s\n" "--------" "------" "------"
    for e in "Apache HTTP:$pa" "Apache HTTPS:443" "Nginx HTTP:$pn" "Nginx HTTPS:443" \
             "Tomcat HTTP:$pt" "Tomcat HTTPS:8443" "FTP:21" "FTPS:990"; do
        local nom="${e%%:*}" prt="${e##*:}"
        ss -tuln 2>/dev/null | grep -q ":$prt " && \
            printf "  %-18s %-8s \033[32m%s\033[0m\n" "$nom" "$prt" "ACTIVO" || \
            printf "  %-18s %-8s \033[90m%s\033[0m\n" "$nom" "$prt" "INACTIVO"
    done

    echo ""; echo "  Certificados SSL (P7):"
    for cert in /etc/httpd/ssl/p7/server.crt /etc/nginx/ssl/p7/server.crt \
                /opt/tomcat/ssl/server.crt    /etc/vsftpd/ssl/server.crt; do
        [[ -f "$cert" ]] && printf "    %-45s Expira: %s\n" \
            "$(openssl x509 -subject -noout -in $cert 2>/dev/null | sed 's/subject=//')" \
            "$(openssl x509 -enddate -noout -in $cert 2>/dev/null | cut -d= -f2)"
    done
}

mostrar_resumen_final() {
    escribir_titulo "RESUMEN FINAL - PRACTICA 7 LINUX"
    if [[ ! -s "$RESUMEN_FILE" ]]; then
        echo "  No hay acciones registradas."
    else
        printf "  %-25s %-20s %-15s %s\n" "Servicio" "Accion" "Estado" "Detalle"
        printf "  %-25s %-20s %-15s %s\n" "--------" "------" "------" "-------"
        while IFS='|' read -r s a e d; do
            printf "  %-25s %-20s %-15s %s\n" "$s" "$a" "$e" "$d"
        done < "$RESUMEN_FILE"
    fi
    local ip; ip=$(hostname -I | awk '{print $1}')
    echo ""; echo "  Comandos evidencias:"
    echo "    curl -k -I https://$ip"
    echo "    openssl s_client -connect $ip:443 -servername $DOMINIO_SSL"
    echo "    openssl s_client -connect $ip:8443 -servername $DOMINIO_SSL"
    echo "    openssl s_client -connect $ip:21 -starttls ftp"
    echo ""
    ver_estado_servicios
}

# ================================================================
# SECCION 9 - ADMINISTRACION FTP LOCAL (P5 integrado)
# ================================================================

ftp_instalar() {
    escribir_titulo "INSTALAR VSFTPD"
    if rpm -q vsftpd &>/dev/null; then
        echo "  vsftpd ya instalado."
        read -p "  Reinstalar? [s/N]: " r
        [[ "$r" =~ ^[sS]$ ]] && dnf reinstall -y vsftpd 2>/dev/null
    else
        dnf install -y vsftpd acl 2>/dev/null
    fi
    systemctl enable vsftpd; systemctl start vsftpd
    firewall-cmd --permanent --add-service=ftp 2>/dev/null
    firewall-cmd --permanent --add-port=40000-40100/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    command -v getenforce &>/dev/null && [[ "$(getenforce)" == "Enforcing" ]] && \
        setsebool -P ftpd_full_access 1 2>/dev/null && echo "  SELinux: ftpd_full_access habilitado."
    echo "  vsftpd instalado."
    registrar_resumen "vsftpd" "Instalacion" "OK"
}

ftp_configurar() {
    escribir_titulo "CONFIGURAR VSFTPD"
    local conf="$FTP_CONF"
    cp -n "$conf" "${conf}.bak" 2>/dev/null
    for param in "anonymous_enable=YES" "local_enable=YES" "write_enable=YES" \
        "chroot_local_user=YES" "allow_writeable_chroot=YES" "pasv_enable=YES" \
        "hide_ids=YES" "local_umask=002" "anon_upload_enable=NO" \
        "anon_mkdir_write_enable=NO" "anon_world_readable_only=YES" \
        "anon_root=/ftp/public"; do
        local key="${param%%=*}"
        grep -q "^${key}=" "$conf" && sed -i "s|^${key}=.*|${param}|" "$conf" || echo "$param" >> "$conf"
    done
    grep -q "^pasv_min_port" "$conf" || echo "pasv_min_port=40000" >> "$conf"
    grep -q "^pasv_max_port" "$conf" || echo "pasv_max_port=40100" >> "$conf"
    grep -q "^hide_file"     "$conf" || echo 'hide_file={public,users}' >> "$conf"
    systemctl restart vsftpd
    echo "  vsftpd configurado."
}

ftp_crear_grupos() {
    escribir_titulo "CREAR GRUPOS FTP"
    for g in reprobados recursadores ftpusuarios; do
        getent group "$g" &>/dev/null && echo "  Grupo '$g' ya existe." || \
            { groupadd "$g"; echo "  Grupo '$g' creado."; }
    done
}

ftp_crear_estructura() {
    escribir_titulo "CREAR ESTRUCTURA FTP"
    mkdir -p /ftp/public/general
    mkdir -p /ftp/public/http/Linux/{Apache,Nginx,Tomcat}
    mkdir -p /ftp/users/{reprobados,recursadores}
    mkdir -p /ftp/general
    mountpoint -q /ftp/general || mount --bind /ftp/public/general /ftp/general
    ln -sfn /ftp/users/reprobados   /ftp/reprobados
    ln -sfn /ftp/users/recursadores /ftp/recursadores
    chmod 755 /ftp /ftp/public; chmod 775 /ftp/public/general
    echo "  Estructura creada."
}

ftp_asignar_permisos() {
    escribir_titulo "ASIGNAR PERMISOS FTP"
    chown root:root /ftp; chmod 755 /ftp; chmod 755 /ftp/users
    chown root:reprobados /ftp/users/reprobados; chmod 2770 /ftp/users/reprobados
    chown root:recursadores /ftp/users/recursadores; chmod 2770 /ftp/users/recursadores
    chown root:ftpusuarios /ftp/public/general; chmod 775 /ftp/public/general
    setfacl -m g:ftpusuarios:rwx /ftp/public/general 2>/dev/null
    setfacl -m u:ftp:rx /ftp /ftp/public /ftp/public/general 2>/dev/null
    echo "  Permisos aplicados."
}

ftp_crear_usuarios() {
    escribir_titulo "CREAR USUARIOS FTP"
    read -p "  Numero de usuarios: " n
    for (( i=1; i<=n; i++ )); do
        echo ""; echo "  --- Usuario $i de $n ---"
        read -p "  Nombre: " nombre
        id "$nombre" &>/dev/null && { echo "  '$nombre' ya existe. Omitiendo."; continue; }
        read -s -p "  Contrasena: " password; echo ""
        read -p "  Grupo (reprobados/recursadores): " grupo
        [[ "$grupo" != "reprobados" && "$grupo" != "recursadores" ]] && { echo "  Grupo invalido."; continue; }

        useradd -m -d "/ftp/users/$nombre" -s /bin/bash -g "$grupo" -G ftpusuarios "$nombre"
        echo "$nombre:$password" | chpasswd

        # Crear carpetas por separado (no usar expansion de llaves con comillas dobles)
        mkdir -p "/ftp/users/$nombre/general"
        mkdir -p "/ftp/users/$nombre/$grupo"
        mkdir -p "/ftp/users/$nombre/$nombre"
        mkdir -p "/ftp/users/$nombre/http"

        mountpoint -q "/ftp/users/$nombre/general" || \
            mount --bind /ftp/public/general "/ftp/users/$nombre/general"
        mountpoint -q "/ftp/users/$nombre/$grupo" || \
            mount --bind "/ftp/users/$grupo" "/ftp/users/$nombre/$grupo"
        mountpoint -q "/ftp/users/$nombre/http" || \
            mount --bind "/ftp/public/http" "/ftp/users/$nombre/http"

        chown -R "$nombre:$grupo" "/ftp/users/$nombre/$nombre"
        chmod 700 "/ftp/users/$nombre/$nombre"
        chown :"$grupo" "/ftp/users/$nombre/$grupo"; chmod 775 "/ftp/users/$nombre/$grupo"

        echo "  Usuario '$nombre' creado en grupo '$grupo'."
    done
}

ftp_ver_usuarios() {
    echo ""; echo "  Usuarios FTP:"; echo ""
    getent group ftpusuarios &>/dev/null || { echo "  (Grupo ftpusuarios no existe)"; return; }
    local m; m=$(getent group ftpusuarios | cut -d: -f4 | tr ',' '\n')
    [[ -z "$m" ]] && echo "  (Sin usuarios)" && return
    while IFS= read -r u; do
        [[ -z "$u" ]] && continue
        printf "    %-20s Grupo: %s\n" "$u" "$(id -gn $u 2>/dev/null)"
    done <<< "$m"
    echo ""
}

ftp_cambiar_grupo() {
    escribir_titulo "CAMBIAR GRUPO"
    ftp_ver_usuarios
    read -p "  Nombre del usuario: " nombre
    id "$nombre" &>/dev/null || { echo "  '$nombre' no existe."; return; }
    read -p "  Nuevo grupo (reprobados/recursadores): " nuevo_grupo
    [[ "$nuevo_grupo" != "reprobados" && "$nuevo_grupo" != "recursadores" ]] && { echo "  Grupo invalido."; return; }
    local ga; ga=$(id -gn "$nombre")
    usermod -g "$nuevo_grupo" "$nombre"
    chown -R "$nombre:$nuevo_grupo" "/ftp/users/$nombre"
    if mountpoint -q "/ftp/users/$nombre/$ga"; then
        umount -l "/ftp/users/$nombre/$ga"; rm -rf "/ftp/users/$nombre/$ga"
    fi
    mkdir -p "/ftp/users/$nombre/$nuevo_grupo"
    mount --bind "/ftp/users/$nuevo_grupo" "/ftp/users/$nombre/$nuevo_grupo"
    chown :"$nuevo_grupo" "/ftp/users/$nombre/$nuevo_grupo"; chmod 775 "/ftp/users/$nombre/$nuevo_grupo"
    echo "  '$nombre' movido a '$nuevo_grupo'."
}

menu_administrar_ftp() {
    while true; do
        escribir_titulo "ADMINISTRAR SERVIDOR FTP LOCAL"
        echo "  -- CONFIGURACION INICIAL --"
        echo "   1) Instalar vsftpd"
        echo "   2) Configurar vsftpd.conf"
        echo "   3) Crear grupos"
        echo "   4) Crear estructura de carpetas"
        echo "   5) Asignar permisos"
        echo "  -- GESTION DE USUARIOS --"
        echo "   6) Crear usuario(s) FTP"
        echo "   7) Cambiar grupo de usuario"
        echo "   8) Ver usuarios FTP"
        echo "  -- UTILIDADES --"
        echo "   9) Ver estado"
        echo "  10) Reiniciar vsftpd"
        echo "   0) Volver"
        echo ""
        read -p "  Seleccione: " op
        case $op in
            1) ftp_instalar ;;
            2) ftp_configurar ;;
            3) ftp_crear_grupos ;;
            4) ftp_crear_estructura ;;
            5) ftp_asignar_permisos ;;
            6) ftp_crear_usuarios ;;
            7) ftp_cambiar_grupo ;;
            8) ftp_ver_usuarios ;;
            9) echo ""; systemctl is-active --quiet vsftpd && echo "  vsftpd: ACTIVO" || echo "  vsftpd: INACTIVO"
               ss -tuln | grep -E ":21 |:990 " ;;
            10) systemctl restart vsftpd && echo "  vsftpd reiniciado." ;;
            0) return ;;
            *) echo "  Opcion invalida." ;;
        esac
    done
}

# Inicializar resumen
> "$RESUMEN_FILE"
