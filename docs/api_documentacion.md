# Documentación de la API REST - Sistema Inteligente de Control de Peaje

**Versión de la API:** `v1`  
**Base URL Producción:** `https://peaje.tudominio.com/api/v1` *(reemplazar por tu subdominio HTTPS final)*  
**Formato de Intercambio:** `JSON` (peticiones y respuestas)  
**Mecanismo de Autenticación:** `Bearer Token` (Laravel Sanctum) obtenido tras validar el `id_token` de Google OAuth 2.0 contra Google y la lista blanca en BD.

---

## 1. Autenticación (Google OAuth 2.0)

### Obtener Configuración Pública de Google OAuth
* **Método:** `GET`
* **Ruta:** `/auth/config`
* **Acceso:** Público.
* **Descripción:** Devuelve `google_client_id`, `google_android_client_id` y `google_oauth_enabled`.

### Iniciar Sesión con Google
* **Método:** `POST`
* **Ruta:** `/auth/google`
* **Acceso:** Público (única ruta de autenticación del sistema).
* **Descripción:** Recibe el `id_token` JWT emitido por Google Sign-In desde la aplicación web o móvil, lo verifica contra Google (`tokeninfo`), valida el correo contra la **lista blanca** en la base de datos y genera el token de sesión Sanctum.

#### Cuerpo de la Petición (Request Body)
```json
{
  "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI..."
}
```

#### Respuesta Exitosa (HTTP 200 OK)
```json
{
  "success": true,
  "token": "1|LfTh1H3CbZfVQpPEBMSzp3W97umM8l3JPwm5MYZQ5f20d204",
  "usuario": {
    "id": 1,
    "nombre": "Docente Evaluador",
    "email_google": "docente@peaje.edu",
    "rol": "administrador",
    "activo": true
  }
}
```

#### Respuesta de Acceso Denegado (HTTP 403 Forbidden)
```json
{
  "success": false,
  "message": "Acceso denegado. La cuenta de Google no se encuentra en la lista blanca de usuarios autorizados."
}
```

---

## 2. Registro de Tránsito y Pasos en Caseta

### Registrar Frame de Video en Caseta
* **Método:** `POST`
* **Ruta:** `/pasos/frame`
* **Autenticación:** Requerida (`Bearer Token`).
* **Descripción:** Recibe el frame o fotografía capturada por la aplicación móvil en la caseta. Guarda la evidencia, invoca al motor de inferencia en la nube (`/predict`), procesa la tarifa según la categoría y los ejes, evalúa el saldo y emite de inmediato el evento en tiempo real.

#### Cuerpo de la Petición (Multipart o JSON Base64)
```json
{
  "frame_base64": "data:image/jpeg;base64,/9j/4AAQSkZJRg...",
  "caseta_id": 1
}
```

#### Respuesta Exitosa (HTTP 201 Created)
```json
{
  "success": true,
  "paso": {
    "id": 42,
    "placa_leida": "4021-XYZ",
    "placa_normalizada": "4021XYZ",
    "confianza_ocr": "0.95",
    "categoria_detectada": "auto",
    "ejes_detectados": 2,
    "monto": "10.00",
    "caseta_id": 1,
    "usuario_id": 2,
    "imagen_url": "/storage/evidencias/evidencia_1732468900_a1b2c3.jpg",
    "estado": "Registrada y con paso",
    "pasajeros": 2,
    "created_at": "2026-11-24T19:26:10.000000Z"
  },
  "vehiculo": {
    "id": 1,
    "placa": "4021XYZ",
    "propietario": "Carlos Mendoza",
    "categoria": "auto",
    "ejes": 2,
    "saldo": "110.00"
  },
  "latencia_ms": 68.4,
  "alerta": null
}
```

---

## 3. Consultas de Placas

### Consultar Placa por Texto
* **Método:** `POST`
* **Ruta:** `/placas/consultar`
* **Autenticación:** Requerida (`Bearer Token`).
* **Descripción:** Consulta una placa por texto normalizado y devuelve su condición en el sistema y sugerencias en caso de inconsistencia.

#### Cuerpo de la Petición
```json
{
  "placa": "4021-XYZ"
}
```

#### Respuesta Exitosa (HTTP 200 OK)
```json
{
  "success": true,
  "data": {
    "estado": "Registrada y con paso",
    "vehiculo": {
      "id": 1,
      "placa": "4021XYZ",
      "propietario": "Carlos Mendoza",
      "categoria": "auto",
      "ejes": 2,
      "saldo": "120.00"
    },
    "ultimo_paso": {
      "fecha": "2026-11-24 19:26:10",
      "caseta": "Caseta Principal Norte",
      "categoria": "auto",
      "ejes": 2,
      "monto": "10.00",
      "imagen_url": "/storage/evidencias/ejemplo_4021XYZ.jpg"
    },
    "total_pasos": 5,
    "sugerencias": []
  }
}
```

