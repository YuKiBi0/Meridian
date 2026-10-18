// Time formatting and parsing shared by every view (DESIGN §5.4).

const pad = (n: number) => String(n).padStart(2, '0')

/** Formats milliseconds as H:MM:SS or MM:SS, rounding seconds up. */
export function formatRemaining(ms: number): string {
  const total = Math.max(0, Math.ceil(ms / 1000))
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
}

/** Formats overtime as +MM:SS, rounding seconds down. */
export function formatOvertime(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000))
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  return '+' + (h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`)
}

/** Formats a duration for inputs and lists: 15:00, 1:30:00, 0:30. */
export function formatDuration(ms: number): string {
  const total = Math.round(ms / 1000)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}

/**
 * Parses operator input: "15" is 15 minutes, "1:30" is 1 min 30 s,
 * "1:30:00" is 1 h 30 min. Returns null when the input is not a duration.
 */
export function parseDuration(input: string): number | null {
  const text = input.trim().replace(/：/g, ':')
  if (!/^\d+(\.\d+)?$|^\d+(:\d{1,2}){1,2}$/.test(text)) return null
  const parts = text.split(':')
  if (parts.length === 1) return Math.round(parseFloat(parts[0]) * 60_000)
  const nums = parts.map(Number)
  if (nums.slice(1).some((n) => n >= 60)) return null
  if (nums.length === 2) return (nums[0] * 60 + nums[1]) * 1000
  return (nums[0] * 3600 + nums[1] * 60 + nums[2]) * 1000
}

/** Remaining time below which the countdown turns vermilion (DESIGN §5.2). */
export function alertThreshold(totalMs: number): number {
  return Math.min(60_000, totalMs * 0.2)
}
