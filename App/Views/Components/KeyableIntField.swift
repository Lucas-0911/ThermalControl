import SwiftUI
import AppKit

struct SoftNumberField: View {
    @Binding var value: Int
    var width: CGFloat = 72
    var enabled = true
    var onCommit: () -> Void = {}
    var onLive: () -> Void = {}

    var body: some View {
        KeyableIntField(value: $value, enabled: enabled, onCommit: onCommit, onLive: onLive)
            .frame(width: width, height: 26)
            .background(
                TCTheme.fieldFill,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
    }
}

/// NSTextField so the menu-bar extra can actually receive keypresses
/// (plain SwiftUI TextField is unreliable inside MenuBarExtra windows).
struct KeyableIntField: NSViewRepresentable {
    @Binding var value: Int
    var enabled: Bool
    var onCommit: () -> Void
    var onLive: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: "\(value)")
        tf.delegate = context.coordinator
        tf.alignment = .center
        tf.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.formatter = nil
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
        tf.isEnabled = enabled
        if tf.currentEditor() == nil, tf.stringValue != "\(value)" {
            tf.stringValue = "\(value)"
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: KeyableIntField
        init(_ parent: KeyableIntField) { self.parent = parent }

        func controlTextDidBeginEditing(_ obj: Notification) {
            NSApp.activate(ignoringOtherApps: true)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            apply(tf.stringValue, live: true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            apply(tf.stringValue, live: false)
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                apply(textView.string, live: false)
                parent.onCommit()
                return true
            }
            return false
        }

        private func apply(_ raw: String, live: Bool) {
            let digits = raw.filter(\.isNumber)
            guard let n = Int(digits) else { return }
            if parent.value != n { parent.value = n }
            if live { parent.onLive() }
        }
    }
}