#!/bin/bash
# ==============================================================
# Archivo: funciones_p11.sh
# Práctica 11 — Infraestructura como Código (IaC)
# Orquestación multicapa: Nginx + App + PostgreSQL + PgAdmin + SSH
# Adaptado desde funciones_p10.sh
# ==============================================================

DIR_BASE="/opt/practica11"

# ============================================================
# 1. INSTALAR DEPENDENCIAS
# ============================================================
instalar_dependencias() {
    echo "----------------------------------------"
    echo " Preparando Dependencias del Sistema"
    echo "----------------------------------------"

    if command -v docker &> /dev/null; then
        echo "Docker ya está instalado."
        read -p "¿Forzar reinstalación/actualización? (s/n): " reinstalar_docker
        if [[ "$reinstalar_docker" == "s" || "$reinstalar_docker" == "S" ]]; then
            echo "Reinstalando Docker..."
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io
        fi
    else
        echo "Instalando Docker..."
        dnf -y install dnf-plugins-core
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io
    fi

    systemctl enable docker
    systemctl start docker

    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo "Instalando Docker Compose Plugin..."
        dnf install -y docker-compose-plugin
    else
        echo "Docker Compose ya está instalado."
    fi

    # Herramientas para pruebas y túnel SSH
    for pkg in curl openssh-server openssh-clients; do
        if ! rpm -q "$pkg" &> /dev/null; then
            echo "Instalando $pkg..."
            dnf install -y "$pkg"
        else
            echo "$pkg ya instalado."
        fi
    done

    # Habilitar y arrancar sshd para los túneles SSH (Prueba 11.3)
    systemctl enable sshd
    systemctl start sshd
    echo "  - sshd activo y habilitado."

    echo "----------------------------------------"
    echo " Dependencias listas."
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 2. PREPARAR ENTORNO (CARPETAS + ARCHIVOS CONFIG)
# ============================================================
preparar_entorno_docker() {
    echo "----------------------------------------"
    echo " Preparando Estructura de Práctica 11"
    echo "----------------------------------------"

    echo "Creando directorios en $DIR_BASE..."
    mkdir -p "$DIR_BASE/nginx/html"
    mkdir -p "$DIR_BASE/webapp"
    mkdir -p "$DIR_BASE/db"
    mkdir -p "$DIR_BASE/backups"
    chmod -R 755 "$DIR_BASE"
    echo "  - Directorios listos."

    # Crear el archivo .env si no existe
    if [ ! -f "$DIR_BASE/.env" ]; then
        cat << 'EOF' > "$DIR_BASE/.env"
# Práctica 11 — Variables de Entorno
NGINX_HOST_PORT=80
POSTGRES_USER=admin_p11
POSTGRES_PASSWORD=SuperClave2025!
POSTGRES_DB=db_practica11
DB_PORT=5432
PGADMIN_EMAIL=admin@gmail.com
PGADMIN_PASSWORD=PgAdmin2025!
EOF
        echo "  - Archivo .env creado (modifica las credenciales si lo deseas)."
    else
        echo "  - Archivo .env ya existe. Se conserva."
    fi

    echo "----------------------------------------"
    echo " Entorno preparado en $DIR_BASE"
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 3. GENERAR ARCHIVOS DE CONFIGURACIÓN
# ============================================================
generar_archivos_configuracion() {
    echo "----------------------------------------"
    echo " Generando Archivos de Configuración"
    echo "----------------------------------------"

    # ── nginx.conf ────────────────────────────────────────────
    cat << 'EOF' > "$DIR_BASE/nginx/nginx.conf"
worker_processes auto;
events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # Ocultar versión del servidor (hardening)
    server_tokens off;

    # Cabeceras de seguridad
    add_header X-Content-Type-Options  "nosniff"       always;
    add_header X-Frame-Options         "SAMEORIGIN"    always;
    add_header X-XSS-Protection        "1; mode=block" always;
    proxy_hide_header X-Powered-By;

    upstream app_cluster {
        server webapp:8080;
    }

    server {
        listen 80;
        server_name _;

        location /health {
            access_log off;
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }

        location /static/ {
            root /usr/share/nginx/html;
            expires 1d;
        }

        location / {
            proxy_pass         http://app_cluster;
            proxy_http_version 1.1;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }
    }
}
EOF
    echo "  - nginx/nginx.conf generado."

    # ── Página estática para nginx ────────────────────────────
    cat << 'EOF' > "$DIR_BASE/nginx/html/index.html"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Práctica 11 — IaC Docker</title>
  <style>
    body { font-family: monospace; background: #0a0e1a; color: #00ff9f;
           display: flex; align-items: center; justify-content: center;
           min-height: 100vh; margin: 0; }
    .box { border: 1px solid #00ff9f; padding: 2rem; max-width: 500px;
           text-align: center; }
    h1 { font-size: 1.4rem; margin-bottom: 1rem; }
    p  { color: #c8d8e8; font-size: 0.9rem; line-height: 1.6; }
    .badge { background: rgba(0,255,159,0.1); border: 1px solid #00ff9f;
             padding: 3px 12px; border-radius: 20px; font-size: 0.75rem; }
  </style>
</head>
<body>
  <div class="box">
    <h1>⚡ Infraestructura como Código</h1>
    <p>Práctica 11 — Orquestación con Docker Compose</p>
    <br>
    <p><span class="badge">nginx</span> Balanceador activo</p>
    <p><span class="badge">webapp</span> Servidor de aplicaciones interno</p>
    <p><span class="badge">postgresql</span> Base de datos aislada</p>
    <p><span class="badge">pgadmin</span> Panel via túnel SSH</p>
  </div>
</body>
</html>
EOF
    echo "  - nginx/html/index.html generado."

    # ── Dockerfile y app del servidor interno ─────────────────
    cat << 'EOF' > "$DIR_BASE/webapp/Dockerfile"
FROM python:3.11-alpine
WORKDIR /app
RUN pip install flask psycopg2-binary --no-cache-dir
COPY app.py .
RUN adduser -D appuser
USER appuser
EXPOSE 8080
CMD ["python", "app.py"]
EOF

    cat << 'APPEOF' > "$DIR_BASE/webapp/app.py"
import os
from flask import Flask, jsonify
app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST", "db")
DB_NAME = os.getenv("DB_NAME", "db_practica11")
DB_USER = os.getenv("DB_USER", "admin_p11")

@app.route("/")
def index():
    return jsonify({
        "servicio": "Servidor de Aplicaciones Interno",
        "practica": "P11 - IaC",
        "estado": "activo",
        "nota": "Solo accesible via nginx, no desde el exterior."
    })

@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

@app.route("/db-status")
def db_status():
    try:
        import psycopg2
        conn = psycopg2.connect(
            host=DB_HOST, port=os.getenv("DB_PORT", 5432),
            dbname=DB_NAME, user=DB_USER,
            password=os.getenv("DB_PASSWORD", ""), connect_timeout=3
        )
        conn.close()
        return jsonify({"db": "conectada", "host": DB_HOST}), 200
    except Exception as e:
        return jsonify({"db": "error", "detalle": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
APPEOF
    echo "  - webapp/Dockerfile y app.py generados."

    # ── Script SQL de inicialización de BD ────────────────────
    cat << 'EOF' > "$DIR_BASE/db/init.sql"
CREATE TABLE IF NOT EXISTS registros_prueba (
    id        SERIAL PRIMARY KEY,
    mensaje   VARCHAR(200) NOT NULL,
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO registros_prueba (mensaje)
VALUES ('BD inicializada correctamente — Práctica 11');
EOF
    echo "  - db/init.sql generado."

    # ── docker-compose.yml ────────────────────────────────────
    _generar_compose

    echo "----------------------------------------"
    echo " Todos los archivos de configuración listos en $DIR_BASE"
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# Función interna: genera el docker-compose.yml
_generar_compose() {
    cat << 'EOF' > "$DIR_BASE/docker-compose.yml"
version: '3.8'

services:

  nginx:
    image: nginx:alpine
    container_name: balanceador_p11
    restart: always
    ports:
      - "${NGINX_HOST_PORT}:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/html:/usr/share/nginx/html:ro
    networks:
      - red_publica
      - red_interna
    depends_on:
      - webapp
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  webapp:
    build:
      context: ./webapp
      dockerfile: Dockerfile
    container_name: app_server_p11
    restart: always
    expose:
      - "8080"
    environment:
      - DB_HOST=db
      - DB_PORT=${DB_PORT}
      - DB_NAME=${POSTGRES_DB}
      - DB_USER=${POSTGRES_USER}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
    networks:
      - red_interna
      - red_datos
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  db:
    image: postgres:15-alpine
    container_name: base_datos_p11
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - db_data:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    networks:
      - red_datos
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: panel_admin_p11
    restart: always
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD}
      PGADMIN_LISTEN_PORT: 80
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    networks:
      - red_datos
    depends_on:
      db:
        condition: service_healthy

volumes:
  db_data:
    name: p11_db_data
    driver: local
  pgadmin_data:
    name: p11_pgadmin_data
    driver: local

networks:
  red_publica:
    name: p11_red_publica
    driver: bridge
  red_interna:
    name: p11_red_interna
    driver: bridge
  red_datos:
    name: p11_red_datos
    driver: bridge
    internal: true
EOF
    echo "  - docker-compose.yml generado."
}

# ============================================================
# 4. DESPLEGAR CONTENEDORES
# ============================================================
desplegar_contenedores() {
    echo "----------------------------------------"
    echo " Desplegando Infraestructura con Compose"
    echo "----------------------------------------"

    HOST_IP=$(hostname -I | awk '{print $1}')

    if [ ! -f "$DIR_BASE/docker-compose.yml" ]; then
        echo "ERROR: No se encontró docker-compose.yml."
        echo "Ejecuta primero la opción 3 (Generar Archivos)."
        read -p "Presiona Enter para continuar..."
        return 1
    fi

    cd "$DIR_BASE" || exit

    echo "Construyendo imágenes y levantando contenedores..."
    docker compose --env-file .env up -d --build

    if [ $? -eq 0 ]; then
        echo ""
        echo "----------------------------------------"
        echo " DESPLIEGUE EXITOSO — Práctica 11"
        echo "----------------------------------------"
        echo " Servicios activos:"
        echo "   - Nginx (público):  http://$HOST_IP"
        echo "   - App (interno):    solo via nginx"
        echo "   - PostgreSQL:       solo en red_datos"
        echo "   - PgAdmin:          solo via túnel SSH"
        echo ""
        echo " Para acceder a PgAdmin desde tu PC:"
        echo "   ssh -L 8080:panel_admin_p11:80 $(whoami)@$HOST_IP"
        echo "   Luego abre: http://localhost:8080"
        echo "----------------------------------------"
        docker compose ps
    else
        echo "ERROR al desplegar. Revisa los mensajes anteriores."
    fi

    cd - > /dev/null
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 5. CONFIGURAR FIREWALL (UFW / IPTABLES)
# ============================================================
configurar_firewall() {
    echo "----------------------------------------"
    echo " Configurando Firewall del Sistema"
    echo "----------------------------------------"
    echo ""
    echo " Esta acción bloqueará el acceso externo a puertos"
    echo " internos (PostgreSQL y PgAdmin) y solo permitirá:"
    echo "   - Puerto 80  (nginx público)"
    echo "   - Puerto 22  (SSH para administración)"
    echo ""
    read -p " ¿Continuar? (s/n): " confirmar_fw
    [[ "$confirmar_fw" != "s" && "$confirmar_fw" != "S" ]] && return

    if command -v ufw &> /dev/null; then
        echo "Usando UFW..."
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp    comment 'SSH - acceso administrativo'
        ufw allow 80/tcp    comment 'HTTP - nginx público'
        ufw --force enable
        echo ""
        echo " Estado del firewall:"
        ufw status verbose

    elif command -v iptables &> /dev/null; then
        echo "Usando iptables..."
        # Permitir tráfico establecido
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        # Permitir loopback
        iptables -A INPUT -i lo -j ACCEPT
        # Permitir SSH
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        # Permitir HTTP público (nginx)
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        # Bloquear el resto
        iptables -A INPUT -j DROP
        # Guardar reglas
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
            service iptables save 2>/dev/null
        echo " Reglas iptables aplicadas."
    else
        echo " AVISO: No se encontró ufw ni iptables."
        echo " Instala uno con: dnf install -y iptables-services"
    fi

    echo ""
    echo " NOTA: Los contenedores se comunican por redes internas"
    echo " de Docker. El firewall del HOST protege el perímetro."
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 6. MENÚ DE PRUEBAS DE VALIDACIÓN
# ============================================================
menu_pruebas() {
    while true; do
        clear
        echo "=========================================================="
        echo " Protocolo de Pruebas (Validación Práctica 11)"
        echo "=========================================================="
        echo " 1. Prueba 11.1 — Aislamiento de Red (curl debe fallar)"
        echo " 2. Prueba 11.2 — DNS Interno entre contenedores"
        echo " 3. Prueba 11.3 — Instrucciones Túnel SSH"
        echo " 4. Prueba 11.4 — Persistencia y Healthcheck"
        echo ""
        echo " 0. Volver al menú principal"
        echo "=========================================================="
        read -p " Selecciona la prueba: " op_prueba

        case $op_prueba in
            1) prueba_aislamiento_red ;;
            2) prueba_dns_interno ;;
            3) prueba_tunel_ssh ;;
            4) prueba_persistencia ;;
            0) break ;;
            *) echo "Opción no válida."; sleep 2 ;;
        esac
    done
}

# Prueba 11.1 — Aislamiento de red
prueba_aislamiento_red() {
    echo "----------------------------------------"
    echo " Prueba 11.1: Aislamiento de Red"
    echo "----------------------------------------"
    HOST_IP=$(hostname -I | awk '{print $1}')

    echo "[1/3] Intentando conectar a PostgreSQL (5432) desde el host..."
    echo "      → Debe FALLAR (timeout o connection refused)"
    timeout 5 bash -c "echo '' > /dev/tcp/$HOST_IP/5432" 2>&1 \
        && echo "  ✗ ATENCIÓN: Puerto 5432 accesible (revisar configuración)" \
        || echo "  ✓ CORRECTO: Puerto 5432 no accesible desde el exterior"

    echo ""
    echo "[2/3] Intentando conectar a PgAdmin (5050) desde el host..."
    echo "      → Debe FALLAR (pgadmin no tiene puerto expuesto)"
    timeout 5 bash -c "echo '' > /dev/tcp/$HOST_IP/5050" 2>&1 \
        && echo "  ✗ ATENCIÓN: Puerto 5050 accesible (revisar configuración)" \
        || echo "  ✓ CORRECTO: Puerto 5050 no accesible desde el exterior"

    echo ""
    echo "[3/3] Probando acceso al nginx (puerto 80)..."
    echo "      → Debe FUNCIONAR (es el único punto de entrada público)"
    if curl -s -o /dev/null -w "%{http_code}" "http://$HOST_IP" | grep -q "200"; then
        echo "  ✓ CORRECTO: Nginx responde en puerto 80"
    else
        echo "  ✗ ERROR: Nginx no responde. Verifica el despliegue."
    fi

    echo ""
    echo " TOMA CAPTURA DE PANTALLA DE ESTA SALIDA PARA TU REPORTE"
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# Prueba 11.2 — DNS interno
prueba_dns_interno() {
    echo "----------------------------------------"
    echo " Prueba 11.2: Resolución DNS Interna"
    echo " (Ping desde nginx hacia el servicio db)"
    echo "----------------------------------------"

    echo "[1/3] Conectando nginx a red_datos temporalmente..."
    docker network connect p11_red_datos balanceador_p11 2>/dev/null \
        && echo "  - nginx conectado a red_datos." \
        || echo "  - nginx ya estaba conectado (normal si se repite la prueba)."

    echo ""
    echo "[2/3] Ping desde balanceador_p11 (nginx) → db por nombre de servicio..."
    echo "      → Debe FUNCIONAR (DNS interno de Docker resuelve 'db')"
    echo ""
    docker exec balanceador_p11 ping -c 4 db
    RESULTADO=$?

    echo ""
    if [ $RESULTADO -eq 0 ]; then
        echo "  ✓ CORRECTO: nginx resolvió 'db' por nombre y recibió respuesta."
    else
        echo "  ✗ ERROR: No se pudo hacer ping. Verifica que los contenedores estén activos."
    fi

    echo ""
    echo "[3/3] Desconectando nginx de red_datos (restaurando aislamiento)..."
    docker network disconnect p11_red_datos balanceador_p11 2>/dev/null \
        && echo "  - Aislamiento restaurado correctamente." \
        || echo "  - No se pudo desconectar (revisar manualmente)."

    echo ""
    echo " Los contenedores se encuentran POR NOMBRE, no por IP fija."
    echo " TOMA CAPTURA DE PANTALLA DE ESTA SALIDA PARA TU REPORTE"
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# Prueba 11.3 — Túnel SSH
prueba_tunel_ssh() {
    # Obtener IP correcta del servidor (interfaz enp0s9 o la que no sea NAT)
    HOST_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1\|10.0.2' | awk '{print $2}' | cut -d/ -f1 | head -1)
    # Si no encontró IP alternativa, usar la principal
    [ -z "$HOST_IP" ] && HOST_IP=$(hostname -I | awk '{print $1}')
    USUARIO=$(whoami)

    # Obtener IP interna del contenedor pgadmin
    PGADMIN_IP=$(docker inspect panel_admin_p11 \
        --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.IPAddress}} {{end}}' \
        2>/dev/null | tr ' ' '\n' | grep -v '^$' | grep -v 'invalid' | head -1)

    echo "----------------------------------------"
    echo " Prueba 11.3: Túnel SSH hacia PgAdmin"
    echo "----------------------------------------"
    echo ""
    echo " Esta prueba se realiza desde tu COMPUTADORA LOCAL."
    echo " El servidor PgAdmin NO tiene puerto público expuesto."
    echo " Solo es accesible a través de un túnel SSH cifrado."
    echo ""
    echo " IP del servidor (usar esta):  $HOST_IP"
    echo " IP interna de PgAdmin:        $PGADMIN_IP"
    echo ""
    echo " ┌──────────────────────────────────────────────────────┐"
    echo " │  PASO 1: Abre PowerShell en tu PC local              │"
    echo " │                                                      │"
    echo " │  Ejecuta este comando:                               │"
    echo " │                                                      │"
    echo " │  ssh -L 8080:$PGADMIN_IP:80 $USUARIO@$HOST_IP"
    echo " │                                                      │"
    echo " │  PASO 2: Pon tu contraseña y deja la terminal abierta│"
    echo " │                                                      │"
    echo " │  PASO 3: En tu navegador, ve a:                      │"
    echo " │  http://localhost:8080                               │"
    echo " │                                                      │"
    echo " │  PASO 4: Inicia sesión en PgAdmin con:               │"
    echo " │  Email:    admin@gmail.com                           │"
    echo " │  Password: PgAdmin2025!                              │"
    echo " │                                                      │"
    echo " │  PASO 5: Conecta a PostgreSQL:                       │"
    echo " │  Host:     db                                        │"
    echo " │  Puerto:   5432                                      │"
    echo " │  Usuario/Pass: los de tu .env                        │"
    echo " └──────────────────────────────────────────────────────┘"
    echo ""
    echo " TOMA CAPTURA DEL NAVEGADOR CON PGADMIN CARGADO"
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# Prueba 11.4 — Persistencia y healthcheck
prueba_persistencia() {
    echo "----------------------------------------"
    echo " Prueba 11.4: Persistencia y Healthcheck"
    echo "----------------------------------------"

    # Cargar variables del .env
    source "$DIR_BASE/.env" 2>/dev/null || true

    echo "[1/5] Insertando registro de prueba en la BD..."
    docker exec base_datos_p11 psql \
        -U "${POSTGRES_USER:-admin_p11}" \
        -d "${POSTGRES_DB:-db_practica11}" \
        -c "INSERT INTO registros_prueba (mensaje) VALUES ('Prueba de persistencia P11 — $(date)');"

    echo ""
    echo "[2/5] Consultando registros actuales..."
    docker exec base_datos_p11 psql \
        -U "${POSTGRES_USER:-admin_p11}" \
        -d "${POSTGRES_DB:-db_practica11}" \
        -c "SELECT * FROM registros_prueba;"

    echo ""
    echo "[3/5] Deteniendo todo el stack..."
    cd "$DIR_BASE" && docker compose down
    echo "  - Contenedores eliminados."

    echo ""
    echo "[4/5] Levantando de nuevo (los datos deben sobrevivir)..."
    docker compose --env-file .env up -d --build
    echo "  - Esperando que la BD arranque (healthcheck)..."

    # Esperar a que la BD esté healthy
    local intentos=0
    while ! docker exec base_datos_p11 pg_isready \
        -U "${POSTGRES_USER:-admin_p11}" &>/dev/null; do
        sleep 3
        intentos=$((intentos + 1))
        echo "  - Intento $intentos — esperando a PostgreSQL..."
        [ $intentos -ge 15 ] && echo "  TIMEOUT — revisa los logs con: docker compose logs db" && break
    done

    echo ""
    echo "[5/5] Verificando que los datos persisten..."
    docker exec base_datos_p11 psql \
        -U "${POSTGRES_USER:-admin_p11}" \
        -d "${POSTGRES_DB:-db_practica11}" \
        -c "SELECT * FROM registros_prueba;" 2>/dev/null \
        && echo "" \
        && echo "  ✓ PERSISTENCIA CONFIRMADA: Los datos sobrevivieron al docker compose down" \
        || echo "  ✗ ERROR: No se pudieron recuperar los datos."

    echo ""
    echo " Verificando estado de healthcheck de todos los servicios:"
    docker compose ps

    echo ""
    echo " TOMA CAPTURA DE PANTALLA DE ESTA SALIDA PARA TU REPORTE"
    echo "----------------------------------------"

    cd - > /dev/null
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 7. GESTIONAR INFRAESTRUCTURA
# ============================================================
limpiar_infraestructura() {
    while true; do
        clear
        echo "=========================================================="
        echo " Gestión de Infraestructura — Práctica 11"
        echo "=========================================================="
        echo " 1. Detener contenedores (datos conservados)"
        echo " 2. Reiniciar contenedores"
        echo " 3. Ver estado actual (docker ps + logs)"
        echo " 4. Ver logs de un servicio específico"
        echo " 5. ELIMINAR TODO (contenedores + volúmenes + imágenes)"
        echo ""
        echo " 0. Volver al menú principal"
        echo "=========================================================="
        read -p " Selecciona una opción: " op_clean

        case $op_clean in
            1)
                cd "$DIR_BASE" && docker compose stop
                echo "  - Contenedores detenidos. Datos conservados en volúmenes."
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                cd "$DIR_BASE" && docker compose restart
                echo "  - Contenedores reiniciados."
                read -p "Presiona Enter para continuar..."
                ;;
            3)
                echo "Estado de contenedores:"
                docker compose -f "$DIR_BASE/docker-compose.yml" ps
                echo ""
                echo "Uso de recursos:"
                docker stats --no-stream
                read -p "Presiona Enter para continuar..."
                ;;
            4)
                echo "Servicios disponibles: nginx, webapp, db, pgadmin"
                read -p "¿De cuál servicio quieres ver logs? " servicio
                docker compose -f "$DIR_BASE/docker-compose.yml" logs --tail=50 "$servicio"
                read -p "Presiona Enter para continuar..."
                ;;
            5)
                echo "----------------------------------------"
                echo " ADVERTENCIA: Se eliminarán contenedores,"
                echo " volúmenes e imágenes construidas."
                echo "----------------------------------------"
                read -p " Escribe 'CONFIRMAR' para continuar: " confirmacion
                if [ "$confirmacion" == "CONFIRMAR" ]; then
                    cd "$DIR_BASE" && docker compose down -v --rmi local
                    echo "  - Infraestructura eliminada."
                    echo "  - Archivos en $DIR_BASE conservados."
                else
                    echo "  - Operación cancelada."
                fi
                read -p "Presiona Enter para continuar..."
                ;;
            0) break ;;
            *) echo "Opción no válida."; sleep 2 ;;
        esac
    done
}