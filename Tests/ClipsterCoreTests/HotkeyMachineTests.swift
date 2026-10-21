import Testing
@testable import ClipsterCore

private typealias M = HotkeyMachine

private func down(_ code: Int, _ mods: M.Modifiers = .command, repeat r: Bool = false, chars: String = "") -> M.Event {
    .keyDown(code: code, mods: mods, isRepeat: r, chars: chars)
}
private func up(_ code: Int, _ mods: M.Modifiers = .command) -> M.Event { .keyUp(code: code, mods: mods) }
private let cmdUp = M.Event.flagsChanged([])
private let digit1 = 18, digit3 = 20

@Suite struct TapBehavesLikeSystem {
    @Test func tapCopyPassesThroughUntouched() {
        var m = M()
        #expect(m.handle(down(KeyCode.c)) == .init(swallow: false, [.startHoldTimer]))
        #expect(m.handle(up(KeyCode.c)) == .init(swallow: false, [.cancelHoldTimer]))
        #expect(m.phase == .idle)
    }

    @Test func tapPasteIsHeldBackThenReplayed() {
        var m = M()
        #expect(m.handle(down(KeyCode.v)) == .init(swallow: true, [.startHoldTimer]))
        #expect(m.handle(up(KeyCode.v)) == .init(swallow: true, [.cancelHoldTimer, .sendPaste]))
        #expect(m.phase == .idle)
    }

    @Test func releasingCommandFirstStillPastes() {
        var m = M()
        _ = m.handle(down(KeyCode.v))
        #expect(m.handle(cmdUp).effects == [.cancelHoldTimer, .sendPaste])
    }

    @Test func otherModifierCombosAreIgnored() {
        var m = M()
        #expect(m.handle(down(KeyCode.v, [.command, .shift, .option])) == .init(swallow: false))
        #expect(m.handle(down(KeyCode.c, [.command, .shift])) == .init(swallow: false))
        #expect(m.handle(down(KeyCode.c, [])) == .init(swallow: false))
        #expect(m.phase == .idle)
    }
}

@Suite struct HoldCopy {
    @Test func holdOpensThenDigitSavesAndReleaseCloses() {
        var m = M()
        _ = m.handle(down(KeyCode.c))
        _ = m.handle(down(KeyCode.c, repeat: true))
        #expect(m.handle(.holdTimerFired).effects == [.open(.copy)])
        #expect(m.handle(down(digit3)) == .init(swallow: true, [.saveSelectedToSlot(3)]))
        #expect(m.handle(cmdUp).effects == [.close])
        #expect(m.phase == .idle)
    }

    @Test func releaseWithoutActionGoesSticky() {
        var m = M()
        _ = m.handle(down(KeyCode.c))
        _ = m.handle(.holdTimerFired)
        #expect(m.handle(cmdUp).effects.isEmpty)
        #expect(m.phase == .sticky(.copy))
    }

    @Test func autorepeatWhileHeldIsSwallowed() {
        var m = M()
        _ = m.handle(down(KeyCode.c))
        _ = m.handle(.holdTimerFired)
        #expect(m.handle(down(KeyCode.c, repeat: true)).swallow)
    }
}

@Suite struct HoldPaste {
    @Test func digitPastesSlotImmediately() {
        var m = M()
        _ = m.handle(down(KeyCode.v))
        _ = m.handle(.holdTimerFired)
        #expect(m.handle(down(digit1)) == .init(swallow: true, [.close, .pasteSlot(1)]))
        #expect(m.phase == .idle)
    }

    @Test func tappingVCyclesAndReleasePastesSelection() {
        var m = M()
        _ = m.handle(down(KeyCode.v))
        _ = m.handle(.holdTimerFired)
        #expect(m.handle(up(KeyCode.v)).swallow)
        #expect(m.handle(down(KeyCode.v)) == .init(swallow: true, [.moveSelection(1)]))
        #expect(m.handle(cmdUp).effects == [.close, .pasteSelected])
    }

    @Test func otherShortcutClosesAndPassesThrough() {
        var m = M()
        _ = m.handle(down(KeyCode.v))
        _ = m.handle(.holdTimerFired)
        let out = m.handle(down(6 /* Z */))
        #expect(out == .init(swallow: false, [.close]))
        #expect(m.phase == .idle)
    }
}

@Suite struct Sticky {
    private func stickyMachine(_ trigger: Int = KeyCode.v) -> M {
        var m = M()
        _ = m.handle(down(trigger))
        _ = m.handle(.holdTimerFired)
        _ = m.handle(cmdUp)
        return m
    }

    @Test func typingSearchesAndReturnPastes() {
        var m = stickyMachine()
        #expect(m.handle(down(0, [], chars: "a")) == .init(swallow: true, [.appendQuery("a")]))
        #expect(m.handle(down(KeyCode.delete, [])) == .init(swallow: true, [.deleteQueryChar]))
        #expect(m.handle(down(KeyCode.down, [])) == .init(swallow: true, [.moveSelection(1)]))
        #expect(m.handle(down(KeyCode.return, [])) == .init(swallow: true, [.close, .pasteSelected]))
        #expect(m.phase == .idle)
    }

    @Test func tabTogglesModeChangingWhatDigitsDo() {
        var m = stickyMachine()
        _ = m.handle(down(KeyCode.tab, []))
        #expect(m.phase == .sticky(.copy))
        #expect(m.handle(down(digit1)) == .init(swallow: true, [.saveSelectedToSlot(1)]))
        #expect(m.phase == .sticky(.copy))
    }

    @Test func copyShortcutClosesPanelAndCanArmANewHold() {
        var m = stickyMachine()
        #expect(m.handle(down(KeyCode.c)) == .init(swallow: false, [.close, .startHoldTimer]))
        #expect(m.phase == .pending(.copy))
    }

    @Test func escapeCloses() {
        var m = stickyMachine()
        #expect(m.handle(down(KeyCode.escape, [])) == .init(swallow: true, [.close]))
    }
}
