# Carpeta FTP - Práctica 10

Esta carpeta es el volumen compartido entre el servidor FTP y el servidor Web (Nginx).

## ¿Cómo funciona?

- El servidor FTP (servidor_ftp_p10) guarda los archivos aquí.
- El servidor Web (servidor_web_p10) sirve estos archivos desde Nginx.
- Ambos comparten el volumen Docker llamado `web_content`.

## Credenciales FTP

- Usuario:     adminftp
- Contraseña:  passwordftp
- Puerto:      21
- Modo:        Pasivo (puertos 21000-21010)

## Ejemplo de uso

Conectar con FileZilla u otro cliente FTP:
  Host:     IP_DE_TU_SERVIDOR
  Usuario:  adminftp
  Clave:    passwordftp
  Puerto:   21

O desde línea de comandos:
  curl -T archivo.html ftp://adminftp:passwordftp@localhost/

Los archivos subidos estarán disponibles en:
  http://IP_DE_TU_SERVIDOR/nombre_del_archivo
