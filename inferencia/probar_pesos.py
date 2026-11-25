#!/usr/bin/env python3
"""
==============================================================================
Pipeline Unificado de Evaluación de Inferencia (M1, M2, M3 y M4)
Sistema Inteligente de Control de Peaje
==============================================================================
Utiliza el motor unificado `pipeline.py` (compartido con RunPod FastAPI `main.py`):
- M1: YOLOv9-t ONNX + CCT-XS OCR (`fast-plate-ocr`)
- M2: YOLO11s-seg (Segmentación y Categoría Vehicular)
- M3: YOLO11s-pose (Keypoints de Ruedas, Filtro de Repuestos y Conteo de Ejes)
- M4: YOLO11s-seg (Segmentación y Conteo de Pasajeros - Bonificación +5 Pts)

Modos de uso:
- Sin argumentos: abre el explorador visual de archivos (Zenity / Tkinter).
- Con rutas o `--image`: evalúa las imágenes/carpetas y guarda `prueba_peaje_X/`.
- Con `--json`: imprime JSON limpio a stdout (modo backend fallback).
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

# AUTO-DELEGACIÓN TRANSPARENTE AL ENTORNO VIRTUAL
# Si el intérprete actual no tiene ultralytics o fast_plate_ocr, re-ejecutar con el .venv
try:
    import ultralytics  # noqa: F401
    import fast_plate_ocr  # noqa: F401
    import onnxruntime  # noqa: F401
except ImportError:
    posibles_venvs = [
        Path(__file__).resolve().parent / ".venv" / "bin" / "python",
        Path(__file__).resolve().parent.parent / ".venv" / "bin" / "python",
        Path("/home/alele/Documentos/PROYECTO_IA_H4/AI_services/.venv/bin/python"),
    ]
    for venv_py in posibles_venvs:
        if venv_py.exists():
            os.execv(str(venv_py), [str(venv_py)] + sys.argv)

import cv2
import numpy as np

# Importar motor unificado compartido con RunPod
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pipeline import (
    BASE_DIR,
    EXTS_VALIDAS,
    M1_CFG_PATH,
    M1_DET_PATH,
    M1_OCR_PATH,
    M2_PATH,
    M3_PATH,
    M4_PATH,
    PeajePipeline,
    dibujar_anotaciones,
)

# Colores para salida en terminal
GREEN = "\033[92m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
RED = "\033[91m"
BOLD = "\033[1m"
RESET = "\033[0m"


def crear_carpeta_prueba(base_dir: Path) -> Path:
    """Crea una carpeta secuencial prueba_peaje_X para guardar los resultados."""
    max_idx = 0
    for item in base_dir.iterdir():
        if item.is_dir():
            m = re.fullmatch(r"prueba_peaje_(\d+)", item.name)
            if m:
                max_idx = max(max_idx, int(m.group(1)))
    nueva = base_dir / f"prueba_peaje_{max_idx + 1}"
    nueva.mkdir(parents=True, exist_ok=False)
    return nueva


def crear_imagen_ejemplo(ruta_destino: Path) -> str:
    """Genera una imagen sintética representativa si el usuario no tiene una foto a mano."""
    img = np.ones((640, 640, 3), dtype=np.uint8) * 235
    cv2.rectangle(img, (0, 480), (640, 640), (70, 70, 75), -1)
    cv2.rectangle(img, (110, 260), (530, 490), (180, 70, 50), -1)
    cv2.rectangle(img, (170, 170), (470, 260), (130, 160, 200), -1)

    cv2.circle(img, (250, 205), 22, (210, 170, 150), -1)
    cv2.rectangle(img, (230, 227), (270, 260), (45, 45, 45), -1)
    cv2.circle(img, (390, 205), 22, (210, 170, 150), -1)
    cv2.rectangle(img, (370, 227), (410, 260), (45, 45, 45), -1)

    cv2.circle(img, (180, 490), 48, (25, 25, 25), -1)
    cv2.circle(img, (180, 490), 22, (130, 130, 130), -1)
    cv2.circle(img, (460, 490), 48, (25, 25, 25), -1)
    cv2.circle(img, (460, 490), 22, (130, 130, 130), -1)

    cv2.rectangle(img, (260, 400), (380, 450), (255, 255, 255), -1)
    cv2.rectangle(img, (260, 400), (380, 450), (10, 10, 10), 2)
    cv2.putText(img, "4021XYZ", (270, 435), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (0, 0, 0), 2)

    cv2.imwrite(str(ruta_destino), img)
    return str(ruta_destino)


def seleccionar_imagenes_interactivo():
    """Abre el explorador de archivos visual para escoger una o varias fotos."""
    print(f"\n{BOLD}{YELLOW}[INFO] Abriendo explorador de archivos para escoger foto(s)...{RESET}")

    try:
        import subprocess

        cmd = [
            "zenity",
            "--file-selection",
            "--multiple",
            "--separator=|",
            "--title=Selecciona imágenes de vehículos para el Pipeline (M1+M2+M3+M4)",
            "--file-filter=Imágenes (*.jpg, *.png, *.jpeg)|*.jpg *.jpeg *.png *.webp *.bmp *.JPG *.PNG",
            "--file-filter=Todos los archivos|*",
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
        if res.returncode == 0 and res.stdout.strip():
            archivos = [p.strip() for p in res.stdout.strip().split("|") if p.strip()]
            if archivos:
                return archivos
    except Exception:
        pass

    try:
        import tkinter as tk
        from tkinter import filedialog

        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        rutas = filedialog.askopenfilenames(
            title="Selecciona una o varias imágenes de vehículos (Pipeline Peaje M1+M2+M3+M4)",
            filetypes=[
                ("Imágenes", "*.jpg *.jpeg *.png *.webp *.bmp"),
                ("Todos los archivos", "*.*"),
            ],
        )
        root.destroy()
        if rutas:
            return list(rutas)
    except Exception:
        pass

    print(f"{YELLOW}Pega la ruta de la imagen o presiona [ENTER] para usar la foto de prueba:{RESET}")
    entrada = input(f"{BOLD}Ruta > {RESET}").strip()
    if not entrada:
        ejemplo = BASE_DIR / "ejemplo_vehiculo.jpg"
        if not ejemplo.exists():
            crear_imagen_ejemplo(ejemplo)
        return [str(ejemplo)]
    return [p.strip("'\"") for p in entrada.split()]


def recolectar_imagenes(args_rutas):
    """Recolecta rutas de imágenes desde argumentos o selección interactiva."""
    rutas_raw = args_rutas if args_rutas else seleccionar_imagenes_interactivo()
    imagenes = []
    for r in rutas_raw:
        p = Path(r).expanduser()
        if p.is_dir():
            for f in sorted(p.iterdir()):
                if f.is_file() and f.suffix.lower() in EXTS_VALIDAS:
                    imagenes.append(str(f))
        elif p.is_file() and p.suffix.lower() in EXTS_VALIDAS:
            imagenes.append(str(p))
    return imagenes


def verificar_pesos():
    for ruta, desc in [
        (M1_DET_PATH, "M1 Detector Placas (ONNX)"),
        (M1_OCR_PATH, "M1 OCR Placas (ONNX)"),
        (M1_CFG_PATH, "M1 Config YAML OCR"),
        (M2_PATH, "M2 Segmentación Vehicular (.pt)"),
        (M3_PATH, "M3 Keypoints Llantas/Ejes (.pt)"),
        (M4_PATH, "M4 Segmentación Pasajeros (.pt)"),
    ]:
        if not ruta.exists():
            print(f"{RED}[ERROR] Falta archivo de modelo: {ruta} ({desc}){RESET}", file=sys.stderr)
            sys.exit(1)


def procesar_imagen(img_path: str, engine: PeajePipeline, carpeta_salida: Path):
    img = cv2.imread(img_path)
    if img is None:
        return [f"[ERROR] No se pudo leer: {img_path}"], None

    vehiculos, llantas, placas, pasajeros = engine.analizar_imagen(img)
    vis, lineas_log = dibujar_anotaciones(
        img,
        vehiculos,
        llantas,
        placas,
        pasajeros,
        has_m4=(engine.m4 is not None),
        nombre_imagen=Path(img_path).name,
    )

    nombre_salida = f"res_{Path(img_path).stem}.jpg"
    ruta_guardado = carpeta_salida / nombre_salida
    cv2.imwrite(str(ruta_guardado), vis)

    vehiculos_json = PeajePipeline.serializar_vehiculos(vehiculos)
    registro_json = {
        "imagen": Path(img_path).name,
        "salida_anotada": str(ruta_guardado),
        "vehiculos": vehiculos_json,
    }
    return lineas_log, registro_json


def run_json_mode(imagenes):
    """Ejecuta inferencia silenciosa e imprime JSON estructurado para integración backend."""
    import contextlib
    import io

    verificar_pesos()
    # Silenciar mensajes de inicialización para que stdout contenga únicamente JSON válido
    with contextlib.redirect_stdout(io.StringIO()):
        engine = PeajePipeline(warmup_on_init=False)

    resultados = []
    for img_path in imagenes:
        img = cv2.imread(img_path)
        if img is None:
            resultados.append({"imagen": Path(img_path).name, "error": "No se pudo leer la imagen", "vehiculos": []})
            continue
        res = engine.predict_frame(img)
        res["imagen"] = Path(img_path).name
        resultados.append(res)

    salida = resultados[0] if len(resultados) == 1 else resultados
    print(json.dumps(salida, ensure_ascii=False))


def run_batch(imagenes):
    if not imagenes:
        print(f"{YELLOW}No se seleccionaron imágenes.{RESET}")
        return

    verificar_pesos()
    carpeta_salida = crear_carpeta_prueba(BASE_DIR)

    print(f"\n{BOLD}{CYAN}========================================================================{RESET}")
    print(f"{BOLD}{CYAN}   PIPELINE UNIFICADO PEAJE INTELIGENTE (M1, M2, M3 Y M4)   {RESET}")
    print(f"{BOLD}{CYAN}========================================================================{RESET}")
    print(f"Directorio de salida: {BOLD}{GREEN}{carpeta_salida}{RESET}\n")

    print(f"{BOLD}[1/2] Inicializando modelos de visión (engine unificado)...{RESET}")
    engine = PeajePipeline(warmup_on_init=False)
    health = engine.health_info()
    modelos = health["models"]
    print(f"  • Dispositivo: {BOLD}{health['device']} (CUDA={health['cuda_available']}){RESET}")
    print(f"  • M1 Detector: {'✔' if modelos['m1_detector'] else '✘'} | M1 OCR ({health['ocr_backend']}): {'✔' if modelos['m1_ocr'] else '✘'}")
    print(f"  • M2 Vehículos: {'✔' if modelos['m2_segmentation'] else '✘'} | M3 Ruedas: {'✔' if modelos['m3_keypoints'] else '✘'} | M4 Pasajeros: {'✔' if modelos['m4_passengers'] else '✘'}")

    print(f"\n{BOLD}[2/2] Procesando {len(imagenes)} imagen(es)...{RESET}\n")
    resumen_total = []
    resultados_json = []

    for img_path in imagenes:
        lineas, reg = procesar_imagen(img_path, engine, carpeta_salida)
        bloque = "\n".join(lineas)
        print(bloque)
        print("-" * 72)
        resumen_total.append(bloque)
        if reg is not None:
            resultados_json.append(reg)

    (carpeta_salida / "resumen.txt").write_text("\n\n".join(resumen_total), encoding="utf-8")
    (carpeta_salida / "resultados.json").write_text(
        json.dumps(resultados_json, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print(f"\n{BOLD}{GREEN}✔ Proceso completado exitosamente.{RESET}")
    print(f"📁 Resultados, imágenes anotadas y JSON guardados en:\n   {BOLD}{CYAN}{carpeta_salida}{RESET}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pipeline Unificado Peaje Inteligente (M1+M2+M3+M4)")
    parser.add_argument("rutas", nargs="*", help="Rutas de imágenes o carpetas a evaluar")
    parser.add_argument("-i", "--image", nargs="+", dest="images", default=[], help="Imágenes a procesar")
    parser.add_argument("--json", action="store_true", help="Imprimir resultado estructurado en JSON puro a stdout")
    args = parser.parse_args()

    rutas_entrada = list(args.images) + list(args.rutas)
    imgs = recolectar_imagenes(rutas_entrada)

    if args.json:
        run_json_mode(imgs)
    else:
        run_batch(imgs)
