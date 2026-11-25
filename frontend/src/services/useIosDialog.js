import { ref } from 'vue'

const activo = ref(false)
const titulo = ref('')
const mensaje = ref('')
const icono = ref('warning')
const confirmText = ref('Eliminar')
const onConfirmFn = ref(null)

export function useIosDialog() {
  function confirmar({ title, message, icon = 'warning', confirmLabel = 'Eliminar', onConfirm }) {
    titulo.value = title
    mensaje.value = message
    icono.value = icon
    confirmText.value = confirmLabel
    onConfirmFn.value = onConfirm
    activo.value = true
  }

  function aceptar() {
    activo.value = false
    if (onConfirmFn.value) {
      onConfirmFn.value()
    }
  }

  function cancelar() {
    activo.value = false
  }

  return {
    activo,
    titulo,
    mensaje,
    icono,
    confirmText,
    confirmar,
    aceptar,
    cancelar,
  }
}

