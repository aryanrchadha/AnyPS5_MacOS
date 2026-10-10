import Foundation
import Observation

enum PlayStatus: String, Codable, CaseIterable, Identifiable {
    case nothing, boots, menus, inGame, playable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nothing: "Doesn't start"
        case .boots: "Boots"
        case .menus: "Menus"
        case .inGame: "In game"
        case .playable: "Playable"
        }
    }

    var detail: String {
        switch self {
        case .nothing: "Exits or crashes before showing anything"
        case .boots: "Shows a window or splash, no menus"
        case .menus: "Reaches menus but not gameplay"
        case .inGame: "Gameplay starts, with serious issues"
        case .playable: "Can be played through"
        }
    }
}

struct LibraryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var titleId: String?
    var source: URL
    var output: URL
    var target: TargetPlatform
    var convertedAt: Date
    var exitCode: Int32
    var iconURL: URL?
    var report: ConversionReport?
    var profile: LaunchProfile?
    var sessions: [PlaySession]?
    var relinkerCommit: String?
    var status: PlayStatus?
    var notes: String?

    var succeeded: Bool { exitCode == 0 }
    var outputExists: Bool { FileManager.default.fileExists(atPath: output.path) }
    var sourceExists: Bool { FileManager.default.fileExists(atPath: source.path) }
    var launchProfile: LaunchProfile { profile ?? LaunchProfile() }
    var playTime: TimeInterval { (sessions ?? []).reduce(0) { $0 + $1.duration } }
    var lastSession: PlaySession? { sessions?.last }
}

struct LibraryArchive: Codable, Equatable {
    static let currentVersion = 1

    var version = LibraryArchive.currentVersion
    var exportedAt: Date
    var entries: [LibraryEntry]
    var favorites: [String]

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func read(_ data: Data) throws -> LibraryArchive {
        let archive = try decoder.decode(LibraryArchive.self, from: data)
        guard archive.version <= currentVersion else {
            throw TitleDataError.invalid("This export was made by a newer AnyPS5 Studio (format \(archive.version)).")
        }
        return archive
    }
}

struct LibraryMergeResult: Equatable {
    var added = 0
    var updated = 0
    var unchanged = 0
}

@Observable
final class LibraryStore {
    private(set) var entries: [LibraryEntry] = []
    private(set) var setAside: URL?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var savingBlocked = false

    init(directory: URL = LibraryStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("library.json")
        load()
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AnyPS5 Studio", isDirectory: true)
    }

    func record(_ entry: LibraryEntry) {
        var entry = entry
        if let previous = self.entry(for: entry.output) {
            entry.profile = entry.profile ?? previous.profile
            entry.sessions = entry.sessions ?? previous.sessions
            entry.status = entry.status ?? previous.status
            entry.notes = entry.notes ?? previous.notes
        }
        entries.removeAll { $0.output.standardizedFileURL == entry.output.standardizedFileURL }
        entries.insert(entry, at: 0)
        save()
    }

    func entry(for output: URL) -> LibraryEntry? {
        entries.first { $0.output.standardizedFileURL == output.standardizedFileURL }
    }

    func update(_ entry: LibraryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func setProfile(_ profile: LaunchProfile, for output: URL) {
        guard var entry = entry(for: output) else { return }
        entry.profile = profile == LaunchProfile() ? nil : profile
        update(entry)
    }

    func setStatus(_ status: PlayStatus?, notes: String?, for output: URL) {
        guard var entry = entry(for: output) else { return }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.status = status
        entry.notes = (trimmed?.isEmpty ?? true) ? nil : trimmed
        update(entry)
    }

    func addSession(_ session: PlaySession, for output: URL) {
        guard var entry = entry(for: output) else { return }
        var sessions = entry.sessions ?? []
        sessions.append(session)
        entry.sessions = Array(sessions.suffix(200))
        update(entry)
    }

    @discardableResult
    func merge(_ imported: [LibraryEntry]) -> LibraryMergeResult {
        var result = LibraryMergeResult()
        for incoming in imported {
            guard let index = entries.firstIndex(where: { $0.output.standardizedFileURL == incoming.output.standardizedFileURL }) else {
                var added = incoming
                if entries.contains(where: { $0.id == added.id }) { added.id = UUID() }
                entries.append(added)
                result.added += 1
                continue
            }
            var current = entries[index]
            let before = current
            if current.profile == nil { current.profile = incoming.profile }
            if current.status == nil { current.status = incoming.status }
            if current.notes == nil { current.notes = incoming.notes }
            let known = Set((current.sessions ?? []).map { "\($0.start.timeIntervalSince1970)|\($0.duration)" })
            let extra = (incoming.sessions ?? []).filter { !known.contains("\($0.start.timeIntervalSince1970)|\($0.duration)") }
            if !extra.isEmpty {
                current.sessions = Array(((current.sessions ?? []) + extra).sorted { $0.start < $1.start }.suffix(200))
            }
            if current == before {
                result.unchanged += 1
            } else {
                entries[index] = current
                result.updated += 1
            }
        }
        if result.added + result.updated > 0 { save() }
        return result
    }

    func archive(favorites: Set<String>, now: Date = Date()) -> LibraryArchive {
        LibraryArchive(exportedAt: now, entries: entries, favorites: favorites.sorted())
    }

    func remove(_ entry: LibraryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func removeMissing() {
        entries.removeAll { !$0.outputExists }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try LibraryArchive.decoder.decode([LibraryEntry].self, from: data)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent("library.unreadable-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
                setAside = aside
            } catch {
                savingBlocked = true
                NSLog("AnyPS5 Studio: could not set the unreadable library aside: %@", error.localizedDescription)
            }
            NSLog("AnyPS5 Studio: the library could not be read: %@", String(describing: error))
        }
    }

    private func save() {
        guard !savingBlocked else { return }
        let encoder = LibraryArchive.encoder
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("AnyPS5 Studio: could not save the library: %@", error.localizedDescription)
        }
    }
}
