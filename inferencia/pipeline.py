"""
Núcleo Unificado de Inferencia para Sistema Inteligente de Control de Peaje.
Consolida la lógica validada de `probar_pesos.py` para ejecución tanto en
producción (FastAPI en RunPod GPU CUDA / CPU) como en evaluación CLI/local.

Modelos integrados:
- M1: YOLOv9-t ONNX + CCT-XS OCR (`fast-plate-ocr` con fallback ONNX nativo)
- M2: YOLO11s-seg (Segmentación vehicular con filtro de ruido y NMS IoU/contención)
- M3: YOLO11s-pose (Keypoints de ruedas, filtro de repuestos y conteo de ejes)
- M4: YOLO11s-seg (Segmentación y conteo de pasajeros en cabina, +5 pts extras)
"""
from __future__ import annotations

import base64
import os
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import numpy as np
import yaml

try:
    import torch
    HAS_TORCH = True
except ImportError:
    torch = None
    HAS_TORCH = False

try:
    from ultralytics import YOLO
    HAS_YOLO = True
except ImportError:
    YOLO = None
    HAS_YOLO = False

try:
    import onnxruntime as ort
    HAS_ORT = True
except ImportError:
    ort = None
    HAS_ORT = False

try:
    from fast_plate_ocr import LicensePlateRecognizer
    HAS_FAST_PLATE_OCR = True
except ImportError:
    LicensePlateRecognizer = None
    HAS_FAST_PLATE_OCR = False


# ===================== Rutas y Constantes =====================
BASE_DIR = Path(__file__).resolve().parent
PESOS_DIR = Path(os.getenv("PESOS_DIR", str(BASE_DIR / "pesos")))
if not PESOS_DIR.exists() and (BASE_DIR / "modelo").exists():
    PESOS_DIR = BASE_DIR
MODELO_DIR = PESOS_DIR / "modelo"

M1_DET_PATH = MODELO_DIR / "yolo-v9-t-384-license-plates-end2end.onnx"
M1_OCR_PATH = MODELO_DIR / "cct_xs_v2_global.onnx"
M1_CFG_PATH = MODELO_DIR / "cct_xs_v2_global_plate_config.yaml"
M2_PATH = PESOS_DIR / "m2_vehiculos.pt"
M3_PATH = PESOS_DIR / "m3_llantas.pt"
M4_PATH = PESOS_DIR / "m4_pasajeros_seg.pt"

# Parámetros M1 y Formatos de Matrícula
LADO_M1 = 384
FORMATO_BOLIVIA = re.compile(r"^\d{3,4}[A-Z]{3}$")
FORMATO_MERCOSUR = re.compile(r"^[A-Z]{2,3}\d{3,4}[A-Z]{0,2}$|^[A-Z]{3}\d[A-Z]\d{2}$")
FORMATO_INTERNACIONAL = re.compile(r"^[A-Z0-9]{3,8}$")

# Parámetros M3 (asociación y ejes)
UMBRAL_CONTENCION = 0.70
UMBRAL_CERCANA = 0.65
SEPARACION_EJE = 0.60
EXTS_VALIDAS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


