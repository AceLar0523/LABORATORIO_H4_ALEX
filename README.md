# Sistema Inteligente de Control de Peaje (IAM-811)

Sistema integral de control y cobro automático de peajes basado en visión por computadora, inferencia en la nube, aplicación móvil en tiempo real, panel web administrativo con actualización instantánea, autenticación exclusiva con Google OAuth 2.0 y agente conversacional.

---

## Integrantes y Roles

| Integrante | Rol Principal | Responsabilidades |
| :--- | :--- | :--- |
| **Kevin Alexis Mujica Laime** | Arquitectura, IA & Despliegue Full-Stack | Gestión de datasets (Roboflow), entrenamiento M2/M3 (Colab), servicio de inferencia unificado M1+M2+M3 (RunPod/Colab), backend Laravel + tiempo real + agente conversacional, frontend Vue, app móvil Flutter y despliegue en VPS. |

*(Agregar aquí si hay más integrantes del equipo).*

---

## Enlaces de Producción y Recursos

* **Aplicación Web (Subdominio HTTPS):** `https://peaje.tudominio.me` *(actualizar con tu subdominio final)*
* **Endpoint de Inferencia (RunPod / Colab):** `https://<POD_ID>-8000.proxy.runpod.net` *(actualizar al levantar el servidor)*
* **Datasets en Roboflow:**
  * **M2 (Segmentación de vehículos):** `https://universe.roboflow.com/<workspace>/peaje-vehiculos-seg`
  * **M3 (Keypoints de ruedas/ejes):** `https://universe.roboflow.com/<workspace>/peaje-llantas-pose`
* **Carpeta de Evidencias y Documentación (Drive):** `https://drive.google.com/...`

---

## Arquitectura del Sistema

```text
                      Google OAuth 2.0 (inicio de sesión)
                         │                      │
App móvil ──video/frames──► Aplicación web (subdominio HTTPS)
  (Flutter)                   ├─ Frontend SPA (Vue 3 + Tailwind)
                              ├─ API REST + Tiempo Real (Laravel 12)
                              ├─ Base de Datos (PostgreSQL / MySQL)
                              └─ Agente Conversacional (LLM + Tools)
                                     │
                                     ▼  INFERENCE_URL
                     RunPod o Google Colab (endpoint FastAPI)
                     ├─ M1: Detección de placas (YOLOv9-t ONNX) + OCR (fast-plate-ocr)
                     ├─ M2: Segmentación de instancias (YOLO11s-seg → categoría)
                     └─ M3: Keypoints de ruedas (YOLO11s-pose → número de ejes)