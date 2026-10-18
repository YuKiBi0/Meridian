<script setup lang="ts">
import { ref } from 'vue'
import { api, ApiError } from '../api'
import { t } from '../i18n'

const emit = defineEmits<{ done: [] }>()
const token = ref('')
const error = ref('')
const busy = ref(false)

async function submit() {
  if (!token.value || busy.value) return
  busy.value = true
  error.value = ''
  try {
    await api.login(token.value)
    emit('done')
  } catch (e) {
    const err = e as ApiError
    error.value = err.status === 429 ? t.value.tooMany : err.status === 401 ? t.value.wrongToken : t.value.networkError
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="login">
    <form @submit.prevent="submit">
      <svg class="mark" viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="9" />
        <line x1="12" y1="2" x2="12" y2="22" />
        <circle class="dot" cx="12" cy="8.7" r="2" />
      </svg>
      <h1>{{ t.brand }}</h1>
      <p class="muted">{{ t.consoleName }}</p>
      <div class="field">
        <label for="token">{{ t.adminToken }}</label>
        <input id="token" v-model="token" type="password" autocomplete="current-password" autofocus />
        <div v-if="error" class="error">{{ error }}</div>
      </div>
      <button class="primary" type="submit" :disabled="!token || busy">{{ t.enter }}</button>
    </form>
  </main>
</template>

<style scoped>
.login {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
}
form {
  width: 100%;
  max-width: 320px;
}
.mark {
  width: 40px;
  height: 40px;
  fill: none;
  stroke: var(--fg);
  stroke-width: 2;
}
.mark .dot {
  fill: var(--accent);
  stroke: none;
}
h1 {
  margin: 16px 0 0;
  font-size: 22px;
  font-weight: 600;
}
p {
  margin: 0 0 32px;
}
input {
  width: 100%;
}
button {
  width: 100%;
}
</style>
