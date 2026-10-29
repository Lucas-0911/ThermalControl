import AppKit
import SwiftUI
import ServiceManagement

enum AppScene {
    static let dashboard = "main"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var viewModel: ThermalViewModel?
    private var terminationApproved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--migrate-legacy-helper") || arguments.contains("--restore-legacy-control") || arguments.contains("--register-helper") || arguments.contains("--unregister-helper") || arguments.contains("--helper-status") || arguments.contains("--set-charge-limit") || arguments.contains("--test-fan-ramp") {
            Task { @MainActor in
                exit(await HelperMaintenance.run(arguments: arguments))
            }
            return
        }
        if arguments.contains("--restore-system-control") || arguments.contains("--release-transient-control") {
            Task { @MainActor in
                let client = XPCClient()
                client.connect()
                // Protocol 4 has the same restore call. The installer must release that helper before replacing it.
                guard let cap = await client.capabilities(),
                      cap.protocolVersion == TC.protocolVersion || cap.protocolVersion == 4 else {
                    client.invalidate()
                    exit(2)
                }
                let components = arguments.contains("--release-transient-control") ? RestoreResult.transient : RestoreResult.all
                let result = await client.restore(components: components)
                client.invalidate()
                if let message = result.message { fputs("\(message)\n", stderr) }
                exit(result.succeeded ? 0 : 1)
            }
            return
        }
        applyRoundedAppIcon()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationApproved, let viewModel = Self.viewModel else { return .terminateNow }
        Task { @MainActor in
            let ready = await viewModel.prepareToQuit()
            terminationApproved = ready
            sender.reply(toApplicationShouldTerminate: ready)
        }
        return .terminateLater
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

    var body: some Scene {
        Window("Thermal Control", id: AppScene.dashboard) {
            DashboardView()
                .onAppear { AppDelegate.viewModel = vm }
                .environmentObject(vm)
                .environmentObject(vm.fan)
                .environmentObject(vm.battery)
                .environmentObject(vm.power)
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
                .onAppear { AppDelegate.viewModel = vm }
                .environmentObject(vm)
                .environmentObject(vm.fan)
                .environmentObject(vm.battery)
                .environmentObject(vm.power)
                .environmentObject(lang)
                .environment(\.locale, lang.locale)
                .id(lang.selection)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vm.menuSymbol)
                Text(vm.menuTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
