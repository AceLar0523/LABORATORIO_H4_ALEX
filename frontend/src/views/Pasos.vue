<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-white">Historial de Pasos</h1>
      <p class="text-slate-400 text-sm">Registro auditable con imagen de evidencia, caseta y clasificación</p>
    </div>

    <div class="bg-slate-800 rounded-2xl border border-slate-700 overflow-hidden shadow-xl">
      <table class="w-full text-left text-sm text-slate-300">
        <thead class="bg-slate-900/80 text-xs uppercase text-slate-400 border-b border-slate-700">
          <tr>
            <th class="py-3.5 px-4">Evidencia</th>
            <th class="py-3.5 px-4">Placa Normalizada</th>
            <th class="py-3.5 px-4">Categoría / Ejes</th>
            <th class="py-3.5 px-4">Caseta</th>
            <th class="py-3.5 px-4">Monto</th>
            <th class="py-3.5 px-4">Estado</th>
            <th class="py-3.5 px-4">Fecha y Hora</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-700/50">
          <tr v-for="p in pasos" :key="p.id" class="hover:bg-slate-700/30 transition">
            <td class="py-3.5 px-4">
              <div class="w-14 h-11 rounded-lg bg-slate-900 border border-slate-700 overflow-hidden flex items-center justify-center">
                <img v-if="p.imagen_url" :src="p.imagen_url" class="w-full h-full object-cover" />
                <span v-else class="text-[10px] text-slate-500">Sin foto</span>
              </div>
            </td>
            <td class="py-3.5 px-4 font-mono font-bold text-white">
              {{ p.placa_normalizada }}
              <div class="text-[11px] text-slate-400 font-sans">Leída: {{ p.placa_leida }} ({{ (p.confianza_ocr * 100).toFixed(0) }}%)</div>
            </td>
            <td class="py-3.5 px-4 capitalize">{{ p.categoria_detectada }} ({{ p.ejes_detectados }} ejes)</td>
            <td class="py-3.5 px-4">{{ p.caseta ? p.caseta.nombre : 'Caseta General' }}</td>
            <td class="py-3.5 px-4 font-semibold text-emerald-400">Bs. {{ parseFloat(p.monto).toFixed(2) }}</td>
            <td class="py-3.5 px-4">
              <span class="px-2 py-0.5 rounded-full text-xs font-medium" :class="getEstadoBadge(p.estado)">
                {{ p.estado }}
              </span>
            </td>
            <td class="py-3.5 px-4 text-xs text-slate-400">{{ formatFecha(p.created_at) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const pasos = ref([])

function getEstadoBadge(estado) {
  switch (estado) {
    case 'Registrada y con paso': return 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
    case 'Registrada sin paso': return 'bg-blue-500/20 text-blue-400 border border-blue-500/30'
    case 'Identificada no registrada': return 'bg-red-500/20 text-red-400 border border-red-500/30'
    default: return 'bg-slate-700 text-slate-300'
  }
}

function formatFecha(dateStr) {
  if (!dateStr) return ''
  const d = new Date(dateStr)
  return d.toLocaleString()
}

async function cargarPasos() {
  try {
    const res = await api.get('/pasos')
    pasos.value = res.data.data
  } catch (err) {
    console.error(err)
  }
}

onMounted(cargarPasos)
</script>

