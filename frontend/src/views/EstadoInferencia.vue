<template>
  <div class="max-w-2xl mx-auto space-y-5">
    <div class="pb-2 border-b border-slate-200">
      <h1 class="text-xl font-bold text-slate-900 tracking-tight">Estado de la Infraestructura en la Nube</h1>
      <p class="text-xs text-slate-500 mt-0.5">Diagnóstico en tiempo real de conectividad con RunPod GPU, modelos M1/M2/M3 y Ollama</p>
    </div>

    <div class="bg-white border border-slate-200/90 rounded-2xl p-6 shadow-xs space-y-6">
      <!-- Estado General -->
      <div class="flex items-center justify-between pb-5 border-b border-slate-100">
        <div>
          <span class="text-[10px] uppercase text-slate-400 font-bold tracking-wider">Estado del Endpoint de Visión</span>
          <div class="flex items-center gap-2 mt-1">
            <span
              class="w-2.5 h-2.5 rounded-full"
              :class="info.status === 'online' ? 'bg-emerald-500 animate-pulse' : 'bg-rose-500'"
            ></span>
            <h2
              class="text-base font-bold tracking-tight"
              :class="info.status === 'online' ? 'text-emerald-700' : 'text-rose-600'"
            >
              {{ info.status === 'online' ? 'En Línea (Conectado)' : 'Desconectado (No se detecta servidor activo)' }}
            </h2>
          </div>
        </div>
        <button
          @click="verificar"
          :disabled="verificando"
          class="bg-slate-900 hover:bg-slate-800 active:scale-95 text-white text-xs font-semibold py-2 px-3.5 rounded-xl transition-all cursor-pointer flex items-center gap-1.5 disabled:opacity-50"
        >
          <svg class="w-3.5 h-3.5" :class="{ 'animate-spin': verificando }" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          <span>{{ verificando ? 'Verificando...' : 'Comprobar Conexión' }}</span>
        </button>
      </div>

      <!-- Tarjetas de Métricas de Red -->
      <div class="grid grid-cols-2 gap-3.5 text-xs">
        <div class="bg-slate-50 p-3.5 rounded-xl border border-slate-100">
          <span class="text-slate-400 block text-[10px] font-semibold uppercase">URL Endpoint Inferencia</span>
          <span class="font-mono text-slate-800 text-xs mt-1 block truncate">{{ info.url }}</span>
        </div>
        <div class="bg-slate-50 p-3.5 rounded-xl border border-slate-100">
          <span class="text-slate-400 block text-[10px] font-semibold uppercase">Latencia de Respuesta</span>
          <span class="font-bold text-slate-900 text-sm mt-1 block">
            {{ info.status === 'online' ? `${info.latencia_ms} ms` : 'Sin respuesta (Timeout)' }}
          </span>
        </div>
      </div>

      <!-- Estado individual de cada modelo -->
      <div>
        <h3 class="text-xs font-bold text-slate-900 uppercase tracking-wider mb-3">Diagnóstico de Modelos (M1, M2, M3 & LLM)</h3>
        <div class="space-y-2.5 text-xs">
          <!-- M1 -->
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 border border-slate-100">
            <div>
              <span class="text-slate-800 font-semibold block">M1: Detección de Placas (YOLOv9) + OCR CCT</span>
              <span class="text-[10px] text-slate-400">Localiza placa y decodifica caracteres</span>
            </div>
            <span
              class="text-[10px] px-2.5 py-1 rounded-md font-bold"
              :class="info.modelos?.m1_detector && info.modelos?.m1_ocr
                ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                : 'bg-rose-50 text-rose-700 border border-rose-200'"
            >
              {{ info.modelos?.m1_detector && info.modelos?.m1_ocr ? 'Operativo' : 'Inactivo' }}
            </span>
          </div>

          <!-- M2 -->
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 border border-slate-100">
            <div>
              <span class="text-slate-800 font-semibold block">M2: Segmentación de Vehículos (YOLO-seg)</span>
              <span class="text-[10px] text-slate-400">m2_vehiculos.pt (categoría → tarifa)</span>
            </div>
            <span
              class="text-[10px] px-2.5 py-1 rounded-md font-bold"
              :class="info.modelos?.m2_segmentation
                ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                : 'bg-rose-50 text-rose-700 border border-rose-200'"
            >
              {{ info.modelos?.m2_segmentation ? 'Operativo' : 'Inactivo' }}
            </span>
          </div>

          <!-- M3 -->
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 border border-slate-100">
            <div>
              <span class="text-slate-800 font-semibold block">M3: Keypoints de Ruedas (YOLO-pose)</span>
              <span class="text-[10px] text-slate-400">m3_llantas.pt (conteo de ejes)</span>
            </div>
            <span
              class="text-[10px] px-2.5 py-1 rounded-md font-bold"
              :class="info.modelos?.m3_keypoints
                ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                : 'bg-rose-50 text-rose-700 border border-rose-200'"
            >
              {{ info.modelos?.m3_keypoints ? 'Operativo' : 'Inactivo' }}
            </span>
          </div>

          <!-- M4: Pasajeros -->
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 border border-slate-100">
            <div>
              <span class="text-slate-800 font-semibold block">M4: Segmentación de Pasajeros (YOLO-seg)</span>
              <span class="text-[10px] text-slate-400">m4_pasajeros_seg.pt (conteo de ocupantes por cabina)</span>
            </div>
            <span
              class="text-[10px] px-2.5 py-1 rounded-md font-bold"
              :class="info.modelos?.m4_passengers
                ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                : 'bg-rose-50 text-rose-700 border border-rose-200'"
            >
              {{ info.modelos?.m4_passengers ? 'Operativo' : 'Inactivo' }}
            </span>
          </div>

          <!-- Ollama LLM -->
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 border border-slate-100 gap-3">
            <div>
              <span class="text-slate-800 font-semibold block">
                Ollama LLM ({{ info.ollama_models?.length ? info.ollama_models.join(', ') : 'llama3.2:3b' }})
              </span>
              <span
                v-if="info.ollama_status === 'sin_modelo'"
                class="text-[10px] text-amber-700 font-medium block mt-0.5"
              >
                Conectado a RunPod, sin modelo descargado — ejecuta: <code class="font-mono">ollama pull llama3.2:3b</code>
              </span>
              <span v-else class="text-[10px] text-slate-400">
                Agente Conversacional (RunPod){{ info.detalles?.device ? ` • ${info.detalles.device}` : '' }}
              </span>
            </div>
            <span
              class="text-[10px] px-2.5 py-1 rounded-md font-bold shrink-0"
              :class="info.ollama_status === 'online'
                ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                : info.ollama_status === 'sin_modelo'
                  ? 'bg-amber-50 text-amber-800 border border-amber-200'
                  : 'bg-rose-50 text-rose-700 border border-rose-200'"
            >
              {{ info.ollama_status === 'online' ? 'Operativo' : info.ollama_status === 'sin_modelo' ? 'Sin modelo' : 'Inactivo' }}
            </span>
          </div>

          <!-- Base de datos -->
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-50 border border-slate-100">
            <div>
              <span class="text-slate-800 font-semibold block">Base de Datos Relacional</span>
              <span class="text-[10px] text-slate-400">Padrón vehicular, pasos y lista blanca Google OAuth</span>
            </div>
            <span class="text-[10px] px-2.5 py-1 rounded-md bg-emerald-50 text-emerald-800 border border-emerald-200 font-bold">
              Conectado ({{ info.vehiculos_registrados ?? 0 }} vehículos • {{ info.usuarios_autorizados ?? 0 }} usuarios OAuth)
            </span>
          </div>
        </div>
      </div>
    </div>

    <!-- Análisis Manual de Vehículo por Fotografía -->
    <div class="bg-white border border-slate-200/90 rounded-2xl p-6 shadow-xs space-y-4">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-3 border-b border-slate-100">
        <div>
          <h3 class="text-sm font-bold text-slate-900 tracking-tight">Análisis Manual de Vehículo por Fotografía</h3>
          <p class="text-xs text-slate-500 mt-0.5">Carga una imagen para ejecutar detección en RunPod (M1, M2, M3 y M4)</p>
        </div>
        <label class="bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 active:scale-95 text-white text-xs font-semibold py-2 px-3.5 rounded-xl transition-all cursor-pointer flex items-center justify-center gap-1.5 shadow-xs shrink-0">
          <input type="file" accept="image/*" class="hidden" @change="onFotoSeleccionada" />
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
          <span>Subir Fotografía</span>
        </label>
      </div>

      <!-- Si aún no ha seleccionado foto -->
      <div
        v-if="!fotoPreview"
        class="border-2 border-dashed border-slate-200 rounded-2xl p-8 text-center bg-slate-50/60 hover:bg-slate-50 transition-colors"
      >
        <label class="cursor-pointer block">
          <input type="file" accept="image/*" class="hidden" @change="onFotoSeleccionada" />
          <div class="w-12 h-12 mx-auto mb-3 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center border border-blue-100 shadow-2xs">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
            </svg>
          </div>
          <span class="text-xs font-bold text-slate-800 block">Haz clic para buscar en tus carpetas</span>
          <span class="text-[11px] text-slate-400 block mt-1">Formatos admitidos: JPG, PNG, WEBP de vehículos o placas</span>
        </label>
      </div>

      <!-- Área de Previsualización y Resultados -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-4 pt-1">
        <!-- Imagen subida -->
        <div class="rounded-xl overflow-hidden border border-slate-200 bg-slate-100 relative max-h-[280px] flex items-center justify-center shadow-2xs">
          <img :src="fotoPreview" class="w-full h-full object-contain" />
          <button
            @click="quitarFoto"
            class="absolute top-2 right-2 bg-slate-900/80 hover:bg-slate-900 text-white rounded-lg px-2 py-1 text-[11px] font-semibold cursor-pointer shadow-sm transition"
          >
            ✕ Cambiar foto
          </button>
        </div>

        <!-- Resultados de la Inferencia -->
        <div class="space-y-3 flex flex-col justify-center">
          <div v-if="analizando" class="py-12 text-center text-xs text-slate-500 flex flex-col items-center gap-2.5">
            <span class="w-6 h-6 border-2 border-blue-600 border-t-transparent rounded-full animate-spin"></span>
            <span class="font-semibold text-slate-700">Analizando frame en RunPod (M1, M2, M3 y M4)...</span>
          </div>

          <div v-else-if="errorFoto" class="p-3.5 rounded-xl bg-rose-50 border border-rose-200 text-xs text-rose-800">
            <strong class="block font-semibold mb-1">No se pudo completar la inferencia en RunPod</strong>
            <span>{{ errorFoto }}</span>
          </div>

          <div v-else-if="resultadoFoto" class="space-y-2.5 text-xs">
            <!-- M1 -->
            <div class="p-3 rounded-xl bg-slate-50 border border-slate-200/80 flex items-center justify-between">
              <div>
                <span class="text-[10px] text-slate-400 font-bold uppercase tracking-wider block">M1: Placa de Matrícula</span>
                <span class="font-mono font-extrabold text-base text-blue-950">{{ resultadoFoto.placa }}</span>
              </div>
              <span class="text-[11px] font-bold text-emerald-800 bg-emerald-50 px-2.5 py-1 rounded-lg border border-emerald-200">
                OCR: {{ (resultadoFoto.confianza * 100).toFixed(0) }}%
              </span>
            </div>

            <!-- M2, M3, M4 en Cuadrícula -->
            <div class="grid grid-cols-3 gap-2">
              <div class="p-2.5 rounded-xl bg-slate-50 border border-slate-200/80 text-center">
                <span class="text-[9.5px] text-slate-400 block font-bold uppercase">M2 Categoría</span>
                <span class="font-bold text-slate-800 capitalize text-xs mt-0.5 block">{{ resultadoFoto.categoria }}</span>
              </div>
              <div class="p-2.5 rounded-xl bg-slate-50 border border-slate-200/80 text-center">
                <span class="text-[9.5px] text-slate-400 block font-bold uppercase">M3 Ejes</span>
                <span class="font-bold text-slate-800 text-xs mt-0.5 block">{{ resultadoFoto.ejes }} ejes</span>
              </div>
              <div class="p-2.5 rounded-xl bg-indigo-50 border border-indigo-200/80 text-center">
                <span class="text-[9.5px] text-indigo-700 block font-bold uppercase">M4 Pasajeros</span>
                <span class="font-bold text-indigo-900 text-xs mt-0.5 block">{{ resultadoFoto.pasajeros }} pers.</span>
              </div>
            </div>

            <!-- Latencia y Estado -->
            <div class="p-2.5 rounded-xl bg-emerald-50/70 border border-emerald-200 text-[11px] text-emerald-900 flex items-center justify-between font-medium">
              <span>✔ Inferencia ejecutada correctamente</span>
              <span class="font-mono font-bold">{{ resultadoFoto.latencia_ms }} ms</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const info = ref({
  status: 'checking',
  url: '',
  latencia_ms: 0,
  modelos: null,
  ollama_status: 'offline',
  ollama_models: [],
})
const verificando = ref(false)

