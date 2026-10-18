<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { t } from '../i18n'
import { live } from '../live'
import { buildReminders, toRows } from '../reminders'
import type { Reminder } from '../types'
import ReminderFields from './ReminderFields.vue'

/** remindersSeq is the version the edit is based on (PRD 5.4.1). */
const emit = defineEmits<{ save: [reminders: Reminder[], remindersSeq: number]; cancel: [] }>()

const rows = reactive(toRows(live.state?.reminders ?? []))
const errors = reactive<Record<string, string>>({})
const basedOn = ref(live.state?.reminders_seq ?? 0)
const stale = computed(() => live.state !== null && live.state.reminders_seq !== basedOn.value)

/** Discards local edits and starts over from the server's reminders. */
function loadLatest() {
  rows.splice(0, rows.length, ...toRows(live.state?.reminders ?? []))
  basedOn.value = live.state?.reminders_seq ?? 0
  for (const k of Object.keys(errors)) delete errors[k]
}

function submit() {
  for (const k of Object.keys(errors)) delete errors[k]
  const reminders = buildReminders(rows, live.state?.total_ms ?? null, errors)
  if (Object.keys(errors).length === 0) emit('save', reminders, basedOn.value)
}

defineExpose({ setError: (msg: string) => (errors.form = msg) })
</script>

<template>
  <div class="overlay" @click.self="emit('cancel')" @keydown.esc="emit('cancel')">
    <form class="dialog" @submit.prevent="submit">
      <h2>{{ t.editReminders }}</h2>
      <p class="hint">{{ t.editRemindersHint }}</p>
      <div v-if="stale" class="stale" role="status">
        <span>{{ t.remindersChanged }}</span>
        <button type="button" class="quiet" @click="loadLatest">{{ t.loadLatest }}</button>
      </div>
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
.stale {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin: 0 0 16px;
  padding: 8px 12px;
  border: 1px solid var(--line);
  border-left: 3px solid var(--fg);
  border-radius: var(--r-sm);
  font-size: 13px;
}
.stale button {
  height: 28px;
  font-weight: 500;
}
</style>
