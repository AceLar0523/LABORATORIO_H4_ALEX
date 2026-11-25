#!/bin/bash
# ==============================================================================
# Script de Inicio Todo-en-Uno para RunPod (GPU Cloud)
# Inicia Ollama (LLM para Agente) + Motor Unificado FastAPI (M1 + M2 + M3 + M4)
# Basado en el pipeline validado en probar_pesos.py + pipeline.py
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================================="
echo " [1/5] Verificando GPU NVIDIA y Entorno PyTorch/CUDA"
echo "=========================================================="
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || nvidia-smi
else
    echo "[WARN] Sin GPU NVIDIA detectada, ejecutando en modo CPU."
fi

python3 - <<'PY' || true
try:
    import torch
    print(f"[INFO] PyTorch {torch.__version__} | CUDA disponible: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"[INFO] GPU activa: {torch.cuda.get_device_name(0)}")
except Exception as e:
    print(f"[WARN] PyTorch aún no verificado ({e}); se instalará vía pip.")
PY

echo "=========================================================="
echo " [2/5] Verificando Pesos de Modelos (M1, M2, M3 y M4)"
echo "=========================================================="
PESOS_DIR="${PESOS_DIR:-$SCRIPT_DIR/pesos}"
mkdir -p "$PESOS_DIR/modelo"

# Si falta m2_vehiculos.pt y existe pesos.zip, descomprimir automáticamente
if [ ! -f "$PESOS_DIR/m2_vehiculos.pt" ]; then
    if [ -f "$SCRIPT_DIR/pesos.zip" ]; then
        echo "[INFO] Extrayendo $SCRIPT_DIR/pesos.zip..."
        unzip -o "$SCRIPT_DIR/pesos.zip" -d "$SCRIPT_DIR"
    elif [ -f "/workspace/pesos.zip" ]; then
        echo "[INFO] Extrayendo /workspace/pesos.zip..."
        unzip -o "/workspace/pesos.zip" -d "$SCRIPT_DIR"
    fi
fi

# Descarga automática de M4 (YOLO11s-seg) si falta únicamente ese peso
if [ ! -f "$PESOS_DIR/m4_pasajeros_seg.pt" ]; then
    echo "[INFO] Descargando peso M4 (yolo11s-seg.pt -> m4_pasajeros_seg.pt)..."
    curl -fsSL -o "$PESOS_DIR/m4_pasajeros_seg.pt" \
        "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11s-seg.pt"
fi

REQUIRED_FILES=(
    "$PESOS_DIR/m2_vehiculos.pt"
    "$PESOS_DIR/m3_llantas.pt"
    "$PESOS_DIR/m4_pasajeros_seg.pt"
    "$PESOS_DIR/modelo/yolo-v9-t-384-license-plates-end2end.onnx"
    "$PESOS_DIR/modelo/cct_xs_v2_global.onnx"
    "$PESOS_DIR/modelo/cct_xs_v2_global_plate_config.yaml"
)

MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "[ERROR] Falta el archivo de modelo requerido: $f"
        MISSING=1
    else
        echo "  ✔ Encontrado: $f"
    fi
done

if [ "$MISSING" -eq 1 ]; then
    echo "[FATAL] Faltan pesos en $PESOS_DIR. Sube 'pesos.zip' o la carpeta 'pesos/' antes de iniciar."
    exit 1
fi

echo "=========================================================="
echo " [3/5] Verificando Dependencias del Sistema y Python"
echo "=========================================================="
if command -v apt-get &> /dev/null; then
    NEED_APT=0
    for pkg_cmd in curl unzip; do
        if ! command -v "$pkg_cmd" &> /dev/null; then
            NEED_APT=1
        fi
    done
    if [ "$NEED_APT" -eq 1 ] || ! ldconfig -p 2>/dev/null | grep -q libGL.so.1; then
        apt-get update && apt-get install -y --no-install-recommends \
            libgl1 libglib2.0-0 libsm6 libxext6 curl unzip zstd ca-certificates \
            && rm -rf /var/lib/apt/lists/*
    fi
fi

pip install --no-cache-dir -r requirements.txt

# Opcional: si el usuario solicita aceleración CUDA también para ONNX Runtime
if [ "${USE_ORT_GPU:-0}" = "1" ]; then
    echo "[INFO] Habilitando onnxruntime-gpu..."
    pip uninstall -y onnxruntime || true
    pip install --no-cache-dir onnxruntime-gpu
fi

echo "=========================================================="
echo " [4/5] Configurando e Iniciando Ollama LLM (Puerto 11434)"
echo "=========================================================="
if [ "${SKIP_OLLAMA:-0}" = "1" ]; then
    echo "[INFO] SKIP_OLLAMA=1 activo, omitiendo inicio de Ollama."
else
    if ! command -v ollama &> /dev/null; then
        echo "[INFO] Instalando Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi

    export OLLAMA_HOST="0.0.0.0:11434"
    export OLLAMA_ORIGINS="*"
    if [ -d "/workspace" ] && [ -w "/workspace" ]; then
        export OLLAMA_MODELS="${OLLAMA_MODELS:-/workspace/ollama_models}"
        mkdir -p "$OLLAMA_MODELS"
    fi

    ollama serve > /tmp/ollama.log 2>&1 &
    OLLAMA_PID=$!

    echo "Esperando que Ollama responda..."
    for i in $(seq 1 20); do
        if curl -s http://127.0.0.1:11434/api/tags > /dev/null; then
            echo "[OK] Ollama activo en http://0.0.0.0:11434 (PID $OLLAMA_PID)"
            break
        fi
        sleep 1
    done

    MODELO_LLM="${OLLAMA_MODEL:-llama3.2:3b}"
    echo "Verificando/descargando modelo LLM ($MODELO_LLM)..."
    ollama pull "$MODELO_LLM" || ollama pull tinyllama || echo "[WARN] No se pudo descargar LLM, el backend usará modo estructurado."
fi

echo "=========================================================="
echo " [5/5] Verificando Pipeline e Iniciando FastAPI Unificado"
echo "=========================================================="
python3 -c "import pipeline, main; print('[OK] Módulos pipeline y main importados correctamente.')"

PORT="${PORT:-8000}"
echo "✔ Motor FastAPI (M1 + M2 + M3 + M4) escuchando en: http://0.0.0.0:${PORT}"
echo "✔ Health Check:   GET  http://0.0.0.0:${PORT}/"
echo "✔ Inferencia:     POST http://0.0.0.0:${PORT}/predict"
echo "✔ Solo OCR M1:    POST http://0.0.0.0:${PORT}/predict/ocr"
echo "✔ Proxy Ollama:   POST http://0.0.0.0:${PORT}/ollama/generate"
echo "=========================================================="
echo "CONEXIÓN DESDE LARAVEL (backend/.env):"
echo "  INFERENCE_URL=https://<POD_ID>-${PORT}.proxy.runpod.net"
echo "  OLLAMA_URL=https://<POD_ID>-11434.proxy.runpod.net"
echo "  OLLAMA_MODEL=${OLLAMA_MODEL:-llama3.2:3b}"
echo "=========================================================="

exec uvicorn main:app --host 0.0.0.0 --port "$PORT" --workers 1
