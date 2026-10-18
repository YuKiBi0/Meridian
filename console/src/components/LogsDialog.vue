<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api } from '../api'
import { lang, t } from '../i18n'
import { formatDuration } from '../time'
import type { LogEntry } from '../types'

const emit = defineEmits<{ close: [] }>()
const logs = ref<LogEntry[] | null>(null)

onMounted(async () => {
  try {
    logs.value = await api.logs(200)
  } catch {
    logs.value = []
  }
})

function when(at: string) {
  return new Date(at).toLocaleString(lang.value === 'zh' ? 'zh-CN' : 'en-GB', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

/** The room an entry belongs to; deleted rooms keep the name they had. */
function roomOf(e: LogEntry) {
  if (!e.room_id) return ''
  if (e.room_name) return e.room_name
  const name = e.params?.name
  return e.action.startsWith('room.') && typeof name === 'string' ? name : t.value.deletedRoom
}

function detail(e: LogEntry) {
  const p = e.params ?? {}
  const parts: string[] = []
  if (typeof p.preset === 'string') parts.push(p.preset)
  else if (typeof p.name === 'string' && !e.action.startsWith('room.')) parts.push(p.name)
  else if (e.action === 'room.rename' && typeof p.name === 'string') parts.push(p.name)
  else if (typeof p.title === 'string' && p.title) parts.push(p.title)
  if (typeof p.total_ms === 'number') parts.push(formatDuration(p.total_ms))
  if (typeof p.delta_ms === 'number') {
    const mode = p.mode === 'total' ? t.value.extendTotal : t.value.extendRemaining
    parts.push(`${mode} +${formatDuration(p.delta_ms)}`)
  }
  return parts.join(' · ')
}
</script>

<template>
  <div class="overlay" @click.self="emit('close')" @keydown.esc="emit('close')">
    <div class="dialog" role="dialog" aria-modal="true">
      <h2>{{ t.logs }}</h2>
      <p v-if="logs && logs.length === 0" class="muted">{{ t.noLogs }}</p>
      <table v-else-if="logs">
        <tr v-for="e in logs" :key="e.id">
          <td class="muted num">{{ when(e.at) }}</td>
          <td class="room">{{ roomOf(e) }}</td>
          <td>{{ t.logAction[e.action] ?? e.action }}</td>
          <td class="muted">{{ detail(e) }}</td>
        </tr>
      </table>
      <div class="actions">
        <button autofocus @click="emit('close')">{{ t.close }}</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
table {
  width: 100%;
  border-collapse: collapse;
  font-size: 14px;
}
td {
  padding: 8px 8px 8px 0;
  border-top: 1px solid var(--line);
  vertical-align: top;
}
td:first-child {
  white-space: nowrap;
}
.room {
  max-width: 10em;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
