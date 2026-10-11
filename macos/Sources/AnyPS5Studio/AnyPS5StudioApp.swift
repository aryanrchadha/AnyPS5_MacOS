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
                Button("Convert All Queued") { model.convertAll() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!model.canConvert || model.queue.isEmpty)
                Button("Stop") { model.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.runner.state.isRunning)
                Button(model.lastPlayedEntry.map { "Launch \($0.title)" } ?? "Launch Last Played") { model.launchLastPlayed() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(!model.canLaunchLastPlayed)
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

        MenuBarExtra("AnyPS5 Studio", systemImage: "gamecontroller") {
            MenuBarContent()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text) else { return }
        OpenRequests.submit([url])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil {
            MainActor.assumeIsolated { NSApp.applicationIconImage = AppIconRenderer.image(scale: 0.5) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        OpenRequests.submit(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum OpenRequests {
    static let didReceive = Notification.Name("AnyPS5StudioOpenRequests")
    private static var pending: [URL] = []

    static func submit(_ urls: [URL]) {
        pending.append(contentsOf: urls)
        NotificationCenter.default.post(name: didReceive, object: nil)
    }

    static func drain() -> [URL] {
        defer { pending.removeAll() }
        return pending
    }
}
