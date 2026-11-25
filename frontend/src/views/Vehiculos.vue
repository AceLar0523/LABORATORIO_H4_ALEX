<template>
  <div class="space-y-5">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-2 border-b border-slate-200">
      <div>
        <h1 class="text-xl font-bold text-slate-900 tracking-tight">Padrón de Vehículos Registrados</h1>
        <p class="text-xs text-slate-500 mt-0.5">Gestión de placas, propietarios, categorías y saldos prepago</p>
      </div>
      <button
        v-if="esAdmin"
        @click="abrirModalCrear"
        class="bg-blue-600 hover:bg-blue-700 active:scale-95 text-white text-xs font-semibold py-2 px-3.5 rounded-xl transition-all shadow-xs cursor-pointer flex items-center gap-1.5"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" /></svg>
        <span>Registrar Vehículo</span>
      </button>
    </div>

    <!-- Aviso de solo lectura si no es administrador -->
    <div
      v-if="!esAdmin"
      class="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 text-xs text-amber-900 flex items-center gap-2"
    >
      <svg class="w-4 h-4 text-amber-600 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <span>Vista de solo lectura. Solo los usuarios con rol <strong>Administrador</strong> pueden crear, editar o eliminar vehículos.</span>
    </div>

    <!-- Buscador y Filtro -->
    <div class="bg-white p-3 rounded-xl border border-slate-200/90 flex items-center justify-between gap-3 shadow-xs">
      <div class="relative flex-1 max-w-sm">
        <span class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400">
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" /></svg>
        </span>
        <input
          v-model="busqueda"
          @input="buscar"
          type="text"
          placeholder="Buscar por placa o propietario..."
          class="bg-slate-50 border border-slate-200 rounded-lg pl-9 pr-3 py-1.5 text-xs text-slate-900 w-full focus:outline-none focus:border-blue-500 focus:bg-white"
        />
      </div>
      <span class="text-xs text-slate-400 font-medium">{{ totalRegistros }} vehículos registrados (pág. {{ paginaActual }}/{{ ultimaPagina }})</span>
    </div>

    <!-- Tabla -->
    <div class="bg-white rounded-xl border border-slate-200/90 overflow-x-auto shadow-xs">
      <table class="w-full text-left text-xs text-slate-600">
        <thead class="bg-slate-50 text-[11px] uppercase tracking-wider text-slate-500 border-b border-slate-200">
          <tr>
            <th class="py-3 px-4 font-semibold">Placa</th>
            <th class="py-3 px-4 font-semibold">Propietario</th>
            <th class="py-3 px-4 font-semibold">Categoría</th>
            <th class="py-3 px-4 font-semibold">Ejes</th>
            <th class="py-3 px-4 font-semibold">Saldo</th>
            <th class="py-3 px-4 font-semibold">Estado</th>
            <th v-if="esAdmin" class="py-3 px-4 font-semibold text-right">Acciones</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="v in vehiculos" :key="v.id" class="hover:bg-blue-50/40 transition-colors">
            <td class="py-3 px-4 font-mono font-bold text-blue-950 text-xs">{{ v.placa }}</td>
            <td class="py-3 px-4 text-slate-800 font-medium">{{ v.propietario }}</td>
            <td class="py-3 px-4 capitalize text-slate-600">{{ v.categoria }}</td>
            <td class="py-3 px-4">{{ v.ejes }} ejes</td>
            <td class="py-3 px-4 font-bold" :class="parseFloat(v.saldo) > 0 ? 'text-slate-900' : 'text-rose-600'">
              Bs. {{ parseFloat(v.saldo).toFixed(2) }}
            </td>
            <td class="py-3 px-4">
              <span class="px-2 py-0.5 text-[10px] rounded font-semibold" :class="v.activo ? 'bg-emerald-50 text-emerald-800 border border-emerald-200' : 'bg-slate-100 text-slate-600'">
                {{ v.activo ? 'Habilitado' : 'Suspendido' }}
              </span>
            </td>
            <td v-if="esAdmin" class="py-3 px-4 text-right space-x-2.5">
              <button
                @click="editar(v)"
                class="text-blue-600 hover:text-blue-800 font-semibold text-xs cursor-pointer hover:underline"
              >
                Editar
              </button>
              <button
                @click="confirmarBorrado(v)"
                class="text-rose-600 hover:text-rose-800 font-semibold text-xs cursor-pointer hover:underline"
              >
                Eliminar
              </button>
            </td>
          </tr>
          <tr v-if="vehiculos.length === 0">
            <td :colspan="esAdmin ? 7 : 6" class="text-center py-10 text-slate-400 text-xs">
              No se encontraron vehículos registrados.
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Paginación -->
    <div v-if="ultimaPagina > 1" class="flex items-center justify-between bg-white px-4 py-2.5 rounded-xl border border-slate-200/90 text-xs text-slate-600 shadow-xs">
      <span>Página {{ paginaActual }} de {{ ultimaPagina }} ({{ totalRegistros }} vehículos)</span>
      <div class="flex items-center gap-2">
        <button
          @click="cambiarPagina(paginaActual - 1)"
          :disabled="paginaActual <= 1"
          class="px-3 py-1 rounded-lg border border-slate-200 hover:bg-slate-50 disabled:opacity-40 cursor-pointer font-semibold"
        >
          Anterior
        </button>
        <button
          @click="cambiarPagina(paginaActual + 1)"
          :disabled="paginaActual >= ultimaPagina"
          class="px-3 py-1 rounded-lg border border-slate-200 hover:bg-slate-50 disabled:opacity-40 cursor-pointer font-semibold"
        >
          Siguiente
        </button>
      </div>
    </div>

    <!-- Modal Formulario Edición / Creación -->
    <div v-if="modalVisible" class="fixed inset-0 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4 z-50">
      <div class="bg-white border border-slate-200 rounded-2xl p-6 max-w-md w-full shadow-xl animate-new-row">
        <h3 class="text-base font-bold text-slate-900 mb-4">{{ form.id ? 'Editar Vehículo' : 'Registrar Nuevo Vehículo' }}</h3>
        <form @submit.prevent="guardar" class="space-y-3.5">
          <div>
            <label class="block text-xs font-semibold text-slate-700 mb-1">Número de Placa</label>
            <input v-model="form.placa" required class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 font-mono focus:outline-none focus:border-blue-500 focus:bg-white" />
          </div>
          <div>
            <label class="block text-xs font-semibold text-slate-700 mb-1">Propietario / Empresa</label>
            <input v-model="form.propietario" required class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-semibold text-slate-700 mb-1">Categoría</label>
              <select v-model="form.categoria" class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white">
                <option value="auto">Auto</option>
                <option value="moto">Moto</option>
                <option value="minibus">Minibús</option>
                <option value="bus">Bus</option>
                <option value="camion">Camión</option>
                <option value="trailer">Tráiler</option>
              </select>
            </div>
            <div>
              <label class="block text-xs font-semibold text-slate-700 mb-1">Número de Ejes</label>
              <input v-model.number="form.ejes" type="number" min="1" max="10" required class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white" />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3 items-end">
            <div>
              <label class="block text-xs font-semibold text-slate-700 mb-1">Saldo Prepago (Bs.)</label>
              <input v-model.number="form.saldo" type="number" step="0.5" min="0" class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white" />
            </div>
            <label class="flex items-center gap-2 text-xs font-medium text-slate-700 pb-2 cursor-pointer select-none">
              <input v-model="form.activo" type="checkbox" class="rounded border-slate-300 text-blue-600 focus:ring-blue-500" />
              <span>Vehículo habilitado</span>
            </label>
          </div>
          <div class="flex justify-end gap-2.5 mt-5 pt-3 border-t border-slate-100">
            <button type="button" @click="modalVisible = false" class="px-3.5 py-2 rounded-xl text-xs text-slate-600 hover:bg-slate-100 cursor-pointer font-medium">Cancelar</button>
            <button
              type="submit"
              :disabled="guardando"
              class="px-4 py-2 bg-blue-600 hover:bg-blue-700 active:scale-95 text-white rounded-xl text-xs font-semibold transition cursor-pointer flex items-center gap-1.5"
            >
              <svg v-if="guardando" class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
              </svg>
              <span>{{ guardando ? 'Guardando...' : 'Guardar Cambios' }}</span>
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

