// Wire types, mirroring PRD §9.

export type Status = 'idle' | 'running' | 'paused' | 'expired'
export type OnExpire = 'stop' | 'overtime'
export type ExtendMode = 'remaining' | 'total'

export interface TimerState {
  seq: number
  run_id: string | null
  status: Status
  title: string
  total_ms: number
  remaining_ms: number
  overtime_ms: number
  on_expire: OnExpire
  marks_ms: number[]
  reminders: RunReminder[]
  /** seq at which the reminders were last set; sent back when editing them. */
  reminders_seq: number
  server_time: number
  last_end: { run_id: string; at: number } | null
}

export interface SyncEvent {
  seq: number
  status: Status
  remaining_ms: number
  overtime_ms: number
  server_time: number
}

export interface Reminder {
  id?: string
  at_ms: number
  text: string
  duration_ms: number
  sticky: boolean
}

/** A reminder of the current run; fired also covers skipped ones. */
export interface RunReminder extends Reminder {
  id: string
  fired: boolean
}

export interface TimerConfig {
  title: string
  total_ms: number
  on_expire: OnExpire
  reminders: Reminder[]
}

export interface Preset extends TimerConfig {
  id: string
  name: string
}

export interface LogEntry {
  id: number
  at: string
  action: string
  params: Record<string, unknown>
  seq_after: number | null
  remote_ip: string
  /** Set for room operations; room_name is empty once the room is deleted. */
  room_id: string | null
  room_name: string
}

export interface RoomInfo {
  id: string
  name: string
}

/** A room as the console lists it. */
export interface RoomSummary extends RoomInfo {
  created_at: string
  /** Desktop clients in the room right now. */
  clients: number
  state: TimerState
}
