<template>
  <div class="space-y-6">
    <!-- Encabezado con estado en vivo -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-2 border-b border-slate-200">
      <div>
        <h1 class="text-xl font-bold text-slate-900 tracking-tight">Monitoreo de Caseta en Vivo</h1>
        <p class="text-xs text-slate-500 mt-0.5">Transmisión instantánea de pasos y cobros en caseta</p>
      </div>
      <div class="flex items-center gap-2">
        <button
          @click="cargarResumen"
          :disabled="cargando"
          class="p-2 bg-white hover:bg-slate-100 border border-slate-200 rounded-xl text-slate-600 hover:text-slate-900 transition shadow-2xs cursor-pointer"
          title="Actualizar datos"
        >
          <svg class="w-4 h-4" :class="{ 'animate-spin': cargando }" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
        <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200 shadow-2xs">
          <span class="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
          Conectado en Vivo
        </span>
      </div>
    </div>

    <!-- Indicadores Métricos Claves -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <div class="bg-white border border-slate-200/90 rounded-2xl p-4.5 shadow-xs interactive-card relative overflow-hidden">
        <div class="absolute top-0 left-0 w-1 h-full bg-blue-500"></div>
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Tránsitos de Hoy</span>
          <span class="w-9 h-9 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center border border-blue-100">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" /></svg>
          </span>
        </div>
        <div class="mt-3 flex items-baseline gap-2">
          <span class="text-3xl font-extrabold text-slate-900 tracking-tight">{{ stats.pasos_hoy }}</span>
          <span class="text-xs font-medium text-blue-600 bg-blue-50 px-1.5 py-0.5 rounded">{{ stats.total_pasos }} acum. • {{ stats.vehiculos_registrados }} padrón</span>
        </div>
      </div>

      <div class="bg-white border border-slate-200/90 rounded-2xl p-4.5 shadow-xs interactive-card relative overflow-hidden">
        <div class="absolute top-0 left-0 w-1 h-full bg-emerald-500"></div>
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Recaudación Total</span>
          <span class="w-9 h-9 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center border border-emerald-100">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
          </span>
        </div>
        <div class="mt-3 flex items-baseline gap-2">
          <span class="text-3xl font-extrabold text-slate-900 tracking-tight">Bs. {{ stats.recaudacion_hoy.toFixed(2) }}</span>
          <span class="text-xs font-medium text-emerald-700 bg-emerald-50 px-1.5 py-0.5 rounded">Cobrado</span>
        </div>
      </div>

      <div class="bg-white border border-slate-200/90 rounded-2xl p-4.5 shadow-xs interactive-card relative overflow-hidden">
        <div class="absolute top-0 left-0 w-1 h-full bg-amber-500"></div>
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Alertas Activas</span>
          <span class="w-9 h-9 rounded-xl bg-amber-50 text-amber-600 flex items-center justify-center border border-amber-100">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
          </span>
        </div>
        <div class="mt-3 flex items-baseline gap-2">
          <span class="text-3xl font-extrabold text-amber-700 tracking-tight">{{ stats.alertas_pendientes }}</span>
          <span class="text-xs font-medium text-amber-700 bg-amber-50 px-1.5 py-0.5 rounded">Pendientes</span>
        </div>
      </div>

      <div class="bg-white border border-slate-200/90 rounded-2xl p-4.5 shadow-xs interactive-card relative overflow-hidden">
        <div class="absolute top-0 left-0 w-1 h-full bg-indigo-500"></div>
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Infraestructura Nube</span>
          <span class="w-9 h-9 rounded-xl bg-indigo-50 text-indigo-600 flex items-center justify-center border border-indigo-100">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2" /></svg>
          </span>
        </div>
        <div class="mt-3">
          <span class="text-sm font-bold text-slate-800 block">RunPod GPU + API</span>
          <span class="text-[11px] font-medium text-indigo-600">Inferencia en Tiempo Real</span>
        </div>
      </div>
    </div>

    <!-- Feed Principal: Tabla de Tránsitos + Alertas de Caseta -->
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 bg-white border border-slate-200/90 rounded-2xl shadow-xs overflow-hidden flex flex-col">
        <div class="px-5 py-3.5 border-b border-slate-100 flex items-center justify-between bg-slate-50/50">
          <div class="flex items-center gap-2">
            <h2 class="text-xs font-bold text-slate-900 uppercase tracking-wider">Flujo de Vehículos en Tiempo Real</h2>
            <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
          </div>
          <span class="text-[11px] font-medium text-slate-500">{{ ultimosPasos.length }} registros cargados</span>
        </div>

        <div class="overflow-x-auto flex-1">
          <table class="w-full text-left text-xs text-slate-600">
            <thead class="bg-slate-50 text-[11px] uppercase tracking-wider text-slate-500 border-b border-slate-200">
              <tr>
                <th class="py-3 px-4 font-semibold">Evidencia</th>
                <th class="py-3 px-4 font-semibold">Placa / Conf.</th>
                <th class="py-3 px-4 font-semibold">Categoría & Ejes</th>
                <th class="py-3 px-4 font-semibold">Tarifa</th>
                <th class="py-3 px-4 font-semibold">Estado</th>
                <th class="py-3 px-4 font-semibold">Hora</th>
                <th v-if="esAdmin" class="py-3 px-3 font-semibold text-right"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="p in ultimosPasos" :key="p.id" class="hover:bg-blue-50/40 transition-colors animate-new-row">
                <td class="py-2.5 px-4">
                  <div class="w-12 h-9 rounded-lg bg-slate-100 border border-slate-200 overflow-hidden flex items-center justify-center shadow-2xs">
                    <img v-if="resolveMediaUrl(p.imagen_url)" :src="resolveMediaUrl(p.imagen_url)" class="w-full h-full object-cover" />
                    <span v-else class="text-[9px] text-slate-400 font-medium">Sin foto</span>
                  </div>
                </td>
                <td class="py-2.5 px-4">
                  <div class="font-mono font-bold text-blue-950 text-xs">{{ p.placa_normalizada || p.placa_leida }}</div>
                  <div class="text-[10px] text-slate-400 font-sans">Confianza: {{ (p.confianza_ocr * 100).toFixed(0) }}%</div>
                </td>
                <td class="py-2.5 px-4 text-slate-700 font-medium">
                  <div class="capitalize">{{ p.categoria_detectada }} • {{ p.ejes_detectados }} ejes</div>
                  <div class="text-[10px] text-indigo-600 font-semibold flex items-center gap-1 mt-0.5">
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" /></svg>
                    <span>{{ p.pasajeros ?? 0 }} {{ (p.pasajeros ?? 0) === 1 ? 'pasajero' : 'pasajeros' }}</span>
                  </div>
                </td>
                <td class="py-2.5 px-4 font-bold text-slate-900">
                  Bs. {{ parseFloat(p.monto).toFixed(2) }}
                </td>
                <td class="py-2.5 px-4">
                  <span class="inline-block px-2.5 py-1 rounded-md text-[10px] font-semibold" :class="getEstadoBadge(p.estado)">
                    {{ p.estado }}
                  </span>
                </td>
                <td class="py-2.5 px-4 text-slate-400 whitespace-nowrap text-[11px]">
                  {{ formatHora(p.created_at) }}
                </td>
                <td v-if="esAdmin" class="py-2.5 px-3 text-right">
                  <button
                    @click="confirmarEliminarPaso(p)"
                    title="Eliminar registro erróneo"
                    class="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 transition cursor-pointer"
                  >
                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                  </button>
                </td>
              </tr>
              <tr v-if="ultimosPasos.length === 0">
                <td :colspan="esAdmin ? 7 : 6" class="text-center py-12 text-slate-400 text-xs">
                  Aún no se han recibido tránsitos hoy.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Feed de Alertas (1 columna) -->
      <div class="bg-white border border-slate-200/90 rounded-2xl shadow-xs p-5 flex flex-col">
        <div class="flex items-center justify-between pb-3 border-b border-slate-100 mb-4">
          <div class="flex items-center gap-2">
            <h2 class="text-xs font-bold text-slate-900 uppercase tracking-wider">Alertas de Caseta</h2>
            <span class="w-2 h-2 rounded-full bg-rose-500 animate-pulse"></span>
          </div>
          <span class="text-[11px] font-semibold text-rose-600 bg-rose-50 px-2 py-0.5 rounded-md">{{ ultimasAlertas.length }} registradas</span>
        </div>

        <div class="space-y-3 overflow-y-auto max-h-[460px] pr-1 flex-1">
          <div
            v-for="a in ultimasAlertas"
            :key="a.id"
            class="p-3.5 rounded-xl border text-xs transition-all animate-new-row"
            :class="a.atendida ? 'bg-slate-50 border-slate-200 opacity-60' : 'bg-amber-50/70 border-amber-200 shadow-xs'"
          >
            <div class="flex items-center justify-between gap-2 mb-1.5">
              <span class="font-bold tracking-tight" :class="a.atendida ? 'text-slate-500' : 'text-amber-900'">
                {{ a.tipo === 'placa_no_registrada' ? '⚠️ Vehículo No Registrado' : '⚠️ Saldo Insuficiente' }}
              </span>
              <span class="text-[10px] text-slate-400">{{ formatHora(a.created_at) }}</span>
            </div>
            <p class="text-slate-700 leading-relaxed mb-2.5 font-medium">{{ a.mensaje }}</p>
            <div class="flex items-center justify-between pt-2 border-t border-slate-200/60">
              <span class="text-[10px] font-semibold" :class="a.atendida ? 'text-slate-400' : 'text-amber-800'">
                {{ a.atendida ? 'Atendida' : 'Requiere Cobro Manual' }}
              </span>
              <button
                v-if="!a.atendida"
                @click="atenderAlerta(a.id)"
                class="px-2.5 py-1 bg-white hover:bg-slate-50 active:scale-95 border border-slate-300 text-slate-700 rounded-lg text-[10px] font-bold transition-all cursor-pointer shadow-2xs"
              >
                Marcar Atendida
              </button>
            </div>
          </div>

          <div v-if="ultimasAlertas.length === 0" class="text-center py-12 text-slate-400 text-xs">
            No hay alertas registradas en este momento.
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { toast } from 'vue-sonner'
import { useIosDialog } from '../services/useIosDialog'
import api, { resolveMediaUrl } from '../services/api'