const vehiculos = ref([])
const busqueda = ref('')
const paginaActual = ref(1)
const ultimaPagina = ref(1)
const totalRegistros = ref(0)
const modalVisible = ref(false)
const guardando = ref(false)
const form = ref({ id: null, placa: '', propietario: '', categoria: 'auto', ejes: 2, saldo: 0, activo: true })

const iosDialog = useIosDialog()

const esAdmin = computed(() => {
  try {
    return JSON.parse(localStorage.getItem('peaje_user') || 'null')?.rol === 'administrador'
  } catch {
    return false
  }
})

async function cargar(page = paginaActual.value) {
  try {
    const res = await api.get('/vehiculos', { params: { q: busqueda.value, page } })
    vehiculos.value = res.data.data || []
    paginaActual.value = res.data.current_page ?? 1
    ultimaPagina.value = res.data.last_page ?? 1
    totalRegistros.value = res.data.total ?? vehiculos.value.length
  } catch (err) {
    console.error(err)
    toast.error('Error al sincronizar vehículos con la base de datos')
  }
}

function buscar() {
  cargar(1)
}

function cambiarPagina(nueva) {
  if (nueva < 1 || nueva > ultimaPagina.value) return
  cargar(nueva)
}

function abrirModalCrear() {
  form.value = { id: null, placa: '', propietario: '', categoria: 'auto', ejes: 2, saldo: 50, activo: true }
  modalVisible.value = true
}

