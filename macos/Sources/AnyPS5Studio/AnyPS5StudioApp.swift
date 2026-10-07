import AppKit
import SwiftUI

@main
struct AnyPS5StudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        MainActor.assumeIsolated { AppIconRenderer.renderIfRequested() }
    }

    var body: some Scene {
        Window("AnyPS5 Studio", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1120, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Game…") { model.chooseExecutable() }
                    .keyboardShortcut("o")
                Button("Choose Output Folder…") { model.chooseOutputDirectory() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Conversion") {
                Button("Convert") { model.convert() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canConvert)
                Button("Stop") { model.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.runner.state.isRunning)
                Divider()
                ForEach(Route.allCases) { route in
                    Button(route.title) { model.route = route }
                        .keyboardShortcut(KeyEquivalent(Character("\(Route.allCases.firstIndex(of: route)! + 1)")))
                }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` starts the binary outside a bundle; make it a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil {
            NSApp.applicationIconImage = MainActor.assumeIsolated { AppIconRenderer.image(scale: 0.5) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
