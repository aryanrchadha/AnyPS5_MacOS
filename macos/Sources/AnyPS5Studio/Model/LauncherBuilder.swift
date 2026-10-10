import Foundation

enum LauncherBuilder {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("AnyPS5", isDirectory: true)
    }

    static func bundleName(for title: String) -> String {
        let cleaned = title.unicodeScalars.map { scalar -> Character in
            CharacterSet(charactersIn: "/:\\").contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
                ? "-" : Character(scalar)
        }
        let name = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "AnyPS5 Title" : name
    }

    static func bundleIdentifier(title: String, titleId: String?) -> String {
        let base = (titleId ?? title).lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return "io.github.anyps5.launcher." + (base.isEmpty ? "title" : base)
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static let ditto = "/usr/bin/ditto"
    static let timestamp = "$(date '+%Y-%m-%d %H.%M.%S')"

    static func prune(_ folder: String, pattern: String, keeping count: Int) -> String {
        "ls -1 \"\(folder)\" | grep \(shellQuoted(pattern)) | sort -r | tail -n +\(max(count, 0) + 1) | while IFS= read -r old; do rm -f \"\(folder)/$old\"; done"
    }

    static func script(executable: URL, wine: URL, environment: [String: String],
                       title: String? = nil, logFolder: URL? = nil, backupFolder: URL? = nil) -> String {
        var lines = ["#!/bin/sh", "cd \(shellQuoted(executable.deletingLastPathComponent().path)) || exit 1"]
        for key in environment.keys.sorted() where key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil {
            lines.append("export \(key)=\(shellQuoted(environment[key] ?? ""))")
        }
        if let backupFolder {
            lines += [
                "backup_dir=\(shellQuoted(backupFolder.path))",
                "if [ -n \"$(find \(shellQuoted(SaveData.folderName)) -type f 2>/dev/null | head -n 1)\" ]; then",
                "  mkdir -p \"$backup_dir\" && \(ditto) -c -k --sequesterRsrc --keepParent \(shellQuoted(SaveData.folderName)) \"$backup_dir/\(SaveData.automaticPrefix) \(timestamp).zip\"",
                "  " + prune("$backup_dir", pattern: "^\(SaveData.automaticPrefix) .*\\.zip$", keeping: SaveData.automaticRetention),
                "fi",
            ]
        }
        let command = "\(shellQuoted(wine.path)) \(shellQuoted(executable.path)) \"$@\""
        guard let logFolder else {
            lines.append("exec " + command)
            return lines.joined(separator: "\n") + "\n"
        }
        lines += [
            "log_dir=\(shellQuoted(logFolder.path))",
            "mkdir -p \"$log_dir\"",
            "log=\"$log_dir/\(SessionLog.prefix) \(timestamp).log\"",
            "started=$(date +%s)",
            "{ printf '%s\\n' \(shellQuoted("# " + (title ?? executable.deletingPathExtension().lastPathComponent))) \"# Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')\" '# Launched from Applications' ''; } > \"$log\"",
            prune("$log_dir", pattern: "^\(SessionLog.prefix) .*\\.log$", keeping: SessionLog.retention),
            command + " >> \"$log\" 2>&1",
            "code=$?",
            "printf '%s\\n' \"# Duration: $(( $(date +%s) - started ))s\" \"# Exit code: $code\" >> \"$log\"",
            "exit $code",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    static func infoPlist(title: String, titleId: String?) throws -> Data {
        let dictionary: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleIdentifier": bundleIdentifier(title: title, titleId: titleId),
            "CFBundleName": title,
            "CFBundleDisplayName": title,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true,
        ]
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    @discardableResult
    static func build(title: String, titleId: String?, executable: URL, wine: URL,
                      environment: [String: String], logFolder: URL? = nil, backupFolder: URL? = nil,
                      in directory: URL = defaultDirectory) throws -> URL {
        let manager = FileManager.default
        let app = directory.appendingPathComponent(bundleName(for: title) + ".app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        if manager.fileExists(atPath: app.path) { try manager.removeItem(at: app) }
        try manager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try infoPlist(title: title, titleId: titleId).write(to: contents.appendingPathComponent("Info.plist"))
        let launcher = macOS.appendingPathComponent("launch")
        try script(executable: executable, wine: wine, environment: environment,
                   title: title, logFolder: logFolder, backupFolder: backupFolder)
            .write(to: launcher, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        return app
    }
}
