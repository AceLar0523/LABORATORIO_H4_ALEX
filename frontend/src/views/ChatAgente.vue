<template>
  <div class="max-w-5xl mx-auto p-4 md:p-6 h-[calc(100vh-5rem)] flex flex-col">
    <!-- Encabezado -->
    <div class="bg-white rounded-2xl border border-slate-200 p-4 mb-4 flex flex-wrap items-center justify-between gap-3 shadow-sm">
      <div>
        <h1 class="text-lg font-bold text-slate-900">Agente Conversacional Exclusivo de Peaje</h1>
        <p class="text-xs text-slate-500 mt-0.5">
          Análisis multi-imagen con modelos M1–M4 en RunPod, consulta de placas, tarifas, alertas y recaudación.
        </p>
      </div>

      <div class="flex items-center gap-3 text-xs">
        <span
          class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full font-medium border"
          :class="
            estadoVision === 'online'
              ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
              : 'bg-rose-50 text-rose-700 border-rose-200'
          "
        >
          <span
            class="w-2 h-2 rounded-full"
            :class="estadoVision === 'online' ? 'bg-emerald-500 animate-pulse' : 'bg-rose-500'"
          ></span>
          RunPod M1–M4: {{ estadoVision === 'online' ? 'En línea' : 'Offline' }}
        </span>
        <span
          class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full font-medium border"
          :class="
            estadoOllama === 'online'
              ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
              : estadoOllama === 'sin_modelo'
                ? 'bg-amber-50 text-amber-700 border-amber-200'
                : 'bg-rose-50 text-rose-700 border-rose-200'
          "
        >
          <span
            class="w-2 h-2 rounded-full"
            :class="{
              'bg-emerald-500 animate-pulse': estadoOllama === 'online',
              'bg-amber-500': estadoOllama === 'sin_modelo',
              'bg-rose-500': estadoOllama === 'offline'
            }"
          ></span>
          Ollama:
          {{
            estadoOllama === 'online'
              ? 'Activo'
              : estadoOllama === 'sin_modelo'
                ? 'Sin modelo cargado'
                : 'Offline'
          }}
        </span>
        <button
          @click="reiniciarConversacion"
          class="px-3 py-1.5 rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-100 active:scale-95 transition font-medium"
        >
          Nueva sesión
        </button>
      </div>
    </div>

    <!-- Chips de consulta rápida -->
    <div class="flex flex-wrap gap-2 mb-3">
      <button
        v-for="chip in chips"
        :key="chip.label"
        @click="usarChip(chip.prompt)"
        :disabled="cargando"
        class="text-xs px-3 py-1.5 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-100 active:scale-95 transition disabled:opacity-50"
      >
        {{ chip.label }}
      </button>
    </div>

    <!-- Área de conversación -->
    <div
      ref="areaScroll"
      class="flex-1 bg-white rounded-2xl border border-slate-200 p-4 overflow-y-auto shadow-sm"
    >
      <TransitionGroup name="msg-in" tag="div" class="space-y-4">
        <div
          v-for="(msg, index) in mensajes"
          :key="index"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[82%] rounded-2xl px-4 py-3 text-sm leading-relaxed shadow-xs"
            :class="
              msg.role === 'user'
                ? 'bg-slate-900 text-white rounded-br-sm'
                : msg.estado === 'Fuera de dominio'
                  ? 'bg-amber-50 text-amber-950 border border-amber-200 rounded-bl-sm'
                  : 'bg-slate-50 text-slate-800 border border-slate-200 rounded-bl-sm'
            "
          >
            <div v-if="msg.imagenes && msg.imagenes.length" class="flex flex-wrap gap-2 mb-2.5">
              <img
                v-for="(img, imgIdx) in msg.imagenes"
                :key="imgIdx"
                :src="img"
                alt="Imagen vehicular"
                class="w-24 h-24 object-cover rounded-xl border border-slate-600"
              />
            </div>
            <div class="whitespace-pre-wrap" v-html="formatearMarkdownBasico(msg.content)"></div>
          </div>
        </div>
      </TransitionGroup>

      <div v-if="cargando" class="flex justify-start mt-4">
        <div class="bg-slate-50 border border-slate-200 rounded-2xl px-4 py-3 text-sm text-slate-500 flex items-center gap-2.5">
          <span class="flex items-center gap-1">
            <span class="w-2 h-2 rounded-full bg-slate-500 animate-bounce [animation-delay:0ms]"></span>
            <span class="w-2 h-2 rounded-full bg-slate-500 animate-bounce [animation-delay:150ms]"></span>
            <span class="w-2 h-2 rounded-full bg-slate-500 animate-bounce [animation-delay:300ms]"></span>
          </span>
          <span>Procesando análisis en RunPod y consultando base de datos...</span>
        </div>
      </div>
    </div>

    <!-- Previsualización multi-imagen -->
    <div
      v-if="imagenesSeleccionadas.length"
      class="mt-3 bg-slate-50 border border-slate-200 rounded-xl p-3"
    >
      <div class="flex items-center justify-between text-xs text-slate-600 mb-2">
        <span>{{ imagenesSeleccionadas.length }}/{{ maxImagenes }} imágenes adjuntas para análisis individual y consolidado</span>
        <button @click="imagenesSeleccionadas = []" class="text-rose-600 hover:underline font-medium">
          Limpiar adjuntos
        </button>
      </div>
      <div class="flex gap-2.5 overflow-x-auto pb-1">
        <div
          v-for="(img, idx) in imagenesSeleccionadas"
          :key="idx"
          class="relative shrink-0 w-20 h-20 rounded-xl overflow-hidden border border-slate-300 bg-white"
        >
          <img :src="img" class="w-full h-full object-cover" alt="Vehículo" />
          <button
            @click="quitarImagen(idx)"
            class="absolute top-1 right-1 w-5 h-5 rounded-full bg-slate-900/80 text-white text-xs flex items-center justify-center"
            title="Quitar imagen"
          >
            ✕
          </button>
        </div>
      </div>
    </div>

    <!-- Formulario de envío -->
    <form
      @submit.prevent="enviarMensaje"
      class="mt-3 bg-white rounded-2xl border border-slate-200 p-3 flex items-center gap-2.5 shadow-sm"
    >
      <label
        class="cursor-pointer px-3 py-2.5 rounded-xl border border-slate-300 text-slate-700 hover:bg-slate-100 text-xs font-medium flex items-center gap-1.5 shrink-0"
        title="Seleccionar una o varias imágenes (máximo 6)"
      >
        <input
          type="file"
          accept="image/*"
          multiple
          class="hidden"
          @change="seleccionarImagenes"
          :disabled="cargando"
        />
        <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
        <span>Fotos ({{ imagenesSeleccionadas.length }}/{{ maxImagenes }})</span>
      </label>

      <input
        v-model="entradaTexto"
        type="text"
        placeholder="Escribe una consulta del peaje (placa, tarifas, alertas) o pregunta sobre las fotos..."
        class="flex-1 text-sm border border-slate-300 rounded-xl px-3.5 py-2.5 focus:outline-none focus:ring-2 focus:ring-slate-900"
        :disabled="cargando"
      />

      <button
        type="submit"
        :disabled="cargando || (!entradaTexto.trim() && imagenesSeleccionadas.length === 0)"
        class="px-5 py-2.5 rounded-xl bg-slate-900 text-white text-sm font-medium hover:bg-slate-800 disabled:opacity-40 shrink-0"
      >
        Enviar
      </button>
    </form>
  </div>
