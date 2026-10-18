// Reminder rows as edited in forms, shared by the new-countdown editor and
// the live reminder editor.
import { t } from './i18n'
import { formatDuration, parseDuration } from './time'
import type { Reminder } from './types'

export const SHOW_OPTIONS = [5, 8, 15, 30, 60]

export interface ReminderRow {
  id?: string
  at: string
  text: string
  show: string // seconds, or 'sticky'
}

export function toRows(reminders: Reminder[]): ReminderRow[] {
  return [...reminders]
    .sort((a, b) => b.at_ms - a.at_ms)
    .map((r) => ({
      id: r.id,
      at: formatDuration(r.at_ms),
      text: r.text,
      show: r.sticky ? 'sticky' : String(Math.round(r.duration_ms / 1000)),
    }))
}

export function emptyRow(): ReminderRow {
  return { at: '', text: '', show: '8' }
}

/**
 * Validates rows against a run of totalMs (null when the total itself is
 * invalid) and returns the reminders; problems go into errors as at<i> and
 * text<i>.
 */
export function buildReminders(rows: ReminderRow[], totalMs: number | null, errors: Record<string, string>): Reminder[] {
  const seen = new Set<number>()
  return rows.map((row, i) => {
    const at = parseDuration(row.at)
    if (at === null) errors[`at${i}`] = t.value.errDuration
    else if (totalMs !== null && at >= totalMs) errors[`at${i}`] = t.value.errReminderAt
    else if (seen.has(at)) errors[`at${i}`] = t.value.errReminderDup
    if (!row.text.trim()) errors[`text${i}`] = t.value.errReminderText
    if (at !== null) seen.add(at)
    return {
      id: row.id,
      at_ms: at ?? 0,
      text: row.text.trim(),
      sticky: row.show === 'sticky',
      duration_ms: row.show === 'sticky' ? 0 : Number(row.show) * 1000,
    }
  })
}
