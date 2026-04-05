// SurfaceKeyInterceptor.swift
// CTerm
//
// Pure, testable rules for deciding whether a raw NSEvent keystroke
// should be intercepted by CTerm before ghostty sees it. Keep logic
// here minimal and side-effect free — the SurfaceView calls in and
// acts on the Bool.

import AppKit

@MainActor
enum SurfaceKeyInterceptor {

    /// Returns `true` if the event is a plain `#` keystroke that should open
    /// the compose overlay in NL (agent) mode. Matches Warp's `#` prefix UX.
    ///
    /// We bail out when an IME has marked text, when any non-shift modifier
    /// is held, or when the produced character isn't `#`. Shift is allowed
    /// because on US keyboards `#` is Shift-3.
    static func shouldInterceptHash(event: NSEvent, hasMarkedText: Bool) -> Bool {
        guard !hasMarkedText else { return false }
        let disqualifying: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(disqualifying).isEmpty else { return false }
        guard let characters = event.characters, !characters.isEmpty else { return false }
        return characters == "#"
    }
}
