<template>
  <div class="min-h-screen bg-slate-50 text-slate-900 flex flex-col font-sans selection:bg-blue-100">
    <!-- Componente Toaster Sonner con estilos oficiales (arriba al centro estilo Dynamic Island) -->
    <Toaster position="top-center" richColors closeButton />

    <!-- Dialog Modal Nativo Centrado estilo iPhone para confirmaciones críticas -->
    <IosDialog />

    <!-- Navbar Superior con Acentos de Color Elegantes -->
    <header v-if="usuario" class="bg-white/95 backdrop-blur-md border-b border-slate-200 sticky top-0 z-30 transition-all shadow-2xs">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div class="flex items-center gap-8">
          <router-link to="/" class="flex items-center gap-2.5 group">
            <div class="w-9 h-9 rounded-xl bg-gradient-to-tr from-blue-600 to-indigo-600 text-white flex items-center justify-center font-bold text-sm tracking-tight shadow-sm shadow-blue-500/20 transition-transform group-hover:scale-105">
              P
            </div>
            <div class="leading-tight hidden sm:block">
              <span class="text-sm font-bold text-slate-900 block group-hover:text-blue-700 transition-colors">Peaje Inteligente</span>
              <span class="text-[10px] text-blue-600 font-semibold block tracking-wide">SISTEMA EN TIEMPO REAL</span>
            </div>
          </router-link>

          <nav class="hidden md:flex items-center gap-1.5 text-sm font-medium">
            <router-link
              to="/"
              class="px-3 py-1.5 rounded-lg transition-all text-xs font-semibold"
              :class="$route.path === '/' ? 'bg-blue-50 text-blue-700 shadow-2xs border border-blue-200/60' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100/70'"
            >
              Panel en Vivo
            </router-link>
            <router-link
              to="/vehiculos"
              class="px-3 py-1.5 rounded-lg transition-all text-xs font-semibold"
              :class="$route.path === '/vehiculos' ? 'bg-blue-50 text-blue-700 shadow-2xs border border-blue-200/60' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100/70'"
            >
              Vehículos
            </router-link>
            <router-link
              to="/pasos"
              class="px-3 py-1.5 rounded-lg transition-all text-xs font-semibold"
              :class="$route.path === '/pasos' ? 'bg-blue-50 text-blue-700 shadow-2xs border border-blue-200/60' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100/70'"
            >
              Historial de Pasos
            </router-link>
            <router-link
              to="/alertas"
              class="px-3 py-1.5 rounded-lg transition-all text-xs font-semibold relative"
              :class="$route.path === '/alertas' ? 'bg-blue-50 text-blue-700 shadow-2xs border border-blue-200/60' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100/70'"
            >
              Alertas
            </router-link>
            <router-link
              to="/usuarios"
              class="px-3 py-1.5 rounded-lg transition-all text-xs font-semibold"
              :class="$route.path === '/usuarios' ? 'bg-blue-50 text-blue-700 shadow-2xs border border-blue-200/60' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100/70'"
            >
              Usuarios & OAuth
            </router-link>
            <router-link
              to="/estado"
              class="px-3 py-1.5 rounded-lg transition-all text-xs font-semibold"
              :class="$route.path === '/estado' ? 'bg-blue-50 text-blue-700 shadow-2xs border border-blue-200/60' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100/70'"
            >
              Inferencia & RunPod
            </router-link>
          </nav>
        </div>

        <!-- Usuario & Logout -->
        <div class="flex items-center gap-3">
          <div class="text-right hidden sm:block">
            <div class="text-xs font-bold text-slate-800 leading-snug">{{ usuario.nombre }}</div>
            <div class="text-[10px] text-indigo-600 font-semibold capitalize flex items-center justify-end gap-1">
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
              {{ usuario.rol }}
            </div>
          </div>
          <button
            @click="logout"
            class="p-2 rounded-xl text-slate-400 hover:text-rose-600 hover:bg-rose-50 active:scale-95 transition-all cursor-pointer border border-transparent hover:border-rose-100"
            title="Cerrar Sesión"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
            </svg>
          </button>
        </div>
      </div>

      <!-- Navegación compacta móvil -->
      <nav class="md:hidden border-t border-slate-100 px-3 py-2 flex items-center gap-1.5 overflow-x-auto bg-white">
        <router-link to="/" class="px-2.5 py-1 rounded-lg text-[11px] font-semibold whitespace-nowrap" :class="$route.path === '/' ? 'bg-blue-50 text-blue-700' : 'text-slate-600'">Panel</router-link>
        <router-link to="/vehiculos" class="px-2.5 py-1 rounded-lg text-[11px] font-semibold whitespace-nowrap" :class="$route.path === '/vehiculos' ? 'bg-blue-50 text-blue-700' : 'text-slate-600'">Vehículos</router-link>
        <router-link to="/pasos" class="px-2.5 py-1 rounded-lg text-[11px] font-semibold whitespace-nowrap" :class="$route.path === '/pasos' ? 'bg-blue-50 text-blue-700' : 'text-slate-600'">Pasos</router-link>
        <router-link to="/alertas" class="px-2.5 py-1 rounded-lg text-[11px] font-semibold whitespace-nowrap" :class="$route.path === '/alertas' ? 'bg-blue-50 text-blue-700' : 'text-slate-600'">Alertas</router-link>
        <router-link to="/usuarios" class="px-2.5 py-1 rounded-lg text-[11px] font-semibold whitespace-nowrap" :class="$route.path === '/usuarios' ? 'bg-blue-50 text-blue-700' : 'text-slate-600'">Usuarios</router-link>
        <router-link to="/estado" class="px-2.5 py-1 rounded-lg text-[11px] font-semibold whitespace-nowrap" :class="$route.path === '/estado' ? 'bg-blue-50 text-blue-700' : 'text-slate-600'">RunPod</router-link>
      </nav>
    </header>

    <!-- Main Container con transición de rutas -->
    <main class="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6">
      <router-view v-slot="{ Component }">
        <transition name="page" mode="out-in">
          <component :is="Component" />
        </transition>
      </router-view>
    </main>

    <!-- Chatbot Flotante Accesible desde Cualquier Pantalla -->
    <ChatFlotante v-if="usuario" />
  </div>
</template>

<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { Toaster, toast } from 'vue-sonner'
import 'vue-sonner/style.css' // Importación correcta del CSS de vue-sonner
import ChatFlotante from './components/ChatFlotante.vue'
import IosDialog from './components/IosDialog.vue'

const router = useRouter()
const route = useRoute()
const usuario = ref(null)

function cargarUsuario() {
  const userJson = localStorage.getItem('peaje_user')
  usuario.value = userJson ? JSON.parse(userJson) : null
}

function logout() {
  localStorage.removeItem('peaje_token')
  localStorage.removeItem('peaje_user')
  usuario.value = null
  toast.info('Sesión cerrada correctamente')
  router.push('/login')
}

watch(route, () => {
  cargarUsuario()
})

onMounted(() => {
  cargarUsuario()
})
</script>
