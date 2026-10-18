<script setup lang="ts">
import { reactive } from 'vue'
import { t } from '../i18n'
import { live } from '../live'
import { buildReminders, toRows } from '../reminders'
import type { Reminder } from '../types'
import ReminderFields from './ReminderFields.vue'

const emit = defineEmits<{ save: [reminders: Reminder[]]; cancel: [] }>()

const rows = reactive(toRows(live.state?.reminders ?? []))
const errors = reactive<Record<string, string>>({})

function submit() {
  for (const k of Object.keys(errors)) delete errors[k]
  const reminders = buildReminders(rows, live.state?.total_ms ?? null, errors)
  if (Object.keys(errors).length === 0) emit('save', reminders)
}

defineExpose({ setError: (msg: string) => (errors.form = msg) })
</script>

<template>
  <div class="overlay" @click.self="emit('cancel')" @keydown.esc="emit('cancel')">
    <form class="dialog" @submit.prevent="submit">
      <h2>{{ t.editReminders }}</h2>
      <p class="hint">{{ t.editRemindersHint }}</p>
      <ReminderFields :rows="rows" :errors="errors" :remaining-ms="live.remainingMs" />
      <div v-if="errors.form" class="error">{{ errors.form }}</div>
      <div class="actions">
        <button type="button" @click="emit('cancel')">{{ t.cancel }}</button>
        <button type="submit" class="primary">{{ t.save }}</button>
      </div>
    </form>
  </div>
</template>

<style scoped>
.hint {
  margin: -4px 0 16px;
}
</style>
