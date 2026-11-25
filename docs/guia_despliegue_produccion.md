# Guía Completa de Despliegue a Producción en la Nube (\$0 con GitHub Student Pack)

Esta guía está pensada para llevarte **desde cero hasta tener todo el sistema funcionando en internet con HTTPS**, gastando **\$0** gracias a tu cuenta de **GitHub Student Developer Pack** y capas gratuitas confiables.

---

## 1. ¿Dónde alojar Backend, Frontend y Base de Datos sin gastar dinero?

### ¿Por qué GitHub Student Developer Pack te resuelve prácticamente todo?

Con tu cuenta de **GitHub Students** ([education.github.com/pack](https://education.github.com/pack)) tienes acceso gratuito a:

1. **Dominio gratis por 1 año (para cumplir el requisito del subdominio HTTPS):**
   - **Namecheap:** dominio `.me` gratis por 1 año (por ejemplo `peaje-tuusuario.me` → subdominio `https://peaje.tuusuario.me`).
   - **Name.com** o **.TECH:** dominios `.live`, `.studio`, `.software`, `.tech`, etc. gratis por 1 año.
   - *SSL HTTPS gratis:* Let's Encrypt (`certbot`) es 100% gratuito y se renueva automáticamente.
2. **Servidor VPS gratis con créditos:**
   - **Azure for Students:** **\$100 USD de crédito gratis por 1 año SIN pedir tarjeta de crédito**. Una VM Linux básica (`B1s` / `B1ms`) cuesta ~\$8–\$15/mes, alcanza de sobra para todo el semestre.
   - **DigitalOcean (vía GitHub Students):** **\$200 USD de crédito gratis por 1 año** (pide método de verificación/tarjeta solo para activar, un Droplet de 1–2 GB RAM cuesta \$6–\$12/mes).
3. **Base de Datos gratuita en la nube:**
   - **Supabase (Free Tier):** PostgreSQL gestionado gratis sin tarjeta (suficiente para este proyecto), **o bien** instalar PostgreSQL directamente dentro del mismo VPS (cero límites de conexiones y latencia mínima).

---

### ¿Conviene alojar Backend y Frontend juntos o separados?

**Recomendación #1: Alojar Frontend (`frontend/dist`) + Backend (`backend/`) JUNTOS en un mismo VPS bajo un único subdominio HTTPS (`https://peaje.tudominio.me`).**

| Aspecto | VPS Único con Nginx (Recomendado) | PaaS Gratuitos Separados (Vercel + Render Free) |
| :--- | :--- | :--- |
| **Costo con GitHub Students** | **\$0** (créditos Azure/DigitalOcean + dominio `.me` gratis) | \$0 |
| **Fotos de evidencia (`/storage/evidencias/`)** | **Persisten en disco** sin borrarse | Render Free borra el disco local en cada reinicio |
| **Tiempo real SSE (`/api/v1/stream/eventos`)** | **Conexión directa sin cortes** (`fastcgi_buffering off`) | Suele cortarse o dormir tras 15 min de inactividad |
| **Problemas de CORS / Cookies / Dominios** | **Cero problemas** (todo vive en el mismo origen HTTPS) | Requiere configurar CORS entre 2 dominios distintos |
| **Control y depuración** | Acceso SSH total a logs (`laravel.log`, Nginx) | Limitado |

*(Alternativa sin VPS si no puedes activar Azure/DigitalOcean: Frontend en Vercel/Netlify + Backend en Render/Railway + BD en Supabase, aunque tendrás que migrar el almacenamiento de evidencias a S3/Cloudinary para que no se borren).*

---

## 2. Arquitectura final en producción

```text
Internet (HTTPS puerto 443)
  │
  ▼  https://peaje.tudominio.me
┌───────────────────────────────────────────────────────────┐
│  VPS Ubuntu 24.04 (Azure Students / DigitalOcean)         │
│  ├─ Nginx (SSL Let's Encrypt gratis)                      │
│  │   ├─ /            -> frontend/dist (Vue 3 compilado)   │
│  │   ├─ /api/*       -> Laravel 12 (PHP-FPM)              │
│  │   └─ /storage/*   -> backend/storage/app/public        │
│  └─ Base de Datos: Supabase PostgreSQL o PostgreSQL local │
└───────────────┬───────────────────────────────────────────┘
                │ INFERENCE_URL / OLLAMA_URL (HTTPS)
                ▼
┌───────────────────────────────────────────────────────────┐
│  Inferencia IA en la Nube                                 │
│  ├─ Opción A (+5 pts): RunPod GPU Pod (puerto 8000)       │
│  └─ Opción B (\$0, 100 pts base): Google Colab + ngrok    │
└───────────────────────────────────────────────────────────┘
```

---

## 3. Paso a Paso: Despliegue desde Cero

### Paso 1: Conseguir tu dominio gratis y crear el subdominio

1. Entra a [education.github.com/pack](https://education.github.com/pack) y reclama tu dominio gratis en **Namecheap** (`.me`) o **Name.com**.
2. Una vez que tengas tu servidor VPS creado (Paso 2) y conozcas su **IP pública** (ej. `203.0.113.45`), ve al panel DNS de tu dominio (Namecheap → *Domain List → Manage → Advanced DNS*).
3. Agrega un registro tipo **A**:
   - **Type:** `A Record`
   - **Host:** `peaje` *(esto crea `peaje.tudominio.me`)*
   - **Value (IP):** `<IP_PUBLICA_DE_TU_VPS>`
   - **TTL:** `Automatic` o `1 min`
4. Espera 2–5 minutos y comprueba desde tu terminal local que ya apunta a tu VPS:
   ```bash
   ping -c 2 peaje.tudominio.me
   ```

---

### Paso 2: Crear el VPS gratis (Azure for Students o DigitalOcean)

#### Opción A — Azure for Students (no pide tarjeta)
1. Actívalo desde el enlace de **Microsoft Azure** en tu GitHub Student Pack usando tu correo universitario.
2. En el portal de Azure → **Virtual Machines → Create → Azure Virtual Machine**:
   - **Image:** `Ubuntu Server 24.04 LTS - x64 Gen2`
   - **Size:** `Standard_B1ms` (2 GB RAM, 1 vCPU) o `Standard_B2s` (si quieres ir sobrado).
   - **Authentication type:** `SSH public key` (descarga el `.pem`) o `Password`.
   - **Inbound port rules (MUY IMPORTANTE):** permite **HTTP (80)**, **HTTPS (443)** y **SSH (22)**.
3. Copia la **Public IP address** de la VM creada.

#### Opción B — DigitalOcean (\$200 crédito)
1. Reclama el cupón en tu GitHub Student Pack y crea tu cuenta en DigitalOcean.
2. **Create → Droplets**:
   - **OS:** Ubuntu `24.04 (LTS) x64`
   - **Plan:** Basic → Regular → **\$6/mo (1 GB RAM)** o **\$12/mo (2 GB RAM)** (recomendado 2 GB RAM para compilar `npm run build` sin problemas).
   - **Authentication:** SSH Key o Password.
3. Si activas firewall (`ufw`), abre puertos `22`, `80` y `443`.

---

### Paso 3: Conectarse al VPS e instalar el software base

Desde tu PC local, entra por SSH a tu servidor:
```bash
ssh root@<IP_PUBLICA_DE_TU_VPS>
# (En Azure suele ser: ssh -i tu-llave.pem azureuser@<IP_PUBLICA_DE_TU_VPS>)
```

Ejecuta estos comandos dentro del VPS para instalar **Nginx, PHP 8.3, Composer, Node.js 22, Git y Certbot**:

```bash
sudo apt update && sudo apt upgrade -y

# 1. Utilidades, Nginx, Git y Certbot (SSL)
sudo apt install -y nginx git unzip curl software-properties-common certbot python3-certbot-nginx

# 2. PHP 8.3 y extensiones requeridas por Laravel 12 + PostgreSQL/SQLite
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update
sudo apt install -y php8.3-fpm php8.3-cli php8.3-common php8.3-mbstring \
  php8.3-xml php8.3-curl php8.3-zip php8.3-bcmath php8.3-pgsql php8.3-sqlite3 php8.3-intl

# 3. Composer
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# 4. Node.js 22 LTS (para compilar Vue 3)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# Verificar versiones
php -v && composer -V && node -v && nginx -v
```

*(Opcional si elegiste usar 1 GB de RAM en DigitalOcean: crea 2 GB de swap para que `npm run build` nunca se quede sin memoria):*
```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

### Paso 4: Base de datos gratuita (elige una opción)

#### Opción 1: Supabase PostgreSQL (Nube gestionada gratuita)
1. Crea un proyecto gratis en [supabase.com](https://supabase.com).
2. Ve a **Project Settings → Database → Connection string → Transaction/Session pooler** (IPv4 compatible).
3. Anota `DB_HOST`, `DB_PORT` (`5432` o `6543`), `DB_DATABASE` (`postgres`), `DB_USERNAME` (`postgres.<project-ref>`) y `DB_PASSWORD`.

#### Opción 2: PostgreSQL instalado en tu mismo VPS (\$0, cero límites)
```bash
sudo apt install -y postgresql postgresql-contrib
sudo -u postgres psql -c "CREATE USER peaje_user WITH PASSWORD 'PON_UNA_CLAVE_SEGURA_AQUI';"
sudo -u postgres psql -c "CREATE DATABASE peaje_db OWNER peaje_user;"
```
Y en `backend/.env` usarás `DB_CONNECTION=pgsql`, `DB_HOST=127.0.0.1`, `DB_PORT=5432`, `DB_DATABASE=peaje_db`, `DB_USERNAME=peaje_user`, `DB_PASSWORD=...`.

---

### Paso 5: Subir el código y configurar el Backend Laravel

En el VPS, clona tu repositorio en `/var/www/peaje-inteligente`:
```bash
sudo mkdir -p /var/www
cd /var/www
sudo git clone https://github.com/AceLar0523/LABORATORIO_H4_ALEX.git peaje-inteligente
sudo chown -R $USER:$USER /var/www/peaje-inteligente
cd /var/www/peaje-inteligente/backend
```

1. **Instalar dependencias PHP de producción:**
   ```bash
   composer install --no-dev --optimize-autoloader
   ```

2. **Crear el archivo de entorno `backend/.env`:**
   ```bash
   cp .env.example .env
   nano .env
   ```
   Asegúrate de configurar estos valores (reemplazando con los tuyos):
   ```env
   APP_NAME="Peaje Inteligente"
   APP_ENV=production
   APP_KEY=
   APP_DEBUG=false
   APP_URL=https://peaje.tudominio.me

   LOG_CHANNEL=stack
   LOG_LEVEL=info

   # Base de datos (Supabase o PostgreSQL local)
   DB_CONNECTION=pgsql
   DB_HOST=<tu-host-postgres>
   DB_PORT=5432
   DB_DATABASE=<tu-db>
   DB_USERNAME=<tu-usuario>
   DB_PASSWORD=<tu-password>
   DB_SSLMODE=require   # usa "prefer" o quítalo si es PostgreSQL local en el VPS

   SESSION_DRIVER=database
   SESSION_LIFETIME=120

   # Google OAuth 2.0 (Web + Android)
   GOOGLE_CLIENT_ID=<TU_WEB_CLIENT_ID>.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=<TU_WEB_CLIENT_SECRET>
   GOOGLE_ANDROID_CLIENT_ID=<TU_ANDROID_CLIENT_ID>.apps.googleusercontent.com

   # Inferencia en la nube (RunPod o Colab)
   INFERENCE_URL=https://<POD_ID>-8000.proxy.runpod.net
   OLLAMA_URL=https://<POD_ID>-8000.proxy.runpod.net/ollama
   OLLAMA_MODEL=llama3.2:3b
   ```

3. **Inicializar clave, migraciones, datos iniciales, storage y caché:**
   ```bash
   php artisan key:generate
   php artisan migrate --force
   php artisan db:seed --force
   php artisan storage:link
   php artisan config:cache
   php artisan route:cache
   ```

4. **Permisos para que Nginx/PHP-FPM puedan escribir logs, caché y fotos de evidencia:**
   ```bash
   sudo chown -R www-data:www-data /var/www/peaje-inteligente/backend/storage /var/www/peaje-inteligente/backend/bootstrap/cache
   sudo chmod -R 775 /var/www/peaje-inteligente/backend/storage /var/www/peaje-inteligente/backend/bootstrap/cache
   ```

---

### Paso 6: Compilar el Frontend Vue 3 (`frontend/`)

```bash
cd /var/www/peaje-inteligente/frontend
cp .env.example .env
nano .env
```
Coloca exactamente tu subdominio HTTPS terminado en `/api/v1`:
```env
VITE_API_BASE_URL=https://peaje.tudominio.me/api/v1
```
Compila los archivos estáticos de producción:
```bash
npm ci
npm run build
```
Esto generará la carpeta `/var/www/peaje-inteligente/frontend/dist/`.

---

### Paso 7: Configurar Nginx y activar HTTPS gratis (Let's Encrypt)

1. Copia la plantilla incluida en el proyecto:
   ```bash
   sudo cp /var/www/peaje-inteligente/deploy/nginx-peaje.conf.example /etc/nginx/sites-available/peaje
   ```

2. Edita `/etc/nginx/sites-available/peaje`:
   - Cambia `peaje.tudominio.com` por tu dominio real (ej. `peaje.tudominio.me`).
   - Revisa qué socket de PHP-FPM tienes instalado (`ls /run/php/`) — si instalaste PHP 8.3, cambia `php8.2-fpm.sock` por `php8.3-fpm.sock`.
   - Temporalmente para el primer certificado SSL, primero puedes dejar un bloque HTTP (puerto 80) o ejecutar Certbot con `--nginx` para que él mismo genere las rutas `ssl_certificate`. Forma más sencilla para la primera vez:
     ```bash
     sudo ln -sf /etc/nginx/sites-available/peaje /etc/nginx/sites-enabled/peaje
     sudo rm -f /etc/nginx/sites-enabled/default
     ```
     Si aún no existen los archivos `/etc/letsencrypt/live/...`, crea primero un server block temporal solo en puerto `80` con `server_name peaje.tudominio.me;`, corre `sudo nginx -t && sudo systemctl reload nginx`, y luego ejecuta:
     ```bash
     sudo certbot --nginx -d peaje.tudominio.me
     ```
     Certbot emitirá el certificado HTTPS gratis. Después sustituye el archivo con la plantilla completa de `deploy/nginx-peaje.conf.example` (actualizando las 2 líneas de `ssl_certificate` con la ruta que creó Certbot y el `php8.3-fpm.sock`), valida y recarga:
     ```bash
     sudo nginx -t && sudo systemctl reload nginx
     ```

3. **Prueba rápida del servidor en la nube:**
   ```bash
   curl -s https://peaje.tudominio.me/api/v1/ping
   ```
   Debe devolver `"success": true`.

---

### Paso 8: Configurar Google Cloud Console (OAuth 2.0 Web y Android) y autorizar al Docente

1. Entra a [console.cloud.google.com](https://console.cloud.google.com) → **APIs & Services → Credentials**.
2. En tu **OAuth 2.0 Client ID (Web application)**:
   - En **Authorized JavaScript origins**, agrega:
     `https://peaje.tudominio.me`
   - Guarda los cambios (puede tardar 2–5 minutos en propagarse).
3. En **OAuth consent screen**:
   - Si tu app está en modo **Testing**, solo podrán entrar los correos listados en **Test users** (agrega el tuyo y el correo de Gmail del docente), **o** pulsa **Publish App** para que no requiera lista en Google Cloud (la lista blanca de la BD de Laravel seguirá bloqueando a cualquiera que no esté autorizado en tu tabla `users`).
4. **Autorizar al docente en el sistema:**
   - Entra a `https://peaje.tudominio.me`, inicia sesión con tu Google (`kevinalexis01mujica@gmail.com`).
   - Ve a **Usuarios & OAuth → Autorizar Cuenta** y agrega el correo Google del docente con rol **Administrador**.

---

### Paso 9: Conectar la Inferencia en la Nube (RunPod o Google Colab)

#### Opción A: RunPod GPU Pod (recomendado, otorga +5 puntos extras)
*Nota sobre costos:* RunPod no está incluido en GitHub Students, pero una GPU económica (ej. RTX 3060 / A4000) cuesta ~\$0.15–\$0.30 por hora. Puedes encender el Pod solo cuando grabes el video y durante la revisión del docente, y detenerlo/terminarlo después para gastar menos de \$1–\$2 en total.

1. Sigue la guía [docs/runpod_inferencia.md](file:///home/alele/Documentos/peaje-inteligente/docs/runpod_inferencia.md) para iniciar `bash start_runpod.sh` en el Pod con el puerto `8000` expuesto.
2. Toma la URL pública del Pod (ej. `https://abcd1234efgh56-8000.proxy.runpod.net`) y actualiza en el VPS `/var/www/peaje-inteligente/backend/.env`:
   ```env
   INFERENCE_URL=https://abcd1234efgh56-8000.proxy.runpod.net
   OLLAMA_URL=https://abcd1234efgh56-8000.proxy.runpod.net/ollama
   ```
3. **Siempre que cambies `backend/.env` en producción, ejecuta:**
   ```bash
   cd /var/www/peaje-inteligente/backend && php artisan config:cache
   ```

#### Opción B: Google Colab (\$0 total, cumple los 100 pts base sin la bonificación de +5 pts de RunPod)
Si no deseas gastar absolutamente nada en RunPod, puedes ejecutar el servidor FastAPI (`inferencia/main.py`) dentro de una sesión de Google Colab con GPU T4 gratuita expuesta con un servicio de túnel público desde la VM de Colab (no desde tu PC local) y colocar esa URL HTTPS en `INFERENCE_URL`.

---

### Paso 10: Compilar el APK Android para Producción (`movil/`)

En tu computadora local (con Flutter instalado):

1. Obtén el **SHA-1** del certificado con el que se firma tu APK (actualmente `build.gradle.kts` usa la llave `debug`):
   ```bash
   cd movil/android
   ./gradlew signingReport
   ```
   Copia el `SHA1` que aparece bajo `Variant: release` / `Config: debug` y verifica que coincida en Google Cloud Console dentro de tu cliente OAuth **Android** (`applicationId`: `com.peaje.ia.movil`).

2. Compila el APK apuntando **obligatoriamente** a tu subdominio HTTPS:
   ```bash
   cd ../
   flutter pub get
   flutter build apk --release --dart-define=API_BASE_URL=https://peaje.tudominio.me/api/v1
   ```
   El APK final quedará en `movil/build/app/outputs/flutter-apk/app-release.apk`. Instálalo en tu celular y prueba:
   - Inicio de sesión con Google (cuenta autorizada y rechazo de cuenta no autorizada).
   - Modo Caseta (cámara/foto/video) viendo en paralelo cómo aparece el paso y la alerta en `https://peaje.tudominio.me` sin recargar la página.
   - Modo Consulta (texto y foto).

---

## 4. ¿Cómo subir correcciones si algo falla después?

Cada vez que hagamos un arreglo en el código local y lo subas con `git push`:

```bash
ssh root@<IP_PUBLICA_DE_TU_VPS>
cd /var/www/peaje-inteligente
git pull

# Si cambió backend/:
cd backend
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache
php artisan route:cache

# Si cambió frontend/:
cd ../frontend
npm ci
npm run build
```

---

## 5. Solución rápida de errores comunes en producción

| Síntoma | Causa probable | Solución inmediata |
| :--- | :--- | :--- |
| **HTTP 500** al abrir `/api/...` | Permisos en `storage/` o caché de config desactualizada | `sudo chown -R www-data:www-data backend/storage backend/bootstrap/cache` y revisar `tail -n 50 backend/storage/logs/laravel.log` |
| **HTTP 502 Bad Gateway** en Nginx | Socket PHP-FPM con otra versión | Revisar `ls /run/php/` y actualizar `fastcgi_pass unix:/run/php/php8.3-fpm.sock;` en `/etc/nginx/sites-available/peaje` |
| **El login de Google en Web no aparece o da `origin_mismatch`** | Falta agregar el subdominio en Google Cloud Console | Agregar `https://peaje.tudominio.me` en *Authorized JavaScript origins* |
| **Login en Android falla con `ApiException: 10`** | SHA-1 del APK no coincide con Google Cloud Console | Obtener SHA-1 con `./gradlew signingReport` y registrarlo en el cliente OAuth Android (`com.peaje.ia.movil`) |
| **El panel no actualiza en vivo por SSE** | Buffering activo en Nginx | Verificar que el bloque `location = /api/v1/stream/eventos` tenga `fastcgi_buffering off;` y recargar Nginx |
| **Inferencia devuelve HTTP 503** | `INFERENCE_URL` vacío, Pod apagado o sin correr `config:cache` | Verificar `curl https://<POD_ID>-8000.proxy.runpod.net/` y correr `php artisan config:cache` |

