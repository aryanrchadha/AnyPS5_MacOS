import AppKit
import SwiftUI

struct LaunchOptionsPanel: View {
    @Environment(AppModel.self) private var model
    let output: URL
    @State var profile = LaunchProfile()
    @State var cache: (files: Int, bytes: Int64) = (0, 0)
    @State var prefix: (files: Int, bytes: Int64)?
    @State var loaded = false
    @State var preflight: LaunchPreflight?

    var body: some View {
        let entry = model.library.entry(for: output)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Launch options", tint: Theme.accent)
                Text(entry?.title ?? output.deletingPathExtension().lastPathComponent)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
            }

            if entry == nil {
                Callout(text: "Convert this title first. Options are stored with its Library entry.")
            } else {
                if let preflight {
                    PreflightList(preflight: preflight)
                    Hairline()
                }
                if let publisher = entry?.publisher {
                    PublisherNotesView(publisher: publisher, measuring: $profile.measureFrameRate)
                    Hairline()
                }
                RuntimeRow(selection: $profile.wineRuntimePath)
                Hairline()
                OptionRow(title: "Metal Performance HUD",
                          detail: "Overlay with frame rate, frame time and GPU memory, drawn by macOS for Metal apps.",
                          flag: "MTL_HUD_ENABLED=1",
                          isOn: $profile.metalHUD)
                Hairline()
                OptionRow(title: "Measure frame rate",
                          detail: "Turn on the runtime's draw profiling, which reports presented frames every 10 seconds, and show frames per second and the output resolution in the Console and under Sessions. Profiling adds overhead, so the measured rate is a lower bound.",
                          flag: "\(FrameRateMeter.environmentKey)=1",
                          isOn: $profile.measureFrameRate)
                Hairline()
                OptionRow(title: "Disable shader cache",
                          detail: "Recompile every shader on launch. For troubleshooting; expect more stutter.",
                          flag: "ANYPS5_NO_SHADER_CACHE=1",
                          isOn: $profile.disableShaderCache)
                Hairline()
                OptionRow(title: "Quiet Wine logging",
                          detail: "Turn off Wine's own debug channels to cut console noise. Runtime output still appears; Wine errors do not.",
                          flag: "WINEDEBUG=-all",
                          isOn: $profile.quietWine)
                Hairline()
                OptionRow(title: "Separate Wine prefix",
                          detail: "Give this title its own Wine prefix in \(WinePrefix.folderName) beside the executable, so DLLs installed for it with winetricks do not change other titles. The first launch takes longer while Wine creates it.",
                          flag: "WINEPREFIX=\u{2026}/\(WinePrefix.folderName)",
                          isOn: $profile.separatePrefix)
                Hairline()
                OptionRow(title: "Back up saves on launch",
                          detail: "Archive the save folder to the Save backups folder in Settings before each launch. The newest \(SaveData.automaticRetention) automatic backups are kept.",
                          flag: "\(SaveData.folderName) → \(SaveData.backupRoot.lastPathComponent)",
                          isOn: $profile.backupSavesOnLaunch)
                Hairline()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extra environment")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    TextEditor(text: $profile.extraEnvironment)
                        .font(.mono)
                        .scrollContentBackground(.hidden)
                        .frame(height: 64)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    Text("KEY=value per line, applied over the Wine environment in Settings.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                }
                Hairline()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shader cache")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(cache.files == 0 ? "Empty" : "\(cache.files) files · \(ByteCountFormatter.string(fromByteCount: cache.bytes, countStyle: .file))")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    GhostButton(title: "Clear", symbol: "trash") {
                        model.clearShaderCache(for: output)
                        cache = model.shaderCacheSize(for: output)
                    }
                    .disabled(cache.files == 0)
                    .opacity(cache.files == 0 ? 0.4 : 1)
                }
                if profile.separatePrefix || prefix != nil {
                    Hairline()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Wine prefix")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(prefix.map { "\($0.files) files \u{B7} \(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file))" }
                                 ?? "Created by Wine on the next launch")
                                .font(.captionText)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if prefix != nil {
                            GhostButton(title: "Reveal", symbol: "folder") { model.revealWinePrefix(for: output) }
                                .fixedSize()
                            GhostButton(title: "Reset\u{2026}", symbol: "arrow.counterclockwise") {
                                model.resetWinePrefix(for: output)
                                prefix = model.winePrefixSize(for: output)
                            }
                            .fixedSize()
                        }
                    }
                }
                if let entry, let sessions = entry.sessions, !sessions.isEmpty {
                    Hairline()
                    SessionSummary(entry: entry)
                }
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Theme.coreRaised)
        .onAppear {
            guard !loaded else { return }
            profile = entry?.launchProfile ?? LaunchProfile()
            cache = model.shaderCacheSize(for: output)
            prefix = model.winePrefixSize(for: output)
            preflight = model.preflight(for: output)
            loaded = true
        }
        .onChange(of: profile) { _, newValue in
            guard loaded else { return }
            model.setProfile(newValue, for: output)
            preflight = model.preflight(for: output)
        }
    }
}

struct PreflightList: View {
    let preflight: LaunchPreflight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(color: Self.color(preflight.level))
                Text(preflight.summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            ForEach(preflight.checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: Self.symbol(check.level))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Self.color(check.level))
                        .frame(width: 14)
                    Text(check.title)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 92, alignment: .leading)
                    Text(check.detail)
                        .font(.captionText)
                        .foregroundStyle(check.level == .ok ? Theme.textTertiary : Self.color(check.level))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    static func color(_ level: PreflightLevel) -> Color {
        switch level {
        case .ok: return Theme.success
        case .warning: return Theme.warning
        case .failure: return Theme.failure
        }
    }

    static func symbol(_ level: PreflightLevel) -> String {
        switch level {
        case .ok: return "checkmark"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark"
        }
    }
}

