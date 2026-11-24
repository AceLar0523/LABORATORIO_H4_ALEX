<template>
  <div class="space-y-6">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-white">Centro de Alertas</h1>
        <p class="text-slate-400 text-sm">Detección de vehículos sin saldo o no registrados</p>
      </div>
    </div>

    <div class="grid grid-cols-1 gap-4">
      <div
        v-for="a in alertas"
        :key="a.id"
        class="bg-slate-800 border rounded-2xl p-5 shadow-lg flex flex-col md:flex-row md:items-center justify-between gap-4 transition"
        :class="a.atendida ? 'border-slate-700/60 opacity-60' : 'border-red-500/40 bg-red-500/5'"
      >
        <div class="flex items-start gap-4">
          <div class="w-12 h-12 rounded-xl flex items-center justify-center shrink-0" :class="a.atendida ? 'bg-slate-700 text-slate-400' : 'bg-red-500/20 text-red-400'">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
          </div>
          <div>
            <div class="flex items-center gap-3">
              <span class="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded" :class="a.atendida ? 'bg-slate-700 text-slate-300' : 'bg-red-500/20 text-red-400'">
                {{ a.tipo }}
              </span>
              <span class="text-xs text-slate-500">{{ new Date(a.created_at).toLocaleString() }}</span>
            </div>
            <p class="text-white font-medium mt-1 text-base">{{ a.mensaje }}</p>
          </div>
        </div>

        <div>
          <button
            v-if="!a.atendida"
            @click="atender(a.id)"
            class="bg-red-600 hover:bg-red-500 text-white font-medium py-2 px-4 rounded-xl text-xs transition cursor-pointer"
          >
            Marcar Atendida
          </button>
          <span v-else class="text-xs text-slate-500 font-medium">✓ Resuelta</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const alertas = ref([])

async function cargarAlertas() {
  try {
    const res = await api.get('/alertas')
    alertas.value = res.data.data
  } catch (err) {
    console.error(err)
  }
}

async function atender(id) {
  try {
    await api.patch(`/alertas/${id}/atender`)
    cargarAlertas()
  } catch (err) {
    console.error(err)
  }
}

onMounted(cargarAlertas)
</script>