const fotoPreview = ref(null)
const analizando = ref(false)
const resultadoFoto = ref(null)
const errorFoto = ref('')

function onFotoSeleccionada(e) {
  const file = e.target.files[0]
  if (!file) return

  const reader = new FileReader()
  reader.onload = (event) => {
    fotoPreview.value = event.target.result
    evaluarFoto(event.target.result)
  }
  reader.readAsDataURL(file)
}

function quitarFoto() {
  fotoPreview.value = null
  resultadoFoto.value = null
  errorFoto.value = ''
}

async function evaluarFoto(base64) {
  analizando.value = true
  resultadoFoto.value = null
  errorFoto.value = ''
  try {
    const res = await api.post('/pasos/frame', {
      frame_base64: base64,
      caseta_id: 1,
    })
    const p = res.data.paso
    resultadoFoto.value = {
      placa: p.placa_normalizada || p.placa_leida,
      confianza: Number(p.confianza_ocr ?? 0),
      categoria: p.categoria_detectada || 'auto',
      ejes: p.ejes_detectados ?? 2,
      pasajeros: p.pasajeros ?? 0,
      latencia_ms: res.data.latencia_ms ?? 0,
    }
  } catch (err) {
    errorFoto.value = err.response?.data?.message || 'Error conectando con el motor de inferencia en RunPod.'
  } finally {
    analizando.value = false
  }
}

async function verificar() {
  verificando.value = true
  try {
    const res = await api.get('/estado/inferencia')
    info.value = res.data
  } catch (err) {
    info.value = {
      status: 'offline',
      url: 'No configurado / Sin respuesta',
      latencia_ms: 0,
      modelos: {
        m1_detector: false,
        m1_ocr: false,
        m2_segmentation: false,
        m3_keypoints: false,
        m4_passengers: false,
      },
      ollama_status: 'offline',
      ollama_models: [],
    }
  } finally {
    verificando.value = false
  }
}

onMounted(verificar)
</script>
