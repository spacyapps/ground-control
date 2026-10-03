// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak
//
// Ground Control's context meter, the Claude Code half (docs/CONTEXT-METER.md).
//
// No hook payload carries how full the context window is; a mod can ask for
// the finished percentage. After each turn it sends Ground Control a synthetic
// ContextUsage event through cc-notify, the one door the app reads.
//
// - Main loop only: a subagent shares its parent's window.
// - Silent on every failure: a meter must never get in the way of a turn.
import type { Register } from 'claude-code'

export const register: Register = on => {
  on('turn.complete', async ($, e, next) => {
    try {
      if (!e.agentId) {
        const { context } = await $.session.usage()
        const home = await $.env.get('HOME')
        if (context.percent !== undefined && home) {
          await $.process.run([`${home}/.groundcontrol/bin/cc-notify`], {
            stdin: JSON.stringify({
              hook_event_name: 'ContextUsage',
              session_id: await $.session.id(),
              context_percent: context.percent,
            }),
            timeoutMs: 5000,
          })
        }
      }
    } catch {
      // ignored on purpose
    }

    return next(e)
  })
}