struct RuntimeRow: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        let runtimes = model.system.wineRuntimes
        let missing = selection.flatMap { path in runtimes.contains { $0.executable.path == path } ? nil : path }
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wine runtime")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(missing.map { "\($0) is not installed; the default is used." }
                     ?? "Used for this title by Launch, the menu bar and Add to Applications.")
                    .font(.captionText)
                    .foregroundStyle(missing == nil ? Theme.textSecondary : Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Picker("Wine runtime", selection: $selection) {
                Text("Default (\(model.selectedWine?.name ?? "none"))").tag(String?.none)
                ForEach(runtimes) { runtime in
                    Text("\(runtime.name) · \(runtime.executable.lastPathComponent)").tag(Optional(runtime.executable.path))
                }
                if let missing {
                    Text("Not installed").tag(Optional(missing))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 190)
        }
    }
}

struct PublisherNotesView: View {
    let publisher: Publisher
    @Binding var measuring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "building.2")
                    .font(.system(size: 12, weight: .light))
                Text("\(publisher.name) title")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            ForEach(publisher.notes, id: \.self) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.captionText.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(note.detail)
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !measuring {
                Button("Turn on Measure frame rate") { measuring = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct SessionSummary: View {
    @Environment(AppModel.self) private var model
    let entry: LibraryEntry
    @State var crash: CrashSummary?
    @State var displays: [DisplayTarget] = []

    var body: some View {
        let sessions = entry.sessions ?? []
        VStack(alignment: .leading, spacing: 4) {
            Text("Sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(Self.text(for: entry))
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
            if sessions.count > 1 {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(SessionHistory.rows(for: entry)) { row in
                        HStack(spacing: 10) {
                            Text(row.start.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(Theme.textSecondary)
                            Text(row.duration)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
                            Spacer(minLength: 8)
                            if let frameRate = row.frameRate {
                                Text(frameRate)
                                    .monospacedDigit()
                                    .foregroundStyle(row.meetsTarget ? Theme.success : Theme.textSecondary)
                            }
                            Text(row.succeeded ? "OK" : "Exit \(row.exitCode)")
                                .monospacedDigit()
                                .foregroundStyle(row.succeeded ? Theme.success : Theme.failure)
                        }
                        .font(.captionText)
                        .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityLabel("Recent sessions")
            }
            if let measured = sessions.last(where: { $0.frameRateText != nil }), let text = measured.frameRateText,
               let average = measured.averageFPS {
                Label("Frame rate: \(text)", systemImage: "speedometer")
                    .font(.captionText)
                    .foregroundStyle(FrameRateMeter.meetsTarget(average: average, size: measured.frameSize) ? Theme.success : Theme.textSecondary)
                    .help("Measured \(measured.start.formatted(date: .abbreviated, time: .shortened)) with \(FrameRateMeter.environmentKey); a lower bound")
                if let change = SessionHistory.frameRateChange(for: entry) {
                    Text(change)
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 20)
                }
                if let advice = FrameRateMeter.refreshAdvice(average: average, displays: displays) {
                    HStack(alignment: .top, spacing: 10) {
                        Label(advice, systemImage: "display")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let display = FrameRateMeter.refreshCap(average: average, displays: displays),
                           display.availableRefreshRate > display.maximumRefreshRate {
                            Button("Open Displays") { model.openDisplaySettings() }
                                .controlSize(.small)
                                .fixedSize()
                        }
                    }
                    .padding(.top, 2)
                }
            }
            if let last = sessions.last, last.exitCode != 0 {
                Text("The last session exited with code \(last.exitCode). Its log has the full output.")
                    .font(.captionText)
                    .foregroundStyle(Theme.warning)
                if let crash, !crash.findings.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(crash.findings.enumerated()), id: \.offset) { _, finding in
                            Text(finding.headline)
                                .font(.mono)
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = finding.detail {
                                Text(detail)
                                    .font(.captionText)
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ForEach(crash.advice, id: \.self) { advice in
                            Label(advice, systemImage: "arrow.turn.down.right")
                                .font(.captionText)
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 2)
                }
                if let crash {
                    ForEach(Array(Set(crash.findings.compactMap(\.winetricksVerb))).sorted(), id: \.self) { verb in
                        Button("Copy winetricks \(verb) command") { model.copyWinetricksCommand(for: entry, verb: verb) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .help(model.winetricksCommand(for: entry, verb: verb))
                    }
                }
                Button("Launch again with Wine errors") { model.launch(entry, diagnostic: true) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .disabled(model.runner.state.isRunning)
            }
            if !sessions.isEmpty {
                Button("Open last session log") { model.openLastSessionLog(for: entry) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .task(id: sessions.count) {
            crash = model.lastCrash(for: entry)
            displays = DisplayProbe.displays()
        }
    }

    static func text(for entry: LibraryEntry) -> String {
        let sessions = entry.sessions ?? []
        guard let last = sessions.last else { return "Not launched yet" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let total = formatter.string(from: entry.playTime) ?? "\(Int(entry.playTime))s"
        let plays = sessions.count == 1 ? "1 launch" : "\(sessions.count) launches"
        return "\(plays) · \(total) total · last \(last.start.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct LaunchOptionsButton: View {
    let output: URL
    @State var presented = false

    var body: some View {
        GhostButton(title: "Options", symbol: "slider.horizontal.3") { presented.toggle() }
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                LaunchOptionsPanel(output: output)
            }
    }
}
