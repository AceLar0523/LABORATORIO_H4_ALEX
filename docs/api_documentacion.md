# Documentación de la API REST - Sistema Inteligente de Control de Peaje

**Versión de la API:** `v1`  
**Base URL Producción:** `https://peaje.tudominio.com/api/v1`  
**Base URL Local / Pruebas:** `http://localhost:8000/api/v1`  
**Formato de Intercambio:** `JSON` (peticiones y respuestas)  
**Mecanismo de Autenticación:** `Bearer Token` (Laravel Sanctum) obtenido tras validar con Google OAuth 2.0.

---

## 1. Autenticación (Google OAuth 2.0)

### Iniciar Sesión con Google
* **Método:** `POST`
* **Ruta:** `/auth/google`
* **Acceso:** Público (única ruta pública del sistema).
* **Descripción:** Recibe el token emitido por Google Sign-In desde la aplicación web o móvil, valida el correo contra la **lista blanca** en la base de datos y genera el token de sesión.

#### Cuerpo de la Petición (Request Body)
```json
{
  "email": "docente@peaje.edu",
  "name": "Docente Evaluador",
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

## 6. Monitoreo y Tiempo Real

### Servidor de Eventos en Tiempo Real (SSE)
* **Método:** `GET`
* **Ruta:** `/stream/eventos`
* **Content-Type:** `text/event-stream`
* **Descripción:** Transmite en tiempo real eventos `nuevo_paso` y `nueva_alerta` al panel web sin recarga.

### Estado de Conectividad con la Inferencia
* **Método:** `GET`
* **Ruta:** `/estado/inferencia`
* **Respuesta:** Verifica si el endpoint en RunPod / Colab responde, indicando latencia del ping y salud de los 3 modelos.

