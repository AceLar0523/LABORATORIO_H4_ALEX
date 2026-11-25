<template>
  <div class="login-wrapper">
    <div class="login-card">
      <!-- Encabezado con Icono Proporcionado y Elegante -->
      <div class="login-header">
        <div class="login-icon-badge">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="login-icon">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path>
            <path d="m9 12 2 2 4-4"></path>
          </svg>
        </div>
        <h1 class="login-title">Peaje Inteligente</h1>
        <p class="login-subtitle">Sistema de Control y Monitoreo en Tiempo Real</p>
      </div>

      <!-- Mensaje de Error -->
      <div v-if="errorMsg" class="login-alert-error">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="login-error-icon">
          <circle cx="12" cy="12" r="10"></circle>
          <line x1="12" y1="8" x2="12" y2="12"></line>
          <line x1="12" y1="16" x2="12.01" y2="16"></line>
        </svg>
        <span>{{ errorMsg }}</span>
      </div>

      <!-- ACCESO EXCLUSIVO GOOGLE OAUTH 2.0 (Lista Blanca) -->
      <div class="login-google-section">
        <div v-if="cargandoConfig" class="text-center text-xs text-slate-500 py-4">
          Verificando configuración de Google OAuth 2.0...
        </div>
        <div v-else-if="googleEnabled">
          <div ref="googleBtnRef" class="google-btn-container"></div>
          <p v-if="loading" class="google-helper-text">
            Validando acceso en la lista blanca...
          </p>
          <p v-else class="google-helper-text">
            Acceso exclusivo mediante Google Sign-In para cuentas autorizadas en la lista blanca.
          </p>
        </div>
        <div v-else class="oauth-pending-box">
          <strong>Google OAuth 2.0 no disponible</strong>
          <span>
            No se pudo cargar la configuración desde el servidor API. Verifica que el backend esté en línea y con
            <code>GOOGLE_CLIENT_ID</code> configurado.
          </span>
          <button
            type="button"
            @click="cargarConfigGoogle"
            class="btn-retry"
          >
            Reintentar conexión
          </button>
        </div>
      </div>

      <!-- Pie de Página -->
      <div class="login-footer">
        Sistema Inteligente de Control de Peaje &bull; Exclusivo Google OAuth 2.0
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import api from '../services/api'

const router = useRouter()
const loading = ref(false)
const cargandoConfig = ref(true)
const googleEnabled = ref(false)
const googleClientId = ref('')
const googleBtnRef = ref(null)
const errorMsg = ref('')

function procesarExito(data) {
  localStorage.setItem('peaje_token', data.token)
  localStorage.setItem('peaje_user', JSON.stringify(data.usuario))
  router.push('/')
}

async function handleGoogleCredential(response) {
  if (!response?.credential) {
    errorMsg.value = 'No se recibió credencial válida de Google.'
    return
  }
  loading.value = true
  errorMsg.value = ''
  try {
    const res = await api.post('/auth/google', {
      id_token: response.credential,
    })
    if (res.data.success) {
      procesarExito(res.data)
    }
  } catch (err) {
    errorMsg.value = err.response?.data?.message || 'Acceso denegado: cuenta no registrada en la lista blanca.'
  } finally {
    loading.value = false
  }
}

async function renderGoogleButton() {
  if (!googleEnabled.value || !googleClientId.value) return
  await nextTick()
  if (!googleBtnRef.value) return

  let intentos = 0
  const intentarRender = () => {
    if (window.google?.accounts?.id && googleBtnRef.value) {
      window.google.accounts.id.initialize({
        client_id: googleClientId.value,
        callback: handleGoogleCredential,
      })
      googleBtnRef.value.innerHTML = ''
      window.google.accounts.id.renderButton(googleBtnRef.value, {
        theme: 'outline',
        size: 'large',
        width: 340,
        text: 'continue_with',
        locale: 'es',
      })
      return
    }
    intentos += 1
    if (intentos < 15) {
      setTimeout(intentarRender, 200)
    }
  }
  intentarRender()
}

async function cargarConfigGoogle() {
  cargandoConfig.value = true
  errorMsg.value = ''
  try {
    const res = await api.get('/auth/config')
    googleClientId.value = res.data?.google_client_id || ''
    googleEnabled.value = Boolean(res.data?.google_oauth_enabled && googleClientId.value)
  } catch (_) {
    googleEnabled.value = false
  } finally {
    cargandoConfig.value = false
    if (googleEnabled.value) {
      renderGoogleButton()
    }
  }
}

onMounted(cargarConfigGoogle)
</script>

<style scoped>
.login-wrapper {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px 16px;
  background-color: #f8fafc;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}

.login-card {
  width: 100%;
  max-width: 420px;
  background-color: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 20px;
  box-shadow: 0 10px 25px -5px rgba(15, 23, 42, 0.08), 0 8px 10px -6px rgba(15, 23, 42, 0.04);
  padding: 32px 28px;
  box-sizing: border-box;
}

.login-header {
  text-align: center;
  margin-bottom: 24px;
}

.login-icon-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 52px;
  height: 52px;
  border-radius: 16px;
  background: linear-gradient(135deg, #2563eb, #4f46e5);
  color: #ffffff;
  margin-bottom: 12px;
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.25);
}

.login-title {
  margin: 0;
  font-size: 22px;
  font-weight: 700;
  color: #0f172a;
  letter-spacing: -0.02em;
}

.login-subtitle {
  margin: 4px 0 0;
  font-size: 13px;
  color: #64748b;
}

.login-alert-error {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  background-color: #fef2f2;
  border: 1px solid #fecaca;
  color: #b91c1c;
  border-radius: 12px;
  padding: 10px 12px;
  font-size: 12.5px;
  margin-bottom: 18px;
  line-height: 1.4;
}

.login-error-icon {
  flex-shrink: 0;
  margin-top: 1px;
}

.login-google-section {
  display: flex;
  flex-direction: column;
  align-items: center;
}

.google-btn-container {
  display: flex;
  justify-content: center;
  min-height: 44px;
}

.google-helper-text {
  margin: 12px 0 0;
  font-size: 12px;
  color: #64748b;
  text-align: center;
  line-height: 1.45;
}

.oauth-pending-box {
  background-color: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  padding: 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  font-size: 12px;
  color: #475569;
  line-height: 1.45;
  text-align: center;
  width: 100%;
}

.oauth-pending-box strong {
  color: #0f172a;
}

.btn-retry {
  margin-top: 4px;
  background-color: #0f172a;
  color: #ffffff;
  border: none;
  border-radius: 10px;
  padding: 9px 14px;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}

.btn-retry:hover {
  background-color: #1e293b;
}

.login-footer {
  margin-top: 24px;
  padding-top: 16px;
  border-top: 1px solid #f1f5f9;
  text-align: center;
  font-size: 11.5px;
  color: #94a3b8;
}
</style>
