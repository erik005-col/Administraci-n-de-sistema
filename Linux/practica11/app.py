#!/usr/bin/env python3
"""
app.py — Servidor de aplicaciones interno
Práctica 11 — No expuesto directamente al exterior
Accedido únicamente a través del balanceador nginx
"""

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
        "practica": "P11 — Infraestructura como Código",
        "estado": "activo",
        "base_datos": DB_HOST,
        "nota": "Este servidor NO es accesible directamente desde internet. "
                "Pasa por el balanceador nginx."
    })


@app.route("/health")
def health():
    """Endpoint de salud para el healthcheck de Docker y nginx."""
    return jsonify({"status": "healthy"}), 200


@app.route("/db-status")
def db_status():
    """Verifica conexión a la base de datos."""
    try:
        import psycopg2
        conn = psycopg2.connect(
            host=DB_HOST,
            port=os.getenv("DB_PORT", 5432),
            dbname=DB_NAME,
            user=DB_USER,
            password=os.getenv("DB_PASSWORD", ""),
            connect_timeout=3
        )
        conn.close()
        return jsonify({"db": "conectada", "host": DB_HOST}), 200
    except Exception as e:
        return jsonify({"db": "error", "detalle": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
