import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum Route: String, CaseIterable, Identifiable {
    case convert, library, controls, console, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: "Convert"
        case .library: "Library"
        case .controls: "Controls"
        case .console: "Console"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .library: "square.grid.2x2"
        case .controls: "gamecontroller"
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

    private(set) var lastReport: ConversionReport?
    private(set) var inputConfig = InputConfig()
    private(set) var inputConfigDirectory: URL?
    private(set) var inputConfigSaved = true

    let runner = ProcessRunner()
    let library = LibraryStore()
    let compatibility = CompatibilityList.load()
    let controllers = ControllerMonitor()
    @ObservationIgnored private var conversionStartLine = -1

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
        EnvironmentText.parse(wineEnvironment)
    }

    func launchEnvironment(for output: URL) -> [String: String] {
        (library.entry(for: output)?.launchProfile ?? LaunchProfile()).merged(over: parsedWineEnvironment)
    }

    func setProfile(_ profile: LaunchProfile, for output: URL) {
        library.setProfile(profile, for: output)
    }

    func shaderCacheSize(for output: URL) -> (files: Int, bytes: Int64) {
        ShaderCache.size(at: ShaderCache.directory(besides: output))
    }

    func clearShaderCache(for output: URL) {
        do {
            try ShaderCache.clear(at: ShaderCache.directory(besides: output))
            runner.note("Cleared the shader cache for \(output.lastPathComponent)")
        } catch {
            banner = "Clearing the shader cache failed: \(error.localizedDescription)"
        }
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
        conversionStartLine = runner.lines.last?.id ?? -1
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
        let report = ConversionReport(lines: runner.lines.filter { $0.id > conversionStartLine && $0.source != .system }.map(\.text))
        lastReport = report
        library.record(LibraryEntry(
            title: inspection.displayTitle,
            titleId: inspection.titleId,
            source: inspection.executable,
            output: output,
            target: settings.target,
            convertedAt: Date(),
            exitCode: code,
            iconURL: inspection.iconURL,
            report: report
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
        let environment = launchEnvironment(for: output)
        let overrides = environment.keys.sorted().map { "\($0)=\(environment[$0] ?? "")" }.joined(separator: " ")
        if !overrides.isEmpty { runner.note("Environment: \(overrides)") }
        let started = Date()
        runner.run(label: "Launch via \(wine.name)", executable: wine.executable, arguments: [output.path],
                   workingDirectory: output.deletingLastPathComponent(),
                   environment: environment) { [weak self] code in
            guard let self else { return }
            let duration = Date().timeIntervalSince(started)
            self.library.addSession(PlaySession(start: started, duration: duration, exitCode: code), for: output)
            self.runner.note("Session ended after \(Int(duration))s with exit code \(code).")
        }
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

    var inputConfigURL: URL? {
        inputConfigDirectory?.appendingPathComponent(InputConfig.fileName)
    }

    var controlsTargets: [LibraryEntry] {
        var seen = Set<String>()
        return library.entries.filter { entry in
            entry.succeeded && entry.outputExists
                && seen.insert(entry.output.deletingLastPathComponent().standardizedFileURL.path).inserted
        }
    }

    func selectControlsTarget(_ directory: URL?) {
        inputConfigDirectory = directory
        reloadInputConfig()
    }

    func reloadInputConfig() {
        guard let url = inputConfigURL else {
            inputConfig = InputConfig()
            inputConfigSaved = true
            return
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        inputConfig = InputConfig(contents: text)
        inputConfigSaved = true
    }

    func reloadInputConfigIfSaved() {
        if inputConfigSaved { reloadInputConfig() }
    }

    func updateInputConfig(_ change: (inout InputConfig) throws -> Void) {
        do {
            var copy = inputConfig
            try change(&copy)
            inputConfig = copy
            inputConfigSaved = false
        } catch {
            banner = "\(error)"
        }
    }

    func saveInputConfig() {
        guard let url = inputConfigURL else { return }
        do {
            let text = inputConfig.serialized
            if text.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else {
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            inputConfig = InputConfig(contents: text)
            inputConfigSaved = true
        } catch {
            banner = "Saving \(InputConfig.fileName) failed: \(error.localizedDescription)"
        }
    }

    func importFonts() {
        guard let output = outputExecutable else { return }
        let destination = output.deletingLastPathComponent().appendingPathComponent("anyps5-fonts", isDirectory: true)
        let panel = NSOpenPanel()
        panel.title = "Choose font files or a folder of fonts"
        panel.message = "Console fonts (SST-*.otf) or Noto substitutes (NotoSans-*.ttf, NotoSansCJK-*.ttc)."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        let manager = FileManager.default
        let extensions: Set<String> = ["otf", "ttf", "ttc"]
        var fonts: [URL] = []
        for url in panel.urls {
            var isDirectory: ObjCBool = false
            _ = manager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                fonts += ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                    .filter { extensions.contains($0.pathExtension.lowercased()) }
            } else if extensions.contains(url.pathExtension.lowercased()) {
                fonts.append(url)
            }
        }
        guard !fonts.isEmpty else {
            banner = "No .otf, .ttf or .ttc files were selected."
            return
        }
        do {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            for font in fonts {
                let target = destination.appendingPathComponent(font.lastPathComponent)
                if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
                try manager.copyItem(at: font, to: target)
            }
            runner.note("Imported \(fonts.count) fonts into \(destination.path)")
        } catch {
            banner = "Importing fonts failed: \(error.localizedDescription)"
        }
        refreshLayout()
    }

    func createLauncher(title: String, titleId: String?, executable: URL, iconURL: URL?) {
        guard let wine = selectedWine else {
            banner = "Install CrossOver, Whisky or Wine to create a launcher."
            return
        }
        do {
            let app = try LauncherBuilder.build(title: title, titleId: titleId, executable: executable,
                                                wine: wine.executable, environment: launchEnvironment(for: executable))
            if let iconURL, let image = NSImage(contentsOf: iconURL) {
                NSWorkspace.shared.setIcon(image, forFile: app.path, options: [])
            }
            runner.note("Created \(app.path)")
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            banner = "Creating the launcher failed: \(error.localizedDescription)"
        }
    }

    func createLauncher(for entry: LibraryEntry) {
        createLauncher(title: entry.title, titleId: entry.titleId, executable: entry.output, iconURL: entry.iconURL)
    }

    func createLauncherForCurrent() {
        guard let inspection, let output = outputExecutable else { return }
        createLauncher(title: inspection.displayTitle, titleId: inspection.titleId, executable: output, iconURL: inspection.iconURL)
    }

    func saveBackups(title: String, titleId: String?) -> [SaveBackup] {
        SaveData.backups(in: SaveData.backupFolder(title: title, titleId: titleId))
    }

    @discardableResult
    func backupSaves(output: URL, title: String, titleId: String?, quiet: Bool = false) -> URL? {
        let source = SaveData.directory(besides: output)
        guard SaveData.hasSaves(at: source) else {
            if !quiet { banner = "\(title) has no save data yet." }
            return nil
        }
        let folder = SaveData.backupFolder(title: title, titleId: titleId)
        let archive = folder.appendingPathComponent(SaveData.backupName(for: Date()))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try runTool("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, archive.path])
            runner.note("Backed up \(title) saves to \(archive.path)")
            return archive
        } catch {
            banner = "Backing up saves failed: \(error)"
            return nil
        }
    }

    func restoreSaves(_ backup: SaveBackup, output: URL, title: String, titleId: String?) {
        let alert = NSAlert()
        alert.messageText = "Restore saves from \(backup.url.deletingPathExtension().lastPathComponent)?"
        alert.informativeText = "The current save data of \(title) is backed up first, then replaced."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let destination = SaveData.directory(besides: output)
        if SaveData.hasSaves(at: destination), backupSaves(output: output, title: title, titleId: titleId, quiet: true) == nil { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try runTool("/usr/bin/ditto", ["-x", "-k", backup.url.path, output.deletingLastPathComponent().path])
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw TitleDataError.invalid("The backup does not contain a \(SaveData.folderName) folder.")
            }
            runner.note("Restored \(title) saves from \(backup.url.path)")
        } catch {
            banner = "Restoring saves failed: \(error)"
        }
    }

    func entitlementsURL(for output: URL) -> URL {
        output.deletingLastPathComponent().appendingPathComponent(EntitlementsFile.fileName)
    }

    func loadEntitlements(for output: URL) -> EntitlementsFile {
        let text = (try? String(contentsOf: entitlementsURL(for: output), encoding: .utf8)) ?? ""
        return EntitlementsFile(contents: text)
    }

    func saveEntitlements(_ file: EntitlementsFile, for output: URL) {
        let url = entitlementsURL(for: output)
        do {
            if file.labels.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else {
                try file.serialized.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            banner = "Saving \(EntitlementsFile.fileName) failed: \(error.localizedDescription)"
        }
    }

    private func runTool(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw TitleDataError.toolFailed("\((path as NSString).lastPathComponent) exited with \(process.terminationStatus): \(message)")
        }
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
