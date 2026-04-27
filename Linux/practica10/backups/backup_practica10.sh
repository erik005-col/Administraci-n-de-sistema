#!/bin/bash
# backup_practica10.sh
# Script de respaldo automático de PostgreSQL - Práctica 10
# Este archivo es instalado en /usr/local/bin/ por el menú opción 5

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

# Eliminar respaldos de más de 7 días
find "$DIR_BACKUPS" -name "backup_*.sql" -mtime +7 -delete
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Limpieza de respaldos antiguos completada." >> "$LOG"
