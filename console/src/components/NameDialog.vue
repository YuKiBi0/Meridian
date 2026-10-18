<script setup lang="ts">
import { ref } from 'vue'
import { t } from '../i18n'

const props = defineProps<{ title: string; initial?: string }>()
const emit = defineEmits<{ submit: [name: string]; cancel: [] }>()
const value = ref(props.initial ?? '')
const error = ref('')

function submit() {
  const name = value.value.trim()
  if (!name) {
    error.value = t.value.errRoomName
    return
  }
  emit('submit', name)
}

/** Shows a server-side validation message. */
function setError(msg: string) {
  error.value = msg
}
defineExpose({ setError })
</script>

<template>
  <div class="overlay" @click.self="emit('cancel')" @keydown.esc="emit('cancel')">
    <form class="dialog small" @submit.prevent="submit">
      <h2>{{ title }}</h2>
      <div class="field">
        <label for="room-name">{{ t.roomName }}</label>
        <input id="room-name" v-model="value" maxlength="40" autofocus />
        <div class="hint">{{ t.roomNameHint }}</div>
        <div v-if="error" class="error">{{ error }}</div>
      </div>
      <div class="actions">
        <button type="button" @click="emit('cancel')">{{ t.cancel }}</button>
        <button type="submit" class="primary">{{ t.save }}</button>
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
