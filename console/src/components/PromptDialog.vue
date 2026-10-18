<script setup lang="ts">
import { ref } from 'vue'
import { t } from '../i18n'
import { parseDuration } from '../time'

defineProps<{ title: string }>()
const emit = defineEmits<{ submit: [ms: number]; cancel: [] }>()
const value = ref('')
const error = ref('')

function submit() {
  const ms = parseDuration(value.value)
  if (ms === null || ms < 1000 || ms > 86_400_000) {
    error.value = t.value.errDuration
    return
  }
  emit('submit', ms)
}
</script>

<template>
  <div class="overlay" @click.self="emit('cancel')" @keydown.esc="emit('cancel')">
    <form class="dialog small" @submit.prevent="submit">
      <h2>{{ title }}</h2>
      <div class="field">
        <label for="prompt">{{ t.extendBy }}</label>
        <input id="prompt" v-model="value" class="num" inputmode="decimal" placeholder="5" autofocus />
        <div class="hint">{{ t.durationHint }}</div>
        <div v-if="error" class="error">{{ error }}</div>
      </div>
      <div class="actions">
        <button type="button" @click="emit('cancel')">{{ t.cancel }}</button>
        <button type="submit" class="primary">{{ t.confirm }}</button>
      </div>
    </form>
  </div>
</template>

<style scoped>
.small {
  max-width: 380px;
}
input {
  width: 100%;
}
</style>
