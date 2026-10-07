import AppKit
import SwiftUI

private func measureSizes(_ entries: [LibraryEntry]) async -> [String: Int64] {
    await Task.detached(priority: .utility) {
        var result: [String: Int64] = [:]
        for entry in entries where entry.outputExists {
            result[LibraryOrganizer.key(entry)] = LibraryOrganizer.folderSize(entry.output.deletingLastPathComponent())
        }
        return result
    }.value
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State var search = ""
    @State var sort: LibrarySort = .recent
    @State var sizes: [String: Int64] = [:]

    private var entries: [LibraryEntry] {
        LibraryOrganizer.arrange(model.library.entries, query: search, sort: sort, favorites: model.favorites, sizes: sizes)
    }

    var body: some View {
        Page(eyebrow: "Library",
             title: "Converted titles",
             subtitle: "Every conversion is remembered here with its output, target and result. Reopen a title to convert it again with different switches.") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    GlassField(placeholder: "Search by title or title ID", text: $search)
                        .frame(maxWidth: 320)
                    GlassSegmented(options: LibrarySort.allCases, selection: $sort) { $0.title }
                        .frame(maxWidth: 360)
                    Spacer()
                    Text("\(model.library.entries.count) titles")
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                    GhostButton(title: "Forget missing", symbol: "trash") { model.library.removeMissing() }
                }
                .reveal(0.04)

                if model.library.entries.isEmpty {
                    BezelCard(padding: 40) {
                        VStack(spacing: 14) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 30, weight: .ultraLight))
                                .foregroundStyle(Theme.textTertiary)
                            Text("No conversions yet")
                                .font(.sectionTitle)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Titles appear here after the relinker runs on them.")
                                .font(.bodyText)
                                .foregroundStyle(Theme.textSecondary)
                            IslandButton(title: "Convert a title") { model.route = .convert }
                                .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .reveal(0.08)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 20, alignment: .top)],
                              alignment: .leading, spacing: 20) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            LibraryCard(entry: entry, size: sizes[LibraryOrganizer.key(entry)])
                                .reveal(0.06 + Double(min(index, 8)) * 0.04)
                        }
                    }
                }
            }
        }
        .animation(Motion.settle, value: entries.map(\.id))
        .task(id: model.library.entries.map(\.id)) {
            sizes = await measureSizes(model.library.entries)
        }
    }
}

private struct LibraryCard: View {
    @Environment(AppModel.self) private var model
    let entry: LibraryEntry
    let size: Int64?

    var body: some View {
        BezelCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    artwork
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation(Motion.snap) { model.toggleFavorite(entry) }
                            } label: {
                                Image(systemName: model.isFavorite(entry) ? "star.fill" : "star")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundStyle(model.isFavorite(entry) ? Theme.warning : Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .help(model.isFavorite(entry) ? "Unpin" : "Pin to the top")
                        }
                        Text(entry.titleId ?? entry.source.deletingLastPathComponent().lastPathComponent)
                            .font(.monoSmall)
                            .foregroundStyle(Theme.textTertiary)
                        HStack(spacing: 6) {
                            Chip(text: entry.succeeded ? "Converted" : "Exit \(entry.exitCode)",
                                 symbol: entry.succeeded ? "checkmark" : "xmark",
                                 tint: entry.succeeded ? Theme.success : Theme.failure)
                            Chip(text: entry.target.title, symbol: entry.target.symbol)
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.output.path)
                        .font(.monoSmall)
                        .foregroundStyle(entry.outputExists ? Theme.textSecondary : Theme.failure)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                    Text(entry.outputExists
                         ? entry.convertedAt.formatted(date: .abbreviated, time: .shortened)
                             + (size.map { " · " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "")
                         : "Output no longer exists")
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                    if entry.sessions?.isEmpty == false {
                        Text(SessionSummary.text(for: entry))
                            .font(.captionText)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    if let summary = reportSummary {
                        Text(summary)
                            .font(.captionText)
                            .foregroundStyle(entry.succeeded ? Theme.textSecondary : Theme.failure)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 8) {
                    GhostButton(title: "Reopen", symbol: "arrow.uturn.backward") { model.reopen(entry) }
                    GhostButton(title: "Reveal", symbol: "folder") { model.reveal(entry.output) }
                    if entry.succeeded && entry.outputExists {
                        LaunchOptionsButton(output: entry.output)
                        TitleDataButton(entry: entry)
                    }
                    Spacer(minLength: 0)
                    if entry.target == .windows && entry.succeeded && entry.outputExists && !model.system.wineRuntimes.isEmpty {
                        IslandButton(title: "Launch", symbol: "play.fill", enabled: !model.runner.state.isRunning) {
                            model.launch(entry)
                        }
                    }
                }
            }
        }
        .contextMenu {
            Button("Reopen") { model.reopen(entry) }
            Button("Reveal Output in Finder") { model.reveal(entry.output) }
            Button("Reveal Source in Finder") { model.reveal(entry.source) }
            Button("Edit Controls") {
                model.selectControlsTarget(entry.output.deletingLastPathComponent())
                model.route = .controls
            }
            .disabled(!entry.outputExists)
            Button("Add to Applications") { model.createLauncher(for: entry) }
                .disabled(entry.target != .windows || !entry.succeeded || !entry.outputExists || model.selectedWine == nil)
            Button(model.isFavorite(entry) ? "Unpin" : "Pin to Top") { model.toggleFavorite(entry) }
            Button("Export Diagnostics…") { model.exportDiagnostics(for: entry) }
            Divider()
            Button("Remove from Library", role: .destructive) { model.library.remove(entry) }
            Button("Move Conversion to Trash…", role: .destructive) { model.moveToTrash(entry) }
                .disabled(!entry.outputExists)
        }
    }

    private var reportSummary: String? {
        guard let report = entry.report else { return nil }
        if let failure = report.failure { return failure }
        var parts = ["\(report.guestModules) guest modules"]
        if let external = report.externalReferences { parts.append("\(external) system imports") }
        if let total = report.intelTotal, total > 0 { parts.append("\(total) AMD-only rewrites") }
        return parts.joined(separator: " · ")
    }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Group {
            if let url = entry.iconURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.orbTeal.opacity(0.55), Theme.coreRaised],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 22, weight: .ultraLight))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairlineStrong, lineWidth: 1))
    }
}
