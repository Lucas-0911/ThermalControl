import AppKit
import SwiftUI
import XCTest
@testable import ThermalControl

@MainActor
final class ButtonHitAreaTests: XCTestCase {
    func testNumberButtonsAcceptClicksOutsideTheirSymbols() throws {
        var value = 50
        var commits = 0
        let view = ConfigNumberRow(
            title: "Value", value: Binding(get: { value }, set: { value = $0 }),
            step: 1, minVal: 0, maxVal: 100, onLive: { commits += 1 }
        )
        let host = NSHostingView(rootView: view.frame(width: 320, height: 40))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 40),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Click empty corners inside the 30 × 28 labels, not the glyphs.
        try click(NSPoint(x: 184, y: 8), in: window)
        XCTAssertEqual(value, 49)
        XCTAssertEqual(commits, 1)
        try click(NSPoint(x: 280, y: 8), in: window)
        XCTAssertEqual(value, 50)
        XCTAssertEqual(commits, 2)

        try click(NSPoint(x: 280, y: 2), in: window)
        XCTAssertEqual(commits, 2, "Click outside the button must not commit")

        host.rootView = ConfigNumberRow(
            title: "Value", value: Binding(get: { value }, set: { value = $0 }),
            step: 1, minVal: 0, maxVal: 100, enabled: false,
            onLive: { commits += 1 }
        ).frame(width: 320, height: 40)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        try click(NSPoint(x: 184, y: 8), in: window)
        try click(NSPoint(x: 280, y: 8), in: window)
        XCTAssertEqual(value, 50)
        XCTAssertEqual(commits, 2, "Disabled buttons must not commit")
    }

    func testNumberFieldRejectsMalformedInputAndNeverCommitsOnBlurOrReturn() {
        var value = 50
        var writes = 0
        var field = KeyableIntField(
            value: Binding(get: { value }, set: { value = $0 }), enabled: true,
            onCommit: { writes += 1 }, onLive: {}, label: "Charge limit"
        )
        let delegate = field.makeCoordinator()
        let native = NSTextField(string: "50")
        native.stringValue = "-20"
        delegate.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: native))
        XCTAssertEqual(value, 50)
        native.stringValue = "8.5"
        delegate.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: native))
        XCTAssertEqual(value, 50)
        native.stringValue = "85"
        delegate.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: native))
        XCTAssertEqual(value, 85)
        delegate.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: native))
        let editor = NSTextView()
        editor.string = "90"
        XCTAssertTrue(delegate.control(native, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(value, 90)
        XCTAssertEqual(writes, 0, "Blur and Return only finish drafts; Apply owns hardware writes")
        field.enabled = false
        delegate.parent = field
        native.stringValue = "95"
        delegate.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: native))
        XCTAssertEqual(value, 90)
    }

    func testModeAndChoiceHitPaddingAndRespectDisabledState() throws {
        var modeClicks = 0
        var choiceClicks = 0
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            ModeTile(title: "Auto", symbol: "sparkles", compact: true) { modeClicks += 1 }
            ChoicePill(title: "Limit", symbol: "shield", tint: .blue) { choiceClicks += 1 }
        }.frame(width: 300, height: 48))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 48),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        try click(NSPoint(x: 8, y: 24), in: window)
        try click(NSPoint(x: 292, y: 24), in: window)
        XCTAssertEqual(modeClicks, 1)
        XCTAssertEqual(choiceClicks, 1)
        host.rootView = HStack(spacing: 0) {
            ModeTile(title: "Auto", symbol: "sparkles", enabled: false, compact: true) { modeClicks += 1 }
            ChoicePill(title: "Limit", symbol: "shield", tint: .blue, enabled: false) { choiceClicks += 1 }
        }.frame(width: 300, height: 48)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        try click(NSPoint(x: 8, y: 24), in: window)
        try click(NSPoint(x: 292, y: 24), in: window)
        XCTAssertEqual(modeClicks, 1)
        XCTAssertEqual(choiceClicks, 1)
    }

    private func click(_ point: NSPoint, in window: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            NSApp.postEvent(event, atStart: false)
        }
        let deadline = Date().addingTimeInterval(0.2)
        while let event = NSApp.nextEvent(
            matching: [.leftMouseDown, .leftMouseUp], until: deadline,
            inMode: .default, dequeue: true
        ) {
            NSApp.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
