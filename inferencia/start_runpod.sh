#!/bin/bash
# ==============================================================================
# Script de Inicio Todo-en-Uno para RunPod (GPU Cloud)
# Inicia Ollama (LLM para Agente) + Servicio FastAPI (M1 + M2 + M3)
# ==============================================================================

set -e

echo "=== [1/4] Verificando GPU y Entorno CUDA ==="
nvidia-smi || echo "Advertencia: Sin GPU NVIDIA detectada, ejecutando en modo CPU."

echo "=== [2/4] Iniciando Ollama en Background (Puerto 11434) ==="
if ! command -v ollama &> /dev/null; then
    echo "Instalando Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Iniciar servidor Ollama
ollama serve &
OLLAMA_PID=$!
sleep 5

echo "Descargando modelo ligero para el Agente Conversacional (llama3.2:3b)..."
ollama pull llama3.2:3b || ollama pull tinyllama

echo "=== [3/4] Instalando dependencias de Inferencia ==="
cd /workspace/inferencia || cd /app/inferencia || cd "$(dirname "$0")"
pip install --no-cache-dir -r requirements.txt

echo "=== [4/4] Levantando Motor FastAPI (M1, M2, M3) en Puerto 8000 ==="
echo "Endpoint listo en: http://0.0.0.0:8000"
echo "Ollama listo en:   http://0.0.0.0:11434"

uvicorn main:app --host 0.0.0.0 --port 8000

