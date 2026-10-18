<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { t } from '../i18n'
import { buildReminders, toRows } from '../reminders'
import { formatDuration, parseDuration } from '../time'
import type { OnExpire, Preset, TimerConfig } from '../types'
import ReminderFields from './ReminderFields.vue'

const props = defineProps<{ preset?: Preset }>()
const emit = defineEmits<{
  start: [cfg: TimerConfig]
  save: [preset: Omit<Preset, 'id'> & { id?: string }]
  cancel: []
}>()

const editing = computed(() => !!props.preset)
const p = props.preset
const form = reactive({
  name: p?.name ?? '',
  title: p?.title ?? '',
  duration: p ? formatDuration(p.total_ms) : '',
  onExpire: (p?.on_expire ?? 'stop') as OnExpire,
  rows: toRows(p?.reminders ?? []),
})
const errors = reactive<Record<string, string>>({})

/** Validates the form; returns the config or null and fills errors. */
function build(needName: boolean): TimerConfig | null {
  for (const k of Object.keys(errors)) delete errors[k]
  const total = parseDuration(form.duration)
  if (total === null) errors.duration = t.value.errDuration
  else if (total < 1000 || total > 86_400_000) errors.duration = t.value.errDurationRange
  if (needName && !form.name.trim()) errors.name = t.value.errName

  const reminders = buildReminders(form.rows, total, errors)
  if (Object.keys(errors).length > 0) return null
  return { title: form.title.trim(), total_ms: total!, on_expire: form.onExpire, reminders }
}

function start() {
  const cfg = build(false)
  if (cfg) emit('start', cfg)
}

function save() {
  const cfg = build(true)
  if (cfg) emit('save', { ...cfg, id: props.preset?.id, name: form.name.trim() })
}

const showNameField = ref(editing.value)
function saveAsPreset() {
  if (!showNameField.value) {
    showNameField.value = true
    return
  }
  save()
}

defineExpose({ setError: (msg: string) => (errors.form = msg) })
</script>

<template>
  <div class="overlay" @click.self="emit('cancel')" @keydown.esc="emit('cancel')">
    <form class="dialog" @submit.prevent="editing ? save() : start()">
      <h2>{{ editing ? t.edit : t.new }}</h2>

      <div v-if="showNameField" class="field">
        <label for="name">{{ t.name }}</label>
        <input id="name" v-model="form.name" maxlength="40" :autofocus="!editing" />
        <div v-if="errors.name" class="error">{{ errors.name }}</div>
      </div>

      <div class="grid">
        <div class="field">
          <label for="duration">{{ t.duration }}</label>
          <input id="duration" v-model="form.duration" class="num" inputmode="decimal" placeholder="15" />
          <div v-if="errors.duration" class="error">{{ errors.duration }}</div>
          <div v-else class="hint">{{ t.durationHint }}</div>
        </div>
        <div class="field">
          <label for="expire">{{ t.onExpire }}</label>
          <select id="expire" v-model="form.onExpire">
            <option value="stop">{{ t.expireStop }}</option>
            <option value="overtime">{{ t.expireOvertime }}</option>
          </select>
        </div>
      </div>

      <div class="field">
        <label for="title">{{ t.title }}</label>
        <input id="title" v-model="form.title" maxlength="40" />
        <div class="hint">{{ t.titleHint }}</div>
      </div>

      <fieldset>
        <legend>{{ t.reminders }}</legend>
        <ReminderFields :rows="form.rows" :errors="errors" />
      </fieldset>

      <div v-if="errors.form" class="error">{{ errors.form }}</div>

      <div class="actions">
        <button type="button" @click="emit('cancel')">{{ t.cancel }}</button>
        <template v-if="editing">
          <button type="submit" class="primary">{{ t.save }}</button>
        </template>
        <template v-else>
          <button type="button" @click="saveAsPreset">{{ t.savePreset }}</button>
          <button type="submit" class="primary">{{ t.start }}</button>
        </template>
      </div>
    </form>
  </div>
</template>

<style scoped>
.grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.grid input,
.grid select,
.field input {
  width: 100%;
}
fieldset {
  border: 0;
  border-top: 1px solid var(--line);
  margin: 8px 0 0;
  padding: 16px 0 0;
}
legend {
  font-size: 13px;
  color: var(--fg-muted);
  padding: 0 8px 0 0;
}
</style>
