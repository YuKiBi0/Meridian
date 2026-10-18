<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import { api, roomApi, type ApiError } from '../api'
import { t } from '../i18n'
import { connect, onRoomsChanged } from '../live'
import { alertThreshold, formatOvertime, formatRemaining } from '../time'
import type { RoomSummary } from '../types'
import ConfirmDialog from './ConfirmDialog.vue'
import LogsDialog from './LogsDialog.vue'
import NameDialog from './NameDialog.vue'
import TopBar from './TopBar.vue'

const props = defineProps<{ notice?: string }>()
const emit = defineEmits<{ enter: [id: string]; logout: [] }>()

const rooms = ref<RoomSummary[] | null>(null)
const fetchedAt = ref(performance.now())
const now = ref(performance.now())
const naming = ref<{ room?: RoomSummary } | null>(null)
const nameRef = ref<InstanceType<typeof NameDialog> | null>(null)
const confirm = ref<{ message: string; action: () => void } | null>(null)
const showLogs = ref(false)
const notice = ref('')

let noticeTimer: number | undefined
function say(msg: string) {
  notice.value = msg
  clearTimeout(noticeTimer)
  noticeTimer = window.setTimeout(() => (notice.value = ''), 4000)
}

function fail(e: unknown) {
  const err = e as ApiError
  if (err.status === 401) return emit('logout')
  say(err.code === 'network' ? t.value.networkError : err.message || t.value.networkError)
}

async function load() {
  try {
    rooms.value = await api.rooms()
    fetchedAt.value = performance.now()
  } catch (e) {
    fail(e)
  }
}

/** The room's time as the client would show it right now. */
function digits(r: RoomSummary): string {
  const s = r.state
  if (s.status === 'idle') return '--:--'
  const elapsed = s.status === 'running' || s.status === 'expired' ? now.value - fetchedAt.value : 0
  if (s.status === 'expired' || s.remaining_ms - elapsed <= 0) {
    if (s.on_expire !== 'overtime') return formatRemaining(0)
    const over = s.status === 'expired' ? s.overtime_ms + elapsed : elapsed - s.remaining_ms
    return formatOvertime(over)
  }
  return formatRemaining(s.remaining_ms - elapsed)
}

/** live, alert or muted, as on the main display (DESIGN §5.2). */
function tone(r: RoomSummary): string {
  const s = r.state
  if (s.status === 'idle' || s.status === 'paused') return 'muted'
  if (s.status === 'expired') return 'alert'
  const left = s.remaining_ms - (now.value - fetchedAt.value)
  return left <= alertThreshold(s.total_ms) ? 'alert' : 'live'
}

function label(r: RoomSummary): string {
  const s = r.state
  if (s.status === 'idle') return t.value.notStarted
  if (s.status === 'expired' || (s.status === 'running' && s.remaining_ms - (now.value - fetchedAt.value) <= 0)) {
    return t.value.timesUp
  }
  return s.status === 'paused' ? t.value.paused : t.value.running
}

async function saveName(name: string) {
  const r = naming.value?.room
  try {
    if (r) {
      await roomApi(r.id).rename(name)
      naming.value = null
      load()
    } else {
      const created = await api.createRoom(name)
      naming.value = null
      emit('enter', created.id)
    }
  } catch (e) {
    const err = e as ApiError
    if (err.status === 400) nameRef.value?.setError(err.message)
    else {
      naming.value = null
      fail(e)
    }
  }
}

function remove(r: RoomSummary) {
  confirm.value = {
    message: t.value.confirmDeleteRoom(r.name),
    action: async () => {
      try {
        await roomApi(r.id).remove()
      } catch (e) {
        if ((e as ApiError).code !== 'room_not_found') fail(e)
      }
      load()
    },
  }
}

async function logout() {
  await api.logout().catch(() => {})
  emit('logout')
}

let tick: number | undefined
let poll: number | undefined
let offRooms: (() => void) | undefined
onMounted(() => {
  if (props.notice) say(props.notice)
  offRooms = onRoomsChanged(load)
  connect(null)
  load()
  tick = window.setInterval(() => (now.value = performance.now()), 250)
  // Client counts change without an event.
  poll = window.setInterval(load, 5000)
})
onUnmounted(() => {
  offRooms?.()
  clearInterval(tick)
  clearInterval(poll)
})
</script>

<template>
  <div class="page">
    <TopBar @logs="showLogs = true" @logout="logout" />

    <main>
      <header class="head">
        <h1>{{ t.rooms }}</h1>
        <button class="primary" @click="naming = {}">{{ t.newRoom }}</button>
      </header>

      <div v-if="rooms && rooms.length === 0" class="empty">
        <p>{{ t.noRooms }}</p>
        <p class="muted">{{ t.noRoomsHint }}</p>
      </div>
      <ul v-else-if="rooms">
        <li v-for="r in rooms" :key="r.id" :class="tone(r)">
          <button class="info" :title="t.enterRoom" @click="emit('enter', r.id)">
            <span class="name">{{ r.name }}</span>
            <span class="meta muted">
              <span class="digits num">{{ digits(r) }}</span>
              <span>{{ label(r) }}</span>
              <span v-if="r.state.title" class="title">{{ r.state.title }}</span>
            </span>
          </button>
          <span class="muted num online">{{ t.online }} {{ r.clients }}</span>
          <div class="ops">
            <button class="quiet" @click="naming = { room: r }">{{ t.rename }}</button>
            <button class="quiet" @click="remove(r)">{{ t.delete }}</button>
            <button @click="emit('enter', r.id)">{{ t.enterRoom }}</button>
          </div>
        </li>
      </ul>
    </main>

    <div class="notice" :class="{ show: notice }" role="status">{{ notice }}</div>

    <NameDialog
      v-if="naming"
      ref="nameRef"
      :title="naming.room ? t.rename : t.newRoom"
      :initial="naming.room?.name"
      @cancel="naming = null"
      @submit="saveName"
    />
    <ConfirmDialog
      v-if="confirm"
      :message="confirm.message"
      danger
      :confirm-text="t.delete"
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
main {
  padding-top: 40px;
}
.head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 16px;
}
h1 {
  font-size: 20px;
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
  gap: 16px;
  padding: 14px 0;
  border-top: 1px solid var(--line);
}
.info {
  flex: 1;
  min-width: 0;
  height: auto;
  padding: 0;
  border: none;
  text-align: left;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.info:hover .name {
  text-decoration: underline;
  text-underline-offset: 3px;
}
.name {
  font-size: 16px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.meta {
  display: flex;
  gap: 10px;
  font-size: 14px;
  min-width: 0;
}
.digits {
  min-width: 52px;
}
.live .digits {
  color: var(--fg);
}
.alert .digits {
  color: var(--alert);
}
.title {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.online {
  font-size: 14px;
  flex-shrink: 0;
}
.ops {
  display: flex;
  gap: 2px;
  flex-shrink: 0;
}
.empty {
  border-top: 1px solid var(--line);
  padding-top: 16px;
}
.empty p {
  margin: 0 0 6px;
}
@media (max-width: 640px) {
  li {
    flex-wrap: wrap;
    gap: 8px 16px;
  }
  .info {
    flex-basis: 100%;
  }
  .ops {
    margin-left: auto;
  }
}
</style>
