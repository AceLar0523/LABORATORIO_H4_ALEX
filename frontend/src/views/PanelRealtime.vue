<template>
  <div class="space-y-6">
    <!-- Métricas principales en vivo -->
    <div class="grid grid-cols-1 md:grid-cols-4 gap-5">
      <div class="bg-slate-800 border border-slate-700/80 rounded-2xl p-5 shadow-lg relative overflow-hidden">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Pasos Hoy</p>
            <h3 class="text-3xl font-extrabold text-white mt-1">{{ stats.total_pasos }}</h3>
          </div>
          <div class="w-12 h-12 rounded-xl bg-blue-500/20 text-blue-400 flex items-center justify-center">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" /></svg>
          </div>
        </div>
        <div class="mt-3 flex items-center gap-1.5 text-xs text-emerald-400">
          <span class="inline-block w-2 h-2 rounded-full bg-emerald-500 animate-ping"></span>
          <span>En tiempo real vía SSE</span>
        </div>
      </div>

      <div class="bg-slate-800 border border-slate-700/80 rounded-2xl p-5 shadow-lg">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Recaudación Hoy</p>
            <h3 class="text-3xl font-extrabold text-white mt-1">Bs. {{ stats.recaudacion_hoy.toFixed(2) }}</h3>
          </div>
          <div class="w-12 h-12 rounded-xl bg-emerald-500/20 text-emerald-400 flex items-center justify-center">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
          </div>
        </div>
        <p class="mt-3 text-xs text-slate-400">Tarifas cobradas en casetas</p>
      </div>

      <div class="bg-slate-800 border border-slate-700/80 rounded-2xl p-5 shadow-lg">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Alertas Activas</p>
            <h3 class="text-3xl font-extrabold text-white mt-1" :class="stats.alertas_pendientes > 0 ? 'text-red-400' : 'text-slate-300'">
              {{ stats.alertas_pendientes }}
            </h3>
          </div>
          <div class="w-12 h-12 rounded-xl bg-red-500/20 text-red-400 flex items-center justify-center">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
          </div>
        </div>
        <p class="mt-3 text-xs text-slate-400">Placas no registradas / sin saldo</p>
      </div>

      <div class="bg-slate-800 border border-slate-700/80 rounded-2xl p-5 shadow-lg">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Motor Inferencia</p>
            <h3 class="text-xl font-bold mt-2" :class="aiStatus === 'online' ? 'text-emerald-400' : 'text-amber-400'">
              {{ aiStatus === 'online' ? '● En Línea' : '○ Standby / Test' }}
            </h3>
          </div>
          <div class="w-12 h-12 rounded-xl bg-purple-500/20 text-purple-400 flex items-center justify-center">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" /></svg>
          </div>
        </div>
        <p class="mt-3 text-xs text-slate-400">M1 (Placas/OCR) + M2 + M3</p>
      </div>
    </div>

    <!-- Contenido: Últimos Pasos en Vivo y Alertas -->
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Tabla de Pasos en Vivo (2 columnas) -->
      <div class="lg:col-span-2 bg-slate-800 border border-slate-700 rounded-2xl p-6 shadow-xl">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <h2 class="text-lg font-bold text-white">Tránsito de Vehículos en Vivo</h2>
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
              Live Feed
            </span>
          </div>
          <button @click="simularPaso" class="text-xs bg-blue-600 hover:bg-blue-500 text-white font-medium py-1.5 px-3 rounded-lg transition">
            + Simular Paso Caseta
          </button>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-left text-sm text-slate-300">
            <thead class="text-xs uppercase bg-slate-900/60 text-slate-400 border-b border-slate-700">
              <tr>
                <th class="py-3 px-4">Evidencia</th>
                <th class="py-3 px-4">Placa / Conf.</th>
                <th class="py-3 px-4">Categoría / Ejes</th>
                <th class="py-3 px-4">Tarifa</th>
                <th class="py-3 px-4">Estado</th>
                <th class="py-3 px-4">Hora</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-700/50">
              <tr v-for="p in ultimosPasos" :key="p.id" class="hover:bg-slate-700/30 transition">
                <td class="py-3 px-4">
                  <div class="w-12 h-10 rounded-lg bg-slate-900 overflow-hidden border border-slate-700 flex items-center justify-center">
                    <img v-if="p.imagen_url" :src="p.imagen_url" class="w-full h-full object-cover" />
                    <span v-else class="text-[10px] text-slate-500">Sin foto</span>
                  </div>
                </td>
                <td class="py-3 px-4 font-mono font-bold text-white">
                  <div>{{ p.placa_normalizada || p.placa_leida }}</div>
                  <div class="text-[11px] text-slate-400 font-sans">Conf: {{ (p.confianza_ocr * 100).toFixed(0) }}%</div>
                </td>
                <td class="py-3 px-4 capitalize">
                  {{ p.categoria_detectada }} ({{ p.ejes_detectados }} ejes)
                </td>
                <td class="py-3 px-4 font-semibold text-emerald-400">
                  Bs. {{ parseFloat(p.monto).toFixed(2) }}
                </td>
                <td class="py-3 px-4">
                  <span class="inline-block px-2.5 py-1 rounded-full text-xs font-semibold" :class="getEstadoBadge(p.estado)">
                    {{ p.estado }}
                  </span>
                </td>
                <td class="py-3 px-4 text-xs text-slate-400 whitespace-nowrap">
                  {{ formatHora(p.created_at) }}
                </td>
              </tr>
              <tr v-if="ultimosPasos.length === 0">
                <td colspan="6" class="text-center py-8 text-slate-500">
                  Esperando registros de caseta...
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Feed de Alertas en Tiempo Real (1 columna) -->
      <div class="bg-slate-800 border border-slate-700 rounded-2xl p-6 shadow-xl flex flex-col">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-bold text-white">Alertas de Caseta</h2>
          <span class="text-xs bg-red-500/20 text-red-400 border border-red-500/30 px-2 py-0.5 rounded-full font-medium">
            Automáticas
          </span>
        </div>

        <div class="space-y-3 overflow-y-auto max-h-[480px] pr-1 flex-1">
          <div
            v-for="a in ultimasAlertas"
            :key="a.id"
            class="p-4 rounded-xl border transition"
            :class="a.atendida ? 'bg-slate-900/40 border-slate-700/60 opacity-60' : 'bg-red-500/10 border-red-500/40'"
          >
            <div class="flex items-start justify-between gap-2">
              <span class="text-xs font-bold uppercase tracking-wider" :class="a.atendida ? 'text-slate-400' : 'text-red-400'">
                {{ a.tipo === 'placa_no_registrada' ? '🚨 Placa No Registrada' : '⚠️ Saldo Insuficiente' }}
              </span>
              <span class="text-[11px] text-slate-500">{{ formatHora(a.created_at) }}</span>
            </div>
            <p class="text-sm text-slate-200 mt-1 font-medium">{{ a.mensaje }}</p>
            <div class="mt-3 flex items-center justify-between text-xs pt-2 border-t border-slate-700/50">
              <span :class="a.atendida ? 'text-slate-500' : 'text-red-300 font-semibold'">
                {{ a.atendida ? 'Atendida' : 'Requiere Intervención' }}
              </span>
              <button
                v-if="!a.atendida"
                @click="atenderAlerta(a.id)"
                class="px-2.5 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded text-[11px] transition"
              >
                Marcar Atendida
              </button>
            </div>
          </div>

          <div v-if="ultimasAlertas.length === 0" class="text-center py-12 text-slate-500 text-sm">
            No hay alertas pendientes en este momento.
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import api from '../services/api'

