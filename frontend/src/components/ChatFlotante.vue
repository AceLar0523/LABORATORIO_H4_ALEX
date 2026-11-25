<template>
  <div>
    <!-- Botón Flotante Disparador -->
    <button
      v-if="!abierto"
      @click="abrirChat"
      class="fixed bottom-6 right-6 z-50 flex items-center gap-2.5 bg-blue-600 hover:bg-blue-700 text-white font-medium px-4 py-3 rounded-full shadow-lg hover:shadow-xl transition-all duration-200 active:scale-95 cursor-pointer border border-blue-500/30"
      title="Consultar Agente de Placas"
    >
      <div class="relative">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
        </svg>
        <span
          class="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full border-2 border-blue-600"
          :class="ollamaOnline ? 'bg-emerald-400 animate-pulse' : 'bg-amber-400'"
        ></span>
      </div>
      <span class="text-xs font-semibold">Agente IA</span>
    </button>

    <!-- Ventana Flotante del Chatbot -->
    <transition name="chat-slide">
      <div
        v-if="abierto"
        class="fixed bottom-6 right-6 z-50 w-[380px] sm:w-[420px] h-[520px] max-h-[85vh] bg-white border border-slate-200 rounded-2xl shadow-2xl flex flex-col overflow-hidden"
      >
        <!-- Header del Chatbot Flotante con Estado Real de Conexión -->
        <div class="px-4 py-3 bg-gradient-to-r from-blue-700 via-blue-800 to-indigo-900 text-white flex items-center justify-between shadow-sm">
          <div class="flex items-center gap-2.5">
            <div class="w-8 h-8 rounded-lg bg-white/10 backdrop-blur border border-white/20 flex items-center justify-center font-bold text-sm">
              🤖
            </div>
            <div>
              <div class="text-xs font-bold leading-tight flex items-center gap-1.5">
                <span>Agente Peaje IA</span>
                <span
                  class="w-2 h-2 rounded-full"
                  :class="ollamaOnline ? 'bg-emerald-400' : 'bg-amber-400'"
                  :title="ollamaOnline ? 'Ollama en línea' : 'Modo estructurado (Ollama offline)'"
                ></span>
              </div>
              <span class="text-[10px] text-blue-200">
                {{ ollamaOnline ? 'Ollama LLM (Llama 3.2)' : 'Modo BD Directo (Ollama Inactivo)' }}
              </span>
            </div>
          </div>
          <button
            @click="abierto = false"
            class="text-blue-200 hover:text-white p-1.5 rounded-lg hover:bg-white/10 transition-colors cursor-pointer"
            title="Cerrar chat"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Banner Discreto Informativo de Conexión -->
        <div
          v-if="!ollamaOnline && verificado"
          class="bg-amber-50 border-b border-amber-200 px-3 py-1.5 text-[10px] text-amber-800 flex items-center justify-between"
        >
          <span>ℹ️ Ollama no detectado en puerto 11434. Operando con respuestas directas de BD.</span>
          <button @click="verificarConexion" class="font-bold underline ml-1 cursor-pointer">Reintentar</button>
        </div>

        <!-- Área de Mensajes -->
        <div class="flex-1 overflow-y-auto p-3.5 space-y-3 bg-slate-50/70" ref="messagesContainer">
          <div
            v-for="(m, idx) in mensajes"
            :key="idx"
            class="flex"
            :class="m.remitente === 'usuario' ? 'justify-end' : 'justify-start'"
          >
            <div
              class="max-w-[85%] rounded-2xl px-3.5 py-2.5 text-xs leading-relaxed shadow-xs"
              :class="m.remitente === 'usuario'
                ? 'bg-blue-600 text-white rounded-br-xs'
                : 'bg-white border border-slate-200 text-slate-800 rounded-bl-xs'"
            >
              <div v-if="m.imagen" class="mb-2 rounded-lg overflow-hidden border border-slate-300 max-w-[160px]">
                <img :src="m.imagen" class="w-full h-auto object-cover" />
              </div>
              <div class="whitespace-pre-line">{{ m.texto }}</div>
            </div>
          </div>

          <div v-if="cargando" class="flex justify-start">
            <div class="bg-white border border-slate-200 rounded-2xl rounded-bl-xs px-3 py-2 text-slate-500 text-[11px] flex items-center gap-2 shadow-xs">
              <span class="w-1.5 h-1.5 rounded-full bg-blue-600 animate-ping"></span>
              <span>Consultando base de datos...</span>
            </div>
          </div>
        </div>

        <!-- Barra Inferior de Entrada -->
        <div class="p-2.5 bg-white border-t border-slate-200">
          <div v-if="imagenBase64" class="mb-2 flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
            <img :src="imagenBase64" class="w-8 h-8 object-cover rounded border border-slate-300" />
            <span class="text-[11px] text-slate-600 truncate flex-1">Foto de placa lista</span>
            <button @click="quitarImagen" class="text-rose-600 hover:text-rose-800 text-[11px] font-medium pr-1 cursor-pointer">Quitar</button>
          </div>

          <form @submit.prevent="enviar" class="flex items-center gap-1.5">
            <label class="cursor-pointer p-2 rounded-lg hover:bg-slate-100 text-slate-500 hover:text-slate-800 transition" title="Subir foto de placa">
              <input type="file" accept="image/*" class="hidden" @change="onFileChange" />
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </label>

            <input
              v-model="inputTexto"
              type="text"
              placeholder="Consulta una placa (ej. 4021XYZ)..."
              class="flex-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-1.5 text-xs text-slate-800 focus:outline-none focus:border-blue-500 focus:bg-white"
            />

            <button
              type="submit"
              :disabled="cargando || (!inputTexto && !imagenBase64)"
              class="bg-blue-600 hover:bg-blue-700 disabled:opacity-40 text-white p-2 rounded-lg transition-all cursor-pointer shadow-xs active:scale-95"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3" />
              </svg>
            </button>
          </form>
        </div>
      </div>
    </transition>
  </div>
