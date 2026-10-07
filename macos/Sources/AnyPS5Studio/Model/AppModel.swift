import AppKit
import Foundation
import Observation

enum Route: String, CaseIterable, Identifiable {
    case convert, console, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: "Convert"
        case .console: "Console"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .console: "text.alignleft"
        case .system: "cpu"
        }
    }
}

/// Presence of the files the converted title needs at run time (docs/user/USAGE.md, "Runtime layout").
struct RuntimeLayout: Equatable {
    var executableExists: Bool
    var libraryDirectory: URL?
    var libraryCount: Int
    var appDirectoryExists: Bool
    var appEntryCount: Int
    var fontsPresent: Bool

    var isComplete: Bool { executableExists && libraryCount > 0 && appDirectoryExists }
}

@Observable
final class AppModel {
    var route: Route = .convert
    var settings = ConversionSettings()
    private(set) var inspection: GameInspection?
    var outputDirectory: URL? {
        didSet { UserDefaults.standard.set(outputDirectory?.path, forKey: Keys.outputDirectory) }
    }
    var outputName = "app"
    private(set) var relinker: URL?
    private(set) var system: SystemReport
    private(set) var layout: RuntimeLayout?
    var selectedWine: WineRuntime?
    var banner: String?

    let runner = ProcessRunner()

    private enum Keys {
        static let outputDirectory = "outputDirectory"
    }

    init() {
        system = SystemProbe.report()
        relinker = RelinkerLocator.locate()
        selectedWine = system.wineRuntimes.first
        if let saved = UserDefaults.standard.string(forKey: Keys.outputDirectory) {
            outputDirectory = URL(fileURLWithPath: saved, isDirectory: true)
        }
    }

    // MARK: - Derived

    var outputExecutable: URL? {
        guard let directory = outputDirectory, let inspection else { return nil }
        let name = outputName.isEmpty ? inspection.suggestedOutputName : outputName
        return directory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension(settings.target.fileExtension)
    }

    var commandArguments: [String]? {
        guard let inspection, let output = outputExecutable else { return nil }
        return settings.arguments(input: inspection.executable, output: output)
    }

    var commandPreview: String {
        let program = relinker?.path ?? "relinker"
        guard let arguments = commandArguments else { return program + " [options] <input.elf> <output>" }
        return ([program] + arguments).shellCommand
    }

    var blockingIssue: String? {
        if relinker == nil { return "The relinker binary was not found. Set its location in Settings (⌘,)." }
        guard let inspection else { return "Choose a game executable to begin." }
        if let issue = inspection.blockingIssue { return issue }
        if outputDirectory == nil { return "Choose where the converted title should be written." }
        return settings.validationIssue
    }

    var canConvert: Bool { blockingIssue == nil && !runner.state.isRunning }

    // MARK: - Intents

    func refreshEnvironment() {
        system = SystemProbe.report()
        relinker = RelinkerLocator.locate()
        if let current = selectedWine, !system.wineRuntimes.contains(current) { selectedWine = nil }
        if selectedWine == nil { selectedWine = system.wineRuntimes.first }
        refreshLayout()
    }

    func open(_ url: URL) {
        guard let executable = GameInspector.resolveExecutable(from: url) else {
            banner = "No eboot.bin was found in \(url.lastPathComponent). Choose the executable directly."
            return
        }
        let result = GameInspector.inspect(executable)
        inspection = result
        outputName = result.suggestedOutputName
        if outputDirectory == nil {
            outputDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("AnyPS5", isDirectory: true)
        }
        banner = nil
        refreshLayout()
    }

