# Notebooks de Entrenamiento (Google Colab + Roboflow)

Coloca en esta carpeta los notebooks `.ipynb` ejecutados en **Google Colab** antes de la entrega final para cumplir con la estructura de la Sección 7.1 de los requerimientos:

- `M2_vehiculos_seg.ipynb`: Entrenamiento de segmentación de instancias de vehículos (`moto`, `auto`, `minibus`, `camion`, `bus`, `trailer`) a partir del dataset etiquetado en Roboflow (`pesos/m2_vehiculos.pt`).
- `M3_llantas_pose.ipynb`: Entrenamiento de keypoints sobre ruedas para estimación de ejes (`pesos/m3_llantas.pt`).
- `M4_pasajeros_eval.ipynb`: Validación / ajuste de segmentación de pasajeros en cabina (`pesos/m4_pasajeros_seg.pt`).

Recuerda exportar los resultados y métricas reales (`mAP50`, `mAP50-95`, matriz de confusión, error de conteo de ejes y precisión de OCR) e incluirlos en [docs/informe_tecnico.md](file:///home/alele/Documentos/peaje-inteligente/docs/informe_tecnico.md) y en el PDF de la carpeta en Drive.

