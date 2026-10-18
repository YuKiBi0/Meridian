<script setup lang="ts">
import { ref } from 'vue'
import { t } from '../i18n'
import { formatDuration } from '../time'
import type { Preset } from '../types'

const props = defineProps<{ presets: Preset[] }>()
const emit = defineEmits<{
  start: [p: Preset]
  edit: [p: Preset]
  remove: [p: Preset]
  reorder: [ids: string[]]
  create: []
}>()

const dragging = ref<number | null>(null)
const over = ref<number | null>(null)

function drop(to: number) {
  const from = dragging.value
  dragging.value = over.value = null
  if (from === null || from === to) return
  const ids = props.presets.map((p) => p.id)
  const [moved] = ids.splice(from, 1)
  ids.splice(to, 0, moved)
  emit('reorder', ids)
}
</script>

<template>
  <section class="presets">
    <header>
      <h2>{{ t.presets }}</h2>
      <button class="quiet" @click="emit('create')">{{ t.new }}</button>
    </header>
    <p v-if="presets.length === 0" class="muted empty">{{ t.noPresets }}</p>
    <ul>
      <li
        v-for="(p, i) in presets"
        :key="p.id"
        draggable="true"
        :class="{ over: over === i && dragging !== i }"
        @dragstart="dragging = i"
        @dragover.prevent="over = i"
        @dragleave="over === i && (over = null)"
        @drop.prevent="drop(i)"
        @dragend="dragging = over = null"
      >
        <div class="info">
          <div class="name">{{ p.name }}</div>
          <div class="muted small">
            <span class="num">{{ formatDuration(p.total_ms) }}</span>
            <span v-if="p.reminders.length"> · {{ t.reminders }} {{ p.reminders.length }}</span>
          </div>
        </div>
        <div class="ops">
          <button class="quiet" @click="emit('edit', p)">{{ t.edit }}</button>
          <button class="quiet" @click="emit('remove', p)">{{ t.delete }}</button>
          <button @click="emit('start', p)">{{ t.start }}</button>
        </div>
      </li>
    </ul>
  </section>
</template>

<style scoped>
header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}
h2 {
  font-size: 15px;
  font-weight: 600;
  margin: 0;
}
ul {
  list-style: none;
  margin: 0;
  padding: 0;
}
li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 12px 0;
  border-top: 1px solid var(--line);
  cursor: grab;
}
li.over {
  border-top-color: var(--fg);
}
.info {
  min-width: 0;
}
.name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.small {
  font-size: 13px;
}
.ops {
  display: flex;
  gap: 2px;
  flex-shrink: 0;
}
.empty {
  border-top: 1px solid var(--line);
  padding-top: 12px;
}
</style>
