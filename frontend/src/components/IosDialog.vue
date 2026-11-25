<template>
  <!-- Modal Nativo Centrado Exacto Estilo Apple iOS (UIAlertController) -->
  <teleport to="body">
    <transition name="ios-dialog">
      <div
        v-if="activo"
        class="ios-dialog-overlay"
        @click.self="cancelar"
      >
        <div class="ios-dialog-box animate-ios-pop">
          <!-- Contenido Central -->
          <div class="ios-dialog-content">
            <!-- Icono de Advertencia Sutil Estilo iOS -->
            <div class="ios-dialog-icon">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path>
                <line x1="12" y1="9" x2="12" y2="13"></line>
                <line x1="12" y1="17" x2="12.01" y2="17"></line>
              </svg>
            </div>

            <h3 class="ios-dialog-title">{{ titulo }}</h3>
            <p class="ios-dialog-message">{{ mensaje }}</p>
          </div>

          <!-- Barra de Acciones Estilo iOS con Hairlines -->
          <div class="ios-dialog-actions">
            <button
              type="button"
              class="ios-dialog-btn ios-btn-cancel"
              @click="cancelar"
            >
              Cancelar
            </button>
            <button
              type="button"
              class="ios-dialog-btn ios-btn-confirm"
              @click="aceptar"
            >
              {{ confirmText }}
            </button>
          </div>
        </div>
      </div>
    </transition>
  </teleport>
</template>

<script setup>
import { useIosDialog } from '../services/useIosDialog'

const {
  activo,
  titulo,
  mensaje,
  confirmText,
  aceptar,
  cancelar,
} = useIosDialog()
</script>

<style scoped>
.ios-dialog-overlay {
  position: fixed;
  inset: 0;
  z-index: 999999;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
  background-color: rgba(15, 23, 42, 0.45);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
}

.ios-dialog-box {
  width: 100%;
  max-width: 280px;
  background-color: rgba(255, 255, 255, 0.96);
  backdrop-filter: blur(35px) saturate(200%);
  -webkit-backdrop-filter: blur(35px) saturate(200%);
  border-radius: 14px;
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.3), 0 0 0 0.5px rgba(0, 0, 0, 0.12);
  overflow: hidden;
  text-align: center;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", -apple-system-subheadline, "Helvetica Neue", Helvetica, Arial, sans-serif;
  user-select: none;
}

.ios-dialog-content {
  padding: 22px 18px 18px 18px;
}

.ios-dialog-icon {
  width: 42px;
  height: 42px;
  margin: 0 auto 12px auto;
  border-radius: 50%;
  background-color: #fee2e2;
  color: #dc2626;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: inset 0 0 0 1px rgba(220, 38, 38, 0.15);
}

.ios-dialog-title {
  margin: 0;
  font-size: 16.5px;
  font-weight: 600;
  color: #0f172a;
  letter-spacing: -0.02em;
  line-height: 1.3;
}

.ios-dialog-message {
  margin: 8px 0 0 0;
  font-size: 13px;
  font-weight: 400;
  color: #64748b;
  line-height: 1.45;
}

.ios-dialog-actions {
  display: flex;
  border-top: 0.5px solid rgba(60, 60, 67, 0.25);
  background-color: rgba(255, 255, 255, 0.5);
}

.ios-dialog-btn {
  flex: 1;
  height: 44px;
  background: transparent;
  border: none;
  outline: none;
  font-size: 16px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background-color 0.12s ease;
}

.ios-dialog-btn:hover {
  background-color: rgba(0, 0, 0, 0.03);
}

.ios-dialog-btn:active {
  background-color: rgba(0, 0, 0, 0.08);
}

.ios-btn-cancel {
  color: #007aff;
  font-weight: 400;
  border-right: 0.5px solid rgba(60, 60, 67, 0.25);
}

.ios-btn-confirm {
  color: #ff3b30;
  font-weight: 600;
}

/* Transiciones iOS */
.ios-dialog-enter-active,
.ios-dialog-leave-active {
  transition: opacity 0.2s cubic-bezier(0.16, 1, 0.3, 1);
}

.ios-dialog-enter-from,
.ios-dialog-leave-to {
  opacity: 0;
}

@keyframes iosPopAnim {
  0% {
    opacity: 0;
    transform: scale(1.12);
  }
  100% {
    opacity: 1;
    transform: scale(1);
  }
}

.animate-ios-pop {
  animation: iosPopAnim 0.24s cubic-bezier(0.175, 0.885, 0.32, 1.15) forwards;
}
</style>
