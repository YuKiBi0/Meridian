<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { api, ApiError } from '../api'
import { lang, setLang, t } from '../i18n'
import { applyState, connect, connection, live } from '../live'
import type { ExtendMode, Preset, TimerConfig, TimerState } from '../types'
import ConfirmDialog from './ConfirmDialog.vue'
import EditorDialog from './EditorDialog.vue'
import LogsDialog from './LogsDialog.vue'
import PresetList from './PresetList.vue'
import PromptDialog from './PromptDialog.vue'
import StatusPanel from './StatusPanel.vue'

const emit = defineEmits<{ logout: [] }>()

const presets = ref<Preset[]>([])
const online = ref<number | null>(null)
const notice = ref('')
const editor = ref<{ preset?: Preset } | null>(null)
const editorRef = ref<InstanceType<typeof EditorDialog> | null>(null)
const confirm = ref<{ message: string; danger?: boolean; confirmText?: string; action: () => void } | null>(null)
const prompt = ref<ExtendMode | null>(null)
const showLogs = ref(false)

const status = computed(() => live.state?.status ?? 'idle')
const seq = computed(() => live.state?.seq)
const anyDialog = computed(() => !!(editor.value || confirm.value || prompt.value || showLogs.value))

let noticeTimer: number | undefined
function say(msg: string) {
  notice.value = msg
  clearTimeout(noticeTimer)
  noticeTimer = window.setTimeout(() => (notice.value = ''), 4000)
}

function fail(e: unknown): void {
  const err = e as ApiError
  if (err.status === 401) return emit('logout')
  if (err.code === 'seq_conflict') return say(t.value.seqConflict)
  if (err.code === 'invalid_state') return say(t.value.invalidState)
  if (err.code === 'network') return say(t.value.networkError)
  say(err.message || t.value.networkError)
}

async function op(call: () => Promise<TimerState>): Promise<boolean> {
  try {
    applyState(await call())
    return true
  } catch (e) {
    fail(e)
    return false
  }
}

// ---- timer ----

function startWith(body: Partial<TimerConfig> & { preset_id?: string }, after?: () => void) {
  const go = async () => {
    if (await op(() => api.start({ ...body, if_seq: seq.value }))) after?.()
  }
  if (status.value === 'idle') return go()
  confirm.value = { message: t.value.confirmReplace, confirmText: t.value.start, action: go }
}

function toggle() {
  if (status.value === 'running') op(() => api.pause(seq.value))
  else if (status.value === 'paused') op(() => api.resume(seq.value))
}

function end() {
  const go = () => op(() => api.end(seq.value))
  if (status.value === 'expired') return go()
  confirm.value = { message: t.value.confirmEnd, danger: true, confirmText: t.value.end, action: go }
}

function extend(mode: ExtendMode, ms: number) {
  op(() => api.extend(ms, mode, seq.value))
}

// ---- presets ----

async function loadPresets() {
  try {
    presets.value = await api.presets()
  } catch (e) {
    fail(e)
  }
}

async function savePreset(p: Omit<Preset, 'id'> & { id?: string }) {
  try {
    if (p.id) await api.updatePreset(p as Preset)
    else await api.createPreset(p)
    editor.value = null
    say(t.value.saved)
    loadPresets()
  } catch (e) {
    const err = e as ApiError
    if (err.status === 400) editorRef.value?.setError(err.message)
    else fail(e)
  }
}

function removePreset(p: Preset) {
  confirm.value = {
    message: t.value.confirmDelete(p.name),
    danger: true,
    confirmText: t.value.delete,
    action: async () => {
      try {
        await api.deletePreset(p.id)
      } catch (e) {
        fail(e)
      }
      loadPresets()
    },
  }
}

async function reorder(ids: string[]) {
  const byId = new Map(presets.value.map((p) => [p.id, p]))
  presets.value = ids.map((id) => byId.get(id)!)
  try {
    await api.reorderPresets(ids)
  } catch (e) {
    fail(e)
    loadPresets()
  }
}

// ---- session / chrome ----

async function logout() {
  await api.logout().catch(() => {})
  emit('logout')
}

async function pollClients() {
  try {
    online.value = (await api.clients()).client
  } catch {
    online.value = null
  }
}

function onKey(e: KeyboardEvent) {
  if (anyDialog.value || e.metaKey || e.ctrlKey || e.altKey) return
  const tag = (e.target as HTMLElement)?.tagName
  if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA' || tag === 'BUTTON') return
  if (e.code === 'Space') {
    e.preventDefault()
    toggle()
  } else if (e.key === 'n' || e.key === 'N') {
    e.preventDefault()
    editor.value = {}
  }
}

let clientsTimer: number | undefined
onMounted(() => {
  connect()
  loadPresets()
  pollClients()
  clientsTimer = window.setInterval(pollClients, 5000)
  window.addEventListener('keydown', onKey)
})
onUnmounted(() => {
  clearInterval(clientsTimer)
  window.removeEventListener('keydown', onKey)
})

const connectionText = computed(() => t.value[connection.value])
const QUICK = [1, 5, 10]
</script>

