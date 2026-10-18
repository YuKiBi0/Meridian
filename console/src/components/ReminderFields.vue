<script setup lang="ts">
import { t } from '../i18n'
import { emptyRow, SHOW_OPTIONS, type ReminderRow } from '../reminders'
import { parseDuration } from '../time'

// rows is edited in place: it is the parent's reactive array.
const props = defineProps<{
  rows: ReminderRow[]
  errors: Record<string, string>
  /** Remaining time of the live run; rows at or above it are marked passed. */
  remainingMs?: number
}>()

function passed(row: ReminderRow): boolean {
  if (props.remainingMs === undefined) return false
  const at = parseDuration(row.at)
  return at !== null && at > props.remainingMs
}
</script>

<template>
  <div v-for="(row, i) in rows" :key="i" class="row" :class="{ passed: passed(row) }">
    <div class="at">
      <label :for="`at${i}`">{{ t.reminderAt }}</label>
      <input :id="`at${i}`" v-model="row.at" class="num" inputmode="decimal" placeholder="5" />
    </div>
    <div class="text">
      <label :for="`text${i}`">
        {{ t.message }}<span v-if="passed(row)" class="tag">{{ t.reminderPassed }}</span>
      </label>
      <input :id="`text${i}`" v-model="row.text" maxlength="80" />
    </div>
    <div class="show">
      <label :for="`show${i}`">{{ t.showFor }}</label>
      <select :id="`show${i}`" v-model="row.show">
        <option v-for="s in SHOW_OPTIONS" :key="s" :value="String(s)">{{ t.seconds(s) }}</option>
        <option value="sticky">{{ t.sticky }}</option>
      </select>
    </div>
    <button type="button" class="quiet remove" :aria-label="t.remove" @click="rows.splice(i, 1)">×</button>
    <div v-if="errors[`at${i}`] || errors[`text${i}`]" class="error full">
      {{ errors[`at${i}`] || errors[`text${i}`] }}
    </div>
  </div>
  <button v-if="rows.length < 20" type="button" class="quiet add" @click="rows.push(emptyRow())">
    + {{ t.addReminder }}
  </button>
</template>

<style scoped>
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
.passed input,
.passed select {
  color: var(--fg-muted);
}
.tag {
  margin-left: 6px;
  color: var(--fg-muted);
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
