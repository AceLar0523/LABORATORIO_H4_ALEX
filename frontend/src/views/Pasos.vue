<template>
  <div class="space-y-5">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-2 border-b border-slate-200">
      <div>
        <h1 class="text-xl font-bold text-slate-900 tracking-tight">Historial de Tránsito en Caseta</h1>
        <p class="text-xs text-slate-500 mt-0.5">Auditoría con fotografía de evidencia, caseta, fecha y tarifa aplicada</p>
      </div>
      <button
        v-if="esAdmin"
        @click="confirmarLimpiarSinPlaca"
        class="bg-rose-600 hover:bg-rose-700 active:scale-95 text-white text-xs font-semibold py-2 px-3.5 rounded-xl transition-all shadow-xs cursor-pointer flex items-center gap-1.5 self-start sm:self-auto"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
        <span>Limpiar SINPLACA</span>
      </button>
    </div>

    <div class="bg-white rounded-xl border border-slate-200 overflow-x-auto shadow-xs">
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
            <th v-if="esAdmin" class="py-3 px-4 font-medium text-right">Acciones</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="p in pasos" :key="p.id" class="hover:bg-slate-50/80 transition">
            <td class="py-2.5 px-4">
              <div class="w-12 h-9 rounded bg-slate-100 border border-slate-200 overflow-hidden flex items-center justify-center">
                <img v-if="resolveMediaUrl(p.imagen_url)" :src="resolveMediaUrl(p.imagen_url)" class="w-full h-full object-cover" />
                <span v-else class="text-[9px] text-slate-400">Sin foto</span>
              </div>
            </td>
            <td class="py-2.5 px-4">
              <div class="font-mono font-bold text-slate-900">{{ p.placa_normalizada }}</div>
              <div class="text-[10px] text-slate-400">Leída: {{ p.placa_leida }} ({{ (p.confianza_ocr * 100).toFixed(0) }}%)</div>
            </td>
            <td class="py-2.5 px-4 capitalize text-slate-700">
              <div>{{ p.categoria_detectada }} ({{ p.ejes_detectados }} ejes)</div>
              <div class="text-[10px] text-indigo-600 font-semibold">{{ p.pasajeros ?? 0 }} pasajero(s)</div>
            </td>
            <td class="py-2.5 px-4">{{ p.caseta ? p.caseta.nombre : 'Caseta General' }}</td>
            <td class="py-2.5 px-4 font-semibold text-slate-900">Bs. {{ parseFloat(p.monto).toFixed(2) }}</td>
            <td class="py-2.5 px-4">
              <span class="px-2 py-0.5 rounded text-[10px] font-medium" :class="getEstadoBadge(p.estado)">
                {{ p.estado }}
              </span>
            </td>
            <td class="py-2.5 px-4 text-slate-400">{{ formatFecha(p.created_at) }}</td>
            <td v-if="esAdmin" class="py-2.5 px-4 text-right">
              <button
                @click="confirmarEliminarPaso(p)"
                class="text-rose-600 hover:text-rose-800 font-semibold text-xs cursor-pointer hover:underline"
              >
                Eliminar
              </button>
            </td>
          </tr>
          <tr v-if="pasos.length === 0">
            <td :colspan="esAdmin ? 8 : 7" class="text-center py-10 text-slate-400 text-xs">
              No hay pasos registrados.
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="ultimaPagina > 1" class="flex items-center justify-between bg-white px-4 py-2.5 rounded-xl border border-slate-200 text-xs text-slate-600 shadow-xs">
      <span>Página {{ paginaActual }} de {{ ultimaPagina }} ({{ totalRegistros }} pasos)</span>
      <div class="flex items-center gap-2">
        <button @click="cargarPasos(paginaActual - 1)" :disabled="paginaActual <= 1" class="px-3 py-1 rounded-lg border border-slate-200 hover:bg-slate-50 disabled:opacity-40 cursor-pointer font-semibold">Anterior</button>
        <button @click="cargarPasos(paginaActual + 1)" :disabled="paginaActual >= ultimaPagina" class="px-3 py-1 rounded-lg border border-slate-200 hover:bg-slate-50 disabled:opacity-40 cursor-pointer font-semibold">Siguiente</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { toast } from 'vue-sonner'
import { useIosDialog } from '../services/useIosDialog'
import api, { resolveMediaUrl } from '../services/api'

const pasos = ref([])
const paginaActual = ref(1)
const ultimaPagina = ref(1)
const totalRegistros = ref(0)
const iosDialog = useIosDialog()

const esAdmin = computed(() => {
  try {
    return JSON.parse(localStorage.getItem('peaje_user') || 'null')?.rol === 'administrador'
  } catch {
    return false
  }
})

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

async function cargarPasos(page = 1) {
  if (page < 1) return
  try {
    const res = await api.get('/pasos', { params: { page } })
    pasos.value = res.data.data || []
    paginaActual.value = res.data.current_page ?? 1
    ultimaPagina.value = res.data.last_page ?? 1
    totalRegistros.value = res.data.total ?? pasos.value.length
  } catch (err) {
    console.error(err)
  }
}

function confirmarEliminarPaso(p) {
  iosDialog.confirmar({
    title: `¿Eliminar paso ${p.placa_normalizada || p.placa_leida}?`,
    message: `Se eliminará este registro (Bs. ${parseFloat(p.monto).toFixed(2)}) y sus alertas asociadas. Si fue cobrado a un vehículo registrado, se reembolsará su saldo.`,
    confirmLabel: 'Eliminar',
    onConfirm: async () => {
      try {
        await api.delete(`/pasos/${p.id}`)
        toast.success('Registro eliminado correctamente')
        await cargarPasos(paginaActual.value)
      } catch (err) {
        toast.error('No se pudo eliminar el registro', { description: err.response?.data?.message || err.message })
      }
    },
  })
}

function confirmarLimpiarSinPlaca() {
  iosDialog.confirmar({
    title: '¿Limpiar todos los registros SINPLACA?',
    message: 'Se eliminarán todos los falsos registros sin placa legible (SINPLACA / ilegibles) y sus alertas.',
    confirmLabel: 'Limpiar',
    onConfirm: async () => {
      try {
        const res = await api.delete('/pasos/limpiar/sin-placa')
        toast.success(res.data?.message || 'Registros sin placa eliminados')
        await cargarPasos(1)
      } catch (err) {
        toast.error('No se pudo limpiar registros', { description: err.response?.data?.message || err.message })
      }
    },
  })
}

onMounted(() => cargarPasos(1))
</script>
