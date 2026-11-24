<template>
  <div class="min-h-screen bg-slate-900 text-slate-100 flex flex-col font-sans">
    <!-- Navbar Superior -->
    <header v-if="usuario" class="bg-slate-800/80 backdrop-blur border-b border-slate-700 sticky top-0 z-40">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div class="flex items-center gap-8">
          <router-link to="/" class="flex items-center gap-3">
            <div class="w-9 h-9 rounded-xl bg-blue-600 flex items-center justify-center font-bold text-white text-lg shadow-md">
              P
            </div>
            <span class="text-lg font-bold tracking-tight text-white hidden sm:block">Peaje Inteligente</span>
          </router-link>

          <nav class="hidden md:flex items-center gap-1 text-sm font-medium">
            <router-link to="/" class="px-3 py-2 rounded-xl transition" :class="$route.path === '/' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'">
              Panel Realtime
            </router-link>
            <router-link to="/vehiculos" class="px-3 py-2 rounded-xl transition" :class="$route.path === '/vehiculos' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'">
              Vehículos
            </router-link>
            <router-link to="/pasos" class="px-3 py-2 rounded-xl transition" :class="$route.path === '/pasos' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'">
              Pasos
            </router-link>
            <router-link to="/alertas" class="px-3 py-2 rounded-xl transition" :class="$route.path === '/alertas' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'">
              Alertas
            </router-link>
            <router-link to="/chat" class="px-3 py-2 rounded-xl transition" :class="$route.path === '/chat' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'">
              Chat Agente
            </router-link>
            <router-link to="/estado" class="px-3 py-2 rounded-xl transition" :class="$route.path === '/estado' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'">
              Estado Inferencia
            </router-link>
          </nav>
        </div>

        <!-- Usuario & Logout -->
        <div class="flex items-center gap-4">
          <div class="text-right hidden sm:block">
            <div class="text-xs font-bold text-white">{{ usuario.nombre }}</div>
            <div class="text-[11px] text-slate-400 capitalize">{{ usuario.rol }} (Google)</div>
          </div>
          <button @click="logout" class="p-2 rounded-xl bg-slate-700 hover:bg-slate-600 text-slate-300 transition" title="Cerrar Sesión">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" /></svg>
          </button>
        </div>
      </div>
    </header>

    <!-- Main Container -->
    <main class="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6">
      <router-view />
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'

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
  router.push('/login')
}

watch(route, () => {
  cargarUsuario()
})

onMounted(() => {
  cargarUsuario()
})
</script>
