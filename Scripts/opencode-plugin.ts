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

// No import. The type would come from @opencode-ai/plugin, and requiring a
// package to be installed before a monitor can watch you is a poor trade — this
// file has to work in a config folder that has never seen npm.

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
  // Asking a question is the other way an agent stops and waits for you, and it
  // is the one people actually mind missing — "which database?" rather than
  // "may I run this". Present in the SDK; not yet seen fired, because a model
  // that asks in prose instead never reaches it.
  "question.asked",
  "question.replied",
  "question.rejected",
  // session.created and session.idle only bracket a turn — nothing in between
  // ever said "working", so a row parked on its opening "idle" for the whole
  // reply and never moved. session.status carries {"type":"busy"|"idle"} and
  // fires the moment generation actually starts; only the busy half is
  // forwarded below, since the idle half is a between-tool-calls blip, not
  // a real state change, and session.idle already reports true completion.
  "session.status",
])

export const GroundControl = async ({ $, directory, worktree }: any) => {
  // Only session.created carries the directory. Every later event for that
  // session gives just an id, and a row with no working directory is named
  // after nothing — one turned up in the panel called "/". So it is remembered
  // here, per session, and sent with everything.
  const folders = new Map<string, string>()
  const fallback = worktree || directory || process.cwd()
  const send = async (payload: Record<string, unknown>) => {
    // Fire and forget, and never let a monitor break the agent it watches: a
    // hook that throws would surface as an error in somebody's coding session.
    try {
      // Straight to the emitter's stdin — no shell in the path, so nothing in
      // the payload can be read as a command however it is shaped.
      const proc = Bun.spawn([EMITTER], { stdin: "pipe", stdout: "ignore", stderr: "ignore" })
      proc.stdin.write(JSON.stringify(payload))
      proc.stdin.end()
      await proc.exited
    } catch {
      /* the panel simply misses a row */
    }
  }

  return {
    event: async ({ event }: any) => {
      if (!FORWARD.has(event.type)) return
      const properties = event.properties ?? {}
      const sessionID: string | undefined = properties.sessionID
      if (!sessionID) return
      // Nested one level deeper than it looks: properties.status.type, not
      // properties.type. Confirmed against @opencode-ai/sdk's own
      // EventSessionStatus type — the first version of this check read
      // properties.type, which is always undefined, so every session.status
      // event was silently dropped and "working" never fired outside a
      // permission reply.
      if (event.type === "session.status" && properties.status?.type !== "busy") return

      // opencode splits "waiting for you" into asked and replied, which is
      // exactly our alarm going up and coming down.
      const asking = event.type === "permission.asked" || event.type === "question.asked"
      const metadata = properties.metadata ?? {}

      const folder = properties.info?.directory
      if (folder) folders.set(sessionID, folder)

      await send({
        source: "opencode",
        hook_event_name: event.type,
        session_id: sessionID,
        cwd: folders.get(sessionID) || fallback,
        // The command it wants to run is the truest thing a red row can say,
        // and it is right there in the payload.
        message: asking
          ? metadata.description
            || metadata.command
            || properties.question
            || properties.permission
          : properties.info?.title,
        needs_action: asking,
      })
    },
  }
}
