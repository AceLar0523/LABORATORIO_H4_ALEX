<template>
  <div class="space-y-5">
    <!-- Encabezado -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-2 border-b border-slate-200">
      <div>
        <h1 class="text-xl font-bold text-slate-900 tracking-tight">Usuarios y Lista Blanca (Google OAuth)</h1>
        <p class="text-xs text-slate-500 mt-0.5">Gestión de cuentas Google autorizadas, roles y control de acceso al sistema</p>
      </div>
      <button
        v-if="esAdmin"
        @click="abrirModalCrear"
        class="bg-blue-600 hover:bg-blue-700 active:scale-95 text-white text-xs font-semibold py-2 px-3.5 rounded-xl transition-all shadow-xs cursor-pointer flex items-center gap-1.5"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
        <span>Autorizar Cuenta</span>
      </button>
    </div>

    <!-- Aviso de solo lectura si el usuario actual no es administrador -->
    <div
      v-if="!esAdmin"
      class="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 text-xs text-amber-900 flex items-center gap-2"
    >
      <svg class="w-4 h-4 text-amber-600 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <span>Vista de solo lectura. Solo los usuarios con rol <strong>Administrador</strong> pueden modificar la lista blanca de Google OAuth.</span>
    </div>

    <!-- Tarjetas de Resumen -->
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <div class="bg-white border border-slate-200/90 rounded-2xl p-4 shadow-xs">
        <span class="text-[11px] font-semibold text-slate-500 uppercase tracking-wider">Cuentas en Lista Blanca</span>
        <div class="mt-2 flex items-baseline gap-2">
          <span class="text-2xl font-extrabold text-slate-900">{{ resumen.total }}</span>
          <span class="text-xs text-slate-500">registradas</span>
        </div>
      </div>

      <div class="bg-white border border-slate-200/90 rounded-2xl p-4 shadow-xs">
        <span class="text-[11px] font-semibold text-slate-500 uppercase tracking-wider">Accesos Autorizados</span>
        <div class="mt-2 flex items-baseline gap-2">
          <span class="text-2xl font-extrabold text-emerald-700">{{ resumen.activos }}</span>
          <span class="text-xs text-emerald-700 bg-emerald-50 px-1.5 py-0.5 rounded font-medium">Activos</span>
        </div>
      </div>

      <div class="bg-white border border-slate-200/90 rounded-2xl p-4 shadow-xs">
        <span class="text-[11px] font-semibold text-slate-500 uppercase tracking-wider">Distribución de Roles</span>
        <div class="mt-2 flex items-center gap-3 text-xs font-semibold">
          <span class="text-indigo-700 bg-indigo-50 border border-indigo-200 px-2.5 py-1 rounded-lg">
            {{ resumen.administradores }} Admin
          </span>
          <span class="text-slate-700 bg-slate-100 border border-slate-200 px-2.5 py-1 rounded-lg">
            {{ resumen.operadores }} Operadores
          </span>
        </div>
      </div>
    </div>

    <!-- Buscador y Filtros -->
    <div class="bg-white p-3.5 rounded-xl border border-slate-200/90 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-xs">
      <div class="relative flex-1 max-w-sm">
        <span class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400">
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </span>
        <input
          v-model="filtros.q"
          @input="cargar"
          type="text"
          placeholder="Buscar por nombre o correo Google..."
          class="bg-slate-50 border border-slate-200 rounded-lg pl-9 pr-3 py-1.5 text-xs text-slate-900 w-full focus:outline-none focus:border-blue-500 focus:bg-white"
        />
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <select
          v-model="filtros.rol"
          @change="cargar"
          class="bg-slate-50 border border-slate-200 rounded-lg px-2.5 py-1.5 text-xs text-slate-700 focus:outline-none focus:border-blue-500"
        >
          <option value="">Todos los roles</option>
          <option value="administrador">Administrador</option>
          <option value="operador">Operador</option>
        </select>

        <select
          v-model="filtros.activo"
          @change="cargar"
          class="bg-slate-50 border border-slate-200 rounded-lg px-2.5 py-1.5 text-xs text-slate-700 focus:outline-none focus:border-blue-500"
        >
          <option value="">Todos los estados</option>
          <option value="true">Autorizados</option>
          <option value="false">Revocados</option>
        </select>

        <span class="text-xs text-slate-400 font-medium pl-1">{{ usuarios.length }} cuentas</span>
      </div>
    </div>

    <!-- Tabla de Lista Blanca -->
    <div class="bg-white rounded-xl border border-slate-200/90 overflow-x-auto shadow-xs">
      <table class="w-full text-left text-xs text-slate-600">
        <thead class="bg-slate-50 text-[11px] uppercase tracking-wider text-slate-500 border-b border-slate-200">
          <tr>
            <th class="py-3 px-4 font-semibold">Usuario</th>
            <th class="py-3 px-4 font-semibold">Correo Google Autorizado</th>
            <th class="py-3 px-4 font-semibold">Rol</th>
            <th class="py-3 px-4 font-semibold">Acceso</th>
            <th class="py-3 px-4 font-semibold">Estado</th>
            <th v-if="esAdmin" class="py-3 px-4 font-semibold text-right">Acciones</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="u in usuarios" :key="u.id" class="hover:bg-blue-50/40 transition-colors">
            <td class="py-3 px-4">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-full bg-slate-900 text-white text-[11px] font-bold flex items-center justify-center shrink-0">
                  {{ iniciales(u.nombre) }}
                </div>
                <div>
                  <div class="font-semibold text-slate-900 flex items-center gap-1.5">
                    <span>{{ u.nombre }}</span>
                    <span
                      v-if="usuarioActual?.id === u.id"
                      class="text-[10px] bg-blue-50 text-blue-700 border border-blue-200 px-1.5 py-0.5 rounded font-semibold"
                    >
                      Tú
                    </span>
                  </div>
                </div>
              </div>
            </td>

            <td class="py-3 px-4 font-mono text-slate-800">
              <div class="flex items-center gap-1.5">
                <svg class="w-3.5 h-3.5 shrink-0" viewBox="0 0 24 24">
                  <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                  <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                  <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"/>
                  <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
                </svg>
                <span>{{ u.email_google }}</span>
              </div>
            </td>

            <td class="py-3 px-4">
              <span
                class="px-2 py-0.5 rounded-md text-[10px] font-semibold capitalize border"
                :class="u.rol === 'administrador'
                  ? 'bg-indigo-50 text-indigo-700 border-indigo-200'
                  : 'bg-slate-100 text-slate-700 border-slate-200'"
              >
                {{ u.rol }}
              </span>
            </td>

            <td class="py-3 px-4 text-slate-600">
              <span class="px-2 py-0.5 text-[10px] rounded font-semibold bg-blue-50 text-blue-700 border border-blue-200">
                Exclusivo Google OAuth 2.0
              </span>
            </td>

            <td class="py-3 px-4">
              <span
                class="px-2 py-0.5 text-[10px] rounded font-semibold border"
                :class="u.activo
                  ? 'bg-emerald-50 text-emerald-800 border-emerald-200'
                  : 'bg-rose-50 text-rose-700 border-rose-200'"
              >
                {{ u.activo ? 'Autorizado' : 'Revocado' }}
              </span>
            </td>

            <td v-if="esAdmin" class="py-3 px-4 text-right space-x-2.5 whitespace-nowrap">
              <button
                @click="editar(u)"
                class="text-blue-600 hover:text-blue-800 font-semibold text-xs cursor-pointer hover:underline"
              >
                Editar
              </button>
              <button
                @click="confirmarToggle(u)"
                class="font-semibold text-xs cursor-pointer hover:underline"
                :class="u.activo ? 'text-amber-700 hover:text-amber-900' : 'text-emerald-700 hover:text-emerald-900'"
              >
                {{ u.activo ? 'Revocar' : 'Autorizar' }}
              </button>
              <button
                v-if="usuarioActual?.id !== u.id"
                @click="confirmarBorrado(u)"
                class="text-rose-600 hover:text-rose-800 font-semibold text-xs cursor-pointer hover:underline"
              >
                Eliminar
              </button>
            </td>
          </tr>

          <tr v-if="!cargando && usuarios.length === 0">
            <td :colspan="esAdmin ? 6 : 5" class="text-center py-10 text-slate-400 text-xs">
              No se encontraron cuentas en la lista blanca con los filtros seleccionados.
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Modal Crear / Editar Usuario -->
    <div v-if="modalVisible" class="fixed inset-0 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4 z-50">
      <div class="bg-white border border-slate-200 rounded-2xl p-6 max-w-md w-full shadow-xl animate-new-row">
        <h3 class="text-base font-bold text-slate-900 mb-1">
          {{ form.id ? 'Editar Cuenta Autorizada' : 'Autorizar Nueva Cuenta Google' }}
        </h3>
        <p class="text-xs text-slate-500 mb-4">
          Las cuentas autorizadas pueden iniciar sesión mediante Google OAuth 2.0 en la web y en la app móvil.
        </p>

        <form @submit.prevent="guardar" class="space-y-3.5">
          <div>
            <label class="block text-xs font-semibold text-slate-700 mb-1">Nombre Completo</label>
            <input
              v-model="form.nombre"
              required
              placeholder="Ej. Carlos Mendoza"
              class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white"
            />
          </div>

          <div>
            <label class="block text-xs font-semibold text-slate-700 mb-1">Correo de Google (Lista Blanca)</label>
            <input
              v-model="form.email_google"
              type="email"
              required
              placeholder="usuario@gmail.com"
              class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 font-mono focus:outline-none focus:border-blue-500 focus:bg-white"
            />
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-semibold text-slate-700 mb-1">Rol</label>
              <select
                v-model="form.rol"
                class="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white"
              >
                <option value="operador">Operador</option>
                <option value="administrador">Administrador</option>
              </select>
            </div>

            <div class="flex items-end pb-1">
              <label class="flex items-center gap-2 text-xs font-medium text-slate-700 cursor-pointer select-none">
                <input
                  v-model="form.activo"
                  type="checkbox"
                  class="rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                />
                <span>Permitir acceso OAuth</span>
              </label>
            </div>
          </div>

          <div class="flex justify-end gap-2.5 mt-5 pt-3 border-t border-slate-100">
            <button
              type="button"
              @click="modalVisible = false"
              class="px-3.5 py-2 rounded-xl text-xs text-slate-600 hover:bg-slate-100 cursor-pointer font-medium"
            >
              Cancelar
            </button>
            <button
              type="submit"
              :disabled="guardando"
              class="px-4 py-2 bg-blue-600 hover:bg-blue-700 active:scale-95 text-white rounded-xl text-xs font-semibold transition cursor-pointer flex items-center gap-1.5"
            >
              <svg v-if="guardando" class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
              </svg>
              <span>{{ guardando ? 'Guardando...' : 'Guardar Usuario' }}</span>
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

