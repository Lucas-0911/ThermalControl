import SwiftUI

/// View appearance alone does not track minimized or occluded macOS windows.
struct DashboardVisibility: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) { view.onChange = onChange }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
            guard let window else { onChange?(false); return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.onChange?(note.name != NSWindow.willCloseNotification && self.isWindowVisible)
                    }
                })
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onChange?(self.isWindowVisible)
            }
        }

        private var isWindowVisible: Bool {
            guard let window else { return false }
            return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}
