// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The window's actual content view: `chrome`, plus the two controls and the
/// hint that describes them, sitting *outside* chrome's own layer tree.
///
/// A shaped theme masks `PanelBackgroundView`'s layer to an irregular
/// silhouette, and a `CALayer` mask clips its whole rendered output — its own
/// drawing and every subview's, together. `resizeGrip`/`closeMark` used to be
/// chrome's own subviews, so they rode under that mask too; it only ever went
/// unnoticed because their fixed position, tucked into the title strip, has so
/// far always landed inside the visible interior of every shipped theme. A
/// silhouette that tapers away before reaching that spot would have made them
/// invisible and unclickable with nothing to say why.
///
/// Promoting them here removes that dependency entirely: they are always
/// clickable at their fixed position, on any silhouette, because nothing above
/// them can mask them away. Corner decorations (planned) need the same
/// guarantee for the opposite reason — reaching *into* a silhouette's dead
/// corners on purpose — so this is also the layer they will join.
final class PanelRootView: NSView {
    let chrome = PanelBackgroundView()
    let cornerDecorations = CornerDecorationsView()
    let resizeGrip = ResizeGripView()
    let closeMark = CloseMarkView()
    let hint = HintView()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)

        addSubview(chrome)
        // Unmasked, and in this order: chrome, then corner decorations, then
        // the controls, then the hint that labels them — the same "marks,
        // then frame, then panel" rule chrome's own doc comments already
        // state, just enforced by being outside chrome's mask instead of
        // inside its subview order.
        addSubview(cornerDecorations)
        addSubview(resizeGrip)
        addSubview(closeMark)
        addSubview(hint)

        chrome.list.onHint = { [weak self] text, rect in
            guard let self else { return }
            self.hint.show(text, near: self.chrome.list.convert(rect, to: self), in: self)
        }
        let showHint: (String?, NSRect) -> Void = { [weak self] text, rect in
            guard let self else { return }
            self.hint.show(text, near: rect, in: self)
        }
        closeMark.onHint = showHint
        resizeGrip.onHint = showHint
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PanelRootView is created in code only")
    }

    func apply(theme: Theme) {
        chrome.apply(theme: theme)
        cornerDecorations.apply(theme: theme)
        resizeGrip.apply(theme: theme)
        closeMark.apply(theme: theme)
        hint.apply(theme: theme)
        needsLayout = true
    }

    /// Sessions reach both surfaces that care whether anything is working:
    /// chrome (rows, and the frame's own animation) and corner decorations,
    /// independently deriving the same signal from the same list rather than
    /// one reading it off the other.
    func update(sessions: [Session], renames: [String: String]) {
        chrome.update(sessions: sessions, renames: renames)
        cornerDecorations.update(isWorking: sessions.contains { $0.state == .working })
    }

    override func layout() {
        super.layout()
        chrome.frame = bounds
        cornerDecorations.frame = bounds
        // Forces chrome's own layout now rather than on the next cycle, so
        // `closeMarkFrame`/`resizeGripFrame` — derived from where chrome just
        // placed its title bar — read fresh values below, not last frame's.
        chrome.layoutSubtreeIfNeeded()

        closeMark.frame = chrome.closeMarkFrame
        resizeGrip.frame = chrome.resizeGripFrame
    }
}
