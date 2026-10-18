// Admin REST client. URLs are relative to the page, so the console works
// under any base path.
import type { ExtendMode, LogEntry, Preset, Reminder, RoomSummary, TimerConfig, TimerState } from './types'

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message)
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  let resp: Response
  try {
    resp = await fetch(path, {
      method,
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch {
    throw new ApiError(0, 'network', '')
  }
  if (resp.status === 204) return undefined as T
  const data = await resp.json().catch(() => null)
  if (!resp.ok) {
    const err = data?.error ?? {}
    throw new ApiError(resp.status, err.code ?? 'internal', err.message ?? '')
  }
  return data as T
}

const admin = 'api/v1/admin'

export const api = {
  session: () => request<void>('GET', `${admin}/session`),
  login: (token: string) => request<void>('POST', `${admin}/login`, { token }),
  logout: () => request<void>('POST', `${admin}/logout`),

  rooms: () => request<RoomSummary[]>('GET', `${admin}/rooms`),
  createRoom: (name: string) => request<RoomSummary>('POST', `${admin}/rooms`, { name }),

  presets: () => request<Preset[]>('GET', `${admin}/presets`),
  createPreset: (p: Omit<Preset, 'id'>) => request<Preset>('POST', `${admin}/presets`, p),
  updatePreset: (p: Preset) => request<Preset>('PUT', `${admin}/presets/${encodeURIComponent(p.id)}`, p),
  deletePreset: (id: string) => request<void>('DELETE', `${admin}/presets/${encodeURIComponent(id)}`),
  reorderPresets: (ids: string[]) => request<void>('PUT', `${admin}/presets/order`, { ids }),

  logs: (limit = 100) => request<LogEntry[]>('GET', `${admin}/logs?limit=${limit}`),
}

/** Calls scoped to one room. */
export function roomApi(id: string) {
  const room = `${admin}/rooms/${encodeURIComponent(id)}`
  const timer = `${room}/timer`
  return {
    get: () => request<RoomSummary>('GET', room),
    rename: (name: string) => request<RoomSummary>('PUT', room, { name }),
    remove: () => request<void>('DELETE', room),

    start: (body: Partial<TimerConfig> & { preset_id?: string; if_seq?: number }) =>
      request<TimerState>('POST', `${timer}/start`, body),
    pause: (if_seq?: number) => request<TimerState>('POST', `${timer}/pause`, { if_seq }),
    resume: (if_seq?: number) => request<TimerState>('POST', `${timer}/resume`, { if_seq }),
    end: (if_seq?: number) => request<TimerState>('POST', `${timer}/end`, { if_seq }),
    extend: (delta_ms: number, mode: ExtendMode, if_seq?: number) =>
      request<TimerState>('POST', `${timer}/extend`, { delta_ms, mode, if_seq }),
    reduce: (delta_ms: number, mode: ExtendMode, if_seq?: number) =>
      request<TimerState>('POST', `${timer}/reduce`, { delta_ms, mode, if_seq }),
    setReminders: (reminders: Reminder[], if_reminders_seq?: number) =>
      request<TimerState>('PUT', `${timer}/reminders`, { reminders, if_reminders_seq }),
  }
}

export type RoomApi = ReturnType<typeof roomApi>