const stats = ref({
  total_pasos: 0,
  recaudacion_hoy: 0,
  alertas_pendientes: 0,
})

const ultimosPasos = ref([])
const ultimasAlertas = ref([])
const aiStatus = ref('online')
let eventSource = null

function getEstadoBadge(estado) {
  switch (estado) {
    case 'Registrada y con paso': return 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
    case 'Registrada sin paso': return 'bg-blue-500/20 text-blue-400 border border-blue-500/30'
    case 'Identificada no registrada': return 'bg-red-500/20 text-red-400 border border-red-500/30'
    default: return 'bg-slate-700 text-slate-300'
  }
}

function formatHora(dateStr) {
  if (!dateStr) return ''
  const d = new Date(dateStr)
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

async function cargarResumen() {
  try {
    const res = await api.get('/panel/resumen')
    stats.value.total_pasos = res.data.total_pasos
    stats.value.recaudacion_hoy = res.data.recaudacion_hoy
    stats.value.alertas_pendientes = res.data.alertas_pendientes
    ultimosPasos.value = res.data.ultimos_pasos
    ultimasAlertas.value = res.data.ultimas_alertas
  } catch (err) {
    console.error('Error cargando resumen:', err)
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

async function simularPaso() {
  try {
    const placas = ['4021XYZ', '3142ABC', '9999INV', '1540QWE', '8888EVASION']
    const randomPlaca = placas[Math.floor(Math.random() * placas.length)]
    
    // Generar un canvas mínimo o SVG en base64 para cumplir requerimiento de frame
    const canvas = document.createElement('canvas')
    canvas.width = 100
    canvas.height = 100
    const base64 = canvas.toDataURL('image/jpeg')

    await api.post('/pasos/frame', {
      frame_base64: base64,
      mock_placa: randomPlaca,
      caseta_id: 1,
    })
    cargarResumen()
  } catch (err) {
    console.error('Error simulando paso:', err)
  }
}

function iniciarSSE() {
  const url = `${api.defaults.baseURL}/stream/eventos`
  eventSource = new EventSource(url)

  eventSource.addEventListener('nuevo_paso', (e) => {
    const paso = JSON.parse(e.data)
    ultimosPasos.value.unshift(paso)
    if (ultimosPasos.value.length > 10) ultimosPasos.value.pop()
    stats.value.total_pasos += 1
    stats.value.recaudacion_hoy += parseFloat(paso.monto)
  })

  eventSource.addEventListener('nueva_alerta', (e) => {
    const alerta = JSON.parse(e.data)
    ultimasAlertas.value.unshift(alerta)
    if (ultimasAlertas.value.length > 10) ultimasAlertas.value.pop()
    stats.value.alertas_pendientes += 1
  })

  eventSource.onerror = () => {
    // Si se interrumpe, el navegador reconecta automáticamente
  }
}

onMounted(() => {
  cargarResumen()
  iniciarSSE()
})

onUnmounted(() => {
  if (eventSource) eventSource.close()
})
</script>