    func reinspect() {
        guard let executable = inspection?.executable else { return }
        inspection = GameInspector.inspect(executable)
    }

    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose a decrypted game executable or its folder"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose an output folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            refreshLayout()
        }
    }

    func convert() {
        guard canConvert, let relinker, let arguments = commandArguments, let output = outputExecutable else { return }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            banner = "Could not create the output folder: \(error.localizedDescription)"
            return
        }
        route = .console
        runner.run(label: "Conversion", executable: relinker, arguments: arguments,
                   workingDirectory: output.deletingLastPathComponent()) { [weak self] code in
            guard let self else { return }
            switch code {
            case 0: self.runner.note("Conversion finished. Check the runtime layout before launching.")
            case 1: self.runner.note("The relinker rejected the arguments (exit code 1).")
            case 2: self.runner.note("Conversion failed (exit code 2). The reason is printed above.")
            default: self.runner.note("The relinker exited with code \(code).")
            }
            self.refreshLayout()
        }
    }

    func cancel() { runner.terminate() }

    func launch() {
        guard let output = outputExecutable, settings.target == .windows, let wine = selectedWine else { return }
        route = .console
        runner.run(label: "Launch via \(wine.name)", executable: wine.executable, arguments: [output.path],
                   workingDirectory: output.deletingLastPathComponent(),
                   environment: ["WINEDEBUG": "-all", "WINEMSYNC": "1", "WINEESYNC": "1"])
    }

    func revealOutput() {
        guard let output = outputExecutable else { return }
        if FileManager.default.fileExists(atPath: output.path) {
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } else {
            NSWorkspace.shared.open(output.deletingLastPathComponent())
        }
    }

    /// Copies `*.prx` system libraries, built on a Linux or Windows host for the chosen
    /// target, into the library search path.
    func importSystemLibraries() {
        guard let output = outputExecutable,
              let destination = settings.libraryDirectory(besides: output) else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the folder with \(settings.target == .windows ? "Windows" : "Linux") system libraries (*.prx)"
        panel.message = "Built with `cmake --build build --target libs` on a \(settings.target == .windows ? "Windows" : "Linux") host: build/core/libs/libs"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let manager = FileManager.default
        do {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            let libraries = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "prx" }
            guard !libraries.isEmpty else {
                banner = "\(source.lastPathComponent) contains no .prx files."
                return
            }
            for library in libraries {
                let target = destination.appendingPathComponent(library.lastPathComponent)
                if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
                try manager.copyItem(at: library, to: target)
            }
            runner.note("Imported \(libraries.count) system libraries into \(destination.path)")
        } catch {
            banner = "Importing libraries failed: \(error.localizedDescription)"
        }
        refreshLayout()
    }

    /// Symlinks the game's files into `app0/` without copying them. Module folders are
    /// skipped: the relinker writes converted modules there, and a symlink would redirect
    /// those writes into the original game folder.
    func linkGameResources() {
        guard let inspection, let output = outputExecutable,
              FileManager.default.fileExists(atPath: output.path) else { return }
        let manager = FileManager.default
        let appDirectory = output.deletingLastPathComponent().appendingPathComponent("app0", isDirectory: true)
        let skipped: Set<String> = ["sce_module", "sce_modules", "prx", inspection.executable.lastPathComponent]
        do {
            try manager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            var linked = 0
            for entry in try manager.contentsOfDirectory(at: inspection.root, includingPropertiesForKeys: nil) {
                if skipped.contains(entry.lastPathComponent) { continue }
                let target = appDirectory.appendingPathComponent(entry.lastPathComponent)
                if manager.fileExists(atPath: target.path) { continue }
                if (try? manager.destinationOfSymbolicLink(atPath: target.path)) != nil { continue }
                try manager.createSymbolicLink(at: target, withDestinationURL: entry)
                linked += 1
            }
            runner.note("Linked \(linked) game entries into \(appDirectory.path)")
        } catch {
            banner = "Linking game files failed: \(error.localizedDescription)"
        }
        refreshLayout()
    }

    func refreshLayout() {
        guard let output = outputExecutable else {
            layout = nil
            return
        }
        let manager = FileManager.default
        let base = output.deletingLastPathComponent()
        let libraryDirectory = settings.libraryDirectory(besides: output)
        let libraryCount = libraryDirectory.flatMap { try? manager.contentsOfDirectory(atPath: $0.path) }?
            .filter { $0.lowercased().hasSuffix(".prx") }.count ?? 0
        let appDirectory = base.appendingPathComponent("app0", isDirectory: true)
        var isDirectory: ObjCBool = false
        let appExists = manager.fileExists(atPath: appDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue
        let appEntries = appExists ? ((try? manager.contentsOfDirectory(atPath: appDirectory.path))?.count ?? 0) : 0
        let fontsDirectory = ProcessInfo.processInfo.environment["ANYPS5_SYSTEM_FONTS"]
            .map { URL(fileURLWithPath: $0) } ?? base.appendingPathComponent("anyps5-fonts")

        layout = RuntimeLayout(
            executableExists: manager.fileExists(atPath: output.path),
            libraryDirectory: libraryDirectory,
            libraryCount: libraryCount,
            appDirectoryExists: appExists,
            appEntryCount: appEntries,
            fontsPresent: manager.fileExists(atPath: fontsDirectory.path)
        )
    }
}
