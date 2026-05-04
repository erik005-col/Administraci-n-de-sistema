FROM python:3.11-alpine

WORKDIR /app

# Instalar dependencias mínimas
RUN pip install flask psycopg2-binary --no-cache-dir

# Copiar la aplicación
COPY app.py .

# Usuario no-root
RUN adduser -D appuser
USER appuser

EXPOSE 8080
CMD ["python", "app.py"]
