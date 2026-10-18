<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { t } from '../i18n'
import { formatDuration, parseDuration } from '../time'
import type { OnExpire, Preset, Reminder, TimerConfig } from '../types'

const props = defineProps<{ preset?: Preset }>()
const emit = defineEmits<{
  start: [cfg: TimerConfig]
  save: [preset: Omit<Preset, 'id'> & { id?: string }]
  cancel: []
}>()

const SHOW_OPTIONS = [5, 8, 15, 30, 60]

interface Row {
  id?: string
  at: string
  text: string
  show: string // seconds, or 'sticky'
}

const editing = computed(() => !!props.preset)
const p = props.preset
const form = reactive({
  name: p?.name ?? '',
  title: p?.title ?? '',
  duration: p ? formatDuration(p.total_ms) : '',
  onExpire: (p?.on_expire ?? 'stop') as OnExpire,
  rows: (p?.reminders ?? []).map<Row>((r) => ({
    id: r.id,
    at: formatDuration(r.at_ms),
    text: r.text,
    show: r.sticky ? 'sticky' : String(Math.round(r.duration_ms / 1000)),
  })),
})
const errors = reactive<Record<string, string>>({})

function addRow() {
  form.rows.push({ at: '', text: '', show: '8' })
}

function removeRow(i: number) {
  form.rows.splice(i, 1)
}

/** Validates the form; returns the config or null and fills errors. */
function build(needName: boolean): TimerConfig | null {
  for (const k of Object.keys(errors)) delete errors[k]
  const total = parseDuration(form.duration)
  if (total === null) errors.duration = t.value.errDuration
  else if (total < 1000 || total > 86_400_000) errors.duration = t.value.errDurationRange
  if (needName && !form.name.trim()) errors.name = t.value.errName

  const seen = new Set<number>()
  const reminders: Reminder[] = []
  form.rows.forEach((row, i) => {
    const at = parseDuration(row.at)
    if (at === null) errors[`at${i}`] = t.value.errDuration
    else if (total !== null && at >= total) errors[`at${i}`] = t.value.errReminderAt
    else if (seen.has(at)) errors[`at${i}`] = t.value.errReminderDup
    if (!row.text.trim()) errors[`text${i}`] = t.value.errReminderText
    if (at !== null) seen.add(at)
    reminders.push({
      id: row.id,
      at_ms: at ?? 0,
      text: row.text.trim(),
      sticky: row.show === 'sticky',
      duration_ms: row.show === 'sticky' ? 0 : Number(row.show) * 1000,
    })
  })
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
        <div v-for="(row, i) in form.rows" :key="i" class="row">
          <div class="at">
            <label :for="`at${i}`">{{ t.reminderAt }}</label>
            <input :id="`at${i}`" v-model="row.at" class="num" inputmode="decimal" placeholder="5" />
          </div>
          <div class="text">
            <label :for="`text${i}`">{{ t.message }}</label>
            <input :id="`text${i}`" v-model="row.text" maxlength="80" />
          </div>
          <div class="show">
            <label :for="`show${i}`">{{ t.showFor }}</label>
            <select :id="`show${i}`" v-model="row.show">
              <option v-for="s in SHOW_OPTIONS" :key="s" :value="String(s)">{{ t.seconds(s) }}</option>
              <option value="sticky">{{ t.sticky }}</option>
            </select>
          </div>
          <button type="button" class="quiet remove" :aria-label="t.remove" @click="removeRow(i)">×</button>
          <div v-if="errors[`at${i}`] || errors[`text${i}`]" class="error full">
            {{ errors[`at${i}`] || errors[`text${i}`] }}
          </div>
        </div>
        <button v-if="form.rows.length < 20" type="button" class="quiet add" @click="addRow">+ {{ t.addReminder }}</button>
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
.row {
  display: grid;
  grid-template-columns: 84px 1fr 120px 32px;
  gap: 8px;
  align-items: end;
  margin-bottom: 12px;
}
.row input,
.row select {
  width: 100%;
}
.row label {
  font-size: 12px;
}
.remove {
  height: 36px;
  font-size: 18px;
}
.full {
  grid-column: 1 / -1;
  margin-top: 0;
}
.add {
  padding-left: 0;
}
@media (max-width: 520px) {
  .row {
    grid-template-columns: 84px 1fr 32px;
  }
  .row .show {
    grid-column: 1 / 3;
    grid-row: 2;
  }
}
</style>
