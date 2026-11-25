"""
Servicio FastAPI Unificado para RunPod y Desarrollo Local
Sistema Inteligente de Control de Peaje

Expone el motor unificado `PeajePipeline` (`pipeline.py`) con la lógica validada
en `probar_pesos.py`:
- M1: Placas (YOLOv9-t ONNX letterbox 384) + OCR (CCT-XS / fast-plate-ocr) + formato BO/Mercosur/Global
- M2: Segmentación vehicular (YOLO11s-seg) con filtro de ruido y NMS IoU/contención
- M3: Keypoints de ruedas (YOLO11s-pose) + conteo de ejes y filtro de repuesto
- M4: Segmentación de pasajeros en cabina (YOLO11s-seg, +5 pts extras)
- Proxy Ollama integrado en `/ollama/generate` y `/ollama/tags` para RunPod
"""
import os
import urllib.request
from typing import Any, Dict

import cv2
import httpx
import numpy as np
import uvicorn
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from pipeline import PeajePipeline

app = FastAPI(
    title="Motor de Inferencia de Peaje Inteligente",
    description=(
        "Endpoint único de inferencia M1 (Placas/OCR), M2 (Vehículos), "
        "M3 (Keypoints/Ejes), M4 (Pasajeros) y Proxy Ollama para RunPod."
    ),
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

OLLAMA_LOCAL_URL = os.getenv("OLLAMA_LOCAL_URL", "http://127.0.0.1:11434").rstrip("/")
WARMUP_ON_INIT = os.getenv("RUNPOD_WARMUP", "1") == "1"

# Instanciar motor unificado (carga automática en CUDA GPU si está disponible en RunPod)
engine = PeajePipeline(warmup_on_init=WARMUP_ON_INIT)


def _check_ollama_online() -> bool:
    try:
        with urllib.request.urlopen(f"{OLLAMA_LOCAL_URL}/api/tags", timeout=1) as resp:
            return resp.status == 200
    except Exception:
        return False


@app.get("/")
@app.get("/health")
def health_check() -> Dict[str, Any]:
    info = engine.health_info()
    return {
        "status": "online",
        "service": "Sistema de Control de Peaje - Motor de Inferencia",
        "pipeline_version": "2.0-unified",
        "cuda_available": info["cuda_available"],
        "device": info["device"],
        "onnx_providers": info["onnx_providers"],
        "ocr_backend": info["ocr_backend"],
        "ollama_online": _check_ollama_online(),
        "models": info["models"],
    }


@app.get("/ollama/tags")
@app.get("/ollama/api/tags")
async def proxy_ollama_tags() -> Any:
    """Proxy para verificar modelos instalados en Ollama a través del puerto 8000 en RunPod."""
    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            resp = await client.get(f"{OLLAMA_LOCAL_URL}/api/tags")
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Error consultando Ollama tags en RunPod: {e}")


@app.post("/ollama/generate")
@app.post("/ollama/api/generate")
async def proxy_ollama_generate(payload: Dict[str, Any]) -> Any:
    """
    Proxy conveniente para consultar Ollama a través del puerto 8000 en RunPod,
    evitando tener que mapear el puerto 11434 externamente.
    """
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            resp = await client.post(f"{OLLAMA_LOCAL_URL}/api/generate", json=payload)
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Error comunicando con Ollama en RunPod: {e}")


@app.post("/predict")
async def predict_single_endpoint(
    file: UploadFile = File(...),
    annotated: bool = Query(False, description="Si es true, incluye imagen anotada en base64"),
) -> Dict[str, Any]:
    """
    Endpoint único de inferencia M1 + M2 + M3 + M4.
    Devuelve JSON con: placa, confianza, formato_placa, categoria, ejes, pasajeros, latencia_ms y detalles.
    """
    contents = await file.read()
    nparr = np.frombuffer(contents, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if image is None:
        raise HTTPException(status_code=400, detail="Formato de imagen inválido")

    return engine.predict_frame(image, incluir_anotada=annotated)


@app.post("/predict/ocr")
async def predict_ocr_only(file: UploadFile = File(...)) -> Dict[str, Any]:
    """Endpoint auxiliar para M1 + OCR exclusivo (consultas de imagen del agente y placas)."""
    contents = await file.read()
    nparr = np.frombuffer(contents, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if image is None:
        raise HTTPException(status_code=400, detail="Formato de imagen inválido")

    return engine.predict_ocr(image)


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("main:app", host=host, port=port, reload=False)
