-- init.sql
-- Script de inicialización de la base de datos - Práctica 10
-- Se ejecuta automáticamente cuando el contenedor de PostgreSQL arranca por primera vez

-- Tabla de usuarios del sistema
CREATE TABLE IF NOT EXISTS usuarios (
    id        SERIAL PRIMARY KEY,
    nombre    VARCHAR(100) NOT NULL,
    email     VARCHAR(150) UNIQUE NOT NULL,
    rol       VARCHAR(50) DEFAULT 'usuario',
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de archivos subidos vía FTP
CREATE TABLE IF NOT EXISTS archivos (
    id           SERIAL PRIMARY KEY,
    nombre       VARCHAR(200) NOT NULL,
    ruta         VARCHAR(500),
    subido_por   VARCHAR(100),
    subido_en    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Datos de ejemplo
INSERT INTO usuarios (nombre, email, rol) VALUES
    ('Administrador', 'admin@practica10.local', 'admin'),
    ('Usuario Demo',  'demo@practica10.local',  'usuario');

INSERT INTO archivos (nombre, ruta, subido_por) VALUES
    ('instalador_ejemplo.sh', '/ftp/adminftp/instalador_ejemplo.sh', 'adminftp');
