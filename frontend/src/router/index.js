import { createRouter, createWebHistory } from 'vue-router'
import PanelRealtime from '../views/PanelRealtime.vue'
import Vehiculos from '../views/Vehiculos.vue'
import Pasos from '../views/Pasos.vue'
import Alertas from '../views/Alertas.vue'
import ChatAgente from '../views/ChatAgente.vue'
import EstadoInferencia from '../views/EstadoInferencia.vue'
import Usuarios from '../views/Usuarios.vue'
import TarifasCasetas from '../views/TarifasCasetas.vue'
import Login from '../views/Login.vue'

const routes = [
  { path: '/login', name: 'Login', component: Login },
  { path: '/', name: 'Panel', component: PanelRealtime, meta: { requiresAuth: true } },
  { path: '/vehiculos', name: 'Vehiculos', component: Vehiculos, meta: { requiresAuth: true } },
  { path: '/pasos', name: 'Pasos', component: Pasos, meta: { requiresAuth: true } },
  { path: '/alertas', name: 'Alertas', component: Alertas, meta: { requiresAuth: true } },
  { path: '/tarifas-casetas', name: 'TarifasCasetas', component: TarifasCasetas, meta: { requiresAuth: true } },
  { path: '/usuarios', name: 'Usuarios', component: Usuarios, meta: { requiresAuth: true } },
  { path: '/chat', name: 'Chat', component: ChatAgente, meta: { requiresAuth: true } },
  { path: '/estado', name: 'Estado', component: EstadoInferencia, meta: { requiresAuth: true } },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach((to, from, next) => {
  const token = localStorage.getItem('peaje_token')
  if (to.meta.requiresAuth && !token) {
    next('/login')
  } else if (to.path === '/login' && token) {
    next('/')
  } else {
    next()
  }
})

export default router

