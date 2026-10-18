<script setup lang="ts">
import { ref } from 'vue'
import { t } from '../i18n'
import { parseDuration } from '../time'

const props = defineProps<{ title: string; canReduce: boolean }>()
/** ms is signed: negative takes time off. */
const emit = defineEmits<{ submit: [ms: number]; cancel: [] }>()
const value = ref('')
const direction = ref<1 | -1>(1)
const error = ref('')

function submit() {
  const ms = parseDuration(value.value)
  if (ms === null || ms < 1000 || ms > 86_400_000) {
    error.value = t.value.errDuration
    return
  }
  emit('submit', props.canReduce ? direction.value * ms : ms)
}
</script>

<template>
  <div class="overlay" @click.self="emit('cancel')" @keydown.esc="emit('cancel')">
    <form class="dialog small" @submit.prevent="submit">
      <h2>{{ title }}</h2>
      <div v-if="canReduce" class="direction" role="radiogroup">
        <button type="button" :class="{ on: direction === 1 }" :aria-checked="direction === 1" role="radio" @click="direction = 1">
          {{ t.addTime }}
        </button>
        <button type="button" :class="{ on: direction === -1 }" :aria-checked="direction === -1" role="radio" @click="direction = -1">
          {{ t.cutTime }}
        </button>
      </div>
      <div class="field">
        <label for="prompt">{{ direction === 1 ? t.extendBy : t.reduceBy }}</label>
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
.direction {
  display: flex;
  gap: 6px;
  margin-bottom: 16px;
}
.direction .on {
  background: var(--fg);
  border-color: var(--fg);
  color: var(--on-fg);
}
</style>
