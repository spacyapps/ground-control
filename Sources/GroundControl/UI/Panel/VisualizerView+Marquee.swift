// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The word the grid spells while nothing is running.
///
/// Split from the analyser proper because it is a different job — a scroll
/// position, a one-shot timer, a glyph font — that happens to borrow the same
/// LED cells. The bars keep running underneath a sweeping word so it reads as
/// the display forming letters, not as text pasted over a meter.
///
/// The members it shares with `VisualizerView` (`messageText`, `messageScroll`,
/// `start()`, `isAlarmed`, …) are `internal` rather than `private` only for
/// this split.
extension VisualizerView {
    var isShowingMessage: Bool { messageScroll != nil }

    var columnCount: CGFloat { CGFloat(max(1, levels.count)) }

    /// A one-shot rather than a heartbeat: the analyser stops dead at rest, and
    /// this wakes it just long enough to spell the name once.
    func scheduleMessage() {
        // Never restart a countdown that is already running. The bars settle
        // between every burst of activity, and rescheduling on each settle meant
        // the delay never actually elapsed.
        guard messageTimer?.isValid != true else { return }
        messageTimer?.invalidate()
        guard window != nil, !isAlarmed else { return }
        messageTimer = Timer.scheduledTimer(
            withTimeInterval: MatrixMessages.nextDelay(), repeats: false
        ) { [weak self] _ in
            self?.beginMessage()
        }
    }

    func beginMessage() {
        guard window != nil, !isAlarmed else { return }
        messageTurn += 1
        messageText = MatrixMessages.next(
            turn: messageTurn,
            avoiding: messageText,
            harvested: harvested,
            themed: theme.matrix.messages
        )
        messageScroll = columnCount
        start()
    }

    /// Walks the message leftwards across the grid.
    func advanceMessage() {
        guard var scroll = messageScroll else { return }

        // An alarm is the one thing that clears it — nothing should sweep across
        // a panel that needs you.
        if isAlarmed {
            messageScroll = nil
            return
        }

        scroll -= 0.5
        if scroll < -CGFloat(MatrixFont.columns(for: messageText)) {
            messageScroll = nil
            scheduleMessage()
        } else {
            messageScroll = scroll
        }
    }

    /// Extra level for bars just outside the sweeping word, so the letters look
    /// like they are displacing the spectrum rather than sitting on top of it.
    func messageWake(at index: Int) -> CGFloat {
        guard let scroll = messageScroll else { return 0 }
        let distance = abs(CGFloat(index) - scroll)
        let span = CGFloat(MatrixFont.columns(for: messageText))
        guard distance < span + 6 else { return 0 }
        let edge = min(abs(CGFloat(index) - scroll), abs(CGFloat(index) - (scroll + span)))
        return edge < 5 ? (5 - edge) / 5 * 0.35 : 0
    }

    /// Which column of the message, if any, currently sits at this screen
    /// position.
    func messageColumn(at index: Int) -> Int? {
        guard let scroll = messageScroll else { return nil }
        let column = index - Int(scroll.rounded())
        guard column >= 0, column < MatrixFont.columns(for: messageText) else { return nil }
        return column
    }

    /// One column of the sweeping word, drawn in the same cells the bars use.
    func drawLetterColumn(x originX: CGFloat, column: Int, usable: CGFloat, inset: CGFloat) {
        let cell = (usable - CGFloat(Self.rows - 1) * segmentGap) / CGFloat(Self.rows)
        for row in 0..<Self.rows {
            let lit = MatrixFont.isLit(text: messageText, column: column, row: row)
            let y = inset + CGFloat(row) * (cell + segmentGap)
            (lit ? letterColor : theme.matrix.unlit).setFill()
            NSRect(x: originX, y: y, width: barWidth, height: cell).fill()
        }
    }

    /// The word picks its own colour from the palette, so consecutive messages
    /// look different without ever borrowing the alarm red.
    var letterColor: NSColor {
        let blend = theme.matrix.low.blended(withFraction: 0.5, of: theme.matrix.high)
        let palette = [theme.colors.working, theme.colors.accent, blend ?? theme.colors.working]
        let hash = messageText.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}
