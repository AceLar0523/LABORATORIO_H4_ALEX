<template>
  <div class="max-w-2xl mx-auto space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-white">Estado del Motor de Inferencia</h1>
      <p class="text-slate-400 text-sm">Monitoreo de conectividad con RunPod / Colab y salud de los 3 modelos</p>
    </div>

    <div class="bg-slate-800 border border-slate-700 rounded-2xl p-6 shadow-xl space-y-6">
      <div class="flex items-center justify-between pb-6 border-b border-slate-700">
        <div>
          <span class="text-xs uppercase text-slate-400 font-semibold tracking-wider">Estado del Endpoint</span>
          <h2 class="text-2xl font-bold mt-1" :class="info.status === 'online' ? 'text-emerald-400' : 'text-red-400'">
            {{ info.status === 'online' ? '● En Línea (Online)' : '○ Desconectado (Offline)' }}
          </h2>
        </div>
        <button @click="verificar" :disabled="verificando" class="bg-blue-600 hover:bg-blue-500 text-white text-xs font-semibold py-2 px-4 rounded-xl transition">
          {{ verificando ? 'Verificando...' : 'Reintentar Ping' }}
        </button>
      </div>

      <div class="grid grid-cols-2 gap-4 text-sm">
        <div class="bg-slate-900 p-4 rounded-xl border border-slate-700/60">
          <span class="text-xs text-slate-400 block">URL de Inferencia</span>
          <span class="font-mono text-white text-xs mt-1 block break-all">{{ info.url }}</span>
        </div>
        <div class="bg-slate-900 p-4 rounded-xl border border-slate-700/60">
          <span class="text-xs text-slate-400 block">Latencia Ping</span>
          <span class="font-bold text-white text-base mt-1 block">{{ info.latencia_ms }} ms</span>
        </div>
      </div>

      <div>
        <h3 class="text-sm font-bold text-white mb-3">Modelos Requeridos (M1, M2, M3)</h3>
        <div class="space-y-2">
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-900 border border-slate-700">
            <span class="text-sm text-slate-200">M1: Detección de Placas + OCR ONNX</span>
            <span class="text-xs px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-medium">Activo</span>
          </div>
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-900 border border-slate-700">
            <span class="text-sm text-slate-200">M2: Segmentación YOLO (m2_vehiculos.pt)</span>
            <span class="text-xs px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-medium">Activo</span>
          </div>
          <div class="flex items-center justify-between p-3 rounded-xl bg-slate-900 border border-slate-700">
            <span class="text-sm text-slate-200">M3: Keypoints de Ruedas / Ejes (m3_llantas.pt)</span>
            <span class="text-xs px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-medium">Activo</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const info = ref({ status: 'checking', url: '', latencia_ms: 0 })
const verificando = ref(false)

async function verificar() {
  verificando.value = true
  try {
    const res = await api.get('/estado/inferencia')
    info.value = res.data
  } catch (err) {
    info.value = { status: 'offline', url: 'Error al contactar API', latencia_ms: 0 }
  } finally {
    verificando.value = false
  }
}

onMounted(verificar)
</script>

