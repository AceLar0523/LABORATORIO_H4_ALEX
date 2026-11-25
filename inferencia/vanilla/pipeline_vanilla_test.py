import json
import os
import re
import sys
from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
from fast_plate_ocr import LicensePlateRecognizer
from ultralytics import YOLO

BASE_DIR = Path(__file__).resolve().parent
MODELO_DIR = BASE_DIR / "modelo"

# Pesos de los 3 módulos
M1_DET_PATH = MODELO_DIR / "yolo-v9-t-384-license-plates-end2end.onnx"
M1_OCR_PATH = MODELO_DIR / "cct_xs_v2_global.onnx"
M1_CFG_PATH = MODELO_DIR / "cct_xs_v2_global_plate_config.yaml"
M2_PATH = BASE_DIR / "m2_vehiculos.pt"
M3_PATH = BASE_DIR / "m3_llantas.pt"

# Parámetros M1 (detector.py)
LADO_M1 = 384
FORMATO_BOLIVIA = re.compile(r"^\d{3,4}[A-Z]{3}$")

# Parámetros M3 (asociación y ejes)
UMBRAL_CONTENCION = 0.70
UMBRAL_CERCANA = 0.65
SEPARACION_EJE = 0.60
EXTS_VALIDAS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def crear_carpeta_prueba(base_dir: Path) -> Path:
    max_idx = 0
    for item in base_dir.iterdir():
        if item.is_dir():
            m = re.fullmatch(r"prueba_peaje_(\d+)", item.name)
            if m:
                max_idx = max(max_idx, int(m.group(1)))
    nueva = base_dir / f"prueba_peaje_{max_idx + 1}"
    nueva.mkdir(parents=True, exist_ok=False)
    return nueva


