#!/bin/bash
# Archivo: funciones_p10.sh
# Práctica 10 - Virtualización con Docker

# Ruta raíz de infraestructura (fuera del repositorio)
DIR_BASE="/opt/practica10"

# ============================================================
# 1. INSTALAR DEPENDENCIAS
# ============================================================
instalar_dependencias() {
    echo "----------------------------------------"
    echo " Preparando Dependencias del Sistema"
    echo "----------------------------------------"

    if command -v docker &> /dev/null; then
        echo "Se ha detectado que Docker ya está instalado."
        read -p "¿Deseas forzar la reinstalación/actualización? (s/n): " reinstalar_docker
        if [[ "$reinstalar_docker" == "s" || "$reinstalar_docker" == "S" ]]; then
            echo "Reinstalando Docker..."
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io
        else
            echo "Omitiendo reinstalación de Docker."
        fi
    else
        echo "Docker no está instalado. Procediendo a instalar..."
        dnf -y install dnf-plugins-core
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io
    fi

    systemctl enable docker
    systemctl start docker

    if docker compose version &> /dev/null || command -v docker-compose &> /dev/null; then
        echo "Docker Compose ya está instalado."
    else
        echo "Instalando Docker Compose..."
        dnf install -y docker-compose-plugin
    fi

    # curl es necesario para la Prueba 10.3
    if ! command -v curl &> /dev/null; then
        echo "Instalando curl (necesario para pruebas)..."
        dnf install -y curl
    fi

    echo "----------------------------------------"
    echo " Dependencias listas y servicios activos."
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 2. PREPARAR ENTORNO (CARPETAS + RED)
# ============================================================
preparar_entorno_docker() {
    echo "----------------------------------------"
    echo " Preparando Estructura y Red de Docker"
    echo "----------------------------------------"

    echo "Creando directorios en $DIR_BASE..."
    mkdir -p "$DIR_BASE/web" "$DIR_BASE/db" "$DIR_BASE/ftp" "$DIR_BASE/backups"
    chmod -R 755 "$DIR_BASE"
    echo "  - Directorios listos (web, db, ftp, backups)."

    echo "Validando red de Docker (infra_red - 172.20.0.0/16)..."
    if docker network ls | grep -q "infra_red"; then
        echo "  - La red 'infra_red' ya existe. Omitiendo creación."
    else
        docker network create --subnet=172.20.0.0/16 infra_red
        if [ $? -eq 0 ]; then
            echo "  - Red 'infra_red' creada exitosamente."
        else
            echo "  - ERROR al crear la red."
        fi
    fi

    echo "----------------------------------------"
    echo " Entorno de carpetas y red preparado."
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 3. GENERAR ARCHIVOS DE CONFIGURACIÓN WEB
# ============================================================
generar_archivos_configuracion() {
    echo "----------------------------------------"
    echo " Generando Archivos de Configuracion Web"
    echo "----------------------------------------"

    if [ -f "$DIR_BASE/web/Dockerfile" ]; then
        read -p "Los archivos web ya existen. ¿Sobrescribir? (s/n): " sobrescribir_web
        [[ "$sobrescribir_web" == "s" || "$sobrescribir_web" == "S" ]] && generar_web="si" || generar_web="no"
    else
        generar_web="si"
    fi

    if [ "$generar_web" == "si" ]; then

        # --- nginx.conf: server_tokens off, usuario no-root en puerto 8080 ---
        cat << 'EOF' > "$DIR_BASE/web/nginx.conf"
worker_processes 1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    server_tokens off;

    server {
        listen 8080;
        server_name localhost;

        location / {
            root  /usr/share/nginx/html;
            index index.html index.htm;
        }
    }
}
EOF

        # --- index.html con recursos estáticos externos (style.css + logo.svg) ---
        cat << 'EOF' > "$DIR_BASE/web/index.html"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Práctica 10 — Infraestructura Docker</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="contenedor">
    <header>
      <img src="logo.svg" alt="Logo Docker" class="logo-img">
      <h1>Infraestructura con Docker</h1>
      <p class="subtitulo">Práctica 10 &mdash; Virtualización y Contenedores</p>
    </header>
    <div class="grid">
      <div class="tarjeta">
        <svg class="icono" viewBox="0 0 52 52" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect x="2" y="8" width="48" height="36" rx="5" stroke="#00ff9f" stroke-width="2.5"/>
          <path d="M2 16h48" stroke="#00ff9f" stroke-width="2"/>
          <circle cx="10" cy="12" r="2" fill="#00ff9f"/>
          <circle cx="18" cy="12" r="2" fill="#00c8ff"/>
          <circle cx="26" cy="12" r="2" fill="#ffaa00"/>
          <path d="M12 28h12M12 34h20" stroke="#00c8ff" stroke-width="2" stroke-linecap="round"/>
        </svg>
        <h2>Servidor Web</h2>
        <p>Nginx sobre Alpine Linux. Imagen personalizada con usuario no-root y server tokens desactivados.</p>
        <span class="badge">Puerto 80 → 8080</span>
      </div>
      <div class="tarjeta">
        <svg class="icono" viewBox="0 0 52 52" fill="none" xmlns="http://www.w3.org/2000/svg">
          <ellipse cx="26" cy="14" rx="18" ry="7" stroke="#00c8ff" stroke-width="2.5"/>
          <path d="M8 14v10c0 3.87 8.06 7 18 7s18-3.13 18-7V14" stroke="#00c8ff" stroke-width="2.5"/>
          <path d="M8 24v10c0 3.87 8.06 7 18 7s18-3.13 18-7V24" stroke="#00c8ff" stroke-width="2.5"/>
          <circle cx="26" cy="14" r="3" fill="#00ff9f"/>
        </svg>
        <h2>Base de Datos</h2>
        <p>PostgreSQL 15 en Alpine. Volumen persistente db_data con respaldo automático al host.</p>
        <span class="badge">Puerto 5432</span>
      </div>
      <div class="tarjeta">
        <svg class="icono" viewBox="0 0 52 52" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect x="6" y="10" width="40" height="32" rx="4" stroke="#ffaa00" stroke-width="2.5"/>
          <path d="M6 20h40" stroke="#ffaa00" stroke-width="2"/>
          <path d="M26 30 L20 36 M26 30 L32 36 M26 30 V24" stroke="#00ff9f" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        <h2>Servidor FTP</h2>
        <p>Transferencia de archivos al volumen compartido web_content, accesible directamente por Nginx.</p>
        <span class="badge">Puerto 21</span>
      </div>
    </div>
    <div class="status-bar">
      <div class="status-item"><span class="dot"></span> servidor_web_p10 — ACTIVO</div>
      <div class="status-item"><span class="dot azul"></span> base_datos_p10 — ACTIVO</div>
      <div class="status-item"><span class="dot naranja"></span> servidor_ftp_p10 — ACTIVO</div>
      <div class="status-item" style="margin-left:auto; color: rgba(200,216,232,0.4)">
        Red: infra_red | 172.20.0.0/16
      </div>
    </div>
    <footer>Oracle Linux &bull; Docker Compose &bull; Práctica 10 &bull; 2025</footer>
  </div>
</body>
</html>
EOF

        # --- style.css como recurso estático externo ---
        cat << 'EOF' > "$DIR_BASE/web/style.css"
@import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Exo+2:wght@300;600;900&display=swap');
:root { --verde:#00ff9f; --azul:#00c8ff; --oscuro:#0a0e1a; --panel:rgba(0,255,159,0.06); --borde:rgba(0,255,159,0.25); }
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Exo 2',sans-serif;background-color:var(--oscuro);color:#c8d8e8;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:2rem;overflow-x:hidden}
body::before{content:'';position:fixed;inset:0;background:radial-gradient(ellipse 80% 50% at 20% 40%,rgba(0,200,255,0.07) 0%,transparent 60%),radial-gradient(ellipse 60% 80% at 80% 60%,rgba(0,255,159,0.05) 0%,transparent 60%);pointer-events:none;z-index:0}
.contenedor{position:relative;z-index:1;width:100%;max-width:860px}
header{text-align:center;margin-bottom:2.5rem;animation:fadeDown 0.8s ease both}
header .logo-img{width:90px;height:90px;margin:0 auto 1.2rem;display:block;filter:drop-shadow(0 0 18px var(--verde));animation:pulso 3s ease-in-out infinite}
@keyframes pulso{0%,100%{filter:drop-shadow(0 0 12px var(--verde))}50%{filter:drop-shadow(0 0 28px var(--azul))}}
header h1{font-family:'Share Tech Mono',monospace;font-size:clamp(1.5rem,4vw,2.4rem);color:var(--verde);letter-spacing:.06em;text-shadow:0 0 20px rgba(0,255,159,.5)}
header p.subtitulo{font-size:.9rem;font-weight:300;color:rgba(200,216,232,.6);margin-top:.4rem;letter-spacing:.12em;text-transform:uppercase}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:1.2rem;margin-bottom:2rem}
.tarjeta{background:var(--panel);border:1px solid var(--borde);border-radius:12px;padding:1.4rem 1.2rem;transition:transform .25s,box-shadow .25s;animation:fadeUp .7s ease both}
.tarjeta:nth-child(1){animation-delay:.1s}.tarjeta:nth-child(2){animation-delay:.25s}.tarjeta:nth-child(3){animation-delay:.4s}
.tarjeta:hover{transform:translateY(-4px);box-shadow:0 8px 32px rgba(0,255,159,.12)}
.tarjeta .icono{width:52px;height:52px;margin-bottom:.9rem}
.tarjeta h2{font-size:1rem;font-weight:600;color:var(--verde);margin-bottom:.4rem;font-family:'Share Tech Mono',monospace}
.tarjeta p{font-size:.82rem;line-height:1.55;color:rgba(200,216,232,.75)}
.badge{display:inline-block;margin-top:.7rem;background:rgba(0,255,159,.12);border:1px solid var(--verde);color:var(--verde);font-family:'Share Tech Mono',monospace;font-size:.7rem;padding:2px 10px;border-radius:20px;letter-spacing:.08em}
.status-bar{background:var(--panel);border:1px solid var(--borde);border-radius:10px;padding:1rem 1.4rem;display:flex;flex-wrap:wrap;gap:1.2rem;align-items:center;animation:fadeUp .7s .5s ease both}
.status-item{display:flex;align-items:center;gap:.5rem;font-family:'Share Tech Mono',monospace;font-size:.78rem;color:rgba(200,216,232,.8)}
.dot{width:8px;height:8px;border-radius:50%;background:var(--verde);box-shadow:0 0 8px var(--verde);animation:parpadeo 1.8s ease-in-out infinite}
.dot.azul{background:var(--azul);box-shadow:0 0 8px var(--azul);animation-delay:.6s}
.dot.naranja{background:#ffaa00;box-shadow:0 0 8px #ffaa00;animation-delay:1.2s}
@keyframes parpadeo{0%,100%{opacity:1}50%{opacity:.3}}
@keyframes fadeDown{from{opacity:0;transform:translateY(-20px)}to{opacity:1;transform:translateY(0)}}
@keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
footer{text-align:center;margin-top:2rem;font-size:.72rem;color:rgba(200,216,232,.3);font-family:'Share Tech Mono',monospace;letter-spacing:.1em;animation:fadeUp .7s .7s ease both;opacity:0;animation-fill-mode:forwards}
EOF

        # --- logo.svg como recurso de imagen estático ---
        cat << 'EOF' > "$DIR_BASE/web/logo.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs>
    <radialGradient id="g1" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#00ff9f" stop-opacity="0.9"/>
      <stop offset="100%" stop-color="#00c8ff" stop-opacity="0.6"/>
    </radialGradient>
  </defs>
  <polygon points="50,5 90,27.5 90,72.5 50,95 10,72.5 10,27.5" fill="none" stroke="url(#g1)" stroke-width="3"/>
  <polygon points="50,18 78,33.5 78,66.5 50,82 22,66.5 22,33.5" fill="none" stroke="#00c8ff" stroke-width="1.5" opacity="0.5"/>
  <rect x="30" y="44" width="10" height="7" rx="1.5" fill="#00ff9f"/>
  <rect x="43" y="38" width="10" height="7" rx="1.5" fill="#00ff9f"/>
  <rect x="43" y="47" width="10" height="7" rx="1.5" fill="#00c8ff"/>
  <rect x="56" y="44" width="10" height="7" rx="1.5" fill="#00ff9f"/>
  <path d="M28 55 Q38 50 48 55 Q58 60 68 55 Q73 52 75 55" fill="none" stroke="#00c8ff" stroke-width="2" stroke-linecap="round"/>
</svg>
EOF

        echo "  - Archivos web creados exitosamente en $DIR_BASE/web"
        echo "    (index.html + style.css + logo.svg + nginx.conf + Dockerfile)"
    fi

    # --- Dockerfile personalizado ---
    cat << 'EOF' > "$DIR_BASE/web/Dockerfile"
FROM nginx:alpine

# Copiar configuración y recursos estáticos
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html
COPY style.css  /usr/share/nginx/html/style.css
COPY logo.svg   /usr/share/nginx/html/logo.svg

# Ajustar permisos para usuario no-root
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

# Ejecutar con usuario no administrativo
USER nginx
EXPOSE 8080
EOF

    echo "----------------------------------------"
    echo " Configuración web finalizada."
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 4. DESPLEGAR CONTENEDORES
# ============================================================
desplegar_contenedores() {
    echo "----------------------------------------"
    echo " Desplegando Infraestructura con Compose"
    echo "----------------------------------------"

    # Obtener IP del host para el servidor FTP (modo pasivo)
    HOST_IP=$(hostname -I | awk '{print $1}')
    echo "  - IP detectada del host: $HOST_IP (usada para FTP pasivo)"

    echo "Generando docker-compose.yml en $DIR_BASE..."

    # NOTA: usamos mem_limit y cpus directamente (no deploy.resources)
    # porque deploy.resources solo funciona con Docker Swarm, no con compose up normal.
    cat << EOF > "$DIR_BASE/docker-compose.yml"
version: '3.8'

services:

  db:
    image: postgres:15-alpine
    container_name: base_datos_p10
    restart: unless-stopped
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: admin_password
      POSTGRES_DB: base_practica
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - infra_red
    mem_limit: 512m
    cpus: 0.5

  ftp:
    image: delfer/alpine-ftp-server
    container_name: servidor_ftp_p10
    restart: unless-stopped
    environment:
      USERS: "adminftp|passwordftp"
      ADDRESS: $HOST_IP
    ports:
      - "21:21"
      - "21000-21010:21000-21010"
    volumes:
      - web_content:/ftp/adminftp
    networks:
      - infra_red
    mem_limit: 256m
    cpus: 0.2

  web:
    build:
      context: ./web
      dockerfile: Dockerfile
    container_name: servidor_web_p10
    restart: unless-stopped
    ports:
      - "80:8080"
    volumes:
      - web_content:/usr/share/nginx/html
    networks:
      - infra_red
    depends_on:
      - db
      - ftp
    mem_limit: 512m
    cpus: 0.5

volumes:
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DIR_BASE/db
  web_content:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DIR_BASE/ftp

networks:
  infra_red:
    external: true
EOF

    echo "  - docker-compose.yml generado."
    echo "Iniciando construcción y despliegue de contenedores..."

    cd "$DIR_BASE" || exit

    docker compose up -d --build

    if [ $? -eq 0 ]; then
        echo "----------------------------------------"
        echo " DESPLIEGUE EXITOSO."
        echo " Servicios activos:"
        echo "   - Web:  http://$HOST_IP (Nginx + Alpine)"
        echo "   - BD:   base_datos_p10 (PostgreSQL 15)"
        echo "   - FTP:  servidor_ftp_p10 (puerto 21)"
        echo " Usa 'docker ps' para verificar el estado."
        echo "----------------------------------------"
    else
        echo "----------------------------------------"
        echo " ERROR al levantar los contenedores."
        echo " Revisa los mensajes anteriores."
        echo "----------------------------------------"
    fi

    cd - > /dev/null
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 5. RESPALDO DE BASE DE DATOS (manual + cron automático)
# ============================================================

# Script auxiliar que ejecuta el pg_dump (lo usa el cron)
SCRIPT_BACKUP="/usr/local/bin/backup_practica10.sh"

respaldar_base_datos() {
    while true; do
        clear
        echo "=========================================================="
        echo " Gestión de Respaldos — PostgreSQL"
        echo "=========================================================="
        echo " 1. Ejecutar respaldo AHORA (manual)"
        echo " 2. Instalar respaldo AUTOMÁTICO (cron diario 02:00 AM)"
        echo " 3. Ver respaldos existentes"
        echo " 4. Eliminar respaldos antiguos (más de 7 días)"
        echo " 5. Desinstalar cron de respaldo automático"
        echo ""
        echo " 0. Volver al menú principal"
        echo "=========================================================="
        read -p " Selecciona una opción: " op_backup

        case $op_backup in
            1)
                _ejecutar_backup_ahora
                ;;
            2)
                _instalar_cron_backup
                ;;
            3)
                echo "----------------------------------------"
                echo " Respaldos en $DIR_BASE/backups/:"
                echo "----------------------------------------"
                if [ -z "$(ls -A $DIR_BASE/backups/ 2>/dev/null)" ]; then
                    echo "  No hay respaldos todavía. Ejecuta la opción 1."
                else
                    ls -lh "$DIR_BASE/backups/"
                fi
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            4)
                echo "----------------------------------------"
                echo " Eliminando respaldos de más de 7 días..."
                find "$DIR_BASE/backups/" -name "backup_*.sql" -mtime +7 -delete
                echo "  - Limpieza completada."
                ls -lh "$DIR_BASE/backups/" 2>/dev/null || echo "  (Carpeta vacía)"
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            5)
                echo "----------------------------------------"
                echo " Desinstalando cron de respaldo automático..."
                crontab -l 2>/dev/null | grep -v "$SCRIPT_BACKUP" | crontab -
                rm -f "$SCRIPT_BACKUP"
                echo "  - Cron eliminado correctamente."
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            0)
                break
                ;;
            *)
                echo "Opción no válida."
                sleep 2
                ;;
        esac
    done
}