</template>

<script setup>
import { ref, nextTick, onMounted } from 'vue'
import api from '../services/api'

const abierto = ref(false)
const inputTexto = ref('')
const imagenBase64 = ref(null)
const cargando = ref(false)
const messagesContainer = ref(null)
const ollamaOnline = ref(false)
const verificado = ref(false)

const mensajes = ref([
  {
    remitente: 'agente',
    texto: '¡Hola! Soy tu asistente de control de peaje. Puedes consultarme el estado de cualquier placa escribiéndola (ej: 4021XYZ) o enviando una fotografía.',
  }
])

async function verificarConexion() {
  try {
    const res = await api.get('/estado/inferencia')
    ollamaOnline.value = (res.data.ollama_status === 'online')
  } catch (e) {
    ollamaOnline.value = false
  } finally {
    verificado.value = true
  }
}

function abrirChat() {
  abierto.value = true
  verificarConexion()
}

function onFileChange(e) {
  const file = e.target.files[0]
  if (!file) return
  const reader = new FileReader()
  reader.onload = (event) => {
    imagenBase64.value = event.target.result
  }
  reader.readAsDataURL(file)
}

function quitarImagen() {
  imagenBase64.value = null
}

async function scrollAbajo() {
  await nextTick()
  if (messagesContainer.value) {
    messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
  }
}

async function enviar() {
  const txt = inputTexto.value.trim()
  const img = imagenBase64.value

  if (!txt && !img) return

  mensajes.value.push({
    remitente: 'usuario',
    texto: txt || 'Consultando placa por fotografía...',
    imagen: img,
  })

  inputTexto.value = ''
  imagenBase64.value = null
  cargando.value = true
  scrollAbajo()

  try {
    const res = await api.post('/agente/chat', {
      mensaje: txt,
      imagen_base64: img,
    })

    mensajes.value.push({
      remitente: 'agente',
      texto: res.data.respuesta,
      estado: res.data.estado,
    })
  } catch (err) {
    mensajes.value.push({
      remitente: 'agente',
      texto: 'No se pudo procesar la consulta: ' + (err.response?.data?.message || err.message),
    })
  } finally {
    cargando.value = false
    scrollAbajo()
  }
}

onMounted(() => {
  verificarConexion()
})
</script>

<style scoped>
.chat-slide-enter-active,
.chat-slide-leave-active {
  transition: all 0.25s cubic-bezier(0.16, 1, 0.3, 1);
}

.chat-slide-enter-from,
.chat-slide-leave-to {
  opacity: 0;
  transform: translateY(20px) scale(0.96);
}
</style>