const usuarios = ref([])
const resumen = ref({ total: 0, activos: 0, administradores: 0, operadores: 0 })
const filtros = ref({ q: '', rol: '', activo: '' })
const cargando = ref(false)
const modalVisible = ref(false)
const guardando = ref(false)
const form = ref({ id: null, nombre: '', email_google: '', rol: 'operador', activo: true })

const iosDialog = useIosDialog()

const usuarioActual = computed(() => {
  try {
    return JSON.parse(localStorage.getItem('peaje_user') || 'null')
  } catch {
    return null
  }
})

const esAdmin = computed(() => usuarioActual.value?.rol === 'administrador')

function iniciales(nombre) {
  if (!nombre) return 'U'
  return nombre
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() || '')
    .join('')
}

async function cargar() {
  cargando.value = true
  try {
    const params = {}
    if (filtros.value.q.trim()) params.q = filtros.value.q.trim()
    if (filtros.value.rol) params.rol = filtros.value.rol
    if (filtros.value.activo !== '') params.activo = filtros.value.activo

    const res = await api.get('/usuarios', { params })
    usuarios.value = res.data.data || []
    if (res.data.resumen) {
      resumen.value = res.data.resumen
    }
  } catch (err) {
    toast.error('Error al cargar lista blanca de usuarios', {
      description: err.response?.data?.message || err.message,
    })
  } finally {
    cargando.value = false
  }
}

