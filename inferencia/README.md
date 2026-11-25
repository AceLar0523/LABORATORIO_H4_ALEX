# Módulo de Inferencia & LLM en GPU Cloud (RunPod)

Este módulo aloja el motor unificado de visión por computadora (**M1, M2, M3 y M4**) basado exactamente en el pipeline validado en `probar_pesos.py`, junto con el servicio **Ollama LLM** para el Agente Conversacional.

---

## 📦 Estructura del Módulo

- `pipeline.py`: Núcleo unificado compartido por FastAPI (`main.py`) y el evaluador (`probar_pesos.py`).
  - **M1**: YOLOv9-t ONNX (preprocesamiento letterbox 384×384) + OCR CCT-XS (`fast-plate-ocr`) con clasificación multiformato (`BO-OK`, `INT-MERCOSUR`, `INT-GLOBAL`).
  - **M2**: YOLO11s-seg con filtro de micro-ruido de fondo (`<2%`) y supresión NMS por IoU y contención.
  - **M3**: YOLO11s-pose (keypoints de ruedas), filtro de llanta de repuesto y conteo de ejes.
  - **M4**: YOLO11s-seg (segmentación de pasajeros en cabina con `conf=0.25`, sin reconocimiento facial, +5 pts extras).
  - Priorización automática del vehículo principal en caseta (placa legible + primer plano).
- `main.py`: Servidor FastAPI listo para GPU CUDA / CPU con endpoints `/`, `/predict`, `/predict/ocr`, `/ollama/generate` y `/ollama/tags`.
- `probar_pesos.py`: Herramienta CLI y visual (Zenity/Tkinter) usando el mismo `pipeline.py`.
- `start_runpod.sh`: Script todo-en-uno para RunPod (verifica GPU, descomprime `pesos.zip`, instala dependencias, inicia Ollama y levanta FastAPI).
- `Dockerfile` y `requirements.txt`: Listos para GPU CUDA y `fast-plate-ocr`.
- `pesos/` (o `pesos.zip`):
  - `m2_vehiculos.pt`
  - `m3_llantas.pt`
  - `m4_pasajeros_seg.pt`
  - `modelo/yolo-v9-t-384-license-plates-end2end.onnx`
  - `modelo/cct_xs_v2_global.onnx`
  - `modelo/cct_xs_v2_global_plate_config.yaml`

---

## 🚀 Despliegue en RunPod (Paso a Paso)

### Paso 1: Crear el Pod en RunPod
1. Ve a [RunPod.io](https://runpod.io) → **Deploy Pod**.
2. Selecciona una GPU económica (ej. `RTX 3070`, `RTX 3090`, `RTX 4090` o `A4000`).
3. Elige la plantilla **RunPod PyTorch 2.4+ / 2.5+** (CUDA 12.x).
4. En **Expose HTTP Ports**, escribe: `8000, 11434`.

### Paso 2: Subir el código y `pesos.zip` al Pod
En la terminal del Pod (`/workspace`):
```bash
cd /workspace
git clone <TU_REPOSITORIO_GIT> peaje-inteligente
cd peaje-inteligente/inferencia
```
*(Si los `.pt` / `.onnx` no están en el repositorio Git, sube `inferencia/pesos.zip` a `/workspace/peaje-inteligente/inferencia/pesos.zip`; el script `start_runpod.sh` lo descomprimirá automáticamente).*

### Paso 3: Iniciar todo con 1 comando
```bash
chmod +x start_runpod.sh
./start_runpod.sh
```

Variables opcionales antes de ejecutar `./start_runpod.sh`:
- `PORT=8000` (puerto HTTP de FastAPI, por defecto `8000`)
- `OLLAMA_MODEL=llama3.2:3b` (modelo LLM a descargar)
- `USE_ORT_GPU=1` (si quieres usar `onnxruntime-gpu` además de PyTorch CUDA)
- `SKIP_OLLAMA=1` (si quieres levantar solo visión sin Ollama)

---

## 🔗 Conectar RunPod con Laravel (`backend/.env`)

En RunPod, copia el **POD_ID** de tu instancia e ingrésalo en `backend/.env`:
```env
INFERENCE_URL=https://<POD_ID>-8000.proxy.runpod.net
OLLAMA_URL=https://<POD_ID>-11434.proxy.runpod.net
OLLAMA_MODEL=llama3.2:3b
```
*(Si solo expones el puerto `8000` en RunPod, Laravel usará automáticamente el proxy `/ollama/generate` incluido en `main.py`).*

---

## 🧪 Probar el Endpoint de RunPod con `curl`

```bash
# 1. Salud del servicio, GPU activa y los 5 modelos cargados
curl -s https://<POD_ID>-8000.proxy.runpod.net/ | python3 -m json.tool

# 2. Inferencia completa M1 + M2 + M3 + M4
curl -s -F "file=@tu_auto.jpg" https://<POD_ID>-8000.proxy.runpod.net/predict | python3 -m json.tool

# 3. Solo lectura de placa (M1 + OCR)
curl -s -F "file=@tu_auto.jpg" https://<POD_ID>-8000.proxy.runpod.net/predict/ocr | python3 -m json.tool
```
