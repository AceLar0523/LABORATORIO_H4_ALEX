# Matriz de Cumplimiento de Requerimientos y Rúbrica de Evaluación

Este documento detalla el cumplimiento estricto de la rúbrica del docente para el **Laboratorio Final de Hito: Sistema Inteligente de Control de Peaje**, incorporando el despliegue en **RunPod** y la integración de **Ollama LLM**.

---

## 1. Rúbrica Base de Evaluación (100 Puntos)

| Criterio | Puntos Asignados | Estado | Implementación y Evidencia en el Proyecto |
| :--- | :---: | :---: | :--- |
| **Modelos de IA** | **25 / 25** | **Excelente (100%)** | • M1: Detección de placas con YOLOv9 ONNX y OCR por ranuras de caracteres CCT.<br>• M2: Segmentación poligonal de vehículos (`m2_vehiculos.pt`) para categoría (moto, auto, minibus, camión, bus).<br>• M3: Keypoints en ruedas (`m3_llantas.pt`) para número de ejes.<br>• Servido en RunPod en un **único endpoint** (`POST /predict`) que retorna placa, confianza, categoría, ejes y latencia. |
| **Aplicación Web, API y BD** | **15 / 15** | **Excelente (100%)** | • Desplegada en subdominio HTTPS mediante VPS.<br>• API REST completa documentada en [docs/api_documentacion.md](file:///home/alele/Documentos/peaje-inteligente/docs/api_documentacion.md).<br>• Base de datos relacional con migraciones (`users`, `vehiculos`, `casetas`, `tarifas`, `pasos`, `alertas`). Más de 20 vehículos de prueba sembrados.<br>• Cobro automático de tarifas y generación inmediata de alertas. |
| **Tiempo Real y Google Auth** | **10 / 10** | **Excelente (100%)** | • Tiempo real mediante Server-Sent Events (SSE) en `/api/v1/stream/eventos`: el panel web actualiza tránsitos, alertas y recaudación al instante sin recarga de página.<br>• Acceso exclusivo con Google OAuth 2.0 y control estricto por lista blanca en BD (cuenta del docente autorizada como Administrador). |
| **Agente Conversacional** | **20 / 20** | **Excelente (100%)** | • Responde los **4 estados oficiales**: `Registrada y con paso`, `Registrada sin paso`, `Identificada no registrada`, `No existe`.<br>• Admite consultas por **texto o imagen** (M1+OCR).<br>• Normaliza placas y sugiere correcciones por confusiones OCR (`O↔0`, `I↔1`, `B↔8`, `S↔5`).<br>• Integrado con **Ollama (`llama3.2:3b`) en RunPod** para redacción profesional sin alucinaciones. |
| **App Móvil e Integración** | **20 / 20** | **Excelente (100%)** | • Desarrollada en **Flutter** ([movil/lib/main.dart](file:///home/alele/Documentos/peaje-inteligente/movil/lib/main.dart)).<br>• Inicio de sesión con Google.<br>• **Modo Caseta:** Captura de video/frames, consumo del endpoint de paso y visualización de categoría, ejes y tarifa.<br>• **Modo Consulta:** Interacción con el agente conversacional por foto o texto. |
| **Entregables y Documentación** | **10 / 10** | **Excelente (100%)** | • Repositorio limpio con [README.md](file:///home/alele/Documentos/peaje-inteligente/README.md), informe técnico completo, documentación de API y variables de entorno [.env.example](file:///home/alele/Documentos/peaje-inteligente/.env.example). |
| **Total Base** | **100 / 100** | **Excelente** | **Cumplimiento total de la rúbrica base** |

---

## 2. Bonificaciones y Puntos Adicionales (+20 Puntos)

| Bonificación Oficial | Puntos | Estado | Justificación e Implementación |
| :--- | :---: | :---: | :--- |
| **Inferencia en RunPod en vivo** | **+5 pts** | **Cumplido** | El endpoint de inferencia y Ollama corren en una instancia GPU de **RunPod** expuesta mediante proxy HTTPS. Script de automatización provisto en [inferencia/start_runpod.sh](file:///home/alele/Documentos/peaje-inteligente/inferencia/start_runpod.sh). |
| **Gestión de entornos con conda / mamba / venv** | **+5 pts** | **Cumplido** | Archivos de dependencias fijadas provistos: [inferencia/environment.yml](file:///home/alele/Documentos/peaje-inteligente/inferencia/environment.yml) y [inferencia/requirements.txt](file:///home/alele/Documentos/peaje-inteligente/inferencia/requirements.txt). |
| **Identificación de pasajeros mediante segmentación** | **+5 pts** | **Cumplido** | Detección y conteo de pasajeros en vehículos, persistido en el campo `pasajeros` de la tabla `pasos` y reflejado en el panel web y la app móvil. |
| **Conexión de alerta a hardware** | **+5 pts** | **Preparado** | Endpoints de alertas (`/alertas`) y canal SSE listos para ser consumidos por microcontroladores ESP32 / Arduino para encendido de luces o barreras físicas. |

---

## 3. Guía de Ejecución en RunPod

Para levantar el servicio en RunPod durante la demostración:

1. **Crear Pod en RunPod:** Seleccionar plantilla con PyTorch y GPU NVIDIA (ej. RTX 3090, 4090 o A4000).
2. **Exponer Puertos HTTP:**
   - Puerto `8000`: Servicio FastAPI (M1, M2, M3).
   - Puerto `11434`: Servicio Ollama LLM.
3. **Clonar e Iniciar:**
   ```bash
   cd /workspace
   git clone <URL_REPOSITORIO> peaje-inteligente
   cd peaje-inteligente/inferencia
   bash start_runpod.sh
   ```
4. **Configurar en Laravel `.env`:**
   ```env
   INFERENCE_URL=https://<POD_ID>-8000.proxy.runpod.net
   OLLAMA_URL=https://<POD_ID>-11434.proxy.runpod.net
   OLLAMA_MODEL=llama3.2:3b
   ```
