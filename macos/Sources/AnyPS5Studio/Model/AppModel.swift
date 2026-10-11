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
    var fontsShared = false

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
    var sharedFontCount = SharedFonts.fonts(in: SharedFonts.defaultFolder).count

    private(set) var lastReport: ConversionReport?
    private(set) var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Keys.favorites) ?? [])
    private(set) var inputConfig = InputConfig()
    private(set) var inputConfigDirectory: URL?
    private(set) var inputConfigSaved = true

    let runner = ProcessRunner()
    let library = LibraryStore()
    let compatibility = CompatibilityList.load()
    let controllers = ControllerMonitor()
    let build = BuildInfo.current
    private(set) var updateStatus: UpdateStatus?
    private(set) var updateError: String?
    private(set) var checkingForUpdates = false
    @ObservationIgnored private var conversionStartLine = -1

    private enum Keys {
        static let outputDirectory = "outputDirectory"
        static let settings = "conversionSettings"
        static let wineEnvironment = "wineEnvironment"
        static let favorites = "libraryFavorites"
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
        if let aside = library.setAside {
            banner = "The Library file could not be read, so it was moved to \(aside.path) and the Library starts empty. Import it from there if it was an export, or send it with a bug report."
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
            report: report,
            relinkerCommit: build.commit
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
        guard target == .windows, !runner.state.isRunning else { return }
        let entry = library.entry(for: output)
        let check = preflight(for: output)
        guard check.canLaunch, let wine = wineRuntime(for: output) else {
            let title = entry?.title ?? output.deletingPathExtension().lastPathComponent
            banner = "\(title) was not launched. " + check.failures.map(\.detail).joined(separator: " ")
            return
        }
        route = .console
        for warning in check.warnings { runner.note(warning.detail) }
        linkSharedFonts(besides: output)
        if let entry, entry.launchProfile.backupSavesOnLaunch {
            backupSaves(output: output, title: entry.title, titleId: entry.titleId, quiet: true, automatic: true)
        }
        let firstLine = runner.lines.last?.id ?? -1
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
            let title = entry?.title ?? output.deletingPathExtension().lastPathComponent
            let lines = self.runner.lines.filter { $0.id > firstLine }
            self.writeSessionLog(lines, title: title, titleId: entry?.titleId, started: started, duration: duration, exitCode: code)
            if code != 0 {
                let crash = CrashSummary(lines: lines.filter { $0.source != .system }.map(\.text))
                for finding in crash.findings {
                    self.runner.note("Likely cause: \(finding.headline)" + (finding.detail.map { " \u{2014} \($0)" } ?? ""))
                }
                SystemNotifier.post(title: "\(title) exited with code \(code)",
                                    body: crash.headline ?? "The session log has the full output.")
            }
        }
    }

    func preflight(for output: URL) -> LaunchPreflight {
        let runtime = wineRuntime(for: output)
        return LaunchPreflight(output: output, runtime: runtime?.executable, runtimeName: runtime?.name,
                               pinnedRuntime: library.entry(for: output)?.launchProfile.wineRuntimePath,
                               needsRosetta: system.isAppleSilicon && !system.rosettaInstalled,
                               freeBytes: LaunchPreflight.freeBytes(near: output))
    }

    func wineRuntime(for output: URL) -> WineRuntime? {
        if let pinned = library.entry(for: output)?.launchProfile.wineRuntimePath,
           let runtime = system.wineRuntimes.first(where: { $0.executable.path == pinned }) {
            return runtime
        }
        return selectedWine
    }

    private func writeSessionLog(_ lines: [LogLine], title: String, titleId: String?, started: Date,
                                 duration: TimeInterval, exitCode: Int32) {
        let folder = SessionLog.folder(title: title, titleId: titleId)
        let file = folder.appendingPathComponent(SessionLog.fileName(for: started))
        let text = SessionLog.text(lines, title: title, started: started, duration: duration, exitCode: exitCode)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            for expired in SessionLog.expired(SessionLog.logs(in: folder)) {
                try? FileManager.default.removeItem(at: expired)
            }
            runner.note("Session log saved to \(file.path)")
        } catch {
            runner.note("Could not save the session log: \(error.localizedDescription)")
        }
    }

    func lastSessionLog(for entry: LibraryEntry) -> URL? {
        SessionLog.logs(in: SessionLog.folder(title: entry.title, titleId: entry.titleId)).first
    }

    func lastCrash(for entry: LibraryEntry) -> CrashSummary? {
        guard let last = entry.sessions?.last, last.exitCode != 0, let log = lastSessionLog(for: entry) else { return nil }
        return CrashSummary.read(log: log)
    }

    func openLastSessionLog(for entry: LibraryEntry) {
        guard let log = lastSessionLog(for: entry) else {
            banner = "\(entry.title) has no session logs yet."
            return
        }
        NSWorkspace.shared.open(log)
    }

    var launchableEntries: [LibraryEntry] {
        library.entries.filter { $0.target == .windows && $0.succeeded && $0.outputExists }
    }

    var lastPlayedEntry: LibraryEntry? {
        launchableEntries
            .filter { $0.lastSession != nil }
            .max { LibraryOrganizer.lastActivity($0) < LibraryOrganizer.lastActivity($1) }
    }

    var canLaunchLastPlayed: Bool {
        lastPlayedEntry != nil && selectedWine != nil && !runner.state.isRunning
    }

    static let confirmLinkLaunchKey = "confirmLinkLaunch"

    func handle(_ link: StudioLink) {
        switch link {
        case .library:
            route = .library
        case .launch(let target):
            guard let entry = StudioLink.match(target, in: library.entries) else {
                route = .library
                banner = "No converted title matches \u{201C}\(target)\u{201D}."
                return
            }
            guard launchableEntries.contains(where: { $0.id == entry.id }), wineRuntime(for: entry.output) != nil else {
                route = .library
                banner = "\(entry.title) cannot be launched: it needs a successful Windows conversion, its output folder and a Wine runtime."
                return
            }
            guard !runner.state.isRunning else {
                banner = "\(entry.title) was not launched because another task is running."
                return
            }
            guard confirmLinkLaunch(entry) else { return }
            launch(entry)
        }
    }

    private func confirmLinkLaunch(_ entry: LibraryEntry) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.confirmLinkLaunchKey) != nil, !defaults.bool(forKey: Self.confirmLinkLaunchKey) { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Launch \(entry.title)?"
        alert.informativeText = "An anyps5:// link asked AnyPS5 Studio to launch this title."
        alert.addButton(withTitle: "Launch")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Launch from links without asking"
        let approved = alert.runModal() == .alertFirstButtonReturn
        if approved, alert.suppressionButton?.state == .on { defaults.set(false, forKey: Self.confirmLinkLaunchKey) }
        return approved
    }

    private func confirm(_ message: String, detail: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @discardableResult
    func clearAllShaderCaches() -> Bool {
        guard !runner.state.isRunning else {
            runner.note("Shader caches were not cleared because a title or conversion is running.")
            return false
        }
        guard confirm("Clear every shader cache?",
                      detail: "Deletes shader_cache/ in each Library output folder. Titles rebuild their caches when next launched, with more stutter at first.",
                      action: "Clear Caches") else { return false }
        let result = StorageCleanup.clearShaderCaches(outputs: library.entries.map(\.output))
        runner.note("Cleared \(result.cleared) shader caches" + (result.failed.isEmpty ? "." : "; could not clear \(result.failed.joined(separator: ", "))."))
        return true
    }

    @discardableResult
    func deleteAllSessionLogs() -> Bool {
        guard confirm("Delete all session logs?",
                      detail: "Deletes the session logs in \(SessionLog.root.path). Play times in the Library are kept.",
                      action: "Delete Logs") else { return false }
        let deleted = StorageCleanup.deleteSessionLogs(root: SessionLog.root)
        runner.note("Deleted \(deleted) session logs.")
        return true
    }

    func copyCompatibilityReport(for entry: LibraryEntry) {
        let report = CompatibilityReport(entry: entry,
                                         mac: "\(system.chip), \(system.memoryLabel)",
                                         macOS: system.macOSLabel,
                                         runtime: entry.target == .windows ? wineRuntime(for: entry.output)?.name : nil,
                                         appVersion: appVersion,
                                         crash: lastCrash(for: entry))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.markdown, forType: .string)
        runner.note("Copied the compatibility report for \(entry.title)")
    }

    func copyLaunchLink(for entry: LibraryEntry) {
        guard let url = StudioLink.launchURL(for: entry) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        runner.note("Copied \(url.absoluteString)")
    }

    func launchLastPlayed() {
        guard let entry = lastPlayedEntry else { return }
        launch(entry)
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

    private func chooseFonts() -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "Choose font files or a folder of fonts"
        panel.message = "Console fonts (SST-*.otf) or Noto substitutes (NotoSans-*.ttf, NotoSansCJK-*.ttc)."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return nil }
        let fonts = SharedFonts.collect(from: panel.urls)
        if fonts.isEmpty { banner = "No .otf, .ttf or .ttc files were selected." }
        return fonts.isEmpty ? nil : fonts
    }

    func importFonts() {
        guard let output = outputExecutable else { return }
        let destination = SharedFonts.localFolder(besides: output)
        guard let fonts = chooseFonts() else { return }
        do {
            try SharedFonts.detachShared(besides: output)
            try SharedFonts.copy(fonts, to: destination)
            runner.note("Imported \(fonts.count) fonts into \(destination.path)")
        } catch {
            banner = "Importing fonts failed: \(error.localizedDescription)"
        }
        refreshLayout()
    }

    func importSharedFonts() {
        guard let fonts = chooseFonts() else { return }
        do {
            try SharedFonts.copy(fonts, to: SharedFonts.defaultFolder)
            banner = "Imported \(fonts.count) fonts into the shared fonts folder. Titles without their own \(SharedFonts.folderName)/ link to it when launched."
        } catch {
            banner = "Importing fonts failed: \(error.localizedDescription)"
        }
        sharedFontCount = SharedFonts.fonts(in: SharedFonts.defaultFolder).count
        refreshLayout()
    }

    func revealSharedFonts() {
        try? FileManager.default.createDirectory(at: SharedFonts.defaultFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(SharedFonts.defaultFolder)
    }

    private func linkSharedFonts(besides executable: URL) {
        guard launchEnvironment(for: executable)["ANYPS5_SYSTEM_FONTS"] == nil else { return }
        do {
            if try SharedFonts.link(besides: executable) {
                runner.note("Linked \(SharedFonts.folderName)/ to the shared fonts folder.")
            }
        } catch {
            runner.note("Could not link the shared fonts: \(error.localizedDescription)")
        }
    }

    func createLauncher(title: String, titleId: String?, executable: URL, iconURL: URL?) {
        guard let wine = wineRuntime(for: executable) else {
            banner = "Install CrossOver, Whisky or Wine to create a launcher."
            return
        }
        let profile = library.entry(for: executable)?.launchProfile ?? LaunchProfile()
        linkSharedFonts(besides: executable)
        do {
            let app = try LauncherBuilder.build(title: title, titleId: titleId, executable: executable,
                                                wine: wine.executable, environment: launchEnvironment(for: executable),
                                                logFolder: SessionLog.folder(title: title, titleId: titleId),
                                                backupFolder: profile.backupSavesOnLaunch
                                                    ? SaveData.backupFolder(title: title, titleId: titleId) : nil)
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
    func backupSaves(output: URL, title: String, titleId: String?, quiet: Bool = false, automatic: Bool = false) -> URL? {
        let source = SaveData.directory(besides: output)
        guard SaveData.hasSaves(at: source) else {
            if !quiet { banner = "\(title) has no save data yet." }
            return nil
        }
        let folder = SaveData.backupFolder(title: title, titleId: titleId)
        let archive = folder.appendingPathComponent(SaveData.backupName(for: Date(), automatic: automatic))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try runTool("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, archive.path])
            runner.note("Backed up \(title) saves to \(archive.path)")
            if automatic {
                for expired in SaveData.expiredAutomaticBackups(in: SaveData.backups(in: folder)) {
                    try? FileManager.default.removeItem(at: expired.url)
                }
            }
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

    var outdatedEntries: [LibraryEntry] {
        guard let current = build.commit else { return [] }
        return library.entries.filter { entry in
            guard let commit = entry.relinkerCommit else { return false }
            return commit != current && entry.sourceExists
        }
    }

    func isOutdated(_ entry: LibraryEntry) -> Bool {
        guard let current = build.commit, let commit = entry.relinkerCommit else { return false }
        return commit != current
    }

    func queueOutdated() {
        let sources = outdatedEntries.map(\.source)
        guard !sources.isEmpty else { return }
        open(sources)
        route = .convert
        runner.note("Queued \(sources.count) titles converted with an older relinker. Convert All re-converts them with the current switches.")
    }

    func checkForUpdates() {
        guard !checkingForUpdates else { return }
        checkingForUpdates = true
        updateError = nil
        let build = self.build
        Task { @MainActor in
            do {
                self.updateStatus = try await UpdateChecker.check(build)
            } catch {
                self.updateError = "\(error)"
            }
            self.checkingForUpdates = false
        }
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "development build" }
        return "\(version) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    func isFavorite(_ entry: LibraryEntry) -> Bool {
        favorites.contains(LibraryOrganizer.key(entry))
    }

    func toggleFavorite(_ entry: LibraryEntry) {
        let key = LibraryOrganizer.key(entry)
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
        UserDefaults.standard.set(Array(favorites), forKey: Keys.favorites)
    }

    func moveToTrash(_ entry: LibraryEntry) {
        let folder = entry.output.deletingLastPathComponent()
        guard folder.lastPathComponent == entry.output.deletingPathExtension().lastPathComponent,
              FileManager.default.fileExists(atPath: entry.output.path) else {
            banner = "\(folder.path) was not created by AnyPS5 Studio, so it is not moved to the Trash. Remove it in Finder."
            return
        }
        let hasSaves = SaveData.hasSaves(at: SaveData.directory(besides: entry.output))
        let alert = NSAlert()
        alert.messageText = "Move \(entry.title) to the Trash?"
        alert.informativeText = "This moves \(folder.path) to the Trash, including converted modules, libraries and shader cache."
            + (hasSaves ? " The folder contains save data." : "")
        if hasSaves { alert.addButton(withTitle: "Back Up Saves and Move") }
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        let backUp = hasSaves && response == .alertFirstButtonReturn
        let move = backUp || response == (hasSaves ? .alertSecondButtonReturn : .alertFirstButtonReturn)
        guard move else { return }
        if backUp, backupSaves(output: entry.output, title: entry.title, titleId: entry.titleId, quiet: true) == nil {
            banner = "Backing up the saves failed, so nothing was moved."
            return
        }
        NSWorkspace.shared.recycle([folder]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.banner = "Moving to the Trash failed: \(error.localizedDescription)"
                } else {
                    self.library.remove(entry)
                    self.runner.note("Moved \(folder.path) to the Trash")
                    self.refreshLayout()
                }
            }
        }
    }

    func exportLibrary() {
        let panel = NSSavePanel()
        panel.title = "Export Library"
        panel.message = "Includes titles, launch options, play sessions and pins. Output folders and saves are not copied."
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        panel.nameFieldStringValue = "AnyPS5 Library \(day).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LibraryArchive.encoder.encode(library.archive(favorites: favorites)).write(to: url, options: .atomic)
            runner.note("Exported \(library.entries.count) titles to \(url.path)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            banner = "Exporting the Library failed: \(error.localizedDescription)"
        }
    }

    func importLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Import Library"
        panel.message = "Titles are added or merged; nothing in the current Library is removed."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let archive = try LibraryArchive.read(Data(contentsOf: url))
            let result = library.merge(archive.entries)
            favorites.formUnion(archive.favorites)
            UserDefaults.standard.set(Array(favorites), forKey: Keys.favorites)
            let missing = archive.entries.filter { !$0.outputExists }.count
            banner = "Imported \(archive.entries.count) titles: \(result.added) added, \(result.updated) merged, \(result.unchanged) already up to date."
                + (missing > 0 ? " \(missing) point to output folders that do not exist on this Mac." : "")
        } catch let error as TitleDataError {
            banner = "Importing the Library failed: \(error)"
        } catch {
            banner = "Importing the Library failed: the file is not an AnyPS5 Studio Library export."
        }
    }

    func exportDiagnostics(for entry: LibraryEntry?) {
        var system: [(String, String)] = [
            ("Chip", self.system.chip),
            ("Architecture", self.system.isAppleSilicon ? "Apple Silicon" : "Intel"),
            ("macOS", self.system.macOSLabel),
            ("Memory", self.system.memoryLabel),
            ("Rosetta 2", self.system.rosettaInstalled ? "installed" : "not installed"),
            ("Relinker", relinker?.path ?? "not found"),
            ("Wine runtimes", self.system.wineRuntimes.map { "\($0.name) (\($0.executable.path))" }.joined(separator: ", ")),
        ]
        if let gpu = DisplayProbe.gpu() {
            system.append(("GPU", "\(gpu.name), working set \(ByteCountFormatter.string(fromByteCount: Int64(gpu.recommendedWorkingSetBytes), countStyle: .memory))"))
        }
        for display in DisplayProbe.displays() {
            system.append(("Display", "\(display.name) \(display.pixelWidth)x\(display.pixelHeight) \(display.maximumRefreshRate) Hz"))
        }
        let report = DiagnosticsReport(appVersion: appVersion, system: system, entry: entry, log: runner.lines.map(\.text))
        let panel = NSSavePanel()
        panel.title = "Export diagnostics"
        panel.message = "The report contains file paths, hardware details and the console log. Review it before sharing."
        panel.nameFieldStringValue = "AnyPS5 diagnostics\(entry.map { " - \(LauncherBuilder.bundleName(for: $0.title))" } ?? "").txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            banner = "Exporting diagnostics failed: \(error.localizedDescription)"
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
        let configuredFonts = ProcessInfo.processInfo.environment["ANYPS5_SYSTEM_FONTS"].map { URL(fileURLWithPath: $0) }
        let fontSource = SharedFonts.source(besides: output)
        let ownFonts = configuredFonts.map { !SharedFonts.fonts(in: $0).isEmpty } ?? (fontSource != .none && !SharedFonts.isShared(besides: output))
        let sharedFonts = configuredFonts == nil && !ownFonts && sharedFontCount > 0

        layout = RuntimeLayout(
            executableExists: manager.fileExists(atPath: output.path),
            libraryDirectory: libraryDirectory,
            libraryCount: libraryCount,
            appDirectoryExists: appExists,
            appEntryCount: appEntries,
            fontsPresent: ownFonts || sharedFonts,
            fontsShared: sharedFonts
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
