<template>
  <div class="space-y-5">
    <div class="pb-2 border-b border-slate-200">
      <h1 class="text-xl font-bold text-slate-900 tracking-tight">Historial de Tránsito en Caseta</h1>
      <p class="text-xs text-slate-500 mt-0.5">Auditoría con fotografía de evidencia, caseta, fecha y tarifa aplicada</p>
    </div>

    <div class="bg-white rounded-xl border border-slate-200 overflow-hidden shadow-xs">
      <table class="w-full text-left text-xs text-slate-600">
        <thead class="bg-slate-50 text-[11px] uppercase tracking-wider text-slate-500 border-b border-slate-200">
          <tr>
            <th class="py-3 px-4 font-medium">Evidencia</th>
            <th class="py-3 px-4 font-medium">Placa Normalizada</th>
            <th class="py-3 px-4 font-medium">Categoría & Ejes</th>
            <th class="py-3 px-4 font-medium">Caseta</th>
            <th class="py-3 px-4 font-medium">Monto</th>
            <th class="py-3 px-4 font-medium">Estado</th>
            <th class="py-3 px-4 font-medium">Fecha y Hora</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="p in pasos" :key="p.id" class="hover:bg-slate-50/80 transition">
            <td class="py-2.5 px-4">
              <div class="w-12 h-9 rounded bg-slate-100 border border-slate-200 overflow-hidden flex items-center justify-center">
                <img v-if="p.imagen_url" :src="p.imagen_url" class="w-full h-full object-cover" />
                <span v-else class="text-[9px] text-slate-400">Sin foto</span>
              </div>
            </td>
            <td class="py-2.5 px-4">
              <div class="font-mono font-bold text-slate-900">{{ p.placa_normalizada }}</div>
              <div class="text-[10px] text-slate-400">Leída: {{ p.placa_leida }} ({{ (p.confianza_ocr * 100).toFixed(0) }}%)</div>
            </td>
            <td class="py-2.5 px-4 capitalize text-slate-700">{{ p.categoria_detectada }} ({{ p.ejes_detectados }} ejes)</td>
            <td class="py-2.5 px-4">{{ p.caseta ? p.caseta.nombre : 'Caseta General' }}</td>
            <td class="py-2.5 px-4 font-semibold text-slate-900">Bs. {{ parseFloat(p.monto).toFixed(2) }}</td>
            <td class="py-2.5 px-4">
              <span class="px-2 py-0.5 rounded text-[10px] font-medium" :class="getEstadoBadge(p.estado)">
                {{ p.estado }}
              </span>
            </td>
            <td class="py-2.5 px-4 text-slate-400">{{ formatFecha(p.created_at) }}</td>
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
    case 'Registrada y con paso': return 'bg-emerald-50 text-emerald-800 border border-emerald-200'
    case 'Registrada sin paso': return 'bg-sky-50 text-sky-800 border border-sky-200'
    case 'Identificada no registrada': return 'bg-rose-50 text-rose-800 border border-rose-200'
    default: return 'bg-slate-100 text-slate-700 border border-slate-200'
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