<template>
  <div class="page">
    <header class="top">
      <div class="brand">
        <svg class="mark" viewBox="0 0 24 24" aria-hidden="true">
          <circle cx="12" cy="12" r="9" />
          <line x1="12" y1="2" x2="12" y2="22" />
          <circle class="dot" :class="status" cx="12" cy="8.7" r="2" />
        </svg>
        <span>{{ t.appTitle }}</span>
      </div>
      <nav>
        <span class="conn" :class="connection"><i />{{ connectionText }}</span>
        <span v-if="online !== null" class="muted num">{{ t.online }} {{ online }}</span>
        <button class="quiet" @click="showLogs = true">{{ t.logs }}</button>
        <button class="quiet" @click="setLang(lang === 'zh' ? 'en' : 'zh')">{{ lang === 'zh' ? 'EN' : '中文' }}</button>
        <button class="quiet" @click="logout">{{ t.logout }}</button>
      </nav>
    </header>

    <main class="grid">
      <div class="left">
        <StatusPanel />

        <div class="controls">
          <template v-if="status === 'running'">
            <button class="primary" @click="toggle">{{ t.pause }}</button>
          </template>
          <template v-else-if="status === 'paused'">
            <button class="primary" @click="toggle">{{ t.resume }}</button>
          </template>
          <button :class="{ primary: status === 'idle' }" @click="editor = {}">{{ t.new }}</button>
          <span class="spacer" />
          <button v-if="status !== 'idle'" @click="end">{{ t.end }}</button>
        </div>

        <div class="extend" :class="{ disabled: status === 'idle' }">
          <div v-for="mode in ['remaining', 'total'] as const" :key="mode" class="extend-row">
            <span class="extend-label">{{ mode === 'remaining' ? t.extendRemaining : t.extendTotal }}</span>
            <div class="extend-buttons">
              <button v-for="m in QUICK" :key="m" class="num" :disabled="status === 'idle'" @click="extend(mode, m * 60_000)">
                {{ t.minutes(m) }}
              </button>
              <button :disabled="status === 'idle'" @click="prompt = mode">{{ t.custom }}</button>
            </div>
          </div>
        </div>

        <p class="muted shortcuts">{{ t.shortcuts }}</p>
      </div>

      <aside class="right">
        <PresetList
          :presets="presets"
          @create="editor = {}"
          @start="(p) => startWith({ preset_id: p.id })"
          @edit="(p) => (editor = { preset: p })"
          @remove="removePreset"
          @reorder="reorder"
        />
      </aside>
    </main>

    <div class="notice" :class="{ show: notice }" role="status">{{ notice }}</div>

    <EditorDialog
      v-if="editor"
      ref="editorRef"
      :preset="editor.preset"
      @cancel="editor = null"
      @start="(cfg) => startWith(cfg, () => (editor = null))"
      @save="savePreset"
    />
    <PromptDialog
      v-if="prompt"
      :title="prompt === 'remaining' ? t.extendRemaining : t.extendTotal"
      @cancel="prompt = null"
      @submit="(ms) => (extend(prompt!, ms), (prompt = null))"
    />
    <ConfirmDialog
      v-if="confirm"
      :message="confirm.message"
      :danger="confirm.danger"
      :confirm-text="confirm.confirmText"
      @cancel="confirm = null"
      @confirm="(confirm.action(), (confirm = null))"
    />
    <LogsDialog v-if="showLogs" @close="showLogs = false" />
  </div>
</template>

<style scoped>
.page {
  max-width: 1120px;
  margin: 0 auto;
  padding: 0 16px 48px;
}
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
}
.mark {
  width: 22px;
  height: 22px;
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
.grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 340px;
  gap: 56px;
  padding-top: 40px;
}
.controls {
  display: flex;
  gap: 8px;
  margin-top: 32px;
}
.controls .primary {
  min-width: 96px;
}
.spacer {
  flex: 1;
}
.extend {
  margin-top: 32px;
  border-top: 1px solid var(--line);
  padding-top: 16px;
}
.extend.disabled .extend-label {
  color: var(--fg-muted);
}
.extend-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  padding: 6px 0;
}
.extend-label {
  font-size: 14px;
}
.extend-buttons {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}
.shortcuts {
  font-size: 12px;
  margin-top: 32px;
}
.notice {
  position: fixed;
  left: 50%;
  bottom: 24px;
  transform: translate(-50%, 4px);
  max-width: calc(100vw - 32px);
  padding: 10px 16px;
  background: var(--fg);
  color: var(--on-fg);
  border-radius: var(--r-md);
  font-size: 14px;
  opacity: 0;
  pointer-events: none;
  transition:
    opacity 160ms linear,
    transform 160ms ease-out;
}
.notice.show {
  opacity: 1;
  transform: translate(-50%, 0);
}
@media (max-width: 860px) {
  .grid {
    grid-template-columns: 1fr;
    gap: 40px;
    padding-top: 24px;
  }
  .shortcuts {
    display: none;
  }
}
@media (max-width: 520px) {
  nav {
    gap: 4px 8px;
  }
  .extend-buttons {
    width: 100%;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
  }
  .extend-buttons button {
    padding: 0 4px;
  }
}
</style>