function editar(v) {
  form.value = { ...v, activo: Boolean(v.activo) }
  modalVisible.value = true
}

async function guardar() {
  guardando.value = true
  try {
    if (form.value.id) {
      await api.put(`/vehiculos/${form.value.id}`, form.value)
      toast.success(`Vehículo ${form.value.placa} actualizado`, {
        description: 'Cambios guardados correctamente',
      })
    } else {
      await api.post('/vehiculos', form.value)
      toast.success(`Vehículo ${form.value.placa} registrado`, {
        description: 'Añadido al padrón oficial con éxito',
      })
    }
    modalVisible.value = false
    await cargar()
  } catch (err) {
    const msg = err.response?.data?.message || err.message
    toast.error('No se pudo guardar el vehículo', { description: msg })
  } finally {
    guardando.value = false
  }
}

function confirmarBorrado(v) {
  // Modal emergente en el centro exacto con estilo nativo de iOS
  iosDialog.confirmar({
    title: `¿Eliminar vehículo ${v.placa}?`,
    message: `Propietario: ${v.propietario}. Esta acción eliminará permanentemente el registro de la base de datos.`,
    confirmLabel: 'Eliminar',
    onConfirm: () => ejecutarEliminar(v.id, v.placa),
  })
}

async function ejecutarEliminar(id, placa) {
  const toastId = toast.loading(`Eliminando vehículo ${placa}...`)
  try {
    await api.delete(`/vehiculos/${id}`)
    toast.dismiss(toastId)
    toast.success(`Vehículo ${placa} eliminado`, {
      description: 'Registro removido de la base de datos',
    })
    await cargar()
  } catch (err) {
    toast.dismiss(toastId)
    toast.error('Error al eliminar vehículo', {
      description: err.response?.data?.message || err.message,
    })
  }
}

onMounted(cargar)
</script>