### Consultar Placa por Imagen (M1 + OCR)
* **Método:** `POST`
* **Ruta:** `/placas/consultar-imagen`
* **Autenticación:** Requerida (`Bearer Token`).
* **Descripción:** Extrae la placa de una fotografía mediante el modelo M1 y el OCR, y reporta su estado.

#### Cuerpo de la Petición
```json
{
  "imagen_base64": "data:image/jpeg;base64,/9j/4AAQSk..."
}
```

---

## 4. Historial y Resúmenes

### Historial de Pasos por Placa
* **Método:** `GET`
* **Ruta:** `/placas/{placa}/historial`
* **Autenticación:** Requerida (`Bearer Token`).

### Resumen del Día por Caseta
* **Método:** `GET`
* **Ruta:** `/casetas/{id}/resumen`
* **Autenticación:** Requerida (`Bearer Token`).
* **Respuesta:** Conteo de tránsitos del día, recaudación monetaria acumulada y ubicación de la caseta.

---

## 5. Agente Conversacional

### Enviar Mensaje al Agente (Chat)
* **Método:** `POST`
* **Ruta:** `/agente/chat`
* **Autenticación:** Requerida (`Bearer Token`).
* **Descripción:** Agente conversacional que atiende consultas de placas en lenguaje natural o mediante fotografías adjuntas.

#### Cuerpo de la Petición (Consulta por Texto)
```json
{
  "mensaje": "Quisiera conocer el estado del vehículo con placa 4021XYZ"
}
```

#### Respuesta Exitosa
```json
{
  "success": true,
  "respuesta": "✅ **Estado: Registrada y con paso**\n• **Placa:** 4021XYZ\n• **Propietario:** Carlos Mendoza\n• **Categoría:** auto (2 ejes)\n• **Saldo actual:** Bs. 120.00\n• **Último paso registrado:** 2026-11-24 19:26:10 en Caseta Principal Norte (Tarifa cobrada: Bs. 10.00).\n• **Total de tránsitos:** 1",
  "estado": "Registrada y con paso",
  "data": { ... }
}
```

#### Respuesta con Sugerencia OCR (Confusión de Caracteres)
```json
{
  "success": true,
  "respuesta": "🚫 **Estado: No existe**\nNo existe ningún registro ni paso asociado a la placa **4021XYW** en el sistema.\n\n💡 ¿Quisiste decir alguna de estas placas registradas?: `4021XYZ`",
  "estado": "No existe"
}
```

---

## 6. Monitoreo, Administración (Rol Administrador) y Tiempo Real

### Servidor de Eventos en Tiempo Real (SSE)
* **Método:** `GET`
* **Ruta:** `/stream/eventos?token={BEARER_TOKEN}`
* **Autenticación:** Requerida (`Bearer Token` en cabecera o query `token`, compatible con `EventSource`). Soporta `Last-Event-ID`.
* **Content-Type:** `text/event-stream`
* **Descripción:** Transmite en tiempo real eventos `nuevo_paso` y `nueva_alerta` al panel web sin recarga.

### Gestión de Vehículos, Tarifas, Casetas y Usuarios (Solo Administrador)
* `GET /vehiculos`, `POST /vehiculos`, `PUT /vehiculos/{id}`, `DELETE /vehiculos/{id}` (mutaciones restringidas a `rol=administrador`).
* `GET /tarifas`, `POST /tarifas`, `PUT /tarifas/{id}`, `DELETE /tarifas/{id}` (mutaciones restringidas a `rol=administrador`).
* `GET /casetas`, `POST /casetas`, `PUT /casetas/{id}`, `DELETE /casetas/{id}` (mutaciones restringidas a `rol=administrador`).
* `GET /usuarios`, `POST /usuarios`, `PUT /usuarios/{id}`, `PATCH /usuarios/{id}/estado`, `DELETE /usuarios/{id}` (mutaciones restringidas a `rol=administrador`).

### Estado de Conectividad con la Inferencia
* **Método:** `GET`
* **Ruta:** `/estado/inferencia`
* **Autenticación:** Requerida (`Bearer Token`).
* **Respuesta:** Verifica si el endpoint en RunPod / Colab y Ollama responden, indicando latencia del ping y salud de los modelos M1, M2, M3, M4 y LLM.

