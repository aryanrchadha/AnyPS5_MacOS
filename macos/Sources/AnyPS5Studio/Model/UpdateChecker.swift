import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct BuildInfo: Equatable {
    var commit: String?
    var repository: String?

    static let upstreamReference = "boykopovar:main"

    static var current: BuildInfo {
        let info = Bundle.main.infoDictionary
        return BuildInfo(commit: info?["AnyPS5Commit"] as? String, repository: info?["AnyPS5Repository"] as? String)
    }

    var shortCommit: String? { commit.map { String($0.prefix(8)) } }

    func compareURL(against reference: String = BuildInfo.upstreamReference) -> URL? {
        guard let commit, let repository, Self.isRepository(repository), commit.allSatisfy(\.isHexDigit) else { return nil }
        return URL(string: "https://api.github.com/repos/\(repository)/compare/\(commit)...\(reference)")
    }

    static func isRepository(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    static func repository(fromRemote remote: String) -> String? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "github.com[:/]", options: .regularExpression) else { return nil }
        var path = String(trimmed[range.upperBound...])
        if path.hasSuffix(".git") { path.removeLast(4) }
        return isRepository(path) ? path : nil
    }
}

struct UpdateStatus: Equatable {
    var newerCommits: Int
    var subjects: [String]
    var compareURL: URL?

    init(newerCommits: Int, subjects: [String], compareURL: URL?) {
        self.newerCommits = newerCommits
        self.subjects = subjects
        self.compareURL = compareURL
    }

    init(json data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TitleDataError.invalid("Unexpected response from GitHub.")
        }
        guard let ahead = object["ahead_by"] as? Int else {
            throw TitleDataError.invalid((object["message"] as? String).map { "GitHub: \($0)" } ?? "GitHub did not return a comparison.")
        }
        let commits = object["commits"] as? [[String: Any]] ?? []
        newerCommits = ahead
        subjects = commits.reversed().compactMap { commit in
            ((commit["commit"] as? [String: Any])?["message"] as? String)?
                .split(separator: "\n", maxSplits: 1).first.map(String.init)
        }
        compareURL = (object["html_url"] as? String).flatMap(URL.init(string:))
    }

    var isCurrent: Bool { newerCommits == 0 }
}

enum UpdateChecker {
    static func check(_ build: BuildInfo, session: URLSession = .shared) async throws -> UpdateStatus {
        guard let url = build.compareURL() else {
            throw TitleDataError.invalid("This build does not record its commit. Build it with macos/scripts/build-app.sh to enable update checks.")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let status = try? UpdateStatus(json: data) { return status }
            throw TitleDataError.invalid("GitHub returned HTTP \(http.statusCode).")
        }
        return try UpdateStatus(json: data)
    }
}
