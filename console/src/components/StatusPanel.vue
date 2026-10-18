<script setup lang="ts">
import { computed } from 'vue'
import { t } from '../i18n'
import { live, recentlyEnded } from '../live'
import { alertThreshold, formatDuration, formatOvertime, formatRemaining } from '../time'

const s = computed(() => live.state)

const expired = computed(
  () => s.value?.status === 'expired' || (s.value?.status === 'running' && live.remainingMs <= 0),
)

const digits = computed(() => {
  const st = s.value
  if (!st || st.status === 'idle') return '--:--'
  if (expired.value && st.on_expire === 'overtime') return formatOvertime(live.overtimeMs)
  return formatRemaining(live.remainingMs)
})

const tone = computed(() => {
  const st = s.value
  if (!st || st.status === 'idle' || st.status === 'paused') return 'muted'
  if (expired.value || live.remainingMs <= alertThreshold(st.total_ms)) return 'alert'
  return 'live'
})

const progress = computed(() => {
  const st = s.value
  if (!st || st.status === 'idle' || st.total_ms === 0 || expired.value) return 0
  return Math.min(1, live.remainingMs / st.total_ms)
})

const label = computed(() => {
  const st = s.value
  if (!st || st.status === 'idle') return recentlyEnded.value ? t.value.ended : t.value.notStarted
  if (expired.value) return t.value.timesUp
  return st.status === 'paused' ? t.value.paused : t.value.running
})
</script>

<template>
  <section class="status" :class="tone">
    <div class="title">{{ s?.title || ' ' }}</div>
    <div class="digits num" aria-live="off">{{ digits }}</div>
    <div class="bar" role="progressbar" :aria-valuenow="Math.round(progress * 100)" aria-valuemin="0" aria-valuemax="100">
      <div class="fill" :style="{ transform: `scaleX(${progress})` }" />
    </div>
    <div class="meta">
      <span class="label">{{ label }}</span>
      <span v-if="s && s.status !== 'idle'" class="muted num">{{ t.total }} {{ formatDuration(s.total_ms) }}</span>
    </div>
  </section>
</template>

<style scoped>
.title {
  font-size: 14px;
  color: var(--fg-muted);
  min-height: 21px;
}
.digits {
  font-size: clamp(64px, 14vw, 120px);
  font-weight: 300;
  line-height: 1.05;
  letter-spacing: -0.02em;
  margin: 8px 0 20px;
  transition: color 400ms linear;
}
.muted .digits {
  color: var(--fg-muted);
}
.alert .digits {
  color: var(--alert);
}
.bar {
  height: 6px;
  background: var(--track);
  border-radius: 3px;
  overflow: hidden;
}
.fill {
  height: 100%;
  background: var(--accent);
  transform-origin: left;
  transition:
    transform 240ms linear,
    background-color 400ms linear;
}
.muted .fill {
  background: var(--fg-muted);
}
.alert .fill {
  background: var(--alert);
}
.meta {
  display: flex;
  justify-content: space-between;
  margin-top: 10px;
  font-size: 14px;
}
.alert .label {
  color: var(--alert);
}
</style>
