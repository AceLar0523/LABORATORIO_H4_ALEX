# Sistema Inteligente de Control de Peaje (IAM-811)

Sistema integral de control y cobro automático de peajes basado en visión por computadora, inferencia en la nube, aplicación móvil en tiempo real, panel web administrativo con actualización instantánea, autenticación exclusiva con Google OAuth 2.0 y agente conversacional.

---

## Integrantes y Roles

| Integrante | Rol Principal | Responsabilidades |
| :--- | :--- | :--- |
| **Kevin Alexis Mujica Laime** | Arquitectura, IA & Despliegue Full-Stack | Gestión de datasets (Roboflow), entrenamiento M2/M3 (Colab), servicio de inferencia unificado M1+M2+M3+M4 (RunPod/Colab), backend Laravel + tiempo real + agente conversacional, frontend Vue, app móvil Flutter y despliegue en VPS. |

---

## Enlaces de Producción y Recursos

* **Aplicación Web (Subdominio HTTPS):** `https://peaje.tudominio.com` *(actualizar con tu subdominio final)*
* **Endpoint de Inferencia (RunPod / Colab):** `https://<POD_ID>-8000.proxy.runpod.net` *(actualizar al levantar el Pod)*
* **Datasets en Roboflow:**
  * **M2 (Segmentación de vehículos):** `https://universe.roboflow.com/<workspace>/peaje-vehiculos-seg`
  * **M3 (Keypoints de ruedas/ejes):** `https://universe.roboflow.com/<workspace>/peaje-llantas-pose`
* **Carpeta de Evidencias y Documentación (Drive):** `https://drive.google.com/...` *(actualizar con enlace compartido al docente)*

---

## Arquitectura del Sistema

```text
                      Google OAuth 2.0 (inicio de sesión)
                         │                      │
App móvil ──video/frames──► Aplicación web (subdominio HTTPS)
  (Flutter)                   ├─ Frontend SPA (Vue 3 + Tailwind CSS)
                              ├─ API REST + Tiempo Real SSE (Laravel 12)
                              ├─ Base de Datos (PostgreSQL / Supabase)
                              └─ Agente Conversacional (Grounding BD + Ollama LLM)
                                     │
                                     ▼  INFERENCE_URL
                     RunPod GPU Cloud (endpoint FastAPI único)
                     ├─ M1: Detección de placas (YOLOv9-t ONNX) + OCR (fast-plate-ocr)
                     ├─ M2: Segmentación de instancias (YOLO11s-seg → categoría)
                     ├─ M3: Keypoints de ruedas (YOLO11s-pose → número de ejes)
                     └─ M4: Segmentación de pasajeros (YOLO11s-seg → conteo de ocupantes)
```

---

## Tecnologías Utilizadas

* **Visión Artificial & LLM (`inferencia/`):** Python 3.11, FastAPI, Ultralytics YOLO11-seg / YOLO11-pose, YOLOv9-t ONNX, `fast-plate-ocr` (CCT-XS), OpenCV Headless, ONNX Runtime, Ollama (`llama3.2:3b`).
* **Backend API & Tiempo Real (`backend/`):** PHP 8.2+, Laravel 12, Laravel Sanctum, Google OAuth 2.0 (`tokeninfo`), Server-Sent Events (SSE), PostgreSQL (Supabase) / SQLite.
* **Panel Web (`frontend/`):** Vue 3, Vite, Tailwind CSS v4, Vue Router, Axios, `vue-sonner`.
* **Aplicación Móvil (`movil/`):** Flutter (Material 3), `google_sign_in`, `camera`, `image_picker`, `video_player`, `shared_preferences`.

---

## Estructura del Repositorio

```text
/entrenamiento     Notebooks de Google Colab y métricas de entrenamiento (M2, M3, M4)
/inferencia        Servicio FastAPI unificado (M1+M2+M3+M4), proxy Ollama, Dockerfile, environment.yml y requirements.txt
/backend           API REST Laravel 12, migraciones, seeders, SSE en tiempo real y Agente IA
/frontend          Panel web Vue 3 + Tailwind CSS (tiempo real, CRUDs con roles, chat y diagnóstico)
/movil             Aplicación móvil Flutter (Google Sign-In, Modo Caseta y Modo Consulta)
/deploy            Plantilla Nginx HTTPS para subdominio en producción
/docs              Documentación API (OpenAPI, Postman, Markdown) e Informe Técnico
.env.example       Plantilla consolidada de variables de entorno
```

---

## Instrucciones de Despliegue y Recreación de Entornos

> **Guía paso a paso para principiantes (\$0 con GitHub Student Pack):** consulta [docs/guia_despliegue_produccion.md](file:///home/alele/Documentos/peaje-inteligente/docs/guia_despliegue_produccion.md) para ver cómo obtener dominio gratis, VPS gratis (Azure/DigitalOcean), BD gratis, certificado SSL, OAuth y compilación del APK.

### 1. Inferencia en RunPod GPU Cloud (`inferencia/`)

Los archivos `inferencia/requirements.txt` y `inferencia/environment.yml` fijan versiones exactas para garantizar reproducibilidad (`+5 pts`).

**Opción A — Conda / Mamba:**
```bash
cd inferencia
conda env create -f environment.yml
conda activate peaje-inferencia
python diagnostico_entorno.py
```

**Opción B — Python `venv` o RunPod PyTorch Pod:**
```bash
cd inferencia
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python3 diagnostico_entorno.py
```

**Inicio todo-en-uno en RunPod (FastAPI + Ollama en puerto 8000):**
```bash
cd /workspace/peaje-inteligente/inferencia
chmod +x start_runpod.sh
bash start_runpod.sh
```
Verifica en vivo: `curl -s https://<POD_ID>-8000.proxy.runpod.net/`

---

### 2. Backend Laravel en VPS / Nube (`backend/`)

```bash
cd backend
cp .env.example .env
# Configurar DB_CONNECTION=pgsql (Supabase), APP_URL=https://peaje.tudominio.com,
# INFERENCE_URL, OLLAMA_URL, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET y GOOGLE_ANDROID_CLIENT_ID

composer install --no-dev --optimize-autoloader
php artisan key:generate
php artisan migrate --force
php artisan db:seed --force
php artisan storage:link
php artisan config:cache
php artisan route:cache
```

> **Importante:** Recuerda autorizar el correo Google real del docente con rol `administrador` en la tabla `users` (desde `/usuarios` en el panel web o mediante Tinker/SQL).

---

### 3. Frontend Vue 3 y Subdominio HTTPS (`frontend/` + `deploy/`)

```bash
cd frontend
cp .env.example .env
# Editar VITE_API_BASE_URL=https://peaje.tudominio.com/api/v1

npm ci
npm run build
```

Usa [deploy/nginx-peaje.conf.example](file:///home/alele/Documentos/peaje-inteligente/deploy/nginx-peaje.conf.example) para servir `frontend/dist` y `backend/public` bajo el mismo subdominio HTTPS (con `proxy_buffering off` para `/api/v1/stream/eventos` y alias para `/storage`).

---

### 4. Aplicación Móvil Flutter (`movil/`)

Compila el APK de producción apuntando al subdominio HTTPS (nunca `localhost` ni IP privada):

```bash
cd movil
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://peaje.tudominio.com/api/v1
```

El APK generado quedará en `movil/build/app/outputs/flutter-apk/app-release.apk`. Asegúrate de registrar en Google Cloud Console el `GOOGLE_CLIENT_ID` (Web, usado como `serverClientId`) y el `GOOGLE_ANDROID_CLIENT_ID` con el SHA-1 del certificado con el que firmes el APK.
