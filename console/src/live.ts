// Live countdown state: subscribes to the SSE stream and extrapolates the
// remaining time locally between events, like the desktop client does.
import { computed, reactive, ref } from 'vue'
import type { SyncEvent, TimerState } from './types'

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

let source: EventSource | null = null
let everOpened = false
const presetListeners = new Set<() => void>()

/**
 * Calls fn whenever another console (or this one) changes the presets, and
 * after a reconnect, since events sent while offline are lost.
 */
export function onPresetsChanged(fn: () => void): () => void {
  presetListeners.add(fn)
  return () => presetListeners.delete(fn)
}
let retry = 1000
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

export function connect() {
  source?.close()
  connection.value = 'connecting'
  source = new EventSource('api/v1/stream?role=console')
  source.onopen = () => {
    connection.value = 'connected'
    retry = 1000
    if (everOpened) presetListeners.forEach((fn) => fn())
    everOpened = true
  }
  source.addEventListener('presets', () => presetListeners.forEach((fn) => fn()))
  source.addEventListener('state', (e) => accept(JSON.parse((e as MessageEvent).data)))
  source.addEventListener('sync', (e) => {
    const s: SyncEvent = JSON.parse((e as MessageEvent).data)
    const a = anchor.value
    if (!a || s.seq !== a.state.seq) return
    if (Math.abs(live.remainingMs - s.remaining_ms) > 100 || Math.abs(live.overtimeMs - s.overtime_ms) > 100) {
      accept({ ...a.state, remaining_ms: s.remaining_ms, overtime_ms: s.overtime_ms, server_time: s.server_time })
    }
  })
  source.onerror = () => {
    if (source?.readyState === EventSource.CLOSED) {
      connection.value = 'disconnected'
      setTimeout(connect, retry)
      retry = Math.min(retry * 2, 30_000)
    } else {
      connection.value = 'connecting'
    }
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
