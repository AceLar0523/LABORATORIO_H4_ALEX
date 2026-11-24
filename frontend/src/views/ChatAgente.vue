<template>
  <div class="max-w-4xl mx-auto h-[calc(100vh-140px)] flex flex-col bg-slate-800 border border-slate-700 rounded-2xl shadow-2xl overflow-hidden">
    <!-- Header del Agente -->
    <div class="p-4 bg-slate-900 border-b border-slate-700 flex items-center justify-between">
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-xl bg-blue-600/20 text-blue-400 flex items-center justify-center border border-blue-500/30">
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" /></svg>
        </div>
        <div>
          <h2 class="text-base font-bold text-white">Agente Conversacional de Placas</h2>
          <p class="text-xs text-slate-400">Consulta por texto o fotografía. Responde los 4 estados oficiales.</p>
        </div>
      </div>
      <span class="text-xs bg-emerald-500/20 text-emerald-400 px-2.5 py-1 rounded-full border border-emerald-500/30">
        Activo
      </span>
    </div>

    <!-- Mensajes -->
    <div class="flex-1 overflow-y-auto p-4 space-y-4">
      <div v-for="(m, idx) in mensajes" :key="idx" class="flex" :class="m.remitente === 'usuario' ? 'justify-end' : 'justify-start'">
        <div
          class="max-w-lg rounded-2xl p-4 shadow text-sm leading-relaxed whitespace-pre-line"
          :class="m.remitente === 'usuario' ? 'bg-blue-600 text-white rounded-tr-none' : 'bg-slate-900 border border-slate-700 text-slate-200 rounded-tl-none'"
        >
          <!-- Preview imagen si envió -->
          <div v-if="m.imagen" class="mb-2 rounded-lg overflow-hidden border border-white/20 max-w-[200px]">
            <img :src="m.imagen" class="w-full h-auto" />
          </div>
          <div>{{ m.texto }}</div>
        </div>
      </div>

      <div v-if="cargando" class="flex justify-start">
        <div class="bg-slate-900 border border-slate-700 rounded-2xl rounded-tl-none p-3 text-slate-400 text-xs flex items-center gap-2">
          <span class="inline-block w-2 h-2 rounded-full bg-blue-500 animate-pulse"></span>
          Consultando base de datos e inferencia...
        </div>
      </div>
    </div>

    <!-- Barra de Input con opción de texto e imagen -->
    <div class="p-4 bg-slate-900 border-t border-slate-700">
      <!-- Preview de imagen seleccionada -->
      <div v-if="imagenBase64" class="mb-3 flex items-center gap-3 bg-slate-800 p-2 rounded-xl border border-slate-700">
        <img :src="imagenBase64" class="w-12 h-12 object-cover rounded-lg border border-slate-600" />
        <span class="text-xs text-slate-300">Imagen lista para OCR</span>
        <button @click="quitarImagen" class="ml-auto text-xs text-red-400 hover:text-red-300">Quitar</button>
      </div>

      <form @submit.prevent="enviarMensaje" class="flex items-center gap-2">
        <label class="cursor-pointer p-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 transition" title="Adjuntar foto de placa">
          <input type="file" accept="image/*" class="hidden" @change="onFileChange" />
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
        </label>

        <input
          v-model="inputTexto"
          type="text"
          placeholder="Escribe una placa (ej. 4021XYZ) o consulta..."
          class="flex-1 bg-slate-800 border border-slate-700 rounded-xl px-4 py-2.5 text-white focus:outline-none focus:border-blue-500 text-sm"
        />

        <button
          type="submit"
          :disabled="cargando || (!inputTexto && !imagenBase64)"
          class="bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white font-medium py-2.5 px-5 rounded-xl transition text-sm cursor-pointer"
        >
          Enviar
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
    texto: '¡Hola! Soy el Agente de Control de Peaje. Puedes consultarme el estado de cualquier placa escribiéndola directamente (ej: 4021XYZ) o subiendo una fotografía de la placa.',
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
      texto: '⚠️ Error al procesar tu solicitud: ' + (err.response?.data?.message || err.message),
    })
  } finally {
    cargando.value = false
  }
}
</script>

