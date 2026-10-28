import Foundation

public enum FirefoxProfileError: Error, LocalizedError, Equatable {
    case unreadableProfiles
    case profileNotFound(String)
    case ambiguousProfile(String)
    case profileDirectoryMissing(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableProfiles:
            "Could not read Firefox profiles from profiles.ini"
        case let .profileNotFound(name):
            "Firefox profile not found: \(name)"
        case let .ambiguousProfile(name):
            "More than one Firefox profile is named: \(name)"
        case let .profileDirectoryMissing(name):
            "Firefox profile directory is missing: \(name)"
        }
    }
}

public enum FirefoxProfileResolver {
    public static func validate(named name: String, firefoxDirectory: URL) throws {
        let file = firefoxDirectory.appendingPathComponent("profiles.ini")
        guard let data = try? Data(contentsOf: file),
              var contents = String(data: data, encoding: .utf8) else {
            throw FirefoxProfileError.unreadableProfiles
        }
        if contents.hasPrefix("\u{FEFF}") {
            contents.removeFirst()
        }

        var profiles: [[String: String]] = []
        var currentSection: String?
        var currentValues: [String: String] = [:]
        func appendProfile() {
            if let currentSection, currentSection.hasPrefix("Profile"),
               !currentSection.dropFirst("Profile".count).isEmpty,
               currentSection.dropFirst("Profile".count).allSatisfy(\.isNumber) {
                profiles.append(currentValues)
            }
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                appendProfile()
                currentSection = String(trimmed.dropFirst().dropLast())
                currentValues = [:]
            } else if !trimmed.hasPrefix(";") && !trimmed.hasPrefix("#"),
                      let separator = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                currentValues[key] = value
            }
        }
        appendProfile()

        guard !profiles.isEmpty else {
            throw FirefoxProfileError.unreadableProfiles
        }
        let matches = profiles.filter { $0["Name"] == name }
        guard !matches.isEmpty else {
            throw FirefoxProfileError.profileNotFound(name)
        }
        guard matches.count == 1, let profile = matches.first else {
            throw FirefoxProfileError.ambiguousProfile(name)
        }
        guard let path = profile["Path"], !path.isEmpty,
              let isRelative = profile["IsRelative"], ["0", "1"].contains(isRelative) else {
            throw FirefoxProfileError.unreadableProfiles
        }
        guard isRelative == "1" || path.hasPrefix("/") else {
            throw FirefoxProfileError.unreadableProfiles
        }
        let directory = isRelative == "1"
            ? firefoxDirectory.appendingPathComponent(path).standardizedFileURL
            : URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FirefoxProfileError.profileDirectoryMissing(name)
        }
    }
}
