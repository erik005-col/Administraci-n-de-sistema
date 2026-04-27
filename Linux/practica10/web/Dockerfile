FROM nginx:alpine

# Copiar configuración personalizada (server_tokens off)
COPY nginx.conf /etc/nginx/nginx.conf

# Copiar recursos estáticos de la página web
COPY index.html /usr/share/nginx/html/index.html
COPY style.css  /usr/share/nginx/html/style.css
COPY logo.svg   /usr/share/nginx/html/logo.svg

# Ajustar permisos para usuario no-root (nginx)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

# Ejecutar con usuario no administrativo
USER nginx
EXPOSE 8080
