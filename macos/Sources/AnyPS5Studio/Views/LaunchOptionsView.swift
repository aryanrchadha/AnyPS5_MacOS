import AppKit
import SwiftUI

struct LaunchOptionsPanel: View {
    @Environment(AppModel.self) private var model
    let output: URL
    @State var profile = LaunchProfile()
    @State var cache: (files: Int, bytes: Int64) = (0, 0)
    @State var loaded = false

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
                OptionRow(title: "Metal Performance HUD",
                          detail: "Overlay with frame rate, frame time and GPU memory, drawn by macOS for Metal apps.",
                          flag: "MTL_HUD_ENABLED=1",
                          isOn: $profile.metalHUD)
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
                OptionRow(title: "Back up saves on launch",
                          detail: "Archive the save folder before each launch. The newest \(SaveData.automaticRetention) automatic backups are kept.",
                          flag: "\(SaveData.folderName) → Documents/AnyPS5 Saves",
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
            loaded = true
        }
        .onChange(of: profile) { _, newValue in
            guard loaded else { return }
            model.setProfile(newValue, for: output)
        }
    }
}

struct SessionSummary: View {
    @Environment(AppModel.self) private var model
    let entry: LibraryEntry

    var body: some View {
        let sessions = entry.sessions ?? []
        VStack(alignment: .leading, spacing: 4) {
            Text("Sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(Self.text(for: entry))
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
            if let last = sessions.last, last.exitCode != 0 {
                Text("The last session exited with code \(last.exitCode). Its log has the full output.")
                    .font(.captionText)
                    .foregroundStyle(Theme.warning)
            }
            if !sessions.isEmpty {
                Button("Open last session log") { model.openLastSessionLog(for: entry) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
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
