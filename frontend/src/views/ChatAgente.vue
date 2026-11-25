<template>
  <div class="max-w-4xl mx-auto h-[calc(100vh-120px)] flex flex-col bg-white border border-slate-200 rounded-xl shadow-xs overflow-hidden">
    <!-- Header del Asistente -->
    <div class="px-5 py-3.5 bg-slate-50 border-b border-slate-200 flex items-center justify-between">
      <div>
        <h2 class="text-sm font-semibold text-slate-900">Agente de Consulta Vehicular (Ollama LLM)</h2>
        <p class="text-[11px] text-slate-500">Clasificación en 4 estados oficiales y sugerencias de placas</p>
      </div>
      <span class="text-[10px] bg-slate-200 text-slate-700 px-2 py-0.5 rounded font-medium">
        Llama 3.2:3b en RunPod
      </span>
    </div>

    <!-- Historial de Conversación -->
    <div class="flex-1 overflow-y-auto p-5 space-y-4">
      <div v-for="(m, idx) in mensajes" :key="idx" class="flex" :class="m.remitente === 'usuario' ? 'justify-end' : 'justify-start'">
        <div
          class="max-w-lg rounded-xl p-3.5 text-xs leading-relaxed whitespace-pre-line"
          :class="m.remitente === 'usuario' ? 'bg-slate-900 text-white' : 'bg-slate-50 border border-slate-200 text-slate-800'"
        >
          <!-- Preview si envió foto -->
          <div v-if="m.imagen" class="mb-2 rounded overflow-hidden border border-slate-300 max-w-[180px]">
            <img :src="m.imagen" class="w-full h-auto" />
          </div>
          <div>{{ m.texto }}</div>
        </div>
      </div>

      <div v-if="cargando" class="flex justify-start">
        <div class="bg-slate-50 border border-slate-200 rounded-xl p-3 text-slate-500 text-xs flex items-center gap-2">
          <span class="w-1.5 h-1.5 rounded-full bg-slate-400 animate-pulse"></span>
          Consultando base de datos y procesando respuesta...
        </div>
      </div>
    </div>

    <!-- Input Bar -->
    <div class="p-3 bg-white border-t border-slate-200">
      <div v-if="imagenBase64" class="mb-2 flex items-center gap-2 bg-slate-50 p-2 rounded-lg border border-slate-200">
        <img :src="imagenBase64" class="w-10 h-10 object-cover rounded border border-slate-300" />
        <span class="text-xs text-slate-600">Fotografía seleccionada para OCR</span>
        <button @click="quitarImagen" class="ml-auto text-xs text-rose-600 hover:text-rose-800">Quitar</button>
      </div>

      <form @submit.prevent="enviarMensaje" class="flex items-center gap-2">
        <label class="cursor-pointer p-2 rounded-lg bg-slate-50 hover:bg-slate-100 text-slate-600 border border-slate-200 transition" title="Subir foto de placa">
          <input type="file" accept="image/*" class="hidden" @change="onFileChange" />
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
        </label>

        <input
          v-model="inputTexto"
          type="text"
          placeholder="Escribe el número de placa (ej. 4021XYZ) o consulta..."
          class="flex-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-slate-400"
        />

        <button
          type="submit"
          :disabled="cargando || (!inputTexto && !imagenBase64)"
          class="bg-slate-900 hover:bg-slate-800 disabled:opacity-50 text-white font-medium py-2 px-4 rounded-lg text-xs transition cursor-pointer"
        >
          Consultar
        </button>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import api from '../services/api'

const mensajes = ref([
  {
    remitente: 'agente',
    texto: 'Buenos días. Puedes consultar la situación de cualquier vehículo escribiendo su número de placa (por ejemplo: 4021XYZ) o subiendo una fotografía nítida.',
  }
])

const inputTexto = ref('')
const imagenBase64 = ref(null)
const cargando = ref(false)

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

async function enviarMensaje() {
  const texto = inputTexto.value.trim()
  const img = imagenBase64.value

  if (!texto && !img) return

  mensajes.value.push({
    remitente: 'usuario',
    texto: texto || 'Consultando placa por fotografía...',
    imagen: img,
  })

  inputTexto.value = ''
  imagenBase64.value = null
  cargando.value = true

  try {
    const res = await api.post('/agente/chat', {
      mensaje: texto,
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
      texto: 'No fue posible completar la consulta: ' + (err.response?.data?.message || err.message),
    })
  } finally {
    cargando.value = false
  }
}
</script>
