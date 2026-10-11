import AppKit
import SwiftUI

struct ConsoleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page(eyebrow: "Console",
             title: "Relinker output",
             subtitle: "Live output from the relinker and from launched titles. Exit code 0 is success, 1 means rejected arguments, 2 means the conversion failed.",
             scrolls: false) {
            BannerRow()
            WeightedRow(weights: [1.75, 1]) {
                LogCard().reveal(0.05)
                VStack(spacing: 20) {
                    RunCard()
                    LayoutCard()
                }
                .reveal(0.12)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct LogCard: View {
    @Environment(AppModel.self) private var model
    @State var filter = ""
    @State var issuesOnly = false

    private var visibleLines: [LogLine] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return model.runner.lines.filter { line in
            if issuesOnly && line.tone != .failure && line.tone != .warning { return false }
            return query.isEmpty || line.text.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let lines = visibleLines
        BezelCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Eyebrow(text: lines.count == model.runner.lines.count
                            ? "\(model.runner.lines.count) lines"
                            : "\(lines.count) of \(model.runner.lines.count)")
                    GlassField(placeholder: "Filter", text: $filter, monospaced: true)
                        .frame(maxWidth: 220)
                    Toggle("Issues only", isOn: $issuesOnly.animation(Motion.snap))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(Theme.accent)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    GhostButton(title: "Copy", symbol: "doc.on.doc") {
                        let text = lines.map(\.text).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    GhostButton(title: "Save", symbol: "square.and.arrow.down") { model.saveLog() }
                    GhostButton(title: "Clear", symbol: "trash") { model.runner.clear() }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Hairline()

                if lines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(Theme.textTertiary)
                        Text(model.runner.lines.isEmpty ? "Nothing has run yet." : "No lines match the filter.")
                            .font(.bodyText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(lines) { line in
                                    LogLineView(line: line).id(line.id)
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: lines.last?.id) { _, last in
                            guard let last else { return }
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                        .onAppear {
                            if let last = lines.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
        }
    }
}

private struct LogLineView: View {
    let line: LogLine

    var body: some View {
        Text(line.text.isEmpty ? " " : line.text)
            .font(.mono)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        switch line.tone {
        case .plain: Theme.textPrimary.opacity(0.86)
        case .success: Theme.success
        case .warning: Theme.warning
        case .failure: Theme.failure
        case .muted: Theme.textTertiary
        case .accent: Theme.accent
        }
    }
}

private struct RunCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BezelCard {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(eyebrow: "Status", title: headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(detail(at: context.date))
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !model.runner.state.isRunning, let report = model.lastReport, !report.isEmpty {
                    ReportGrid(report: report)
                }
                HStack(spacing: 10) {
                    if model.runner.state.isRunning {
                        IslandButton(title: "Stop", symbol: "stop.fill", prominent: false) { model.cancel() }
                    } else {
                        IslandButton(title: "Convert again", symbol: "arrow.clockwise", prominent: false,
                                     enabled: model.canConvert) { model.convert() }
                    }
                }
            }
        }
    }

    private var headline: String {
        switch model.runner.state {
        case .idle: "Idle"
        case .running(let label, _): label + "…"
        case .finished(let label, let code, _): code == 0 ? "\(label) succeeded" : "\(label) exited with \(code)"
        case .failedToStart: "Could not start"
        }
    }

    private func detail(at date: Date) -> String {
        switch model.runner.state {
        case .idle: return "Start a conversion from the Convert page."
        case .running(_, let started): return "Running for \(Int(date.timeIntervalSince(started)))s"
        case .finished(_, _, let duration): return String(format: "Finished in %.1fs", duration)
        case .failedToStart(let message): return message
        }
    }
}

private struct LayoutCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BezelCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(eyebrow: "Runtime layout", title: model.layout?.isComplete == true ? "Ready to launch" : "Checklist")

                if let layout = model.layout {
                    VStack(spacing: 0) {
                        CheckRow(title: "Executable", detail: model.outputExecutable?.lastPathComponent ?? "", ok: layout.executableExists)
                        Hairline()
                        CheckRow(title: "System libraries",
                                 detail: layout.libraryDirectory == nil ? "Custom search path" : "\(layout.libraryCount) .prx in libs/",
                                 ok: layout.libraryCount > 0)
                        Hairline()
                        CheckRow(title: "Game files", detail: "\(layout.appEntryCount) entries in app0/", ok: layout.appDirectoryExists && layout.appEntryCount > 1)
                        Hairline()
                        CheckRow(title: "System fonts", detail: layout.fontsPresent ? "anyps5-fonts/" : "Optional", ok: layout.fontsPresent, optional: true)
                    }

                    FlowButtons()
                } else {
                    Text("Choose a game and an output folder first.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

private struct FlowButtons: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GhostButton(title: "Import libraries", symbol: "square.and.arrow.down") { model.importSystemLibraries() }
                GhostButton(title: "Link game files", symbol: "link") { model.linkGameResources() }
                    .disabled(model.layout?.executableExists != true)
                    .opacity(model.layout?.executableExists == true ? 1 : 0.4)
                GhostButton(title: "Import fonts", symbol: "textformat") { model.importFonts() }
            }
            HStack(spacing: 8) {
                GhostButton(title: "Reveal", symbol: "folder") { model.revealOutput() }
                if model.settings.target == .windows {
                    if model.system.wineRuntimes.isEmpty {
                        Text("Install CrossOver, Whisky or Wine to launch.")
                            .font(.captionText)
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Picker("Runtime", selection: $model.selectedWine) {
                            ForEach(model.system.wineRuntimes) { runtime in
                                Text(runtime.name).tag(Optional(runtime))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                        IslandButton(title: "Launch", symbol: "play.fill",
                                     enabled: model.layout?.isComplete == true && !model.runner.state.isRunning) {
                            model.launch()
                        }
                        if let output = model.outputExecutable, model.library.entry(for: output) != nil {
                            LaunchOptionsButton(output: output)
                        }
                        GhostButton(title: "Add to Applications", symbol: "app.badge") { model.createLauncherForCurrent() }
                            .disabled(model.layout?.executableExists != true)
                            .opacity(model.layout?.executableExists == true ? 1 : 0.4)
                    }
                } else {
                    Text("Linux builds run on a Linux x86-64 host.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.top, 4)
    }
}

struct ReportGrid: View {
    let report: ConversionReport

    var body: some View {
        let items = cells
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
                let (label, value) = items[index]
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text(label)
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        if let failure = report.failure {
            Callout(text: failure, tint: Theme.failure, symbol: "xmark.octagon")
        }
    }

    private var cells: [(String, String)] {
        var result: [(String, String)] = []
        if let target = report.target { result.append(("Target", target)) }
        result.append(("Guest modules", "\(report.guestModules)"))
        if let external = report.externalReferences { result.append(("System imports", "\(external)")) }
        if let before = report.nidBefore, let after = report.nidAfter { result.append(("NID references", before == after ? "\(after)" : "\(before) → \(after)")) }
        if let total = report.intelTotal {
            result.append(("AMD-only rewrites", total == 0 ? "None" : "\(report.intelInPlace ?? 0) + \(report.intelStubs ?? 0) stubs"))
        }
        if report.warnings > 0 { result.append(("Warnings", "\(report.warnings)")) }
        return result
    }
}

private struct CheckRow: View {
    let title: String
    let detail: String
    let ok: Bool
    var optional = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle" : (optional ? "circle.dotted" : "circle"))
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(ok ? Theme.success : (optional ? Theme.textTertiary : Theme.warning))
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(detail)
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 9)
    }
}
