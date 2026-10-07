import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum Route: String, CaseIterable, Identifiable {
    case convert, library, console, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: "Convert"
        case .library: "Library"
        case .console: "Console"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .library: "square.grid.2x2"
        case .console: "text.alignleft"
        case .system: "cpu"
        }
    }
}

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
    static let defaultWineEnvironment = "WINEDEBUG=-all\nWINEMSYNC=1\nWINEESYNC=1"

    var route: Route = .convert
    var settings: ConversionSettings {
        didSet { persistSettings() }
    }
    private(set) var inspection: GameInspection?
    private(set) var queue: [GameInspection] = []
    private(set) var isBatchRunning = false
    @ObservationIgnored private var batchFailures = 0
    @ObservationIgnored private var batchCount = 0
    var outputDirectory: URL? {
        didSet { UserDefaults.standard.set(outputDirectory?.path, forKey: Keys.outputDirectory) }
    }
    var outputName = "app"
    var wineEnvironment: String {
        didSet { UserDefaults.standard.set(wineEnvironment, forKey: Keys.wineEnvironment) }
    }
    private(set) var relinker: URL?
    private(set) var system: SystemReport
    private(set) var layout: RuntimeLayout?
    var selectedWine: WineRuntime?
    var banner: String?

    let runner = ProcessRunner()
    let library = LibraryStore()

    private enum Keys {
        static let outputDirectory = "outputDirectory"
        static let settings = "conversionSettings"
        static let wineEnvironment = "wineEnvironment"
    }

    init() {
        let defaults = UserDefaults.standard
        settings = defaults.data(forKey: Keys.settings)
            .flatMap { try? JSONDecoder().decode(ConversionSettings.self, from: $0) } ?? ConversionSettings()
        wineEnvironment = defaults.string(forKey: Keys.wineEnvironment) ?? AppModel.defaultWineEnvironment
        system = SystemProbe.report()
        relinker = RelinkerLocator.locate()
        selectedWine = system.wineRuntimes.first
        if let saved = defaults.string(forKey: Keys.outputDirectory) {
            outputDirectory = URL(fileURLWithPath: saved, isDirectory: true)
        }
    }

    var outputExecutable: URL? {
        guard let inspection else { return nil }
        return outputExecutable(for: inspection, name: outputName)
    }

    func outputExecutable(for inspection: GameInspection, name: String) -> URL? {
        guard let directory = outputDirectory else { return nil }
        let resolved = name.isEmpty ? inspection.suggestedOutputName : name
        return directory
            .appendingPathComponent(resolved, isDirectory: true)
            .appendingPathComponent(resolved)
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

    var parsedWineEnvironment: [String: String] {
        var result: [String: String] = [:]
        for line in wineEnvironment.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = String(trimmed[trimmed.index(after: separator)...])
        }
        return result
    }

    func refreshEnvironment() {
        system = SystemProbe.report()
        relinker = RelinkerLocator.locate()
        if let current = selectedWine, !system.wineRuntimes.contains(current) { selectedWine = nil }
        if selectedWine == nil { selectedWine = system.wineRuntimes.first }
        refreshLayout()
    }

    func open(_ url: URL) {
        open([url])
    }

    func open(_ urls: [URL]) {
        var found: [GameInspection] = []
        var missing: [String] = []
        for url in urls {
            if let executable = GameInspector.resolveExecutable(from: url) {
                found.append(GameInspector.inspect(executable))
            } else {
                missing.append(url.lastPathComponent)
            }
        }
        banner = missing.isEmpty ? nil : "No eboot.bin was found in \(missing.joined(separator: ", ")). Choose the executable directly."
        guard let first = found.first else { return }
        select(first)
        let additions = found.dropFirst().filter { candidate in
            !queue.contains { $0.executable == candidate.executable } && candidate.executable != first.executable
        }
        queue.append(contentsOf: additions)
        if outputDirectory == nil {
            outputDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("AnyPS5", isDirectory: true)
        }
        refreshLayout()
        updateDockBadge()
    }

    func reopen(_ entry: LibraryEntry) {
        guard entry.sourceExists else {
            banner = "\(entry.source.path) no longer exists."
            return
        }
        settings.target = entry.target
        outputDirectory = entry.output.deletingLastPathComponent().deletingLastPathComponent()
        select(GameInspector.inspect(entry.source))
        outputName = entry.output.deletingPathExtension().lastPathComponent
        route = .convert
        refreshLayout()
    }

    private func select(_ candidate: GameInspection) {
        inspection = candidate
        outputName = candidate.suggestedOutputName
        queue.removeAll { $0.executable == candidate.executable }
    }

    func reinspect() {
        guard let executable = inspection?.executable else { return }
        inspection = GameInspector.inspect(executable)
        queue = queue.map { GameInspector.inspect($0.executable) }
    }

    func removeFromQueue(_ item: GameInspection) {
        queue.removeAll { $0.executable == item.executable }
        updateDockBadge()
    }

    func clearQueue() {
        queue.removeAll()
        updateDockBadge()
    }

    func resetSettings() {
        settings = ConversionSettings()
        refreshLayout()
    }

    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose decrypted game executables or their folders"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { open(panel.urls) }
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

    func convertAll() {
        guard canConvert else { return }
        isBatchRunning = true
        batchFailures = 0
        batchCount = 0
        convert()
    }

    func convert() {
        guard canConvert, let relinker, let inspection, let arguments = commandArguments, let output = outputExecutable else {
            isBatchRunning = false
            return
        }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            banner = "Could not create the output folder: \(error.localizedDescription)"
            isBatchRunning = false
            return
        }
        route = .console
        runner.run(label: "Converting \(inspection.displayTitle)", executable: relinker, arguments: arguments,
                   workingDirectory: output.deletingLastPathComponent()) { [weak self] code in
            self?.conversionFinished(inspection, output: output, code: code)
        }
        updateDockBadge()
    }

    private func conversionFinished(_ inspection: GameInspection, output: URL, code: Int32) {
        switch code {
        case 0: runner.note("\(inspection.displayTitle): conversion finished.")
        case 1: runner.note("\(inspection.displayTitle): the relinker rejected the arguments (exit code 1).")
        case 2: runner.note("\(inspection.displayTitle): conversion failed (exit code 2). The reason is printed above.")
        default: runner.note("\(inspection.displayTitle): the relinker exited with code \(code).")
        }
        library.record(LibraryEntry(
            title: inspection.displayTitle,
            titleId: inspection.titleId,
            source: inspection.executable,
            output: output,
            target: settings.target,
            convertedAt: Date(),
            exitCode: code,
            iconURL: inspection.iconURL
        ))
        refreshLayout()
        batchCount += 1
        if code != 0 { batchFailures += 1 }

        if isBatchRunning, let next = nextConvertibleQueueItem() {
            select(next)
            refreshLayout()
            updateDockBadge()
            convert()
            return
        }
        let batch = isBatchRunning
        isBatchRunning = false
        updateDockBadge()
        if batch {
            SystemNotifier.post(
                title: batchFailures == 0 ? "Batch conversion finished" : "Batch conversion finished with failures",
                body: "\(batchCount - batchFailures) of \(batchCount) titles converted."
            )
        } else {
            SystemNotifier.post(title: code == 0 ? "Conversion finished" : "Conversion failed", body: inspection.displayTitle)
        }
    }

    private func nextConvertibleQueueItem() -> GameInspection? {
        while let candidate = queue.first {
            queue.removeFirst()
            if let issue = candidate.blockingIssue {
                runner.note("Skipping \(candidate.displayTitle): \(issue)")
                continue
            }
            return candidate
        }
        return nil
    }

    func cancel() {
        isBatchRunning = false
        runner.terminate()
        updateDockBadge()
    }

    func launch() {
        guard let output = outputExecutable else { return }
        launch(output: output, target: settings.target)
    }

    func launch(_ entry: LibraryEntry) {
        launch(output: entry.output, target: entry.target)
    }

    private func launch(output: URL, target: TargetPlatform) {
        guard target == .windows, let wine = selectedWine else { return }
        route = .console
        runner.run(label: "Launch via \(wine.name)", executable: wine.executable, arguments: [output.path],
                   workingDirectory: output.deletingLastPathComponent(),
                   environment: parsedWineEnvironment)
    }

    func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    func revealOutput() {
        guard let output = outputExecutable else { return }
        reveal(output)
    }

    func importSystemLibraries() {
        guard let output = outputExecutable,
              let destination = settings.libraryDirectory(besides: output) else { return }
        let platform = settings.target == .windows ? "Windows" : "Linux"
        let panel = NSOpenPanel()
        panel.title = "Choose the folder with \(platform) system libraries (*.prx)"
        panel.message = "Built with `cmake --build build --target libs` on a \(platform) host: build/core/libs/libs"
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

    func saveLog() {
        let panel = NSSavePanel()
        panel.title = "Save console output"
        panel.nameFieldStringValue = "anyps5-\(ISO8601DateFormatter().string(from: Date())).log"
            .replacingOccurrences(of: ":", with: "-")
        panel.allowedContentTypes = [.plainText, .log]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try runner.lines.map(\.text).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            banner = "Saving the log failed: \(error.localizedDescription)"
        }
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

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Keys.settings)
        }
    }

    private func updateDockBadge() {
        let active = runner.state.isRunning || isBatchRunning
        let pending = (isBatchRunning ? queue.count : 0) + (active ? 1 : 0)
        NSApp?.dockTile.badgeLabel = pending > 0 ? "\(pending)" : nil
    }
}