# Ejecuta un pg_dump inmediato
_ejecutar_backup_ahora() {
    echo "----------------------------------------"
    echo " Ejecutando Respaldo Manual"
    echo "----------------------------------------"

    if ! docker ps --format '{{.Names}}' | grep -q "base_datos_p10"; then
        echo "  ERROR: El contenedor 'base_datos_p10' no está corriendo."
        echo "  Ejecuta primero la opción 4 del menú principal."
        read -p "Presiona Enter para continuar..."
        return 1
    fi

    mkdir -p "$DIR_BASE/backups"
    FECHA=$(date +"%Y%m%d_%H%M%S")
    ARCHIVO="$DIR_BASE/backups/backup_$FECHA.sql"

    echo "Generando respaldo: $ARCHIVO"
    docker exec base_datos_p10 pg_dump -U admin base_practica > "$ARCHIVO"

    if [ $? -eq 0 ]; then
        TAMAÑO=$(du -sh "$ARCHIVO" | cut -f1)
        echo "  - Respaldo completado. Tamaño: $TAMAÑO"
        echo ""
        echo "  Respaldos disponibles:"
        ls -lh "$DIR_BASE/backups/"
    else
        echo "  - ERROR al generar el respaldo."
        rm -f "$ARCHIVO"
    fi
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# Instala el cron job para respaldo automático diario
_instalar_cron_backup() {
    echo "----------------------------------------"
    echo " Instalando Respaldo Automático (Cron)"
    echo "----------------------------------------"

    # Crear el script que ejecutará el cron
    cat << 'BACKUP_SCRIPT' > "$SCRIPT_BACKUP"
#!/bin/bash
# Script de respaldo automático - Práctica 10
DIR_BACKUPS="/opt/practica10/backups"
FECHA=$(date +"%Y%m%d_%H%M%S")
ARCHIVO="$DIR_BACKUPS/backup_$FECHA.sql"
LOG="$DIR_BACKUPS/backup.log"

mkdir -p "$DIR_BACKUPS"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando respaldo automático..." >> "$LOG"

# Verificar que el contenedor está corriendo
if ! docker ps --format '{{.Names}}' | grep -q "base_datos_p10"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: contenedor base_datos_p10 no está activo." >> "$LOG"
    exit 1
fi

# Ejecutar el respaldo
docker exec base_datos_p10 pg_dump -U admin base_practica > "$ARCHIVO"

if [ $? -eq 0 ]; then
    TAMAÑO=$(du -sh "$ARCHIVO" | cut -f1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Respaldo exitoso: $ARCHIVO ($TAMAÑO)" >> "$LOG"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR al generar respaldo." >> "$LOG"
    rm -f "$ARCHIVO"
    exit 1
fi

# Eliminar respaldos de más de 7 días automáticamente
find "$DIR_BACKUPS" -name "backup_*.sql" -mtime +7 -delete
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Limpieza de respaldos antiguos completada." >> "$LOG"
BACKUP_SCRIPT

    chmod +x "$SCRIPT_BACKUP"
    echo "  - Script de respaldo creado en: $SCRIPT_BACKUP"

    # Registrar en crontab (cada día a las 02:00 AM)
    # Primero verificamos si ya existe para no duplicarlo
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_BACKUP"; then
        echo "  - El cron ya estaba registrado. No se duplica."
    else
        (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPT_BACKUP >> /opt/practica10/backups/backup.log 2>&1") | crontab -
        echo "  - Cron registrado exitosamente."
    fi

    echo ""
    echo "  Programación activa:"
    crontab -l | grep "$SCRIPT_BACKUP"
    echo ""
    echo "  El sistema generará un respaldo AUTOMÁTICO cada día a las 02:00 AM."
    echo "  Los backups se guardan en: $DIR_BASE/backups/"
    echo "  El log de actividad está en: $DIR_BASE/backups/backup.log"
    echo "  Los respaldos de más de 7 días se eliminan solos."
    echo "----------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# ============================================================
# 6. MENÚ DE PRUEBAS
# ============================================================
menu_pruebas() {
    while true; do
        clear
        echo "=========================================================="
        echo " Protocolo de Pruebas (Validación Práctica 10)"
        echo "=========================================================="
        echo "1. Prueba 10.1 — Persistencia de BD"
        echo "2. Prueba 10.2 — Aislamiento y DNS en Red"
        echo "3. Prueba 10.3 — Compartición FTP → Web"
        echo "4. Prueba 10.4 — Límites de Recursos (RAM/CPU)"
        echo ""
        echo "0. Volver al menú principal"
        echo "=========================================================="
        read -p "Selecciona la prueba: " op_prueba

        case $op_prueba in
            1)
                echo "----------------------------------------"
                echo " Prueba 10.1: Persistencia de BD"
                echo "----------------------------------------"
                echo "[1/4] Creando tabla e insertando registro..."
                docker exec base_datos_p10 psql -U admin -d base_practica -c \
                  "CREATE TABLE IF NOT EXISTS test_tabla (id serial, mensaje varchar(100));
                   INSERT INTO test_tabla (mensaje) VALUES ('Persistencia exitosa - Practica 10');"

                echo "[2/4] Eliminando contenedor (simulando fallo)..."
                docker rm -f base_datos_p10

                echo "[3/4] Recreando contenedor desde Compose..."
                cd "$DIR_BASE" && docker compose up -d db
                echo "  - Esperando 6 segundos a que PostgreSQL inicie..."
                sleep 6

                echo "[4/4] Consultando datos (deben seguir ahí)..."
                docker exec base_datos_p10 psql -U admin -d base_practica -c \
                  "SELECT * FROM test_tabla;"
                echo ""
                echo " Si ves el registro arriba, la PERSISTENCIA funciona correctamente."
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                echo "----------------------------------------"
                echo " Prueba 10.2: Red y DNS interno"
                echo "----------------------------------------"
                echo "Ping desde servidor_web_p10 → base_datos_p10 (por nombre)..."
                echo ""
                docker exec servidor_web_p10 ping -c 4 base_datos_p10
                echo ""
                echo " Si ves respuesta de paquetes, la red 'infra_red' funciona."
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            3)
                echo "----------------------------------------"
                echo " Prueba 10.3: FTP → Nginx (volumen compartido)"
                echo "----------------------------------------"
                echo "[1/3] Creando archivo HTML de prueba..."
                echo "<h2>Archivo subido via FTP y servido por Nginx - Practica 10</h2>" > /tmp/prueba_ftp.html

                echo "[2/3] Subiendo archivo al servidor FTP..."
                curl -s --ftp-pasv -T /tmp/prueba_ftp.html \
                  "ftp://adminftp:passwordftp@localhost/" \
                  && echo "  - Subida exitosa." \
                  || echo "  - ERROR en la subida FTP. Verifica que el contenedor FTP esté corriendo."

                echo "[3/3] Consultando el archivo vía Nginx (puerto 80)..."
                sleep 1
                curl -s http://localhost/prueba_ftp.html
                echo ""
                echo "----------------------------------------"
                echo " Si ves el <h2> arriba, el volumen compartido funciona."
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            4)
                echo "----------------------------------------"
                echo " Prueba 10.4: Límites de RAM y CPU"
                echo "----------------------------------------"
                echo " Toma CAPTURA DE PANTALLA de la siguiente tabla para tu evidencia:"
                echo ""
                docker stats --no-stream
                echo ""
                echo " Límites configurados:"
                echo "   - servidor_web_p10:  512 MB RAM / 0.5 CPU"
                echo "   - base_datos_p10:    512 MB RAM / 0.5 CPU"
                echo "   - servidor_ftp_p10:  256 MB RAM / 0.2 CPU"
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            0)
                break
                ;;
            *)
                echo "Opción no válida."
                sleep 2
                ;;
        esac
    done
}

