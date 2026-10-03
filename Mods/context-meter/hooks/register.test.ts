// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak
import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

const turn = { answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as const

// The plugin under test loads itself; these sit beneath it. Answers the calls the mod makes, and records what it ran.
function engine(on: On, percent: number | undefined) {
  const ran: { argv: readonly string[]; stdin?: string }[] = []
  on('session.usage', async () => ({ value: { startedAt: 0, context: { window: 200000, percent }, rateLimits: [] } }) as never)
  on('session.id', async () => ({ value: 'abc123' }) as never)
  on('env.get', async () => ({ value: '/Users/test' }) as never)
  on('process.run', async (_$, e) => {
    ran.push({ argv: e.argv, stdin: e.init?.stdin })

    return { value: { code: 0, stdout: '', stderr: '' } } as never
  })
  on('turn.complete', async () => ({ text: '' }))

  return ran
}

test('sends the percent to cc-notify after a turn', async ($, on) => {
  const ran = engine(on, 42)
  await $.turn.complete(turn as never)
  expect(ran).toHaveLength(1)
  expect(ran[0].argv).toEqual(['/Users/test/.groundcontrol/bin/cc-notify'])
  expect(JSON.parse(ran[0].stdin ?? '{}')).toEqual({
    hook_event_name: 'ContextUsage',
    session_id: 'abc123',
    context_percent: 42,
  })
})

test('sends nothing when there is no reading yet', async ($, on) => {
  const ran = engine(on, undefined)
  await $.turn.complete(turn as never)
  expect(ran).toHaveLength(0)
})

test('ignores a subagent turn', async ($, on) => {
  const ran = engine(on, 42)
  await $.turn.complete({ ...turn, agentId: 'sub1' } as never)
  expect(ran).toHaveLength(0)
})
