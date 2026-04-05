import AppKit
import Foundation
import Testing
@testable import CTerm

@MainActor
@Suite("SurfaceKeyInterceptor")
struct SurfaceKeyInterceptorTests {

    private func makeKeyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        // keyCode 20 is "3" on US ANSI; Shift-3 produces "#". For non-# cases
        // we still use a stable keyCode since the interceptor only looks at
        // `characters` and `modifierFlags`.
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 20
        ) else {
            fatalError("Failed to synthesize NSEvent for test")
        }
        return event
    }

    @Test("Plain # with no modifiers is intercepted")
    func plainHashIntercepted() {
        let event = makeKeyEvent(characters: "#")
        #expect(SurfaceKeyInterceptor.shouldInterceptHash(event: event, hasMarkedText: false))
    }

    @Test("Shift-# (the normal way to type # on US keyboards) is intercepted")
    func shiftHashIntercepted() {
        let event = makeKeyEvent(characters: "#", modifiers: [.shift])
        #expect(SurfaceKeyInterceptor.shouldInterceptHash(event: event, hasMarkedText: false))
    }

    @Test("# with Command modifier is NOT intercepted")
    func cmdHashNotIntercepted() {
        let event = makeKeyEvent(characters: "#", modifiers: [.command])
        #expect(!SurfaceKeyInterceptor.shouldInterceptHash(event: event, hasMarkedText: false))
    }

    @Test("# with Control modifier is NOT intercepted")
    func ctrlHashNotIntercepted() {
        let event = makeKeyEvent(characters: "#", modifiers: [.control])
        #expect(!SurfaceKeyInterceptor.shouldInterceptHash(event: event, hasMarkedText: false))
    }

    @Test("# with Option modifier is NOT intercepted")
    func optHashNotIntercepted() {
        let event = makeKeyEvent(characters: "#", modifiers: [.option])
        #expect(!SurfaceKeyInterceptor.shouldInterceptHash(event: event, hasMarkedText: false))
    }

    @Test("# while IME has marked text is NOT intercepted")
    func markedTextBlocksIntercept() {
        let event = makeKeyEvent(characters: "#")
        #expect(!SurfaceKeyInterceptor.shouldInterceptHash(event: event, hasMarkedText: true))
    }

    @Test("Non-# characters are NOT intercepted")
    func otherCharsNotIntercepted() {
        for ch in ["a", "1", "3", "!", "/", " "] {
            let event = makeKeyEvent(characters: ch)
            #expect(
                !SurfaceKeyInterceptor.shouldInterceptHash(event: event, hasMarkedText: false),
                "char '\(ch)' should not be intercepted"
            )
        }
    }

    @Test("Empty event.characters is NOT intercepted")
    func emptyCharsNotIntercepted() {
        let event = makeKeyEvent(characters: "")
        #expect(!SurfaceKeyInterceptor.shouldInterceptHash(event: event, hasMarkedText: false))
    }
}
