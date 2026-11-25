<template>
  <div class="fixed bottom-5 right-5 z-50 flex flex-col items-end">
    <!-- Ventana del Agente Flotante -->
    <Transition name="chat-pop">
      <div
        v-if="abierto"
        class="mb-3 w-[380px] max-w-[calc(100vw-2rem)] h-[560px] max-h-[82vh] bg-white rounded-2xl shadow-2xl border border-slate-200 flex flex-col overflow-hidden origin-bottom-right"
      >
        <!-- Cabecera -->
        <div class="bg-slate-900 text-white px-4 py-3 flex items-center justify-between">
          <div>
            <h3 class="text-sm font-semibold flex items-center gap-2">
              <span>Agente Exclusivo de Peaje</span>
            </h3>
            <div class="flex items-center gap-2 text-[11px] text-slate-300 mt-0.5">
              <span class="inline-flex items-center gap-1">
                <span
                  class="w-2 h-2 rounded-full"
                  :class="estadoVision === 'online' ? 'bg-emerald-400 animate-pulse' : 'bg-rose-400'"
                ></span>
                Visión M1–M4: {{ estadoVision === 'online' ? 'En línea' : 'Offline' }}
              </span>
              <span>·</span>
              <span class="inline-flex items-center gap-1">
                <span
                  class="w-2 h-2 rounded-full"
                  :class="{
                    'bg-emerald-400 animate-pulse': estadoOllama === 'online',
                    'bg-amber-400': estadoOllama === 'sin_modelo',
                    'bg-rose-400': estadoOllama === 'offline'
                  }"
                ></span>
                LLM:
                {{
                  estadoOllama === 'online'
                    ? 'Activo'
                    : estadoOllama === 'sin_modelo'
                      ? 'Sin modelo'
                      : 'Offline'
                }}
              </span>
            </div>
          </div>
          <div class="flex items-center gap-1">
            <button
              @click="reiniciarChat"
              title="Nueva conversación"
              class="text-xs text-slate-300 hover:text-white px-2 py-1 rounded hover:bg-slate-800 transition"
            >
              Limpiar
            </button>
            <button
              @click="abierto = false"
              class="text-slate-300 hover:text-white p-1 rounded hover:bg-slate-800 transition"
              aria-label="Cerrar chat"
            >
              ✕
            </button>
          </div>
        </div>

        <!-- Aviso si Ollama no tiene modelo aún -->
        <div
          v-if="estadoOllama === 'sin_modelo'"
          class="bg-amber-50 border-b border-amber-200 px-3 py-1.5 text-[11px] text-amber-800"
        >
          Visión M1–M4 y consultas a BD activas en RunPod. Ollama espera modelo (`llama3.2:3b`) para redacción libre.
        </div>

        <!-- Chips rápidos -->
        <div class="px-3 py-2 bg-slate-50 border-b border-slate-200 flex gap-1.5 overflow-x-auto">
          <button
            v-for="chip in chipsRapidos"
            :key="chip.label"
            @click="enviarChip(chip.prompt)"
            :disabled="cargando"
            class="shrink-0 text-[11px] px-2.5 py-1 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-100 active:scale-95 transition disabled:opacity-50"
          >
            {{ chip.label }}
          </button>
        </div>

        <!-- Lista de mensajes -->
        <div ref="contenedorMensajes" class="flex-1 overflow-y-auto p-3 bg-slate-50">
          <TransitionGroup name="msg-in" tag="div" class="space-y-3">
            <div
              v-for="(msg, idx) in mensajes"
              :key="idx"
              class="flex"
              :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
            >
              <div
                class="max-w-[85%] rounded-2xl px-3.5 py-2.5 text-xs leading-relaxed shadow-sm"
                :class="
                  msg.role === 'user'
                    ? 'bg-slate-900 text-white rounded-br-sm'
                    : msg.estado === 'Fuera de dominio'
                      ? 'bg-amber-50 text-amber-950 border border-amber-200 rounded-bl-sm'
                      : 'bg-white text-slate-800 border border-slate-200 rounded-bl-sm'
                "
              >
                <!-- Miniaturas enviadas por el usuario -->
                <div v-if="msg.imagenes && msg.imagenes.length" class="flex flex-wrap gap-1.5 mb-2">
                  <img
                    v-for="(img, iIdx) in msg.imagenes"
                    :key="iIdx"
                    :src="img"
                    alt="Vehículo adjunto"
                    class="w-16 h-16 object-cover rounded-lg border border-slate-600"
                  />
                </div>

                <div class="whitespace-pre-wrap" v-html="formatearTexto(msg.content)"></div>
              </div>
            </div>
          </TransitionGroup>

          <div v-if="cargando" class="flex justify-start mt-3">
            <div class="bg-white border border-slate-200 text-slate-500 rounded-2xl rounded-bl-sm px-3.5 py-2.5 text-xs flex items-center gap-2 shadow-sm">
              <span class="flex items-center gap-1">
                <span class="w-1.5 h-1.5 rounded-full bg-slate-500 animate-bounce [animation-delay:0ms]"></span>
                <span class="w-1.5 h-1.5 rounded-full bg-slate-500 animate-bounce [animation-delay:150ms]"></span>
                <span class="w-1.5 h-1.5 rounded-full bg-slate-500 animate-bounce [animation-delay:300ms]"></span>
              </span>
              <span>Analizando en RunPod y consultando peaje...</span>
            </div>
          </div>
        </div>

        <!-- Cola de imágenes seleccionadas -->
        <div v-if="imagenesSeleccionadas.length" class="px-3 py-2 bg-slate-100 border-t border-slate-200">
          <div class="flex items-center justify-between text-[11px] text-slate-600 mb-1.5">
            <span>{{ imagenesSeleccionadas.length }}/{{ maxImagenes }} imágenes listas para analizar</span>
            <button @click="imagenesSeleccionadas = []" class="text-rose-600 hover:underline">
              Quitar todas
            </button>
          </div>
          <div class="flex gap-2 overflow-x-auto pb-1">
            <div
              v-for="(img, idx) in imagenesSeleccionadas"
              :key="idx"
              class="relative shrink-0 w-14 h-14 rounded-lg overflow-hidden border border-slate-300 bg-white"
            >
              <img :src="img" class="w-full h-full object-cover" alt="Previsualización" />
              <button
                @click="quitarImagen(idx)"
                class="absolute top-0.5 right-0.5 w-4 h-4 rounded-full bg-slate-900/80 text-white text-[10px] flex items-center justify-center"
                title="Quitar imagen"
              >
                ✕
              </button>
            </div>
          </div>
        </div>

        <!-- Barra de entrada -->
        <form @submit.prevent="enviarMensaje" class="p-2.5 bg-white border-t border-slate-200 flex items-center gap-2">
          <label
            class="cursor-pointer p-2 rounded-lg border border-slate-300 text-slate-600 hover:bg-slate-100 active:scale-95 transition shrink-0"
            title="Subir una o varias imágenes (máx. 6)"
          >
            <input
              type="file"
              accept="image/*"
              multiple
              class="hidden"
              @change="manejarImagenes"
              :disabled="cargando"
            />
            <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
          </label>

          <input
            v-model="entradaTexto"
            type="text"
            placeholder="Consulta placa, tarifas o adjunta fotos..."
            class="flex-1 text-xs border border-slate-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-slate-900"
            :disabled="cargando"
          />

          <button
            type="submit"
            :disabled="cargando || (!entradaTexto.trim() && imagenesSeleccionadas.length === 0)"
            class="px-3 py-2 rounded-lg bg-slate-900 text-white text-xs font-medium hover:bg-slate-800 active:scale-95 transition disabled:opacity-40 shrink-0"
          >
            Enviar
          </button>
        </form>
      </div>
    </Transition>

    <!-- Botón flotante -->
    <button
      @click="toggleChat"
      class="h-13 px-4 rounded-full bg-slate-900 text-white shadow-lg hover:bg-slate-800 hover:scale-105 active:scale-95 flex items-center gap-2 text-sm font-medium transition-all duration-200"
    >
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
      </svg>
      <span>{{ abierto ? 'Cerrar Agente' : 'Agente IA Peaje' }}</span>
    </button>
  </div>
