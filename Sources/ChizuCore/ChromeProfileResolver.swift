import Foundation

public enum ChromeProfileError: Error, LocalizedError, Equatable {
    case unreadableProfiles
    case profileNotFound(String)
    case ambiguousProfile(String)
    case profileDirectoryMissing(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableProfiles:
            "Could not read Chrome profiles from Local State"
        case let .profileNotFound(name):
            "Chrome profile not found: \(name)"
        case let .ambiguousProfile(name):
            "More than one Chrome profile is named: \(name)"
        case let .profileDirectoryMissing(name):
            "Chrome profile directory is missing: \(name)"
        }
    }
}

public enum ChromeProfileResolver {
    public static func directory(named displayName: String, userDataDirectory: URL) throws -> String {
        let localState = userDataDirectory.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localState),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: [String: Any]] else {
            throw ChromeProfileError.unreadableProfiles
        }

        let matches = infoCache.filter { _, details in
            (details["name"] as? String) == displayName
        }
        guard !matches.isEmpty else {
            throw ChromeProfileError.profileNotFound(displayName)
        }
        guard matches.count == 1, let directory = matches.keys.first else {
            throw ChromeProfileError.ambiguousProfile(displayName)
        }
        guard directory != ".", directory != "..", !directory.contains("/"), !directory.contains("\\") else {
            throw ChromeProfileError.profileDirectoryMissing(displayName)
        }
        var isDirectory: ObjCBool = false
        let path = userDataDirectory.appendingPathComponent(directory).path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ChromeProfileError.profileDirectoryMissing(displayName)
        }
        return directory
    }
}