# ============================================================
# 7. LIMPIAR / APAGAR INFRAESTRUCTURA
# ============================================================
limpiar_infraestructura() {
    while true; do
        clear
        echo "=========================================================="
        echo " Gestión de Infraestructura"
        echo "=========================================================="
        echo " 1. Detener contenedores (los datos se conservan)"
        echo " 2. Reiniciar contenedores"
        echo " 3. Ver estado actual (docker ps + stats)"
        echo " 4. ELIMINAR TODO (contenedores + volúmenes + red)"
        echo ""
        echo " 0. Volver al menú principal"
        echo "=========================================================="
        read -p " Selecciona una opción: " op_clean

        case $op_clean in
            1)
                echo "----------------------------------------"
                echo " Deteniendo contenedores..."
                cd "$DIR_BASE" && docker compose stop
                echo "  - Contenedores detenidos. Los datos persisten."
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                echo "----------------------------------------"
                echo " Reiniciando contenedores..."
                cd "$DIR_BASE" && docker compose restart
                echo "  - Contenedores reiniciados."
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            3)
                echo "----------------------------------------"
                echo " Estado actual:"
                echo "----------------------------------------"
                docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
                echo ""
                echo " Uso de recursos:"
                docker stats --no-stream
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            4)
                echo "----------------------------------------"
                echo " ADVERTENCIA: Esta acción es irreversible."
                echo " Se eliminarán contenedores, volúmenes y red."
                echo "----------------------------------------"
                read -p " Escribe 'CONFIRMAR' para continuar: " confirmacion
                if [ "$confirmacion" == "CONFIRMAR" ]; then
                    echo "Eliminando infraestructura completa..."
                    cd "$DIR_BASE" && docker compose down -v
                    docker network rm infra_red 2>/dev/null && echo "  - Red 'infra_red' eliminada."
                    echo "  - Infraestructura eliminada. Archivos en $DIR_BASE conservados."
                else
                    echo "  - Operación cancelada."
                fi
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            0)
                break
                ;;
            *)
                echo "Opción no válida."
                sleep 2
                ;;
        esac
    done
}
