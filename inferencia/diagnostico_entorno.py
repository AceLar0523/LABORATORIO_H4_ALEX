#!/usr/bin/env python3
"""
Script de diagnóstico de entorno en la nube (RunPod / Colab)
Genera evidencia de versiones de Python, PyTorch, CUDA, GPU, Ultralytics,
ONNX Runtime, OpenCV y fast-plate-ocr para el criterio de +5 puntos (Sección 10).
"""
import importlib.metadata
import platform
import shutil
import subprocess
import sys


def get_pkg_version(pkg: str) -> str:
    try:
        return importlib.metadata.version(pkg)
    except importlib.metadata.PackageNotFoundError:
        return "NO INSTALADO"


def main() -> None:
    print("============================================================")
    print(" DIAGNOSTICO DE ENTORNO - INFERENCIA PEAJE INTELIGENTE")
    print("============================================================")
    print(f"Sistema Operativo : {platform.platform()}")
    print(f"Python            : {sys.version.split()[0]}")

    try:
        import torch

        print(f"PyTorch           : {torch.__version__}")
        print(f"CUDA disponible   : {torch.cuda.is_available()}")
        print(f"CUDA version      : {torch.version.cuda}")
        if torch.cuda.is_available():
            print(f"GPU activa        : {torch.cuda.get_device_name(0)}")
    except Exception as exc:
        print(f"PyTorch error     : {exc}")

    for pkg in ["ultralytics", "onnxruntime", "onnxruntime-gpu", "fast-plate-ocr", "opencv-python", "fastapi", "uvicorn"]:
        print(f"{pkg:<18}: {get_pkg_version(pkg)}")

    if shutil.which("ollama"):
        out = subprocess.check_output(["ollama", "--version"], text=True).strip()
        print(f"Ollama CLI        : {out}")
    else:
        print("Ollama CLI        : NO INSTALADO")
    print("============================================================")


if __name__ == "__main__":
    main()

