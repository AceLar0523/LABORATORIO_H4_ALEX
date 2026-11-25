# Guía de Despliegue de Inferencia en RunPod (GPU Cloud)

Esta guía detalla paso a paso cómo desplegar el servicio de inferencia (`inferencia/`) en **RunPod**, incluyendo los requisitos de hardware (GPU, VRAM, RAM, disco), el entorno PyTorch recomendado, la puesta en marcha con `start_runpod.sh` y la conexión con el backend Laravel.

---

## 1. Estado del Servicio de Inferencia

El directorio `inferencia/` está preparado para producción en GPU e integra:

- **M1 (Placas + OCR):** `yolo-v9-t-384-license-plates-end2end.onnx` + `cct_xs_v2_global.onnx` (ONNX Runtime).
- **M2 (Vehículos):** `pesos/m2_vehiculos.pt` (Ultralytics YOLO, ~20 MB).
- **M3 (Llantas / Ejes):** `pesos/m3_llantas.pt` (Ultralytics YOLO Keypoints, ~19 MB).
- **M4 (Pasajeros / Seguridad):** `pesos/m4_pasajeros_seg.pt` (Ultralytics YOLO Seg, ~20 MB).
- **Agente Conversacional (Ollama):** Servidor Ollama con `llama3.2:3b` (con proxy integrado en FastAPI en `/ollama/generate`).

---

## 2. Requisitos de Hardware y Entorno (RunPod)

### Consumo estimado de recursos
| Componente | VRAM aproximada | Notas |
| :--- | :--- | :--- |
| M1 (ONNX Placas + OCR) | ~0.3 – 0.5 GB | Ligero, puede correr en CPU o GPU |
| M2 + M3 + M4 (YOLO `.pt`) | ~1.5 – 2.5 GB | Carga simultánea en PyTorch/CUDA |
| Ollama (`llama3.2:3b`) | ~2.2 – 3.0 GB | Modelo cuantizado para el agente |
| Overhead CUDA / Buffers | ~0.5 – 1.0 GB | Frames HD y batching |
| **Total estimado** | **~4.5 – 7.0 GB** | **Mínimo 8 GB VRAM** |

### Especificaciones recomendadas en RunPod
- **GPU (Tarjeta gráfica):**
  - **Mínimo:** 8 GB VRAM (ej. `RTX 3070`, `RTX A2000`, `RTX 4060`).
  - **Recomendado (Mejor relación costo/rendimiento):** **12 GB – 16 GB VRAM** (ej. **`RTX 3060 12GB`**, **`RTX 4060 Ti 16GB`**, **`RTX A4000 16GB`** o **`RTX 3090 / L4`** si habrá alta concurrencia).
- **RAM del sistema:** Mínimo **16 GB RAM** (recomendado **24–32 GB RAM**).
- **Almacenamiento (Container Disk + Volume Disk):** Mínimo **20 GB** libres (para dependencias Python, OpenCV, pesos `.pt`/`.onnx` y descarga de `llama3.2:3b` ~2 GB).
- **Plantilla (Template) de RunPod:**
  - Seleccionar **`RunPod PyTorch 2.x`** (por ejemplo `RunPod PyTorch 2.2.0` o `2.4.0` con **CUDA 12.1+** y Python 3.10/3.11).
  - *Nota:* Esta plantilla ya incluye `torch` y `torchvision` compilados con CUDA, evitando descargas pesadas.

---

## 3. Paso a Paso: Desde Cero hasta Correr en RunPod

