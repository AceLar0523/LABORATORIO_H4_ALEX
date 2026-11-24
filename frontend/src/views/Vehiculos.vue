<template>
  <div class="space-y-6">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold text-white">Padrón de Vehículos</h1>
        <p class="text-slate-400 text-sm">Gestión de placas registradas, categorías, ejes y saldo</p>
      </div>
      <button @click="abrirModalCrear" class="bg-blue-600 hover:bg-blue-500 text-white font-medium py-2 px-4 rounded-xl shadow transition cursor-pointer">
        + Registrar Vehículo
      </button>
    </div>

    <!-- Buscador -->
    <div class="bg-slate-800 p-4 rounded-2xl border border-slate-700 flex gap-4">
      <input
        v-model="busqueda"
        @input="buscar"
        type="text"
        placeholder="Buscar por placa o propietario..."
        class="bg-slate-900 border border-slate-700 rounded-xl px-4 py-2 text-white w-full max-w-md focus:outline-none focus:border-blue-500"
      />
    </div>

    <!-- Tabla -->
    <div class="bg-slate-800 rounded-2xl border border-slate-700 overflow-hidden shadow-xl">
      <table class="w-full text-left text-sm text-slate-300">
        <thead class="bg-slate-900/80 text-xs uppercase text-slate-400 border-b border-slate-700">
          <tr>
            <th class="py-3.5 px-4">Placa</th>
            <th class="py-3.5 px-4">Propietario</th>
            <th class="py-3.5 px-4">Categoría</th>
            <th class="py-3.5 px-4">Ejes</th>
            <th class="py-3.5 px-4">Saldo</th>
            <th class="py-3.5 px-4">Estado</th>
            <th class="py-3.5 px-4 text-right">Acciones</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-700/50">
          <tr v-for="v in vehiculos" :key="v.id" class="hover:bg-slate-700/30 transition">
            <td class="py-3.5 px-4 font-mono font-bold text-white">{{ v.placa }}</td>
            <td class="py-3.5 px-4">{{ v.propietario }}</td>
            <td class="py-3.5 px-4 capitalize">{{ v.categoria }}</td>
            <td class="py-3.5 px-4">{{ v.ejes }}</td>
            <td class="py-3.5 px-4 font-semibold" :class="parseFloat(v.saldo) > 0 ? 'text-emerald-400' : 'text-red-400'">
              Bs. {{ parseFloat(v.saldo).toFixed(2) }}
            </td>
            <td class="py-3.5 px-4">
              <span class="px-2 py-0.5 text-xs rounded-full" :class="v.activo ? 'bg-emerald-500/20 text-emerald-400' : 'bg-red-500/20 text-red-400'">
                {{ v.activo ? 'Activo' : 'Inactivo' }}
              </span>
            </td>
            <td class="py-3.5 px-4 text-right space-x-2">
              <button @click="editar(v)" class="text-blue-400 hover:text-blue-300 font-medium text-xs">Editar</button>
              <button @click="eliminar(v.id)" class="text-red-400 hover:text-red-300 font-medium text-xs">Eliminar</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Modal Formulario -->
    <div v-if="modalVisible" class="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div class="bg-slate-800 border border-slate-700 rounded-2xl p-6 max-w-md w-full shadow-2xl">
        <h3 class="text-lg font-bold text-white mb-4">{{ form.id ? 'Editar Vehículo' : 'Nuevo Vehículo' }}</h3>
        <form @submit.prevent="guardar" class="space-y-4">
          <div>
            <label class="block text-xs font-semibold text-slate-400 mb-1">Número de Placa</label>
            <input v-model="form.placa" required uppercase class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-white" />
          </div>
          <div>
            <label class="block text-xs font-semibold text-slate-400 mb-1">Propietario</label>
            <input v-model="form.propietario" required class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-white" />
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-xs font-semibold text-slate-400 mb-1">Categoría</label>
              <select v-model="form.categoria" class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-white">
                <option value="auto">Auto</option>
                <option value="moto">Moto</option>
                <option value="minibus">Minibús</option>
                <option value="bus">Bus</option>
                <option value="camion">Camión</option>
              </select>
            </div>
            <div>
              <label class="block text-xs font-semibold text-slate-400 mb-1">Número de Ejes</label>
              <input v-model.number="form.ejes" type="number" min="2" max="10" required class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-white" />
            </div>
          </div>
          <div>
            <label class="block text-xs font-semibold text-slate-400 mb-1">Saldo Inicial (Bs.)</label>
            <input v-model.number="form.saldo" type="number" step="0.5" class="w-full bg-slate-900 border border-slate-700 rounded-xl px-3 py-2 text-white" />
          </div>
          <div class="flex justify-end gap-3 mt-6">
            <button type="button" @click="modalVisible = false" class="px-4 py-2 rounded-xl text-slate-400 hover:text-white">Cancelar</button>
            <button type="submit" class="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl font-medium">Guardar</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const vehiculos = ref([])
const busqueda = ref('')
const modalVisible = ref(false)
const form = ref({ id: null, placa: '', propietario: '', categoria: 'auto', ejes: 2, saldo: 0 })

async function cargar() {
  try {
    const res = await api.get('/vehiculos', { params: { q: busqueda.value } })
    vehiculos.value = res.data.data
  } catch (err) {
    console.error(err)
  }
}

function buscar() {
  cargar()
}

function abrirModalCrear() {
  form.value = { id: null, placa: '', propietario: '', categoria: 'auto', ejes: 2, saldo: 50 }
  modalVisible.value = true
}

function editar(v) {
  form.value = { ...v }
  modalVisible.value = true
}

async function guardar() {
  try {
    if (form.value.id) {
      await api.put(`/vehiculos/${form.value.id}`, form.value)
    } else {
      await api.post('/vehiculos', form.value)
    }
    modalVisible.value = false
    cargar()
  } catch (err) {
    alert('Error al guardar vehículo: ' + (err.response?.data?.message || err.message))
  }
}

async function eliminar(id) {
  if (confirm('¿Deseas eliminar este vehículo?')) {
    await api.delete(`/vehiculos/${id}`)
    cargar()
  }
}

onMounted(cargar)
</script>

