<template>
  <div class="space-y-6">
    <!-- Encabezado -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-2 border-b border-slate-200">
      <div>
        <h1 class="text-xl font-bold text-slate-900 tracking-tight">Tarifas y Casetas de Peaje</h1>
        <p class="text-xs text-slate-500 mt-0.5">Configuración de tarifas por categoría/ejes y puntos de control de caseta</p>
      </div>
      <div v-if="esAdmin" class="flex flex-wrap items-center gap-2">
        <button
          @click="confirmarRestaurarTarifas"
          class="bg-emerald-600 hover:bg-emerald-700 active:scale-95 text-white text-xs font-semibold py-2 px-3.5 rounded-xl transition-all shadow-xs cursor-pointer flex items-center gap-1.5"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" /></svg>
          <span>Restaurar Tarifas Oficiales</span>
        </button>
        <button
          @click="abrirModalTarifa()"
          class="bg-blue-600 hover:bg-blue-700 active:scale-95 text-white text-xs font-semibold py-2 px-3.5 rounded-xl transition-all shadow-xs cursor-pointer flex items-center gap-1.5"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" /></svg>
          <span>Nueva Tarifa</span>
        </button>
        <button
          @click="abrirModalCaseta()"
          class="bg-slate-900 hover:bg-slate-800 active:scale-95 text-white text-xs font-semibold py-2 px-3.5 rounded-xl transition-all shadow-xs cursor-pointer flex items-center gap-1.5"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" /></svg>
          <span>Nueva Caseta</span>
        </button>
      </div>
    </div>

    <!-- Aviso de solo lectura para Operador -->
    <div
      v-if="!esAdmin"
      class="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 text-xs text-amber-900 flex items-center gap-2"
    >
      <svg class="w-4 h-4 text-amber-600 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <span>Vista de solo lectura. Solo los usuarios con rol <strong>Administrador</strong> pueden crear, editar o eliminar tarifas y casetas.</span>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Tabla de Tarifas -->
      <div class="bg-white rounded-2xl border border-slate-200/90 overflow-hidden shadow-xs flex flex-col">
        <div class="px-5 py-3.5 border-b border-slate-100 flex items-center justify-between bg-slate-50/60">
          <h2 class="text-xs font-bold text-slate-900 uppercase tracking-wider">Tarifas Vigentes</h2>
          <span class="text-[11px] font-medium text-slate-500">{{ tarifas.length }} configuradas</span>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-xs text-slate-600">
            <thead class="bg-slate-50 text-[11px] uppercase tracking-wider text-slate-500 border-b border-slate-200">
              <tr>
                <th class="py-3 px-4 font-semibold">Categoría</th>
                <th class="py-3 px-4 font-semibold">Ejes</th>
                <th class="py-3 px-4 font-semibold">Monto</th>
                <th v-if="esAdmin" class="py-3 px-4 font-semibold text-right">Acciones</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="t in tarifas" :key="t.id" class="hover:bg-blue-50/40 transition-colors">
                <td class="py-3 px-4 font-semibold capitalize text-slate-900">{{ t.categoria }}</td>
                <td class="py-3 px-4">{{ t.ejes }} ejes</td>
                <td class="py-3 px-4 font-bold text-emerald-700">Bs. {{ parseFloat(t.monto).toFixed(2) }}</td>
                <td v-if="esAdmin" class="py-3 px-4 text-right space-x-2.5 whitespace-nowrap">
                  <button @click="abrirModalTarifa(t)" class="text-blue-600 hover:text-blue-800 font-semibold text-xs cursor-pointer hover:underline">Editar</button>
                  <button @click="confirmarEliminarTarifa(t)" class="text-rose-600 hover:text-rose-800 font-semibold text-xs cursor-pointer hover:underline">Eliminar</button>
                </td>
              </tr>
              <tr v-if="!cargando && tarifas.length === 0">
                <td :colspan="esAdmin ? 4 : 3" class="text-center py-8 text-slate-400 text-xs">No hay tarifas registradas.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Tabla de Casetas -->
      <div class="bg-white rounded-2xl border border-slate-200/90 overflow-hidden shadow-xs flex flex-col">
        <div class="px-5 py-3.5 border-b border-slate-100 flex items-center justify-between bg-slate-50/60">
          <h2 class="text-xs font-bold text-slate-900 uppercase tracking-wider">Casetas de Peaje</h2>
          <span class="text-[11px] font-medium text-slate-500">{{ casetas.length }} activas</span>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-xs text-slate-600">
            <thead class="bg-slate-50 text-[11px] uppercase tracking-wider text-slate-500 border-b border-slate-200">
              <tr>
                <th class="py-3 px-4 font-semibold">ID</th>
                <th class="py-3 px-4 font-semibold">Nombre</th>
                <th class="py-3 px-4 font-semibold">Ubicación</th>
                <th v-if="esAdmin" class="py-3 px-4 font-semibold text-right">Acciones</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="c in casetas" :key="c.id" class="hover:bg-blue-50/40 transition-colors">
                <td class="py-3 px-4 font-mono text-slate-500">#{{ c.id }}</td>
                <td class="py-3 px-4 font-semibold text-slate-900">{{ c.nombre }}</td>
                <td class="py-3 px-4 text-slate-600">{{ c.ubicacion }}</td>
                <td v-if="esAdmin" class="py-3 px-4 text-right space-x-2.5 whitespace-nowrap">
                  <button @click="abrirModalCaseta(c)" class="text-blue-600 hover:text-blue-800 font-semibold text-xs cursor-pointer hover:underline">Editar</button>
                  <button @click="confirmarEliminarCaseta(c)" class="text-rose-600 hover:text-rose-800 font-semibold text-xs cursor-pointer hover:underline">Eliminar</button>
                </td>
              </tr>
              <tr v-if="!cargando && casetas.length === 0">
                <td :colspan="esAdmin ? 4 : 3" class="text-center py-8 text-slate-400 text-xs">No hay casetas registradas.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Modal Tarifa -->
    <div v-if="modalTarifa" class="fixed inset-0 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4 z-50">
      <div class="bg-white border border-slate-200 rounded-2xl p-6 max-w-md w-full shadow-xl animate-new-row">
        <h3 class="text-base font-bold text-slate-900 mb-4">{{ formTarifa.id ? 'Editar Tarifa' : 'Nueva Tarifa' }}</h3>
        <form @submit.prevent="guardarTarifa" class="space-y-3.5">
          <div>
            <label class="block text-xs font-semibold text-slate-700 mb-1">Categoría de Vehículo</label>
            <select v-model="formTarifa.categoria" class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white">
              <option value="moto">Moto</option>
              <option value="auto">Auto</option>
              <option value="minibus">Minibús</option>
              <option value="bus">Bus</option>
              <option value="camion">Camión</option>
              <option value="trailer">Tráiler</option>
            </select>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-semibold text-slate-700 mb-1">Ejes</label>
              <input v-model.number="formTarifa.ejes" type="number" min="1" max="12" required class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white" />
            </div>
            <div>
              <label class="block text-xs font-semibold text-slate-700 mb-1">Monto (Bs.)</label>
              <input v-model.number="formTarifa.monto" type="number" step="0.5" min="0" required class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white" />
            </div>
          </div>
          <div class="flex justify-end gap-2.5 mt-5 pt-3 border-t border-slate-100">
            <button type="button" @click="modalTarifa = false" class="px-3.5 py-2 rounded-xl text-xs text-slate-600 hover:bg-slate-100 cursor-pointer font-medium">Cancelar</button>
            <button type="submit" :disabled="guardando" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-xl text-xs font-semibold transition cursor-pointer">
              {{ guardando ? 'Guardando...' : 'Guardar Tarifa' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- Modal Caseta -->
    <div v-if="modalCaseta" class="fixed inset-0 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4 z-50">
      <div class="bg-white border border-slate-200 rounded-2xl p-6 max-w-md w-full shadow-xl animate-new-row">
        <h3 class="text-base font-bold text-slate-900 mb-4">{{ formCaseta.id ? 'Editar Caseta' : 'Nueva Caseta' }}</h3>
        <form @submit.prevent="guardarCaseta" class="space-y-3.5">
          <div>
            <label class="block text-xs font-semibold text-slate-700 mb-1">Nombre de la Caseta</label>
            <input v-model="formCaseta.nombre" required placeholder="Ej. Caseta Norte Carril 2" class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white" />
          </div>
          <div>
            <label class="block text-xs font-semibold text-slate-700 mb-1">Ubicación</label>
            <input v-model="formCaseta.ubicacion" required placeholder="Ej. Autopista Km 15" class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white" />
          </div>
          <div class="flex justify-end gap-2.5 mt-5 pt-3 border-t border-slate-100">
            <button type="button" @click="modalCaseta = false" class="px-3.5 py-2 rounded-xl text-xs text-slate-600 hover:bg-slate-100 cursor-pointer font-medium">Cancelar</button>
            <button type="submit" :disabled="guardando" class="px-4 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-xl text-xs font-semibold transition cursor-pointer">
              {{ guardando ? 'Guardando...' : 'Guardar Caseta' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { toast } from 'vue-sonner'
import { useIosDialog } from '../services/useIosDialog'
import api from '../services/api'

const tarifas = ref([])
const casetas = ref([])
const cargando = ref(false)
const guardando = ref(false)

const modalTarifa = ref(false)
const formTarifa = ref({ id: null, categoria: 'auto', ejes: 2, monto: 10 })

const modalCaseta = ref(false)
const formCaseta = ref({ id: null, nombre: '', ubicacion: '' })

const iosDialog = useIosDialog()

const esAdmin = computed(() => {
  try {
    return JSON.parse(localStorage.getItem('peaje_user') || 'null')?.rol === 'administrador'
  } catch {
    return false
  }
})

async function cargarTodo() {
  cargando.value = true
  try {
    const [resTarifas, resCasetas] = await Promise.all([api.get('/tarifas'), api.get('/casetas')])
    tarifas.value = resTarifas.data || []
    casetas.value = resCasetas.data || []
  } catch (err) {
    toast.error('Error al cargar tarifas y casetas', {
      description: err.response?.data?.message || err.message,
    })
  } finally {
    cargando.value = false
  }
}

function abrirModalTarifa(t = null) {
  formTarifa.value = t
    ? { id: t.id, categoria: t.categoria, ejes: Number(t.ejes), monto: Number(t.monto) }
    : { id: null, categoria: 'auto', ejes: 2, monto: 5 }
  modalTarifa.value = true
}

function confirmarRestaurarTarifas() {
  iosDialog.confirmar({
    title: '¿Restaurar tarifas oficiales?',
    message: 'Se cargarán las tarifas realistas de referencia en Bs. (Moto Bs. 2, Auto Bs. 5, Minibús Bs. 7, Bus Bs. 12-18, Camión Bs. 12-42, Tráiler Bs. 28-45).',
    confirmLabel: 'Restaurar',
    onConfirm: async () => {
      try {
        const res = await api.post('/tarifas/restaurar')
        tarifas.value = res.data?.data || []
        toast.success('Tarifas oficiales restauradas')
      } catch (err) {
        toast.error('No se pudieron restaurar las tarifas', { description: err.response?.data?.message || err.message })
      }
    },
  })
}

function abrirModalCaseta(c = null) {
  formCaseta.value = c ? { id: c.id, nombre: c.nombre, ubicacion: c.ubicacion } : { id: null, nombre: '', ubicacion: '' }
  modalCaseta.value = true
}

async function guardarTarifa() {
  guardando.value = true
  try {
    const payload = {
      categoria: formTarifa.value.categoria,
      ejes: Number(formTarifa.value.ejes),
      monto: Number(formTarifa.value.monto),
    }
    if (formTarifa.value.id) {
      await api.put(`/tarifas/${formTarifa.value.id}`, payload)
      toast.success('Tarifa actualizada correctamente')
    } else {
      await api.post('/tarifas', payload)
      toast.success('Tarifa registrada correctamente')
    }
    modalTarifa.value = false
    await cargarTodo()
  } catch (err) {
    toast.error('No se pudo guardar la tarifa', { description: err.response?.data?.message || err.message })
  } finally {
    guardando.value = false
  }
}

function confirmarEliminarTarifa(t) {
  iosDialog.confirmar({
    title: `¿Eliminar tarifa ${t.categoria} (${t.ejes} ejes)?`,
    message: `Monto actual: Bs. ${parseFloat(t.monto).toFixed(2)}.`,
    confirmLabel: 'Eliminar',
    onConfirm: async () => {
      try {
        await api.delete(`/tarifas/${t.id}`)
        toast.success('Tarifa eliminada')
        await cargarTodo()
      } catch (err) {
        toast.error('Error al eliminar tarifa', { description: err.response?.data?.message || err.message })
      }
    },
  })
}

async function guardarCaseta() {
  guardando.value = true
  try {
    const payload = { nombre: formCaseta.value.nombre.trim(), ubicacion: formCaseta.value.ubicacion.trim() }
    if (formCaseta.value.id) {
      await api.put(`/casetas/${formCaseta.value.id}`, payload)
      toast.success('Caseta actualizada correctamente')
    } else {
      await api.post('/casetas', payload)
      toast.success('Caseta registrada correctamente')
    }
    modalCaseta.value = false
    await cargarTodo()
  } catch (err) {
    toast.error('No se pudo guardar la caseta', { description: err.response?.data?.message || err.message })
  } finally {
    guardando.value = false
  }
}

function confirmarEliminarCaseta(c) {
  iosDialog.confirmar({
    title: `¿Eliminar caseta "${c.nombre}"?`,
    message: `Ubicación: ${c.ubicacion}.`,
    confirmLabel: 'Eliminar',
    onConfirm: async () => {
      try {
        await api.delete(`/casetas/${c.id}`)
        toast.success('Caseta eliminada')
        await cargarTodo()
      } catch (err) {
        toast.error('Error al eliminar caseta', { description: err.response?.data?.message || err.message })
      }
    },
  })
}

onMounted(cargarTodo)
</script>