</template>

<script setup>
import { ref, nextTick, onMounted } from 'vue'
import api from '../services/api'

const maxImagenes = 6
const cargando = ref(false)
const entradaTexto = ref('')
const imagenesSeleccionadas = ref([])
const areaScroll = ref(null)
const estadoVision = ref('offline')
const estadoOllama = ref('offline')

const chips = [
  { label: 'Tarifas del peaje', prompt: '¿Cuáles son las tarifas vigentes por categoría y ejes?' },
  { label: 'Resumen operativo', prompt: 'Dame el resumen de pasos, recaudación y vehículos registrados' },
  { label: 'Alertas pendientes', prompt: '¿Cuántas alertas pendientes existen actualmente?' },
  { label: 'Modelos M1–M4', prompt: 'Explícame cómo funcionan los modelos M1, M2, M3 y M4 en el peaje' },
]

const crearBienvenida = () => ({
  role: 'assistant',
  content:
    'Bienvenido al **Agente Exclusivo del Sistema Inteligente de Control de Peaje**.\n\n' +
    'Puedes:\n' +
    '• Adjuntar **una o varias fotografías de vehículos** (hasta 6 a la vez) para obtener el análisis individual (placa M1, categoría M2, ejes M3, pasajeros M4, tarifa y estado en BD).\n' +
    '• Hacer preguntas de seguimiento sobre las imágenes analizadas.\n' +
    '• Consultar placas, tarifas vigentes, alertas pendientes, casetas y recaudación.\n\n' +
    '*Nota: No respondo consultas fuera del dominio del sistema de peaje.*',
  imagenes: [],
})