def seleccionar_imagenes_interactivo():
    try:
        import tkinter as tk
        from tkinter import filedialog

        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        rutas = filedialog.askopenfilenames(
            title="Selecciona una o varias imágenes de vehículos (Pipeline Peaje M1+M2+M3)",
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

    entrada = input(
        "Pega una o varias rutas de imágenes (o una carpeta) separadas por espacio y presiona Enter: "
    ).strip()
    if not entrada:
        return []
    return [p.strip("'\"") for p in entrada.split()]


def recolectar_imagenes(args):
    rutas_raw = args if args else seleccionar_imagenes_interactivo()
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


# ===================== M1: Detección de Placas + OCR =====================
def limpiar_texto_placa(texto: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", texto.upper())


def detectar_y_leer_placas(img_bgr, sesion_m1, lector_ocr, umbral=0.35):
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
    salida = sesion_m1.run(None, {sesion_m1.get_inputs()[0].name: entrada})[0]

    placas = []
    for _, x1, y1, x2, y2, _, conf in salida:
        if conf < umbral:
            continue
        x1 = int(max(0, (x1 - margen_x) / escala))
        x2 = int(min(ancho, (x2 - margen_x) / escala))
        y1 = int(max(0, (y1 - margen_y) / escala))
        y2 = int(min(alto, (y2 - margen_y) / escala))
        if x2 <= x1 or y2 <= y1:
            continue

        recorte_rgb = cv2.cvtColor(img_bgr[y1:y2, x1:x2], cv2.COLOR_BGR2RGB)
        pred = lector_ocr.run_one(recorte_rgb, return_confidence=True)
        texto = limpiar_texto_placa(pred.plate)
        conf_ocr = float(pred.char_probs.mean()) if pred.char_probs is not None else None

        placas.append(
            {
                "box": [x1, y1, x2, y2],
                "texto": texto,
                "formato_bolivia": bool(FORMATO_BOLIVIA.match(texto)),
                "conf_det": round(float(conf), 3),
                "conf_ocr": None if conf_ocr is None else round(conf_ocr, 3),
                "vehiculo": None,
            }
        )
    return placas


# ===================== M3: Llantas + Conteo de Ejes =====================
def altura_visible(llanta):
    return max(1.0, float(llanta["kps"][1, 1] - llanta["kps"][2, 1]))


def contenida(a, b):
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    area = max(1e-6, (a[2] - a[0]) * (a[3] - a[1]))
    return inter / area


def limpiar_llantas(llantas):
    orden = sorted(
        llantas,
        key=lambda l: (l["box"][2] - l["box"][0]) * (l["box"][3] - l["box"][1]),
    )
    res = []
    for l in orden:
        if all(contenida(l["box"], r["box"]) < UMBRAL_CONTENCION for r in res):
            res.append(l)
    return res


def analizar_ejes(v, ls):
    if not ls:
        return None, "", "Sin llantas detectadas"

    hmax = max(altura_visible(l) for l in ls)
    cercanas = [l for l in ls if altura_visible(l) >= UMBRAL_CERCANA * hmax]

    # Filtrar llanta de repuesto colgada atrás en vehículos livianos
    if v["clase"] in {"auto", "minibus"} and len(cercanas) >= 3:
        ys_contacto = sorted(float(l["kps"][1, 1]) for l in cercanas)
        linea_suelo = float(np.median(ys_contacto[-2:]))
        en_suelo = [l for l in cercanas if float(l["kps"][1, 1]) >= linea_suelo - 0.85 * hmax]
        if len(en_suelo) >= 2:
            cercanas = en_suelo

    x1, y1, x2, y2 = v["box"]
    proporcion = (x2 - x1) / max(1.0, y2 - y1)

    # Vista frontal/posterior pura: 2 ruedas angostas a la misma altura y sin tercera rueda lateral
    if len(ls) == 2 and len(cercanas) == 2 and proporcion < 1.6:
        a, b = cercanas
        angostas = all(((l["kps"][4, 0] - l["kps"][3, 0]) / altura_visible(l)) < 0.65 for l in cercanas)
        misma_altura = abs(a["kps"][1, 1] - b["kps"][1, 1]) < 0.15 * hmax
        if angostas and misma_altura:
            return None, "frontal/posterior", "No determinable en esta vista"

    xs = sorted(float(l["kps"][0, 0]) for l in cercanas)
    diam = float(np.median([altura_visible(l) for l in cercanas]))
    ejes = 1 + sum(1 for p, q in zip(xs, xs[1:]) if (q - p) > SEPARACION_EJE * diam)
    redondez = float(np.median([(l["kps"][4, 0] - l["kps"][3, 0]) / altura_visible(l) for l in cercanas]))
    vista = "lateral" if redondez > 0.8 else "3/4"
    nota = ""
    if ejes < 2:
        ejes, nota = 2, "Mínimo asumido (solo se detectó 1 eje)"
    return ejes, vista, nota


# ===================== Fusión M1 + M2 + M3 =====================
def asociar_todo(vehiculos, llantas, placas):
    llantas = limpiar_llantas(llantas)
    for v in vehiculos:
        v["llantas"] = []
        v["placas"] = []

    # 1. Asociar llantas (M3) -> vehículo (M2)
    for i, l in enumerate(llantas):
        cx, cy = float(l["kps"][0, 0]), float(l["kps"][0, 1])
        l["vehiculo"] = None
        mejor, area_min = None, None
        for j, v in enumerate(vehiculos):
            x1, y1, x2, y2 = v["box"]
            w, h = x2 - x1, y2 - y1
            # Exige que el centro de la rueda esté en la mitad inferior (evita falsos positivos en faros altos)
            if (x1 - 0.05 * w) <= cx <= (x2 + 0.05 * w) and (y1 + 0.45 * h) <= cy <= (y2 + 0.10 * h):
                area = w * h
                if area_min is None or area < area_min:
                    mejor, area_min = j, area
        if mejor is not None:
            vehiculos[mejor]["llantas"].append(i)
            l["vehiculo"] = mejor

    for v in vehiculos:
        v["ejes"], v["vista"], v["nota"] = analizar_ejes(v, [llantas[i] for i in v["llantas"]])

    # 2. Asociar placas (M1) -> vehículo (M2) por contención máxima
    for k, p in enumerate(placas):
        mejor_v, mejor_score = None, 0.0
        for j, v in enumerate(vehiculos):
            score = contenida(p["box"], v["box"])
            if score > 0.5 and score > mejor_score:
                mejor_v, mejor_score = j, score
        if mejor_v is not None:
            vehiculos[mejor_v]["placas"].append(p)
            p["vehiculo"] = mejor_v

    return vehiculos, llantas, placas


def procesar_imagen(
    img_path,
    sesion_m1,
    lector_ocr,
    m2,
    m3,
    carpeta_salida: Path,
    conf_veh=0.38,
    conf_kp=0.20,
    conf_placa=0.35,
):
    img = cv2.imread(img_path)
    if img is None:
        return [f"[ERROR] No se pudo leer: {img_path}"], None

    # M2: Vehículos
    r2 = m2.predict(img, conf=conf_veh, imgsz=640, verbose=False)[0]
    vehiculos = []
    if len(r2.boxes):
        for cls_id, conf, box in zip(
            r2.boxes.cls.cpu().numpy().astype(int),
            r2.boxes.conf.cpu().numpy(),
            r2.boxes.xyxy.cpu().numpy(),
        ):
            vehiculos.append(
                {
                    "clase": r2.names[cls_id],
                    "conf": round(float(conf), 3),
                    "box": [round(float(c), 1) for c in box.tolist()],
                }
            )

    # M3: Llantas / Keypoints
    r3 = m3.predict(img, conf=conf_kp, imgsz=640, verbose=False)[0]
    llantas = []
    if r3.keypoints is not None and len(r3.boxes):
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
            llantas.append(
                {
                    "conf": float(conf),
                    "box": box.tolist(),
                    "kps": kps,
                }
            )

    # M1: Placas + OCR
    placas = detectar_y_leer_placas(img, sesion_m1, lector_ocr, umbral=conf_placa)

    # Fusión completa
    vehiculos, llantas, placas = asociar_todo(vehiculos, llantas, placas)

    vis = img.copy()
    lineas_log = [f"Imagen: {Path(img_path).name}"]

    if not vehiculos:
        lineas_log.append(f"  Sin vehículos detectados (conf >= {conf_veh})")

    for idx, v in enumerate(vehiculos, start=1):
        x1, y1, x2, y2 = map(int, v["box"])
        ejes_txt = "N/D" if v["ejes"] is None else str(v["ejes"])
        if v["placas"]:
            p_principal = max(v["placas"], key=lambda x: x["conf_det"])
            placa_txt = p_principal["texto"] or "?"
            bol_txt = "BO-OK" if p_principal["formato_bolivia"] else "NO-BO"
            placa_log = f"{placa_txt} ({bol_txt}, ocr={p_principal['conf_ocr']})"
        else:
            placa_txt = "SIN PLACA"
            placa_log = "Sin placa"

        label = f"#{idx} {v['clase']} ({v['conf']:.2f}) | ejes:{ejes_txt} | {placa_txt}"
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
            f"placa={placa_log} | llantas={len(v['llantas'])} vista={v['vista']} ejes={ejes_txt} {v['nota']}".rstrip()
        )
        lineas_log.append(detalle)

    # Dibujar cajas de placas (verde) y keypoints de llantas (verde brillante)
    for p in placas:
        px1, py1, px2, py2 = map(int, p["box"])
        cv2.rectangle(vis, (px1, py1), (px2, py2), (0, 230, 0), 2)
        if p["vehiculo"] is None:
            cv2.putText(
                vis,
                p["texto"] or "?",
                (px1, max(20, py1 - 6)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 230, 0),
                2,
                cv2.LINE_AA,
            )
            lineas_log.append(f"  [Placa suelta]: {p['texto']} (det={p['conf_det']}, ocr={p['conf_ocr']})")

    for l in llantas:
        for x, y, c in l["kps"]:
            if c > 0.05:
                cv2.circle(vis, (int(x), int(y)), 4, (50, 255, 50), -1)

    nombre_salida = f"res_{Path(img_path).stem}.jpg"
    cv2.imwrite(str(carpeta_salida / nombre_salida), vis)

    registro_json = {
        "imagen": Path(img_path).name,
        "vehiculos": [
            {
                "id": idx,
                "clase": v["clase"],
                "conf": v["conf"],
                "box": v["box"],
                "ejes": v["ejes"],
                "vista": v["vista"],
                "llantas_visibles": len(v["llantas"]),
                "placas": [
                    {
                        "texto": p["texto"],
                        "formato_bolivia": p["formato_bolivia"],
                        "conf_det": p["conf_det"],
                        "conf_ocr": p["conf_ocr"],
                        "box": p["box"],
                    }
                    for p in v["placas"]
                ],
            }
            for idx, v in enumerate(vehiculos, start=1)
        ],
    }
    return lineas_log, registro_json


def run_batch(imagenes, conf_veh=0.38, conf_kp=0.20, conf_placa=0.35):
    if not imagenes:
        print("No se seleccionaron imágenes válidas.")
        return

    for ruta in (M1_DET_PATH, M1_OCR_PATH, M1_CFG_PATH, M2_PATH, M3_PATH):
        if not ruta.exists():
            raise FileNotFoundError(f"Falta archivo de modelo requerido: {ruta}")

    carpeta_salida = crear_carpeta_prueba(BASE_DIR)
    print(f"Cargando M1 (ONNX+OCR), M2 (YOLO-seg) y M3 (YOLO-pose)...\nResultados en: {carpeta_salida}\n")

    sesion_m1 = ort.InferenceSession(str(M1_DET_PATH), providers=["CPUExecutionProvider"])
    lector_ocr = LicensePlateRecognizer(
        onnx_model_path=M1_OCR_PATH,
        plate_config_path=M1_CFG_PATH,
    )
    m2 = YOLO(str(M2_PATH))
    m3 = YOLO(str(M3_PATH))

    resumen_total = []
    resultados_json = []
    for img_path in imagenes:
        lineas, reg = procesar_imagen(
            img_path,
            sesion_m1,
            lector_ocr,
            m2,
            m3,
            carpeta_salida,
            conf_veh=conf_veh,
            conf_kp=conf_kp,
            conf_placa=conf_placa,
        )
        bloque = "\n".join(lineas)
        print(bloque)
        print("-" * 70)
        resumen_total.append(bloque)
        if reg is not None:
            resultados_json.append(reg)

    (carpeta_salida / "resumen.txt").write_text("\n\n".join(resumen_total), encoding="utf-8")
    (carpeta_salida / "resultados.json").write_text(
        json.dumps(resultados_json, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"\nListo: {len(imagenes)} imagen(es) procesada(s) en {carpeta_salida}")


if __name__ == "__main__":
    imgs = recolectar_imagenes(sys.argv[1:])
    run_batch(imgs)
    