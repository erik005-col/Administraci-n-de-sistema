-- ==============================================================
-- init.sql — Inicialización de la base de datos
-- Práctica 11 — Se ejecuta automáticamente al crear el contenedor
-- ==============================================================

-- Tabla de prueba para validar persistencia (Prueba 11.4)
CREATE TABLE IF NOT EXISTS registros_prueba (
    id        SERIAL PRIMARY KEY,
    mensaje   VARCHAR(200) NOT NULL,
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Registro inicial
INSERT INTO registros_prueba (mensaje)
VALUES ('Base de datos inicializada correctamente — Práctica 11');

-- Vista útil para verificar estado
CREATE VIEW estado_bd AS
SELECT
    current_database() AS base_de_datos,
    current_user       AS usuario,
    now()              AS fecha_consulta,
    COUNT(*)           AS total_registros
FROM registros_prueba;
