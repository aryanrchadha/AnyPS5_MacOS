import Foundation
import Observation

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

    var succeeded: Bool { exitCode == 0 }
    var outputExists: Bool { FileManager.default.fileExists(atPath: output.path) }
    var sourceExists: Bool { FileManager.default.fileExists(atPath: source.path) }
}

@Observable
final class LibraryStore {
    private(set) var entries: [LibraryEntry] = []

    @ObservationIgnored private let fileURL: URL

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
        entries.removeAll { $0.output.standardizedFileURL == entry.output.standardizedFileURL }
        entries.insert(entry, at: 0)
        save()
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([LibraryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("AnyPS5 Studio: could not save the library: %@", error.localizedDescription)
        }
    }
}