# ===================== Funciones de Placas, Geometría y Fusión =====================
def limpiar_texto_placa(texto: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", (texto or "").upper())


def clasificar_formato_placa(texto: str) -> str:
    """Clasifica el origen y validez del formato de la placa."""
    if not texto or len(texto) < 3:
        return "ILEGIBLE"
    if FORMATO_BOLIVIA.match(texto):
        return "BO-OK"
    if FORMATO_MERCOSUR.match(texto):
        return "INT-MERCOSUR"
    if FORMATO_INTERNACIONAL.match(texto):
        return "INT-GLOBAL"
    return "NO-ESTANDAR"


def altura_visible(llanta: Dict[str, Any]) -> float:
    return max(1.0, float(llanta["kps"][1, 1] - llanta["kps"][2, 1]))


def contenida(a: List[float], b: List[float]) -> float:
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    area = max(1e-6, (a[2] - a[0]) * (a[3] - a[1]))
    return float(inter / area)


def calcular_iou(b1: List[float], b2: List[float]) -> float:
    """Calcula Intersection over Union entre dos cajas delimitadoras."""
    x1, y1 = max(b1[0], b2[0]), max(b1[1], b2[1])
    x2, y2 = min(b1[2], b2[2]), min(b1[3], b2[3])
    inter = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    a1 = max(1e-6, (b1[2] - b1[0]) * (b1[3] - b1[1]))
    a2 = max(1e-6, (b2[2] - b2[0]) * (b2[3] - b2[1]))
    union = a1 + a2 - inter
    return float(inter / max(1e-6, union))


def filtrar_vehiculos_duplicados(
    vehiculos: List[Dict[str, Any]],
    umbral_iou: float = 0.45,
    umbral_contencion: float = 0.65,
) -> List[Dict[str, Any]]:
    """
    Elimina detecciones duplicadas y falsos positivos:
    1. Suprime cajas duplicadas con clases en conflicto (ej. auto vs minibus) mediante IoU.
    2. Suprime cajas contenidas dentro de un vehículo más grande.
    """
    if not vehiculos:
        return []

    orden = sorted(
        vehiculos,
        key=lambda v: (v["conf"], (v["box"][2] - v["box"][0]) * (v["box"][3] - v["box"][1])),
        reverse=True,
    )
    filtrados = []
    for v in orden:
        duplicado = False
        for f in filtrados:
            iou = calcular_iou(v["box"], f["box"])
            c_vf = contenida(v["box"], f["box"])
            c_fv = contenida(f["box"], v["box"])
            if iou >= umbral_iou or c_vf >= umbral_contencion or c_fv >= umbral_contencion:
                duplicado = True
                break
        if not duplicado:
            filtrados.append(v)
    return filtrados


def limpiar_llantas(llantas: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    orden = sorted(
        llantas,
        key=lambda l: (l["box"][2] - l["box"][0]) * (l["box"][3] - l["box"][1]),
    )
    res = []
    for l in orden:
        if all(contenida(l["box"], r["box"]) < UMBRAL_CONTENCION for r in res):
            res.append(l)
    return res


def analizar_ejes(v: Dict[str, Any], ls: List[Dict[str, Any]]) -> Tuple[int, str, str]:
    if not ls:
        return 2, "lateral", "Mínimo asumido (sin llantas claras)"

    hmax = max(altura_visible(l) for l in ls)
    cercanas = [l for l in ls if altura_visible(l) >= UMBRAL_CERCANA * hmax]

    # Filtrar llanta de repuesto colgada atrás en vehículos livianos
    if v.get("clase") in {"auto", "minibus"} and len(cercanas) >= 3:
        ys_contacto = sorted(float(l["kps"][1, 1]) for l in cercanas)
        linea_suelo = float(np.median(ys_contacto[-2:]))
        en_suelo = [l for l in cercanas if float(l["kps"][1, 1]) >= linea_suelo - 0.85 * hmax]
        if len(en_suelo) >= 2:
            cercanas = en_suelo

    x1, y1, x2, y2 = v["box"]
    proporcion = (x2 - x1) / max(1.0, y2 - y1)

    # Vista frontal/posterior pura: 2 ruedas angostas a la misma altura
    if len(ls) == 2 and len(cercanas) == 2 and proporcion < 1.6:
        a, b = cercanas
        angostas = all(((l["kps"][4, 0] - l["kps"][3, 0]) / altura_visible(l)) < 0.65 for l in cercanas)
        misma_altura = abs(a["kps"][1, 1] - b["kps"][1, 1]) < 0.15 * hmax
        if angostas and misma_altura:
            return 2, "frontal/posterior", "Vista frontal (2 ejes estimados)"

    xs = sorted(float(l["kps"][0, 0]) for l in cercanas)
    diam = float(np.median([altura_visible(l) for l in cercanas]))
    ejes = 1 + sum(1 for p, q in zip(xs, xs[1:]) if (q - p) > SEPARACION_EJE * diam)
    redondez = float(np.median([(l["kps"][4, 0] - l["kps"][3, 0]) / altura_visible(l) for l in cercanas]))
    vista = "lateral" if redondez > 0.8 else "3/4"
    nota = ""
    if ejes < 2:
        ejes, nota = 2, "Mínimo asumido (solo se detectó 1 eje visible)"
    return int(ejes), vista, nota


def seleccionar_placa_principal(placas_lista: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Prioriza placas con texto legible (>=2 caracteres) ponderando det * ocr."""
    if not placas_lista:
        return None
    con_texto = [p for p in placas_lista if p.get("texto") and len(p["texto"]) >= 2]
    if con_texto:
        return max(con_texto, key=lambda x: float(x["conf_det"]) * float(x.get("conf_ocr") or 0.8))
    return max(placas_lista, key=lambda x: float(x["conf_det"]))


def asociar_todo(
    vehiculos: List[Dict[str, Any]],
    llantas: List[Dict[str, Any]],
    placas: List[Dict[str, Any]],
    pasajeros: List[Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Asocia llantas (M3), placas (M1) y pasajeros (M4) a vehículos (M2) y ordena por prioridad en caseta."""
    llantas = limpiar_llantas(llantas)
    for v in vehiculos:
        v["llantas"] = []
        v["placas"] = []
        v["pasajeros"] = []

    # 1. Asociar llantas (M3) -> vehículo (M2)
    for i, l in enumerate(llantas):
        cx, cy = float(l["kps"][0, 0]), float(l["kps"][0, 1])
        l["vehiculo"] = None
        mejor, area_min = None, None
        for j, v in enumerate(vehiculos):
            x1, y1, x2, y2 = v["box"]
            w, h = x2 - x1, y2 - y1
            if (x1 - 0.05 * w) <= cx <= (x2 + 0.05 * w) and (y1 + 0.45 * h) <= cy <= (y2 + 0.10 * h):
                area = w * h
                if area_min is None or area < area_min:
                    mejor, area_min = j, area
        if mejor is not None:
            vehiculos[mejor]["llantas"].append(i)
            l["vehiculo"] = mejor

    for v in vehiculos:
        v["ejes"], v["vista"], v["nota"] = analizar_ejes(v, [llantas[i] for i in v["llantas"]])

    # 2. Asociar placas (M1) -> vehículo (M2) por contención
    for p in placas:
        p["vehiculo"] = None
        mejor_v, mejor_score = None, 0.0
        for j, v in enumerate(vehiculos):
            score = contenida(p["box"], v["box"])
            if score > 0.5 and score > mejor_score:
                mejor_v, mejor_score = j, score
        if mejor_v is not None:
            vehiculos[mejor_v]["placas"].append(p)
            p["vehiculo"] = mejor_v

    # 3. Asociar pasajeros (M4) -> vehículo (M2) (+5 Pts Bonificación)
    for pas in pasajeros:
        pas["vehiculo"] = None
        px1, py1, px2, py2 = pas["box"]
        pcx, pcy = (px1 + px2) / 2.0, (py1 + py2) / 2.0
        mejor_v, mejor_score = None, 0.0

        for j, v in enumerate(vehiculos):
            vx1, vy1, vx2, vy2 = v["box"]
            vw, vh = vx2 - vx1, vy2 - vy1

            score = contenida(pas["box"], v["box"])
            en_cabina = (vx1 <= pcx <= vx2) and (vy1 <= pcy <= vy2 - 0.10 * vh)
            if score >= 0.70 or en_cabina:
                total_score = score + (1.0 if en_cabina else 0.0)
                if total_score > mejor_score:
                    mejor_v, mejor_score = j, total_score

        if mejor_v is not None:
            vehiculos[mejor_v]["pasajeros"].append(pas)
            pas["vehiculo"] = mejor_v

    for v in vehiculos:
        v["num_pasajeros"] = len(v["pasajeros"])

    # 4. Ordenar vehículos para que el #1 sea el principal en caseta:
    #    (tiene placa legible, tiene alguna placa detectada, área del vehículo)
    vehiculos.sort(
        key=lambda v: (
            any(p.get("texto") and len(p["texto"]) >= 2 for p in v.get("placas", [])),
            len(v.get("placas", [])) > 0,
            (v["box"][2] - v["box"][0]) * (v["box"][3] - v["box"][1]),
        ),
        reverse=True,
    )

    # Re-indexar referencias tras ordenar
    for idx_v, v in enumerate(vehiculos):
        for i_ll in v["llantas"]:
            llantas[i_ll]["vehiculo"] = idx_v
        for p in v["placas"]:
            p["vehiculo"] = idx_v
        for pas in v["pasajeros"]:
            pas["vehiculo"] = idx_v

    return vehiculos, llantas, placas, pasajeros


def dibujar_anotaciones(
    img: np.ndarray,
    vehiculos: List[Dict[str, Any]],
    llantas: List[Dict[str, Any]],
    placas: List[Dict[str, Any]],
    pasajeros: List[Dict[str, Any]],
    has_m4: bool = True,
    nombre_imagen: str = "frame",
    conf_veh: float = 0.38,
) -> Tuple[np.ndarray, List[str]]:
    """Dibuja cajas de vehículos (ámbar), placas (verde), ruedas (verde lima) y pasajeros (cian)."""
    vis = img.copy()
    lineas_log = [f"Imagen: {nombre_imagen}"]

    if not vehiculos:
        lineas_log.append(f"  Sin vehículos detectados (conf >= {conf_veh})")

    for idx, v in enumerate(vehiculos, start=1):
        x1, y1, x2, y2 = map(int, v["box"])
        ejes_txt = "N/D" if v["ejes"] is None else str(v["ejes"])
        pas_val = v.get("num_pasajeros", 0)

        if v["placas"]:
            p_principal = seleccionar_placa_principal(v["placas"])
            if p_principal and p_principal.get("texto") and len(p_principal["texto"]) >= 2:
                placa_txt = p_principal["texto"]
                tipo_fmt = p_principal.get("formato_tipo", "BO-OK" if p_principal["formato_bolivia"] else "INT")
                placa_log = f"{placa_txt} ({tipo_fmt}, ocr={p_principal['conf_ocr']})"
            else:
                conf_det_p = p_principal["conf_det"] if p_principal else 0.0
                placa_txt = "PLACA ILEGIBLE"
                placa_log = f"Placa no legible (det={conf_det_p})"
        else:
            placa_txt = "SIN PLACA"
            placa_log = "Sin placa"

        pas_extra = f" | pas:{pas_val}" if has_m4 else ""
        label = f"#{idx}, {v['clase']} ({v['conf']:.2f}) | ejes: {ejes_txt}{pas_extra} | {placa_txt}"
        cv2.rectangle(vis, (x1, y1), (x2, y2), (0, 200, 255), 2)
        cv2.putText(
            vis,
            label,
            (x1, max(22, y1 - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.58,
            (0, 200, 255),
            2,
            cv2.LINE_AA,
        )

        detalle = (
            f"  Vehículo #{idx}: clase={v['clase']} conf={v['conf']:.2f} | "
            f"placa={placa_log} | llantas={len(v['llantas'])} vista={v['vista']} ejes={ejes_txt} | "
            f"pasajeros={pas_val} {v.get('nota', '')}".rstrip()
        )
        lineas_log.append(detalle)

    # Placas (Verde)
    for p in placas:
        px1, py1, px2, py2 = map(int, p["box"])
        cv2.rectangle(vis, (px1, py1), (px2, py2), (0, 230, 0), 2)
        if p["vehiculo"] is None:
            texto_p = p["texto"] or "ILEGIBLE"
            cv2.putText(
                vis,
                texto_p,
                (px1, max(20, py1 - 6)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 230, 0),
                2,
                cv2.LINE_AA,
            )
            lineas_log.append(f"  [Placa suelta]: {texto_p} (det={p['conf_det']}, ocr={p['conf_ocr']})")

    # Llantas (Verde lima)
    for l in llantas:
        for x, y, c in l["kps"]:
            if c > 0.05:
                cv2.circle(vis, (int(x), int(y)), 4, (50, 255, 50), -1)

    # Pasajeros (Cian/Amarillo sin recorte facial)
    for pas in pasajeros:
        if pas.get("vehiculo") is not None:
            mask = pas.get("mask")
            bx1, by1, bx2, by2 = map(int, pas["box"])
            cx, cy = int((bx1 + bx2) / 2), int(by1 + (by2 - by1) * 0.3)
            w_p, h_p = max(1, bx2 - bx1), max(1, by2 - by1)

            c_pas = (255, 220, 0)
            c_pas_core = (0, 255, 255)

            if mask is not None and len(mask) >= 6:
                step = max(1, len(mask) // 8)
                for pt in mask[::step]:
                    cv2.circle(vis, (int(pt[0]), int(pt[1])), 4, c_pas, -1)
                cv2.circle(vis, (cx, cy), 5, c_pas_core, -1)
                pts_poly = np.array(mask, dtype=np.int32).reshape((-1, 1, 2))
                cv2.polylines(vis, [pts_poly], isClosed=True, color=c_pas, thickness=1, lineType=cv2.LINE_AA)
            else:
                puntos_silueta = [
                    (cx, int(by1 + 0.20 * h_p)),
                    (int(bx1 + 0.25 * w_p), int(by1 + 0.40 * h_p)),
                    (int(bx2 - 0.25 * w_p), int(by1 + 0.40 * h_p)),
                    (cx, int(by1 + 0.60 * h_p)),
                ]
                for px, py in puntos_silueta:
                    cv2.circle(vis, (px, py), 4, c_pas, -1)
                cv2.circle(vis, (cx, cy), 5, c_pas_core, -1)

    return vis, lineas_log


# ===================== Motor Unificado (RunPod GPU / Local CPU) =====================
class PeajePipeline:
    """Motor unificado M1 + M2 + M3 + M4 listo para GPU CUDA (RunPod) o CPU."""

    def __init__(self, warmup_on_init: bool = False):
        self.cuda_available = bool(HAS_TORCH and torch.cuda.is_available())
        self.device = "cuda" if self.cuda_available else "cpu"
        self.device_name = torch.cuda.get_device_name(0) if self.cuda_available else "CPU"
        self.onnx_providers: List[str] = ["CPUExecutionProvider"]

        self.sesion_m1 = None
        self.lector_ocr = None
        self.ocr_raw_session = None
        self.ocr_backend = "none"
        self.ocr_alphabet = ""
        self.ocr_pad_char = "_"
        self.ocr_img_h = 64
        self.ocr_img_w = 128

        self.m2 = None
        self.m3 = None
        self.m4 = None

        self.load_models()
        if warmup_on_init:
            self.warmup()

    def _select_onnx_providers(self) -> List[str]:
        if not HAS_ORT:
            return []
        avail = ort.get_available_providers()
        force_cpu = os.getenv("ORT_FORCE_CPU", "0") == "1"
        if self.cuda_available and not force_cpu and "CUDAExecutionProvider" in avail:
            return ["CUDAExecutionProvider", "CPUExecutionProvider"]
        return ["CPUExecutionProvider"]

    def load_models(self) -> None:
        print(f"[INFO] Inicializando PeajePipeline en {self.device_name} (CUDA={self.cuda_available})...")
        desired_providers = self._select_onnx_providers()

        # 1. M1 Detector YOLOv9 ONNX
        if HAS_ORT and M1_DET_PATH.exists():
            try:
                self.sesion_m1 = ort.InferenceSession(str(M1_DET_PATH), providers=desired_providers)
                self.onnx_providers = self.sesion_m1.get_providers()
                print(f"[OK] M1 Detector ONNX cargado ({self.onnx_providers})")
            except Exception as e:
                print(f"[WARN] Fallo cargando M1 con {desired_providers}, reintentando CPU: {e}")
                try:
                    self.sesion_m1 = ort.InferenceSession(str(M1_DET_PATH), providers=["CPUExecutionProvider"])
                    self.onnx_providers = self.sesion_m1.get_providers()
                    print(f"[OK] M1 Detector ONNX cargado en CPU fallback ({self.onnx_providers})")
                except Exception as e2:
                    print(f"[ERROR] No se pudo cargar M1 Detector: {e2}")

        # 2. M1 OCR CCT-XS (fast-plate-ocr con fallback ONNX nativo)
        if M1_OCR_PATH.exists() and M1_CFG_PATH.exists():
            with open(M1_CFG_PATH, "r", encoding="utf-8") as f:
                cfg = yaml.safe_load(f) or {}
                self.ocr_alphabet = cfg.get("alphabet", "")
                self.ocr_pad_char = cfg.get("pad_char", "_")
                self.ocr_img_h = int(cfg.get("img_height", 64))
                self.ocr_img_w = int(cfg.get("img_width", 128))

            if HAS_FAST_PLATE_OCR:
                try:
                    self.lector_ocr = LicensePlateRecognizer(
                        onnx_model_path=str(M1_OCR_PATH),
                        plate_config_path=str(M1_CFG_PATH),
                        providers=desired_providers,
                    )
                    self.ocr_backend = "fast-plate-ocr"
                    print(f"[OK] M1 OCR (fast-plate-ocr) cargado ({desired_providers})")
                except Exception as e:
                    print(f"[WARN] fast-plate-ocr falló con {desired_providers}, probando CPU: {e}")
                    try:
                        self.lector_ocr = LicensePlateRecognizer(
                            onnx_model_path=str(M1_OCR_PATH),
                            plate_config_path=str(M1_CFG_PATH),
                            providers=["CPUExecutionProvider"],
                        )
                        self.ocr_backend = "fast-plate-ocr"
                        print("[OK] M1 OCR (fast-plate-ocr) cargado en CPU")
                    except Exception as e2:
                        print(f"[WARN] No se pudo cargar fast-plate-ocr, usando fallback ONNX: {e2}")

            if self.lector_ocr is None and HAS_ORT:
                try:
                    self.ocr_raw_session = ort.InferenceSession(
                        str(M1_OCR_PATH), providers=["CPUExecutionProvider"]
                    )
                    self.ocr_backend = "onnx-raw"
                    print("[OK] M1 OCR cargado con decodificador ONNX nativo")
                except Exception as e:
                    print(f"[ERROR] No se pudo cargar M1 OCR ONNX: {e}")

        # 3. M2, M3 y M4 (YOLO PyTorch)
        if HAS_YOLO:
            for attr, path, label in [
                ("m2", M2_PATH, "M2 Vehículos (YOLO11s-seg)"),
                ("m3", M3_PATH, "M3 Llantas/Ejes (YOLO11s-pose)"),
                ("m4", M4_PATH, "M4 Pasajeros (YOLO11s-seg)"),
            ]:
                if path.exists():
                    try:
                        model = YOLO(str(path))
                        if self.cuda_available:
                            model.to("cuda")
                        setattr(self, attr, model)
                        print(f"[OK] {label} cargado en {self.device.upper()}")
                    except Exception as e:
                        print(f"[ERROR] No se pudo cargar {label}: {e}")
                else:
                    print(f"[WARN] No encontrado peso {path}")

    def warmup(self) -> None:
        """Precalienta kernels GPU/CPU con una imagen dummy al iniciar el servicio."""
        try:
            dummy = np.zeros((640, 640, 3), dtype=np.uint8)
            self.analizar_imagen(dummy)
            print("[OK] Warmup inicial de modelos M1..M4 completado.")
        except Exception as e:
            print(f"[WARN] Warmup omitido: {e}")

    def _leer_placa_ocr(self, recorte_rgb: np.ndarray) -> Tuple[str, Optional[float]]:
        texto = ""
        conf_ocr: Optional[float] = None

        if self.lector_ocr is not None:
            try:
                pred = self.lector_ocr.run_one(recorte_rgb, return_confidence=True)
                texto = limpiar_texto_placa(pred.plate)
                conf_ocr = float(pred.char_probs.mean()) if pred.char_probs is not None else 0.95
                return texto, conf_ocr
            except Exception:
                pass

        if self.ocr_raw_session is not None and self.ocr_alphabet:
            try:
                resized = cv2.resize(recorte_rgb, (self.ocr_img_w, self.ocr_img_h))
                inp = np.expand_dims(resized.astype(np.uint8), axis=0)
                in_name = self.ocr_raw_session.get_inputs()[0].name
                out = self.ocr_raw_session.run(None, {in_name: inp})[0]
                if len(out.shape) == 3:
                    out = out[0]
                chars = []
                probs = []
                for slot in out:
                    idx = int(np.argmax(slot))
                    prob = float(np.max(slot))
                    ch = self.ocr_alphabet[idx] if idx < len(self.ocr_alphabet) else ""
                    if ch and ch != self.ocr_pad_char:
                        chars.append(ch)
                        probs.append(prob)
                texto = limpiar_texto_placa("".join(chars))
                conf_ocr = float(np.mean(probs)) if probs else 0.0
            except Exception:
                pass

        return texto, conf_ocr

    def detectar_placas(self, img_bgr: np.ndarray, umbral: float = 0.35) -> List[Dict[str, Any]]:
        """Detecta placas con YOLOv9-t ONNX (letterbox 384x384) y lee caracteres con OCR."""
        if self.sesion_m1 is None:
            return []

        alto, ancho = img_bgr.shape[:2]
        escala = min(LADO_M1 / alto, LADO_M1 / ancho)
        nuevo_ancho, nuevo_alto = round(ancho * escala), round(alto * escala)
        margen_x, margen_y = (LADO_M1 - nuevo_ancho) / 2, (LADO_M1 - nuevo_alto) / 2

        lienzo = cv2.resize(img_bgr, (nuevo_ancho, nuevo_alto), interpolation=cv2.INTER_LINEAR)
        lienzo = cv2.copyMakeBorder(
            lienzo,
            round(margen_y - 0.1),
            round(margen_y + 0.1),
            round(margen_x - 0.1),
            round(margen_x + 0.1),
            cv2.BORDER_CONSTANT,
            value=(114, 114, 114),
        )
        entrada = (lienzo[:, :, ::-1].transpose(2, 0, 1) / 255.0).astype(np.float32)[None]
        salida = self.sesion_m1.run(None, {self.sesion_m1.get_inputs()[0].name: entrada})[0]
        if len(salida.shape) == 3:
            salida = salida[0]

        placas = []
        for fila in salida:
            if len(fila) == 7:
                x1, y1, x2, y2 = fila[1:5]
                conf = float(fila[6])
            elif len(fila) >= 5:
                x1, y1, x2, y2 = fila[0:4]
                conf = float(fila[4])
            else:
                continue

            if conf < umbral:
                continue

            x1_i = int(max(0, (float(x1) - margen_x) / escala))
            x2_i = int(min(ancho, (float(x2) - margen_x) / escala))
            y1_i = int(max(0, (float(y1) - margen_y) / escala))
            y2_i = int(min(alto, (float(y2) - margen_y) / escala))
            if x2_i <= x1_i or y2_i <= y1_i:
                continue

            recorte_bgr = img_bgr[y1_i:y2_i, x1_i:x2_i]
            recorte_rgb = cv2.cvtColor(recorte_bgr, cv2.COLOR_BGR2RGB)
            texto, conf_ocr = self._leer_placa_ocr(recorte_rgb)

            if len(texto) < 2:
                texto = ""

            formato_str = clasificar_formato_placa(texto)
            placas.append({
                "box": [x1_i, y1_i, x2_i, y2_i],
                "texto": texto,
                "formato_bolivia": bool(FORMATO_BOLIVIA.match(texto)),
                "formato_tipo": formato_str,
                "conf_det": round(conf, 3),
                "conf_ocr": None if conf_ocr is None else round(float(conf_ocr), 3),
                "vehiculo": None,
            })
        return placas

    def analizar_imagen(
        self,
        img_bgr: np.ndarray,
        conf_veh: float = 0.38,
        conf_kp: float = 0.20,
        conf_placa: float = 0.35,
        conf_pas: float = 0.25,
    ) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Ejecuta M2, M3, M4 y M1 en conjunto y fusiona las asociaciones."""
        alto_img, ancho_img = img_bgr.shape[:2]
        area_img = alto_img * ancho_img

        # M2: Vehículos
        vehiculos: List[Dict[str, Any]] = []
        if self.m2 is not None:
            try:
                r2 = self.m2.predict(img_bgr, conf=conf_veh, imgsz=640, verbose=False)[0]
                if r2.boxes is not None and len(r2.boxes):
                    for cls_id, conf, box in zip(
                        r2.boxes.cls.cpu().numpy().astype(int),
                        r2.boxes.conf.cpu().numpy(),
                        r2.boxes.xyxy.cpu().numpy(),
                    ):
                        b = [round(float(c), 1) for c in box.tolist()]
                        w_box = b[2] - b[0]
                        h_box = b[3] - b[1]
                        area_box = w_box * h_box
                        rel_area = area_box / max(1.0, area_img)

                        # Filtrar micro-detecciones de fondo (< 2% del frame)
                        if rel_area < 0.02 and (w_box < 60 or h_box < 60):
                            continue

                        vehiculos.append({
                            "clase": str(r2.names.get(int(cls_id), "auto")).lower(),
                            "conf": round(float(conf), 3),
                            "box": b,
                            "area": round(float(area_box), 1),
                        })
                    vehiculos = filtrar_vehiculos_duplicados(
                        vehiculos, umbral_iou=0.45, umbral_contencion=0.65
                    )
            except Exception as e:
                print(f"[WARN M2]: {e}")

        # Gate M2-primero: si M2 está cargado y no detecta ningún vehículo,
        # no ejecutar M3/M4/M1 ni contar personas sueltas en la calle.
        if self.m2 is not None and len(vehiculos) == 0:
            return [], [], [], []

        # M3: Llantas / Ejes
        llantas: List[Dict[str, Any]] = []
        if self.m3 is not None:
            try:
                r3 = self.m3.predict(img_bgr, conf=conf_kp, imgsz=640, verbose=False)[0]
                if r3.keypoints is not None and r3.boxes is not None and len(r3.boxes):
                    xy = r3.keypoints.xy.cpu().numpy()
                    kc = (
                        r3.keypoints.conf.cpu().numpy()
                        if r3.keypoints.conf is not None
                        else np.ones((len(r3.boxes), 5))
                    )
                    for box, conf, pts, kconf in zip(
                        r3.boxes.xyxy.cpu().numpy(), r3.boxes.conf.cpu().numpy(), xy, kc
                    ):
                        kps = np.concatenate([pts, kconf[:, None]], axis=1)
                        llantas.append({
                            "conf": float(conf),
                            "box": [float(c) for c in box.tolist()],
                            "kps": kps,
                        })
            except Exception as e:
                print(f"[WARN M3]: {e}")

        # M4: Pasajeros
        pasajeros: List[Dict[str, Any]] = []
        if self.m4 is not None:
            try:
                r4 = self.m4.predict(img_bgr, classes=[0], conf=conf_pas, imgsz=640, verbose=False)[0]
                if r4.boxes is not None and len(r4.boxes):
                    boxes_np = r4.boxes.xyxy.cpu().numpy()
                    confs_np = r4.boxes.conf.cpu().numpy()
                    masks_xy = (
                        r4.masks.xy
                        if (r4.masks is not None and hasattr(r4.masks, "xy"))
                        else [None] * len(boxes_np)
                    )
                    for box, conf, mask in zip(boxes_np, confs_np, masks_xy):
                        pasajeros.append({
                            "box": [round(float(c), 1) for c in box.tolist()],
                            "conf": round(float(conf), 3),
                            "mask": mask,
                        })
            except Exception as e:
                print(f"[WARN M4]: {e}")

        # M1: Placas + OCR
        placas = self.detectar_placas(img_bgr, umbral=conf_placa)

        # Fusión espacial y ordenamiento por prioridad en caseta
        return asociar_todo(vehiculos, llantas, placas, pasajeros)

    @staticmethod
    def serializar_vehiculos(vehiculos: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        salida = []
        for idx, v in enumerate(vehiculos, start=1):
            p_main = seleccionar_placa_principal(v.get("placas", []))
            placa_txt = p_main["texto"] if (p_main and p_main.get("texto")) else "SIN_PLACA"
            conf_ocr = float(p_main["conf_ocr"] or 0.0) if (p_main and p_main.get("conf_ocr") is not None) else 0.0
            fmt_tipo = p_main.get("formato_tipo", "SIN_PLACA") if p_main else "SIN_PLACA"
            salida.append({
                "id": idx,
                "categoria": str(v["clase"]),
                "confianza": float(v["conf"]),
                "box": [float(c) for c in v["box"]],
                "ejes": int(v["ejes"]),
                "pasajeros": int(v.get("num_pasajeros", 0)),
                "vista": str(v["vista"]),
                "nota": str(v.get("nota", "")),
                "placa": placa_txt,
                "formato_placa": fmt_tipo,
                "confianza_ocr": conf_ocr,
                "ruedas_detectadas": len(v.get("llantas", [])),
            })
        return salida

    def predict_frame(
        self,
        img_bgr: np.ndarray,
        conf_veh: float = 0.38,
        conf_kp: float = 0.20,
        conf_placa: float = 0.35,
        conf_pas: float = 0.25,
        incluir_anotada: bool = False,
    ) -> Dict[str, Any]:
        """Ejecuta el pipeline unificado y devuelve el contrato JSON para el backend y API."""
        t0 = time.time()
        vehiculos, llantas, placas, pasajeros = self.analizar_imagen(
            img_bgr,
            conf_veh=conf_veh,
            conf_kp=conf_kp,
            conf_placa=conf_placa,
            conf_pas=conf_pas,
        )
        latencia_ms = round((time.time() - t0) * 1000, 2)
        vehiculos_json = self.serializar_vehiculos(vehiculos)

        v0 = vehiculos[0] if vehiculos else None
        if v0 is None:
            return {
                "vehiculo_detectado": False,
                "placa": "SIN_PLACA",
                "confianza": 0.0,
                "formato_placa": "SIN_PLACA",
                "categoria": "ninguno",
                "ejes": 0,
                "pasajeros": 0,
                "latencia_ms": latencia_ms,
                "imagen_size": [int(img_bgr.shape[1]), int(img_bgr.shape[0])],
                "vehiculos": [],
                "detalles": {
                    "m1": {
                        "placa": "SIN_PLACA",
                        "confianza_ocr": 0.0,
                        "formato_tipo": "SIN_PLACA",
                        "bbox": None,
                        "total_placas": 0,
                    },
                    "m2": {
                        "categoria": "ninguno",
                        "confianza_categoria": 0.0,
                        "bbox": None,
                        "total_vehiculos": 0,
                    },
                    "m3": {
                        "ejes": 0,
                        "ruedas_detectadas": 0,
                        "vista": "ninguna",
                        "nota": "Sin vehículo detectado por M2",
                        "confianza_ejes": 0.0,
                        "puntos": [],
                        "cajas_ruedas": [],
                    },
                    "m4": {
                        "pasajeros": 0,
                        "total_personas_imagen": 0,
                        "cajas": [],
                    },
                },
            }

        p_principal = seleccionar_placa_principal(v0["placas"]) if v0["placas"] else None

        # Si el vehículo #1 no tiene placa legible, buscar entre placas sueltas legibles
        if not p_principal or not p_principal.get("texto"):
            p_suelta = seleccionar_placa_principal(placas)
            if p_suelta and p_suelta.get("texto"):
                p_principal = p_suelta
            elif p_principal is None:
                p_principal = p_suelta

        if p_principal and p_principal.get("texto"):
            placa_final = p_principal["texto"]
            conf_ocr_final = float(p_principal["conf_ocr"] or 0.0)
            fmt_final = str(p_principal.get("formato_tipo", "INT-GLOBAL"))
            bbox_placa = [int(c) for c in p_principal["box"]]
        elif p_principal is not None:
            placa_final = "SIN_PLACA"
            conf_ocr_final = 0.0
            fmt_final = "ILEGIBLE"
            bbox_placa = [int(c) for c in p_principal["box"]]
        else:
            placa_final = "SIN_PLACA"
            conf_ocr_final = 0.0
            fmt_final = "SIN_PLACA"
            bbox_placa = None

        categoria_final = str(v0["clase"])
        conf_cat_final = float(v0["conf"])
        bbox_veh_final = [float(c) for c in v0["box"]]
        ejes_final = int(v0["ejes"])
        ruedas_final = len(v0["llantas"])
        vista_final = str(v0["vista"])
        nota_final = str(v0.get("nota", ""))
        pasajeros_final = int(v0.get("num_pasajeros", 0))

        ruedas_src = v0["llantas"]
        puntos_ruedas: List[List[float]] = []
        cajas_ruedas: List[List[float]] = []
        for r in ruedas_src:
            if r.get("box") is not None:
                cajas_ruedas.append([round(float(c), 1) for c in r["box"]])
            kps = r.get("kps")
            if kps is not None:
                for kp in kps:
                    x = float(kp[0])
                    y = float(kp[1])
                    c = float(kp[2]) if len(kp) > 2 else 1.0
                    if c >= 0.20 and (x > 0 or y > 0):
                        puntos_ruedas.append([round(x, 1), round(y, 1), round(c, 2)])

        pas_src = v0.get("pasajeros", [])
        cajas_pasajeros = [
            [round(float(c), 1) for c in p["box"]]
            for p in pas_src
            if p.get("box") is not None
        ]

        resp: Dict[str, Any] = {
            "vehiculo_detectado": True,
            "placa": placa_final,
            "confianza": round(conf_ocr_final, 3),
            "formato_placa": fmt_final,
            "categoria": categoria_final,
            "ejes": ejes_final,
            "pasajeros": pasajeros_final,
            "latencia_ms": latencia_ms,
            "imagen_size": [int(img_bgr.shape[1]), int(img_bgr.shape[0])],
            "vehiculos": vehiculos_json,
            "detalles": {
                "m1": {
                    "placa": placa_final,
                    "confianza_ocr": round(conf_ocr_final, 3),
                    "formato_tipo": fmt_final,
                    "bbox": bbox_placa,
                    "total_placas": len(placas),
                },
                "m2": {
                    "categoria": categoria_final,
                    "confianza_categoria": conf_cat_final,
                    "bbox": bbox_veh_final,
                    "total_vehiculos": len(vehiculos),
                },
                "m3": {
                    "ejes": ejes_final,
                    "ruedas_detectadas": ruedas_final,
                    "vista": vista_final,
                    "nota": nota_final,
                    "confianza_ejes": 0.90 if ruedas_final >= 2 else 0.80,
                    "puntos": puntos_ruedas,
                    "cajas_ruedas": cajas_ruedas,
                },
                "m4": {
                    "pasajeros": pasajeros_final,
                    "total_personas_imagen": len(pasajeros),
                    "cajas": cajas_pasajeros,
                },
            },
        }

        if incluir_anotada:
            vis, _ = dibujar_anotaciones(
                img_bgr, vehiculos, llantas, placas, pasajeros, has_m4=(self.m4 is not None)
            )
            ok, buf = cv2.imencode(".jpg", vis, [int(cv2.IMWRITE_JPEG_QUALITY), 88])
            if ok:
                resp["imagen_anotada_base64"] = "data:image/jpeg;base64," + base64.b64encode(buf.tobytes()).decode("ascii")

        return resp

    def predict_ocr(self, img_bgr: np.ndarray, umbral: float = 0.35) -> Dict[str, Any]:
        """Ejecuta exclusivamente M1 + OCR sobre la imagen."""
        t0 = time.time()
        placas = self.detectar_placas(img_bgr, umbral=umbral)
        latencia_ms = round((time.time() - t0) * 1000, 2)
        p_best = seleccionar_placa_principal(placas)

        if p_best and p_best.get("texto"):
            return {
                "placa": p_best["texto"],
                "confianza": float(p_best["conf_ocr"] or 0.0),
                "formato_placa": str(p_best.get("formato_tipo", "INT-GLOBAL")),
                "latencia_ms": latencia_ms,
                "bbox": [int(c) for c in p_best["box"]],
                "placas": placas,
            }

        return {
            "placa": "SIN_PLACA",
            "confianza": 0.0,
            "formato_placa": "ILEGIBLE" if p_best else "SIN_PLACA",
            "latencia_ms": latencia_ms,
            "bbox": [int(c) for c in p_best["box"]] if p_best else None,
            "placas": placas,
        }

    def health_info(self) -> Dict[str, Any]:
        return {
            "cuda_available": self.cuda_available,
            "device": self.device_name,
            "onnx_providers": self.onnx_providers,
            "ocr_backend": self.ocr_backend,
            "models": {
                "m1_detector": self.sesion_m1 is not None,
                "m1_ocr": (self.lector_ocr is not None) or (self.ocr_raw_session is not None),
                "m2_segmentation": self.m2 is not None,
                "m3_keypoints": self.m3 is not None,
                "m4_passengers": self.m4 is not None,
            },
        }

