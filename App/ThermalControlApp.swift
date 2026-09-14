import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyRoundedAppIcon()
    }

    /// Load the pre-rounded icns. Do this after NSApplication exists — `NSApp` is
    /// an IUO and is nil during `App.init()`, which crashes with
    /// "Unexpectedly found nil while implicitly unwrapping an Optional value".
    /// Prefer the icns over `NSImage(named: "AppIcon")` so Cmd+Tab keeps the
    /// baked corner radius instead of the square asset-catalog tile.
    private func applyRoundedAppIcon() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let img = NSImage(contentsOf: url) else { return }
        img.isTemplate = false
        NSApplication.shared.applicationIconImage = img
    }
}

@main
struct ThermalControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = ThermalViewModel()
    @ObservedObject private var lang = LanguageSettings.shared

    init() {
        if CommandLine.arguments.contains("--smoke-test") {
            SmokeTest.runAndExit()
        }
    }

    var body: some Scene {
        Window("Thermal Control", id: "main") {
            DashboardView()
                .environmentObject(vm)
                .environmentObject(lang)
                .environment(\.locale, lang.locale)
                .id(lang.selection)
        }
        .defaultSize(width: 860, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(vm)
                .environmentObject(lang)
                .environment(\.locale, lang.locale)
                .id(lang.selection)
        } label: {
            Label(vm.menuTitle, systemImage: vm.menuSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
