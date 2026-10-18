// Live countdown state: subscribes to the SSE stream of one room (or to the
// room list) and extrapolates the remaining time locally between events,
// like the desktop client does.
import { computed, reactive, ref } from 'vue'
import { ApiError, roomApi } from './api'
import type { RoomInfo, SyncEvent, TimerState } from './types'

export type Connection = 'connected' | 'connecting' | 'disconnected'

interface Anchor {
  state: TimerState
  at: number // performance.now() when the state was received
}

export const connection = ref<Connection>('connecting')
const anchor = ref<Anchor | null>(null)
const now = ref(performance.now())
/** Run id that was ended in the last few seconds, to show "Ended". */
export const recentlyEnded = ref(false)

/** The room the stream is in, as last announced by the server. */
export const room = ref<RoomInfo | null>(null)

let source: EventSource | null = null
let roomId: string | null = null
let everOpened = false
const presetListeners = new Set<() => void>()
const roomsListeners = new Set<() => void>()
const goneListeners = new Set<() => void>()

function listen(set: Set<() => void>, fn: () => void): () => void {
  set.add(fn)
  return () => set.delete(fn)
}

/**
 * Calls fn whenever another console (or this one) changes the presets, and
 * after a reconnect, since events sent while offline are lost.
 */
export const onPresetsChanged = (fn: () => void) => listen(presetListeners, fn)

/** Calls fn when the room list changes (room list stream only), and after a reconnect. */
export const onRoomsChanged = (fn: () => void) => listen(roomsListeners, fn)

/** Calls fn when the current room is deleted. The stream is closed by then. */
export const onRoomGone = (fn: () => void) => listen(goneListeners, fn)

let retry = 1000
let retryTimer: number | undefined
let endedTimer: number | undefined

function accept(state: TimerState) {
  const cur = anchor.value?.state
  if (cur && state.seq < cur.seq) return
  if (state.status === 'idle' && state.last_end && cur && cur.status !== 'idle' && state.last_end.run_id === cur.run_id) {
    recentlyEnded.value = true
    clearTimeout(endedTimer)
    endedTimer = window.setTimeout(() => (recentlyEnded.value = false), 5000)
  } else if (state.status !== 'idle') {
    recentlyEnded.value = false
  }
  anchor.value = { state, at: performance.now() }
}

/**
 * Subscribes to the room's stream, or to the room list when id is null.
 * Replaces any previous subscription.
 */
export function connect(id: string | null) {
  if (id !== roomId) {
    anchor.value = null
    room.value = null
    recentlyEnded.value = false
    everOpened = false
    retry = 1000
  }
  roomId = id
  open()
}

export function disconnect() {
  clearTimeout(retryTimer)
  source?.close()
  source = null
  roomId = null
}

function gone() {
  disconnect()
  goneListeners.forEach((fn) => fn())
}

function open() {
  clearTimeout(retryTimer)
  source?.close()
  connection.value = 'connecting'
  const id = roomId
  const es = new EventSource(`api/v1/stream?role=console${id ? `&r=${encodeURIComponent(id)}` : ''}`)
  source = es
  es.onopen = () => {
    connection.value = 'connected'
    retry = 1000
    if (everOpened) {
      presetListeners.forEach((fn) => fn())
      roomsListeners.forEach((fn) => fn())
    }
    everOpened = true
  }
  es.addEventListener('presets', () => presetListeners.forEach((fn) => fn()))
  es.addEventListener('rooms', () => roomsListeners.forEach((fn) => fn()))
  es.addEventListener('room', (e) => (room.value = JSON.parse((e as MessageEvent).data)))
  es.addEventListener('room_deleted', gone)
  es.addEventListener('state', (e) => accept(JSON.parse((e as MessageEvent).data)))
  es.addEventListener('sync', (e) => {
    const s: SyncEvent = JSON.parse((e as MessageEvent).data)
    const a = anchor.value
    if (!a || s.seq !== a.state.seq) return
    if (Math.abs(live.remainingMs - s.remaining_ms) > 100 || Math.abs(live.overtimeMs - s.overtime_ms) > 100) {
      accept({ ...a.state, remaining_ms: s.remaining_ms, overtime_ms: s.overtime_ms, server_time: s.server_time })
    }
  })
  es.onerror = async () => {
    if (es !== source) return
    if (es.readyState !== EventSource.CLOSED) {
      connection.value = 'connecting'
      return
    }
    connection.value = 'disconnected'
    // The server refuses the stream of a room deleted while we were away.
    if (id) {
      try {
        await roomApi(id).get()
      } catch (e) {
        if ((e as ApiError).code === 'room_not_found' && es === source) return gone()
      }
    }
    if (es !== source) return
    retryTimer = window.setTimeout(open, retry)
    retry = Math.min(retry * 2, 30_000)
  }
}

/** Applies a state returned by an admin call before the SSE echo arrives. */
export function applyState(state: TimerState) {
  accept(state)
}

function frame() {
  now.value = performance.now()
  window.setTimeout(frame, 100)
}
frame()

const state = computed(() => anchor.value?.state ?? null)

export const live = reactive({
  state,
  remainingMs: computed(() => {
    const a = anchor.value
    if (!a) return 0
    if (a.state.status !== 'running') return a.state.remaining_ms
    return Math.max(0, a.state.remaining_ms - (now.value - a.at))
  }),
  overtimeMs: computed(() => {
    const a = anchor.value
    if (!a) return 0
    if (a.state.status === 'expired' && a.state.on_expire === 'overtime') {
      return a.state.overtime_ms + (now.value - a.at)
    }
    // Ran out locally before the server's expired event arrived.
    if (a.state.status === 'running' && a.state.on_expire === 'overtime') {
      return Math.max(0, now.value - a.at - a.state.remaining_ms)
    }
    return 0
  }),
})
