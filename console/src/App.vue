<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import { api } from './api'
import ConsoleView from './components/ConsoleView.vue'
import LoginView from './components/LoginView.vue'
import RoomsView from './components/RoomsView.vue'
import { disconnect } from './live'

const view = ref<'loading' | 'login' | 'console'>('loading')

// The open room lives in the address (?r=<id>), like the client's, so it
// survives a reload and works with the back button.
const roomInUrl = () => new URLSearchParams(window.location.search).get('r')
const room = ref(roomInUrl())
const notice = ref('')

function go(id: string | null, message = '') {
  const u = new URL(window.location.href)
  if (id) u.searchParams.set('r', id)
  else u.searchParams.delete('r')
  window.history.pushState(null, '', u)
  notice.value = message
  room.value = id
}

function onPop() {
  notice.value = ''
  room.value = roomInUrl()
}

function loggedOut() {
  disconnect()
  view.value = 'login'
}

onMounted(async () => {
  window.addEventListener('popstate', onPop)
  try {
    await api.session()
    view.value = 'console'
  } catch {
    view.value = 'login'
  }
})
onUnmounted(() => window.removeEventListener('popstate', onPop))
</script>

<template>
  <LoginView v-if="view === 'login'" @done="view = 'console'" />
  <template v-else-if="view === 'console'">
    <ConsoleView v-if="room" :key="room" :room-id="room" @leave="(msg) => go(null, msg)" @logout="loggedOut" />
    <RoomsView v-else :notice="notice" @enter="(id) => go(id)" @logout="loggedOut" />
  </template>
</template>