### Paso 1: Crear el Pod en RunPod
1. Ingresa a [RunPod Console](https://www.runpod.io/console/pods) y haz clic en **+ Deploy**.
2. Elige una GPU disponible (ej. **RTX 3060 12GB** o **RTX A4000 16GB**).
3. En **Select Template**, elige **RunPod PyTorch 2.x** (asegúrate de que tenga soporte CUDA 12.x).
4. Haz clic en **Edit Template** (o **Customize Deployment**) y configura:
   - **Expose HTTP Ports:** `8000, 11434`
     - `8000`: API FastAPI (Inferencia M1–M4 + Proxy Ollama).
     - `11434`: Puerto directo de Ollama (opcional si usas el proxy en el puerto `8000`).
   - **Container Disk:** `20 GB` (o superior).
   - **Volume Disk:** `20 GB` (opcional, útil si quieres conservar los pesos y el modelo de Ollama al reiniciar el Pod).
5. Haz clic en **Deploy On-Demand** (o Spot si es solo para pruebas).

---

### Paso 2: Conectarse al Pod y Subir el Código
1. Espera a que el estado del Pod pase a **Running**.
2. Haz clic en **Connect** → **Start Web Terminal** (o conéctate por **SSH** usando el comando que te da RunPod).
3. Dentro de la terminal del Pod, ubícate en `/workspace` (si usas Volume Disk) o `/root`:
   ```bash
   cd /workspace
   ```
4. Sube o clona tu proyecto de modo que quede la carpeta `inferencia/` con su subcarpeta `pesos/` completa:
   - **Opción A (Git):**
     ```bash
     git clone <URL_DE_TU_REPOSITORIO> peaje-inteligente
     cd peaje-inteligente/inferencia
     ```
   - **Opción B (SCP / `runpodctl` desde tu PC local):**
     Si los pesos no están en Git, súbelos usando `pesos.zip`:
     ```bash
     # En tu PC local:
     scp -P <PUERTO_SSH> inferencia/pesos.zip root@<IP_RUNPOD>:/workspace/peaje-inteligente/inferencia/
     # En el Pod:
     cd /workspace/peaje-inteligente/inferencia
     unzip -o pesos.zip
     ```

Verifica que los pesos estén en su sitio:
```bash
ls -lh pesos/ pesos/modelo/
```
Debes ver `m2_vehiculos.pt`, `m3_llantas.pt`, `m4_pasajeros_seg.pt` y dentro de `pesos/modelo/` los archivos `.onnx` y `.yaml`.

---

### Paso 3: Ejecutar el Servicio de Inferencia
El script `start_runpod.sh` automatiza todo: verifica la GPU (`nvidia-smi`), instala/inicia Ollama en segundo plano, descarga `llama3.2:3b`, instala las dependencias de `requirements.txt` y levanta FastAPI en el puerto `8000`.

1. Dale permisos de ejecución (por si se perdieron al copiar) y ejecútalo:
   ```bash
   chmod +x start_runpod.sh
   bash start_runpod.sh
   ```
   *(Recomendación: si quieres que siga corriendo aunque cierres la terminal web, ejecútalo dentro de `tmux`: `tmux new -s inferencia` y luego `bash start_runpod.sh`.)*

2. Al finalizar la carga verás en consola:
   ```text
   ✔ Endpoint de Inferencia listo en: http://0.0.0.0:8000
   ✔ Endpoint de Ollama listo en:     http://0.0.0.0:11434
   ✔ Proxy Ollama integrado en:       http://0.0.0.0:8000/ollama/generate
   ```

---

### Paso 4: Verificar que Todo Funciona
Desde otra terminal (o desde tu PC local usando la URL pública de RunPod):

1. Obtén tu `POD_ID` en la consola de RunPod (en **Connect → HTTP Service [Port 8000]**). La URL tendrá la forma:
   `https://<POD_ID>-8000.proxy.runpod.net`

2. Prueba el endpoint de salud (`/health`) y la documentación interactiva (`/docs`):
   ```bash
   curl https://<POD_ID>-8000.proxy.runpod.net/health
   ```
   Y abre en tu navegador:
   `https://<POD_ID>-8000.proxy.runpod.net/docs`

---

### Paso 5: Conectar con el Backend (Laravel)
En el archivo `backend/.env` de tu proyecto Laravel, actualiza las variables de entorno apuntando a tu Pod:

```env
INFERENCE_URL=https://<POD_ID>-8000.proxy.runpod.net
OLLAMA_URL=https://<POD_ID>-8000.proxy.runpod.net/ollama/generate
```
*(Si expusiste el puerto `11434` directamente, también puedes usar `https://<POD_ID>-11434.proxy.runpod.net` para Ollama).*

---

## 4. Solución de Problemas Frecuentes

- **`nvidia-smi` no aparece o `torch.cuda.is_available()` es `False`:**
  Asegúrate de haber elegido una plantilla **PyTorch + CUDA** en RunPod y no una imagen CPU-only.
- **Error de memoria VRAM (`CUDA out of memory`):**
  Verifica que no haya otro proceso usando la GPU y que la tarjeta tenga al menos **8 GB VRAM** (ideal **12 GB+**).
- **Ollama tarda en responder la primera vez:**
  La primera petición carga `llama3.2:3b` en VRAM (~2–5 segundos). Las siguientes respuestas son inmediatas.
- **El puerto `8000` da error 502 Bad Gateway en RunPod:**
  Espera unos segundos a que `uvicorn` termine de cargar los modelos `.pt` y `.onnx` en memoria, o revisa los logs en la terminal del Pod.

