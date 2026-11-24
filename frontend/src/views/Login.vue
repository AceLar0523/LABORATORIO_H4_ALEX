<template>
  <div class="min-h-screen flex items-center justify-center bg-slate-900 px-4">
    <div class="max-w-md w-full bg-slate-800 rounded-2xl shadow-2xl p-8 border border-slate-700">
      <div class="text-center mb-8">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-600/20 text-blue-400 mb-4 border border-blue-500/30">
          <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
          </svg>
        </div>
        <h1 class="text-2xl font-bold text-white tracking-tight">Peaje Inteligente</h1>
        <p class="text-slate-400 text-sm mt-1">Control de acceso exclusivo mediante Google OAuth 2.0</p>
      </div>

      <div v-if="errorMsg" class="mb-6 p-4 rounded-xl bg-red-500/10 border border-red-500/30 text-red-400 text-sm flex items-start gap-3">
        <svg class="w-5 h-5 shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
        <div>
          <span class="font-semibold block">Acceso Denegado</span>
          <span>{{ errorMsg }}</span>
        </div>
      </div>

      <div class="space-y-4">
        <!-- Botón oficial Google Sign In simulado / OAuth -->
        <button
          @click="loginWithGoogle('docente@peaje.edu')"
          :disabled="loading"
          class="w-full flex items-center justify-center gap-3 bg-white hover:bg-slate-100 text-slate-800 font-medium py-3 px-4 rounded-xl transition duration-200 shadow-sm cursor-pointer disabled:opacity-50"
        >
          <svg class="w-5 h-5" viewBox="0 0 24 24">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"/>
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
          </svg>
          <span>Iniciar sesión como Docente (Admin)</span>
        </button>

        <button
          @click="loginWithGoogle('operador@peaje.com')"
          :disabled="loading"
          class="w-full flex items-center justify-center gap-3 bg-slate-700 hover:bg-slate-600 text-white font-medium py-3 px-4 rounded-xl transition duration-200 cursor-pointer disabled:opacity-50"
        >
          <span>Iniciar sesión como Operador</span>
        </button>

        <button
          @click="loginWithGoogle('noautorizado@gmail.com')"
          :disabled="loading"
          class="w-full flex items-center justify-center gap-3 bg-slate-800 hover:bg-slate-700/60 text-slate-400 hover:text-slate-200 text-xs py-2 px-3 rounded-lg border border-slate-700 transition"
        >
          <span>Probar rechazo de cuenta no autorizada (Demostración)</span>
        </button>
      </div>

      <div class="mt-8 pt-6 border-t border-slate-700/60 text-center text-xs text-slate-500">
        Requisito 4.4: Solo las cuentas en lista blanca de base de datos son admitidas.
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import api from '../services/api'

const router = useRouter()
const loading = ref(false)
const errorMsg = ref('')

async function loginWithGoogle(email) {
  loading.value = true
  errorMsg.value = ''
  try {
    const res = await api.post('/auth/google', {
      email,
      name: email.split('@')[0],
      token: 'mock-google-token-' + Date.now(),
    })

    if (res.data.success) {
      localStorage.setItem('peaje_token', res.data.token)
      localStorage.setItem('peaje_user', JSON.stringify(res.data.usuario))
      router.push('/')
    }
  } catch (err) {
    if (err.response && err.response.data && err.response.data.message) {
      errorMsg.value = err.response.data.message
    } else {
      errorMsg.value = 'Error al comunicarse con el servidor de autenticación.'
    }
  } finally {
    loading.value = false
  }
}
</script>