const iosDialog = useIosDialog()

const esAdmin = computed(() => {
  try {
    return JSON.parse(localStorage.getItem('peaje_user') || 'null')?.rol === 'administrador'
  } catch {
    return false
  }
})

const stats = ref({
  pasos_hoy: 0,
  total_pasos: 0,
  recaudacion_hoy: 0,
  vehiculos_registrados: 0,
  alertas_pendientes: 0,
})

const ultimosPasos = ref([])
const ultimasAlertas = ref([])
const cargando = ref(false)
let eventSource = null
let pollInterval = null

function getEstadoBadge(estado) {
  switch (estado) {
    case 'Registrada y con paso': return 'bg-emerald-50 text-emerald-800 border border-emerald-200'
    case 'Registrada sin paso': return 'bg-blue-50 text-blue-800 border border-blue-200'
    case 'Identificada no registrada': return 'bg-rose-50 text-rose-800 border border-rose-200'
    default: return 'bg-slate-100 text-slate-700 border border-slate-200'
  }
}

function formatHora(dateStr) {
  if (!dateStr) return ''
  const d = new Date(dateStr)
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

async function cargarResumen() {
  cargando.value = true
  try {
    const res = await api.get('/panel/resumen')
    stats.value.pasos_hoy = res.data.pasos_hoy ?? res.data.total_pasos ?? 0
    stats.value.total_pasos = res.data.total_pasos ?? 0
    stats.value.recaudacion_hoy = Number(res.data.recaudacion_hoy ?? 0)
    stats.value.vehiculos_registrados = res.data.vehiculos_registrados ?? 0
    stats.value.alertas_pendientes = res.data.alertas_pendientes ?? 0
    ultimosPasos.value = res.data.ultimos_pasos || []
    ultimasAlertas.value = res.data.ultimas_alertas || []
  } catch (err) {
    console.error('Error cargando resumen:', err)
  } finally {
    cargando.value = false
  }
}

async function atenderAlerta(id) {
  try {
    await api.patch(`/alertas/${id}/atender`)
    cargarResumen()
  } catch (err) {
    console.error(err)
  }
}

function confirmarEliminarPaso(p) {
  iosDialog.confirmar({
    title: `¿Eliminar paso ${p.placa_normalizada || p.placa_leida}?`,
    message: `Se eliminará este registro erróneo (Bs. ${parseFloat(p.monto).toFixed(2)}) y se actualizarán los contadores.`,
    confirmLabel: 'Eliminar',
    onConfirm: async () => {
      try {
        await api.delete(`/pasos/${p.id}`)
        toast.success('Paso eliminado correctamente')
        await cargarResumen()
      } catch (err) {
        toast.error('No se pudo eliminar', { description: err.response?.data?.message || err.message })
      }
    },
  })
}

function iniciarTiempoReal() {
  const token = localStorage.getItem('peaje_token') || ''
  const url = `${api.defaults.baseURL}/stream/eventos?token=${encodeURIComponent(token)}`
  try {
    eventSource = new EventSource(url)

    eventSource.addEventListener('nuevo_paso', (e) => {
      const paso = JSON.parse(e.data)
      if (!ultimosPasos.value.some((x) => x.id === paso.id)) {
        ultimosPasos.value.unshift(paso)
        if (ultimosPasos.value.length > 10) ultimosPasos.value.pop()
        stats.value.pasos_hoy += 1
        stats.value.total_pasos += 1
        stats.value.recaudacion_hoy += parseFloat(paso.monto || 0)
      }
    })

    eventSource.addEventListener('nueva_alerta', (e) => {
      const alerta = JSON.parse(e.data)
      if (!ultimasAlertas.value.some((x) => x.id === alerta.id)) {
        ultimasAlertas.value.unshift(alerta)
        if (ultimasAlertas.value.length > 10) ultimasAlertas.value.pop()
        stats.value.alertas_pendientes += 1
      }
    })

    eventSource.onerror = () => {
      // Reconexión automática o polling de respaldo
    }
  } catch (e) {
    console.warn('SSE no disponible, usando polling:', e)
  }

  // Sondeo cada 4 segundos como respaldo ultra-confiable
  pollInterval = setInterval(() => {
    cargarResumen()
  }, 4000)
}

onMounted(() => {
  cargarResumen()
  iniciarTiempoReal()
})

onUnmounted(() => {
  if (eventSource) eventSource.close()
  if (pollInterval) clearInterval(pollInterval)
})
</script>
