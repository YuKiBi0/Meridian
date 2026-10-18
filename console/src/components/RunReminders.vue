<script setup lang="ts">
import { computed } from 'vue'
import { t } from '../i18n'
import { live } from '../live'
import { formatDuration } from '../time'

defineEmits<{ edit: [] }>()

const editable = computed(() => live.state?.status === 'running' || live.state?.status === 'paused')
const reminders = computed(() => (editable.value ? (live.state?.reminders ?? []) : []))
</script>

<template>
  <section class="run-reminders" :class="{ disabled: !editable }">
    <div class="head">
      <span class="label">{{ t.reminders }}</span>
      <button class="quiet" :disabled="!editable" @click="$emit('edit')">{{ t.editReminders }}</button>
    </div>
    <ul v-if="reminders.length">
      <li v-for="r in reminders" :key="r.id" :class="{ fired: r.fired }">
        <span class="num at">{{ formatDuration(r.at_ms) }}</span>
        <span class="text">{{ r.text }}</span>
        <span v-if="r.fired" class="tag">{{ t.reminderPassed }}</span>
        <span v-else-if="r.sticky" class="tag">{{ t.sticky }}</span>
      </li>
    </ul>
    <p v-else-if="editable" class="muted empty">{{ t.noRunReminders }}</p>
  </section>
</template>

<style scoped>
.run-reminders {
  margin-top: 24px;
  border-top: 1px solid var(--line);
  padding-top: 12px;
}
.head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.label {
  font-size: 14px;
}
.disabled .label {
  color: var(--fg-muted);
}
ul {
  list-style: none;
  margin: 8px 0 0;
  padding: 0;
}
li {
  display: flex;
  align-items: baseline;
  gap: 12px;
  padding: 6px 0;
  font-size: 14px;
}
.at {
  min-width: 56px;
}
.text {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.tag {
  font-size: 12px;
  color: var(--fg-muted);
}
.fired .at,
.fired .text {
  color: var(--fg-muted);
}
.empty {
  font-size: 13px;
  margin: 8px 0 0;
}
</style>