</template>

<script setup>
import { ref, nextTick, onMounted } from 'vue'
import api from '../services/api'

const maxImagenes = 6
const abierto = ref(false)
const cargando = ref(false)
const entradaTexto = ref('')
const imagenesSeleccionadas = ref([])
const contenedorMensajes = ref(null)

const estadoVision = ref('offline')
const estadoOllama = ref('offline')

const chipsRapidos = [
  { label: 'Tarifas', prompt: '¿Cuáles son las tarifas vigentes del peaje?' },
  { label: 'Resumen de hoy', prompt: 'Dame el resumen de pasos y recaudación del sistema' },
  { label: 'Alertas activas', prompt: '¿Cuántas alertas pendientes hay y cuáles son?' },
]

const mensajeBienvenida = () => ({
  role: 'assistant',
  content:
    'Soy el asistente exclusivo del **Sistema Inteligente de Control de Peaje**.\n' +
    'Puedes subir **1 o varias fotos de vehículos** (hasta 6) para analizar placa (M1), categoría (M2), ejes (M3), pasajeros (M4) y tarifa, o consultarme sobre placas, tarifas, alertas y recaudación.',
  imagenes: [],
})

const mensajes = ref([mensajeBienvenida()])

const toggleChat = () => {
  abierto.value = !abierto.value
  if (abierto.value) {
    verificarConexion()
    scrollAbajo()
  }
}

