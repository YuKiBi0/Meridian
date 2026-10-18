import { describe, expect, it } from 'vitest'
import { alertThreshold, formatDuration, formatOvertime, formatRemaining, parseDuration } from './time'

describe('formatRemaining', () => {
  it('rounds up and switches to hours', () => {
    expect(formatRemaining(0)).toBe('00:00')
    expect(formatRemaining(400)).toBe('00:01')
    expect(formatRemaining(299_001)).toBe('05:00')
    expect(formatRemaining(3_909_000)).toBe('1:05:09')
  })
  it('formats overtime', () => {
    expect(formatOvertime(83_900)).toBe('+01:23')
  })
})

describe('parseDuration', () => {
  it('reads minutes, m:ss and h:mm:ss', () => {
    expect(parseDuration('15')).toBe(900_000)
    expect(parseDuration('1:30')).toBe(90_000)
    expect(parseDuration('1:30:00')).toBe(5_400_000)
    expect(parseDuration('1：30')).toBe(90_000)
    expect(parseDuration('0.5')).toBe(30_000)
  })
  it('rejects garbage', () => {
    expect(parseDuration('')).toBeNull()
    expect(parseDuration('abc')).toBeNull()
    expect(parseDuration('1:75')).toBeNull()
  })
  it('round-trips formatDuration', () => {
    expect(parseDuration(formatDuration(5_400_000))).toBe(5_400_000)
    expect(parseDuration(formatDuration(30_000))).toBe(30_000)
  })
})

describe('alertThreshold', () => {
  it('is 60s for long runs and 20% for short ones', () => {
    expect(alertThreshold(900_000)).toBe(60_000)
    expect(alertThreshold(60_000)).toBe(12_000)
  })
})
