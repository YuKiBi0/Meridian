<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api } from './api'
import ConsoleView from './components/ConsoleView.vue'
import LoginView from './components/LoginView.vue'

const view = ref<'loading' | 'login' | 'console'>('loading')

onMounted(async () => {
  try {
    await api.session()
    view.value = 'console'
  } catch {
    view.value = 'login'
  }
})
</script>

<template>
  <LoginView v-if="view === 'login'" @done="view = 'console'" />
  <ConsoleView v-else-if="view === 'console'" @logout="view = 'login'" />
</template>
