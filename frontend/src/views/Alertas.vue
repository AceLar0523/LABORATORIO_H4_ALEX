<template>
  <div class="space-y-5">
    <div class="pb-2 border-b border-slate-200">
      <h1 class="text-xl font-bold text-slate-900 tracking-tight">Registro de Alertas e Incidentes</h1>
      <p class="text-xs text-slate-500 mt-0.5">Control de vehículos sin saldo suficiente o no registrados en caseta</p>
    </div>

    <div class="space-y-3">
      <div
        v-for="a in alertas"
        :key="a.id"
        class="bg-white border rounded-2xl p-4.5 shadow-xs flex flex-col md:flex-row md:items-center justify-between gap-4 transition-all"
        :class="a.atendida ? 'border-slate-200 opacity-60' : 'border-amber-200 bg-amber-50/30'"
      >
        <div class="flex items-start gap-3.5">
          <div class="w-10 h-10 rounded-xl flex items-center justify-center shrink-0 shadow-2xs" :class="a.atendida ? 'bg-slate-100 text-slate-400' : 'bg-amber-100 text-amber-700'">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
          </div>
          <div>
            <div class="flex items-center gap-2">
              <span class="text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-md" :class="a.atendida ? 'bg-slate-100 text-slate-500' : 'bg-amber-100 text-amber-800'">
                {{ a.tipo }}
              </span>
              <span class="text-[11px] text-slate-400">{{ new Date(a.created_at).toLocaleString() }}</span>
            </div>
            <p class="text-slate-800 text-xs font-semibold mt-1">{{ a.mensaje }}</p>
          </div>
        </div>

        <div>
          <button
            v-if="!a.atendida"
            @click="atender(a.id)"
            class="bg-white hover:bg-slate-50 active:scale-95 border border-slate-300 text-slate-700 font-bold py-1.5 px-3.5 rounded-xl text-xs transition shadow-2xs cursor-pointer"
          >
            Marcar Atendida
          </button>
          <span v-else class="text-xs text-slate-400 font-semibold flex items-center gap-1">
            <svg class="w-4 h-4 text-emerald-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" /></svg>
            Resuelta
          </span>
        </div>
      </div>
    </div>

    <div v-if="ultimaPagina > 1" class="flex items-center justify-between bg-white px-4 py-2.5 rounded-xl border border-slate-200 text-xs text-slate-600 shadow-xs">
      <span>Página {{ paginaActual }} de {{ ultimaPagina }} ({{ totalRegistros }} alertas)</span>
      <div class="flex items-center gap-2">
        <button @click="cargarAlertas(paginaActual - 1)" :disabled="paginaActual <= 1" class="px-3 py-1 rounded-lg border border-slate-200 hover:bg-slate-50 disabled:opacity-40 cursor-pointer font-semibold">Anterior</button>
        <button @click="cargarAlertas(paginaActual + 1)" :disabled="paginaActual >= ultimaPagina" class="px-3 py-1 rounded-lg border border-slate-200 hover:bg-slate-50 disabled:opacity-40 cursor-pointer font-semibold">Siguiente</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { toast } from 'vue-sonner'
import api from '../services/api'

const alertas = ref([])
const paginaActual = ref(1)
const ultimaPagina = ref(1)
const totalRegistros = ref(0)

async function cargarAlertas(page = paginaActual.value) {
  if (page < 1) return
  try {
    const res = await api.get('/alertas', { params: { page } })
    alertas.value = res.data.data || []
    paginaActual.value = res.data.current_page ?? 1
    ultimaPagina.value = res.data.last_page ?? 1
    totalRegistros.value = res.data.total ?? alertas.value.length
  } catch (err) {
    console.error(err)
    toast.error('Error al obtener alertas')
  }
}

async function atender(id) {
  try {
    await api.patch(`/alertas/${id}/atender`)
    toast.success('Alerta resuelta', {
      description: 'El incidente fue marcado como atendido por el operador',
    })
    cargarAlertas(paginaActual.value)
  } catch (err) {
    toast.error('No se pudo marcar la alerta', {
      description: err.response?.data?.message || err.message,
    })
  }
}

onMounted(() => cargarAlertas(1))
</script>