function abrirModalCrear() {
  form.value = { id: null, nombre: '', email_google: '', rol: 'operador', activo: true }
  modalVisible.value = true
}

function editar(u) {
  form.value = {
    id: u.id,
    nombre: u.nombre,
    email_google: u.email_google,
    rol: u.rol,
    activo: Boolean(u.activo),
  }
  modalVisible.value = true
}

async function guardar() {
  guardando.value = true
  try {
    const payload = {
      nombre: form.value.nombre.trim(),
      email_google: form.value.email_google.trim().toLowerCase(),
      rol: form.value.rol,
      activo: Boolean(form.value.activo),
    }

    if (form.value.id) {
      await api.put(`/usuarios/${form.value.id}`, payload)
      toast.success(`Cuenta ${payload.email_google} actualizada`)
    } else {
      await api.post('/usuarios', payload)
      toast.success(`Cuenta ${payload.email_google} agregada a la lista blanca`)
    }
    modalVisible.value = false
    await cargar()
  } catch (err) {
    toast.error('No se pudo guardar el usuario', {
      description: err.response?.data?.message || err.message,
    })
  } finally {
    guardando.value = false
  }
}

function confirmarToggle(u) {
  const accion = u.activo ? 'Revocar acceso' : 'Autorizar acceso'
  iosDialog.confirmar({
    title: `¿${accion} para ${u.nombre}?`,
    message: u.activo
      ? `Se bloqueará el acceso de ${u.email_google} al sistema web y móvil.`
      : `Se habilitará nuevamente el acceso de ${u.email_google} con Google OAuth.`,
    confirmLabel: accion,
    onConfirm: async () => {
      try {
        await api.patch(`/usuarios/${u.id}/estado`, { activo: !u.activo })
        toast.success(u.activo ? 'Acceso revocado correctamente' : 'Acceso autorizado correctamente')
        await cargar()
      } catch (err) {
        toast.error('No se pudo actualizar el estado', {
          description: err.response?.data?.message || err.message,
        })
      }
    },
  })
}

function confirmarBorrado(u) {
  iosDialog.confirmar({
    title: `¿Eliminar a ${u.nombre}?`,
    message: `Se eliminará permanentemente ${u.email_google} de la lista blanca de Google OAuth.`,
    confirmLabel: 'Eliminar',
    onConfirm: async () => {
      try {
        await api.delete(`/usuarios/${u.id}`)
        toast.success(`${u.email_google} eliminado de la lista blanca`)
        await cargar()
      } catch (err) {
        toast.error('No se pudo eliminar el usuario', {
          description: err.response?.data?.message || err.message,
        })
      }
    },
  })
}

onMounted(cargar)
</script>

