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
}
