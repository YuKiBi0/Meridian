<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { api, ApiError, roomApi } from '../api'
import { t } from '../i18n'
import { applyState, connect, live, onPresetsChanged, onRoomGone, room } from '../live'
import type { ExtendMode, Preset, Reminder, TimerConfig, TimerState } from '../types'
import ClientAddress from './ClientAddress.vue'
import ConfirmDialog from './ConfirmDialog.vue'
import EditorDialog from './EditorDialog.vue'
import LogsDialog from './LogsDialog.vue'
import PresetList from './PresetList.vue'
import PromptDialog from './PromptDialog.vue'
import RemindersDialog from './RemindersDialog.vue'
import RunReminders from './RunReminders.vue'
import StatusPanel from './StatusPanel.vue'
import TopBar from './TopBar.vue'

const props = defineProps<{ roomId: string }>()
/** leave goes back to the room list, with a message to show there. */
const emit = defineEmits<{ logout: []; leave: [notice?: string] }>()
const rapi = roomApi(props.roomId)

const presets = ref<Preset[]>([])
const online = ref<number | null>(null)
const notice = ref('')
const editor = ref<{ preset?: Preset } | null>(null)
const editorRef = ref<InstanceType<typeof EditorDialog> | null>(null)
const confirm = ref<{ message: string; danger?: boolean; confirmText?: string; action: () => void } | null>(null)
const prompt = ref<ExtendMode | null>(null)
const showLogs = ref(false)
const editingReminders = ref(false)
const remindersRef = ref<InstanceType<typeof RemindersDialog> | null>(null)

const status = computed(() => live.state?.status ?? 'idle')
const seq = computed(() => live.state?.seq)
const active = computed(() => status.value === 'running' || status.value === 'paused')
const anyDialog = computed(() => !!(editor.value || confirm.value || prompt.value || showLogs.value || editingReminders.value))

let noticeTimer: number | undefined
function say(msg: string) {
  notice.value = msg
  clearTimeout(noticeTimer)
  noticeTimer = window.setTimeout(() => (notice.value = ''), 4000)
}

function fail(e: unknown): void {
  const err = e as ApiError
  if (err.status === 401) return emit('logout')
  if (err.code === 'room_not_found') return emit('leave', t.value.roomDeleted)
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
    if (await op(() => rapi.start({ ...body, if_seq: seq.value }))) after?.()
  }
  if (status.value === 'idle') return go()
  confirm.value = { message: t.value.confirmReplace, confirmText: t.value.start, action: go }
}

function toggle() {
  if (status.value === 'running') op(() => rapi.pause(seq.value))
  else if (status.value === 'paused') op(() => rapi.resume(seq.value))
}

function end() {
  const go = () => op(() => rapi.end(seq.value))
  if (status.value === 'expired') return go()
  confirm.value = { message: t.value.confirmEnd, danger: true, confirmText: t.value.end, action: go }
}

/** Adds ms (or takes it off when negative) to the remaining time or total. */
function adjust(mode: ExtendMode, ms: number) {
  if (ms > 0) return op(() => rapi.extend(ms, mode, seq.value))
  const go = () => op(() => rapi.reduce(-ms, mode, seq.value))
  if (-ms < live.remainingMs) return go()
  confirm.value = { message: t.value.confirmCutToZero, danger: true, confirmText: t.value.endEarly, action: go }
}

async function saveReminders(reminders: Reminder[], remindersSeq: number) {
  try {
    applyState(await rapi.setReminders(reminders, remindersSeq))
    editingReminders.value = false
    say(t.value.remindersSaved)
  } catch (e) {
    const err = e as ApiError
    if (err.status === 400) remindersRef.value?.setError(err.message)
    else if (err.code === 'reminders_conflict') remindersRef.value?.setError(t.value.remindersConflict)
    else {
      if (err.code === 'invalid_state') editingReminders.value = false
      fail(e)
    }
  }
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

async function pollRoom() {
  try {
    const r = await rapi.get()
    online.value = r.clients
    room.value ??= { id: r.id, name: r.name }
  } catch (e) {
    online.value = null
    if ((e as ApiError).code === 'room_not_found') emit('leave', t.value.roomNotFound)
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
let offPresets: (() => void) | undefined
let offGone: (() => void) | undefined
onMounted(() => {
  offPresets = onPresetsChanged(loadPresets)
  offGone = onRoomGone(() => emit('leave', t.value.roomDeleted))
  connect(props.roomId)
  loadPresets()
  pollRoom()
  clientsTimer = window.setInterval(pollRoom, 5000)
  window.addEventListener('keydown', onKey)
})
onUnmounted(() => {
  offPresets?.()
  offGone?.()
  clearInterval(clientsTimer)
  window.removeEventListener('keydown', onKey)
})

const QUICK = [-10, -5, -1, 1, 5, 10]
</script>

<template>
  <div class="page">
    <TopBar :status="status" :online="online" @logs="showLogs = true" @logout="logout" />

    <nav class="crumbs">
      <button class="quiet back" @click="emit('leave')">← {{ t.allRooms }}</button>
      <span class="room-name">{{ room?.name ?? '' }}</span>
    </nav>

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
              <button
                v-for="m in QUICK"
                :key="m"
                class="num"
                :disabled="m < 0 ? !active : status === 'idle'"
                @click="adjust(mode, m * 60_000)"
              >
                {{ t.minutes(m) }}
              </button>
              <button :disabled="status === 'idle'" @click="prompt = mode">{{ t.custom }}</button>
            </div>
          </div>
        </div>

        <RunReminders @edit="editingReminders = true" />

        <p class="muted shortcuts">{{ t.shortcuts }}</p>
      </div>

      <aside class="right">
        <ClientAddress :room-id="roomId" @say="say" />
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
      :can-reduce="active"
      @cancel="prompt = null"
      @submit="(ms) => (adjust(prompt!, ms), (prompt = null))"
    />
    <RemindersDialog
      v-if="editingReminders"
      ref="remindersRef"
      @cancel="editingReminders = false"
      @save="saveReminders"
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
.crumbs {
  display: flex;
  align-items: center;
  gap: 8px;
  padding-top: 16px;
  min-width: 0;
}
.back {
  margin-left: -8px;
  flex-shrink: 0;
}
.room-name {
  font-size: 18px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 340px;
  gap: 56px;
  padding-top: 24px;
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
  .extend-buttons {
    width: 100%;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
  }
  .extend-buttons button:last-child {
    grid-column: span 2;
  }
  .extend-buttons button {
    padding: 0 4px;
  }
}
</style>
