// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak
//
// Ground Control's opencode integration.
//
// opencode has no hook commands — nothing in its configuration runs a script on
// an event, the way Claude Code's and Cursor's settings do. What it has is
// plugins: TypeScript that loads into the agent and receives a shell. So this is
// the shape the integration has to take, and it does the same job the hook
// registrations do elsewhere: hand one line per event to cc-notify.
//
// Every event name and field below was measured against opencode 1.17.8 on
// 2026-08-19 by logging a real session, not read from documentation. The record
// is in docs/HOOK-PAYLOADS.md.

import type { Plugin } from "@opencode-ai/plugin"

const EMITTER = `${process.env.HOME}/.groundcontrol/bin/cc-notify`

/** The events worth forwarding. opencode emits a great many more — dozens of
 *  `catalog.updated` and `plugin.added` at startup alone — and a row only ever
 *  needs to know that a session began, that it is busy, that something is
 *  waiting on a human, and that it went quiet. */
const FORWARD = new Set([
  "session.created",
  "session.idle",
  "permission.asked",
  "permission.replied",
])

export const GroundControl: Plugin = async ({ $, directory, worktree }) => {
  const send = async (payload: Record<string, unknown>) => {
    // Fire and forget, and never let a monitor break the agent it watches: a
    // hook that throws would surface as an error in somebody's coding session.
    try {
      // Piped rather than written to stdin: the shell's `stdin` is a readonly
      // stream with no way to hand it a string, and interpolation escapes the
      // JSON into a single argument safely.
      await $`echo ${JSON.stringify(payload)} | ${EMITTER}`.quiet().nothrow()
    } catch {
      /* the panel simply misses a row */
    }
  }

  return {
    event: async ({ event }) => {
      if (!FORWARD.has(event.type)) return
      const properties = (event.properties ?? {}) as Record<string, any>
      const sessionID: string | undefined = properties.sessionID
      if (!sessionID) return

      // opencode splits "waiting for you" into asked and replied, which is
      // exactly our alarm going up and coming down.
      const asking = event.type === "permission.asked"
      const metadata = properties.metadata ?? {}

      await send({
        source: "opencode",
        hook_event_name: event.type,
        session_id: sessionID,
        cwd: properties.info?.directory ?? worktree ?? directory,
        // The command it wants to run is the truest thing a red row can say,
        // and it is right there in the payload.
        message: asking
          ? metadata.description || metadata.command || properties.permission
          : properties.info?.title,
        needs_action: asking,
      })
    },
  }
}