const reiniciarChat = () => {
  mensajes.value = [mensajeBienvenida()]
  imagenesSeleccionadas.value = []
}

const verificarConexion = async () => {
  try {
    const { data } = await api.get('/estado/inferencia')
    estadoVision.value = data.status === 'online' ? 'online' : 'offline'
    estadoOllama.value = data.ollama_status || (data.modelos?.ollama_llm ? 'online' : 'offline')
  } catch {
    estadoVision.value = 'offline'
    estadoOllama.value = 'offline'
  }
}

const manejarImagenes = async (e) => {
  const archivos = Array.from(e.target.files || [])
  if (!archivos.length) return

  const disponibles = maxImagenes - imagenesSeleccionadas.value.length
  const lote = archivos.slice(0, Math.max(0, disponibles))

  for (const archivo of lote) {
    const dataUri = await leerArchivoBase64(archivo)
    if (dataUri) {
      imagenesSeleccionadas.value.push(dataUri)
    }
  }

  e.target.value = ''
}

const leerArchivoBase64 = (file) =>
  new Promise((resolve) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result)
    reader.onerror = () => resolve(null)
    reader.readAsDataURL(file)
  })

const quitarImagen = (idx) => {
  imagenesSeleccionadas.value.splice(idx, 1)
}

const enviarChip = (prompt) => {
  entradaTexto.value = prompt
  enviarMensaje()
}

const construirHistorial = () =>
  mensajes.value.slice(-12).map((m) => ({
    role: m.role,
    content: m.content,
  }))

const enviarMensaje = async () => {
  const texto = entradaTexto.value.trim()
  const imagenes = [...imagenesSeleccionadas.value]

  if (!texto && imagenes.length === 0) return

  const historial = construirHistorial()

  mensajes.value.push({
    role: 'user',
    content: texto || `Analizar ${imagenes.length} imagen(es) vehicular(es)`,
    imagenes,
  })

  entradaTexto.value = ''
  imagenesSeleccionadas.value = []
  cargando.value = true
  await scrollAbajo()

  try {
    const payload = {
      historial,
    }
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
      content: data.respuesta || 'Sin respuesta del agente.',
      estado: data.estado || null,
      imagenes: [],
    })
  } catch (err) {
    const detalle = err.response?.data?.respuesta || err.response?.data?.message || 'Error al consultar el agente.'
    mensajes.value.push({
      role: 'assistant',
      content: detalle,
      imagenes: [],
    })
  } finally {
    cargando.value = false
    await scrollAbajo()
  }
}

const scrollAbajo = async () => {
  await nextTick()
  if (contenedorMensajes.value) {
    contenedorMensajes.value.scrollTop = contenedorMensajes.value.scrollHeight
  }
}

const escaparHtml = (s) =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

const formatearTexto = (texto) => {
  const seguro = escaparHtml(texto || '')
  return seguro
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*\n]+)\*/g, '<em>$1</em>')
    .replace(/`([^`]+)`/g, '<code class="px-1 py-0.5 rounded bg-slate-100 text-slate-800 font-mono text-[11px]">$1</code>')
}

onMounted(() => {
  verificarConexion()
})
</script>

<style scoped>
.chat-pop-enter-active,
.chat-pop-leave-active {
  transition: opacity 0.22s cubic-bezier(0.16, 1, 0.3, 1), transform 0.22s cubic-bezier(0.16, 1, 0.3, 1);
}
.chat-pop-enter-from,
.chat-pop-leave-to {
  opacity: 0;
  transform: translateY(14px) scale(0.95);
}

.msg-in-enter-active {
  transition: opacity 0.24s ease-out, transform 0.24s cubic-bezier(0.16, 1, 0.3, 1);
}
.msg-in-enter-from {
  opacity: 0;
  transform: translateY(10px);
}
</style>