const mensajes = ref([crearBienvenida()])

const verificarEstado = async () => {
  try {
    const { data } = await api.get('/estado/inferencia')
    estadoVision.value = data.status === 'online' ? 'online' : 'offline'
    estadoOllama.value = data.ollama_status || (data.modelos?.ollama_llm ? 'online' : 'offline')
  } catch {
    estadoVision.value = 'offline'
    estadoOllama.value = 'offline'
  }
}

const reiniciarConversacion = () => {
  mensajes.value = [crearBienvenida()]
  imagenesSeleccionadas.value = []
}

const seleccionarImagenes = async (e) => {
  const archivos = Array.from(e.target.files || [])
  if (!archivos.length) return

  const disponibles = maxImagenes - imagenesSeleccionadas.value.length
  const seleccion = archivos.slice(0, Math.max(0, disponibles))

  for (const archivo of seleccion) {
    const base64 = await convertirABase64(archivo)
    if (base64) {
      imagenesSeleccionadas.value.push(base64)
    }
  }

  e.target.value = ''
}

const convertirABase64 = (file) =>
  new Promise((resolve) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result)
    reader.onerror = () => resolve(null)
    reader.readAsDataURL(file)
  })

const quitarImagen = (idx) => {
  imagenesSeleccionadas.value.splice(idx, 1)
}

const usarChip = (prompt) => {
  entradaTexto.value = prompt
  enviarMensaje()
}

const enviarMensaje = async () => {
  const texto = entradaTexto.value.trim()
  const imagenes = [...imagenesSeleccionadas.value]

  if (!texto && imagenes.length === 0) return

  const historial = mensajes.value.slice(-12).map((m) => ({
    role: m.role,
    content: m.content,
  }))

  mensajes.value.push({
    role: 'user',
    content: texto || `Analizar ${imagenes.length} imagen(es) vehicular(es)`,
    imagenes,
  })

  entradaTexto.value = ''
  imagenesSeleccionadas.value = []
  cargando.value = true
  await scrollFinal()

  try {
    const payload = { historial }
    if (texto) payload.mensaje = texto
    if (imagenes.length > 0) {
      payload.imagenes_base64 = imagenes
      if (imagenes.length === 1) {
        payload.imagen_base64 = imagenes[0]
      }
    }

    const { data } = await api.post('/agente/chat', payload)
    mensajes.value.push({
      role: 'assistant',
      content: data.respuesta || 'Sin respuesta disponible.',
      estado: data.estado || null,
      imagenes: [],
    })
  } catch (err) {
    const msgError = err.response?.data?.respuesta || err.response?.data?.message || 'No se pudo contactar al agente.'
    mensajes.value.push({
      role: 'assistant',
      content: msgError,
      imagenes: [],
    })
  } finally {
    cargando.value = false
    await scrollFinal()
  }
}

const scrollFinal = async () => {
  await nextTick()
  if (areaScroll.value) {
    areaScroll.value.scrollTop = areaScroll.value.scrollHeight
  }
}

const escaparHtml = (s) =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

const formatearMarkdownBasico = (texto) =>
  escaparHtml(texto || '')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*\n]+)\*/g, '<em>$1</em>')
    .replace(/`([^`]+)`/g, '<code class="px-1.5 py-0.5 rounded bg-slate-200/70 text-slate-900 font-mono text-xs">$1</code>')

onMounted(() => {
  verificarEstado()
})
</script>

<style scoped>
.msg-in-enter-active {
  transition: opacity 0.24s ease-out, transform 0.24s cubic-bezier(0.16, 1, 0.3, 1);
}
.msg-in-enter-from {
  opacity: 0;
  transform: translateY(10px);
}
</style>
