import AppKit
import SwiftUI

struct TitleDataPanel: View {
    @Environment(AppModel.self) private var model
    let entry: LibraryEntry
    @State var backups: [SaveBackup] = []
    @State var saveSize: (files: Int, bytes: Int64) = (0, 0)
    @State var entitlements = EntitlementsFile()
    @State var newLabel = ""
    @State var labelError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Title data", tint: Theme.accent)
                Text(entry.title)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Save data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(saveSize.files == 0
                             ? "No saves yet in \(SaveData.folderName)/"
                             : "\(saveSize.files) files · \(ByteCountFormatter.string(fromByteCount: saveSize.bytes, countStyle: .file))")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    GhostButton(title: "Back up", symbol: "externaldrive.badge.plus") {
                        model.backupSaves(output: entry.output, title: entry.title, titleId: entry.titleId)
                        refresh()
                    }
                    .disabled(saveSize.files == 0)
                    .opacity(saveSize.files == 0 ? 0.4 : 1)
                    GhostButton(title: "Reveal", symbol: "folder") { model.reveal(SaveData.directory(besides: entry.output)) }
                }
                if backups.isEmpty {
                    Text("Backups are stored in Documents/AnyPS5 Saves.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(backups.prefix(5)) { backup in
                            HStack {
                                Image(systemName: SaveData.isAutomatic(backup) ? "clock.arrow.circlepath" : "archivebox")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundStyle(Theme.textTertiary)
                                Text(backup.created.formatted(date: .abbreviated, time: .shortened))
                                    .font(.captionText)
                                    .foregroundStyle(Theme.textPrimary)
                                if SaveData.isAutomatic(backup) {
                                    Text("Auto")
                                        .font(.captionText)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Text(ByteCountFormatter.string(fromByteCount: backup.bytes, countStyle: .file))
                                    .font(.captionText)
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer()
                                Button("Restore") {
                                    model.restoreSaves(backup, output: entry.output, title: entry.title, titleId: entry.titleId)
                                    refresh()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.accent)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }

            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Owned add-ons")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(EntitlementsFile.fileName)
                        .font(.monoSmall)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text("Entitlement labels of add-ons you own, reported to the title as installed. Up to \(EntitlementsFile.maximumLabelLength) characters each.")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !entitlements.issues.isEmpty {
                    Callout(text: entitlements.issues.joined(separator: "\n"))
                }
                ForEach(entitlements.labels, id: \.self) { label in
                    HStack {
                        Text(label)
                            .font(.mono)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button {
                            entitlements.remove(label)
                            model.saveEntitlements(entitlements, for: entry.output)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                HStack(spacing: 8) {
                    GlassField(placeholder: "Entitlement label", text: $newLabel, monospaced: true)
                        .onSubmit(addLabel)
                    GhostButton(title: "Add", symbol: "plus", action: addLabel)
                }
                if let labelError {
                    Text(labelError)
                        .font(.captionText)
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.coreRaised)
        .onAppear(perform: refresh)
    }

    private func addLabel() {
        do {
            try entitlements.add(newLabel)
            model.saveEntitlements(entitlements, for: entry.output)
            newLabel = ""
            labelError = nil
        } catch {
            labelError = "\(error)"
        }
    }

    private func refresh() {
        saveSize = ShaderCache.size(at: SaveData.directory(besides: entry.output))
        backups = model.saveBackups(title: entry.title, titleId: entry.titleId)
        entitlements = model.loadEntitlements(for: entry.output)
    }
}

struct TitleDataButton: View {
    let entry: LibraryEntry
    @State var presented = false

    var body: some View {
        GhostButton(title: "Data", symbol: "externaldrive") { presented.toggle() }
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                TitleDataPanel(entry: entry)
            }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let launchable = model.launchableEntries
        switch model.runner.state {
        case .running(let label, _):
            Text(label + "…")
            Button("Stop") { model.cancel() }
        default:
            Text(model.relinker == nil ? "Relinker not found" : "Ready")
        }
        Divider()
        if launchable.isEmpty {
            Text("No launchable titles")
        } else if model.selectedWine == nil {
            Text("Install a Wine runtime to launch titles")
        } else {
            if let last = model.lastPlayedEntry {
                Button("Continue \(last.title)") { model.launch(last) }
                    .disabled(model.runner.state.isRunning)
                Divider()
            }
            ForEach(launchable.prefix(8)) { entry in
                Button("Launch \(entry.title)") { model.launch(entry) }
                    .disabled(model.runner.state.isRunning)
            }
        }
        Divider()
        Button("Open AnyPS5 Studio") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") { NSApp.terminate(nil) }
    }
}
