<script setup lang="ts">
import { computed } from 'vue'
import { lang, setLang, t } from '../i18n'
import { connection } from '../live'
import type { Status } from '../types'

defineProps<{ status?: Status; online?: number | null }>()
const emit = defineEmits<{ logs: []; logout: [] }>()

const connectionText = computed(() => t.value[connection.value])
</script>

<template>
  <header class="top">
    <div class="brand">
      <svg class="mark" viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="9" />
        <line x1="12" y1="2" x2="12" y2="22" />
        <circle class="dot" :class="status" cx="12" cy="8.7" r="2" />
      </svg>
      <span>{{ t.appTitle }}</span>
      <slot />
    </div>
    <nav>
      <span class="conn" :class="connection"><i />{{ connectionText }}</span>
      <span v-if="online != null" class="muted num">{{ t.online }} {{ online }}</span>
      <button class="quiet" @click="emit('logs')">{{ t.logs }}</button>
      <button class="quiet" @click="setLang(lang === 'zh' ? 'en' : 'zh')">{{ lang === 'zh' ? 'EN' : '中文' }}</button>
      <button class="quiet" @click="emit('logout')">{{ t.logout }}</button>
    </nav>
  </header>
</template>

<style scoped>
.top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  padding: 14px 0;
  border-bottom: 1px solid var(--line);
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  font-weight: 600;
  min-width: 0;
}
.mark {
  width: 22px;
  height: 22px;
  flex-shrink: 0;
  fill: none;
  stroke: var(--fg);
  stroke-width: 2;
}
.mark .dot {
  stroke: none;
  fill: var(--fg);
}
.mark .dot.running {
  fill: var(--accent);
}
nav {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 14px;
  flex-wrap: wrap;
}
nav button {
  height: 30px;
}
.conn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.conn i {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  border: 1.5px solid var(--fg-muted);
}
.conn.connected i {
  background: var(--fg);
  border-color: var(--fg);
}
.conn.connecting,
.conn.disconnected {
  color: var(--fg-muted);
}
@media (max-width: 520px) {
  nav {
    gap: 4px 8px;
  }
}
</style>
