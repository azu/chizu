import Darwin
import Foundation

public enum ChizuError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case configurationAlreadyExists(String)
    case unsupportedURL(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message): "Invalid configuration: \(message)"
        case let .configurationAlreadyExists(path): "Configuration already exists at \(path); edit it instead"
        case let .unsupportedURL(value): "Only HTTP and HTTPS URLs are supported: \(value)"
        }
    }
}

public struct Destination: Codable, Equatable, Sendable {
    public let bundleID: String
    public let profile: String?

    public init(bundleID: String, profile: String? = nil) {
        self.bundleID = bundleID
        self.profile = profile
    }
}

public struct Match: Codable, Equatable, Sendable {
    public let urlContains: String?
    public let urlRegex: String?
    public let host: String?
    public let pathPrefix: String?
    public let sourceBundleID: String?

    public init(
        urlContains: String? = nil,
        urlRegex: String? = nil,
        host: String? = nil,
        pathPrefix: String? = nil,
        sourceBundleID: String? = nil
    ) {
        self.urlContains = urlContains
        self.urlRegex = urlRegex
        self.host = host
        self.pathPrefix = pathPrefix
        self.sourceBundleID = sourceBundleID
    }

    func matches(_ url: URL, sourceBundleID: String?) throws -> Bool {
        if let urlContains, url.absoluteString.range(of: urlContains, options: .caseInsensitive) == nil {
            return false
        }
        if let urlRegex {
            let expression = try Self.regularExpression(urlRegex)
            let value = url.absoluteString
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if expression.firstMatch(in: value, range: range) == nil {
                return false
            }
        }
        if let host, url.host?.caseInsensitiveCompare(host) != .orderedSame {
            return false
        }
        if let pathPrefix, !url.path.hasPrefix(pathPrefix) {
            return false
        }
        if let requiredSource = self.sourceBundleID,
           sourceBundleID?.caseInsensitiveCompare(requiredSource) != .orderedSame {
            return false
        }
        return true
    }

    func validate(ruleName: String) throws {
        let fields = [urlContains, urlRegex, host, pathPrefix, sourceBundleID]
        guard fields.contains(where: { $0 != nil }) else {
            throw ChizuError.invalidConfiguration("rule '\(ruleName)' has no condition")
        }
        guard fields.allSatisfy({ $0 == nil || !$0!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ChizuError.invalidConfiguration("rule '\(ruleName)' has an empty condition")
        }
        if let host, host.contains("/") || host.contains(":") {
            throw ChizuError.invalidConfiguration("rule '\(ruleName)' host must be a hostname")
        }
        if let pathPrefix, !pathPrefix.hasPrefix("/") {
            throw ChizuError.invalidConfiguration("rule '\(ruleName)' pathPrefix must start with /")
        }
        if let urlRegex {
            do {
                _ = try Self.regularExpression(urlRegex)
            } catch {
                throw ChizuError.invalidConfiguration("rule '\(ruleName)' has invalid urlRegex: \(error.localizedDescription)")
            }
        }
    }

    private static func regularExpression(_ pattern: String) throws -> NSRegularExpression {
        try NSRegularExpression(pattern: "\\A(?:\(pattern))\\z")
    }
}

public struct Rule: Codable, Equatable, Sendable {
    public let name: String
    public let when: Match
    public let destination: Destination

    public init(name: String, when: Match, destination: Destination) {
        self.name = name
        self.when = when
        self.destination = destination
    }
}

public struct RoutingDecision: Equatable, Sendable {
    public let destination: Destination
    public let ruleName: String?

    public init(destination: Destination, ruleName: String?) {
        self.destination = destination
        self.ruleName = ruleName
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public static let diaBundleID = "company.thebrowser.dia"
    public static let chromeBundleID = "com.google.Chrome"
    public static let firefoxBundleID = "org.mozilla.firefox"

    public let version: Int
    public let `default`: Destination
    public let rules: [Rule]

    public init(version: Int = 1, default: Destination, rules: [Rule]) {
        self.version = version
        self.default = `default`
        self.rules = rules
    }

    public static func createStarter(at fileURL: URL) throws {
        let contents = """
            {
              "version": 1,
              // Fallback for links that match no rule.
              "default": { "bundleID": "com.apple.Safari" },
              // Add rules here in priority order.
              "rules": []
            }
            """ + "\n"
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(fileURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            let errorNumber = errno
            if errorNumber == EEXIST {
                throw ChizuError.configurationAlreadyExists(fileURL.path)
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorNumber))
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try file.write(contentsOf: Data(contents.utf8))
            try file.close()
        } catch {
            try? file.close()
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }

    public static func load(from fileURL: URL) throws -> Configuration {
        let data = try JSONC.jsonData(from: Data(contentsOf: fileURL))
        try validateJSONShape(data)
        let configuration = try JSONDecoder().decode(Configuration.self, from: data)
        try configuration.validate()
        return configuration
    }

    public func validate() throws {
        guard version == 1 else {
            throw ChizuError.invalidConfiguration("unsupported version \(version)")
        }
        try validate(destination: `default`, name: "default")
        var names = Set<String>()
        for rule in rules {
            guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ChizuError.invalidConfiguration("rule name is empty")
            }
            guard names.insert(rule.name).inserted else {
                throw ChizuError.invalidConfiguration("duplicate rule name '\(rule.name)'")
            }
            try rule.when.validate(ruleName: rule.name)
            try validate(destination: rule.destination, name: rule.name)
        }
    }

    public func decide(_ url: URL, sourceBundleID: String? = nil) throws -> RoutingDecision {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            throw ChizuError.unsupportedURL(url.absoluteString)
        }
        for rule in rules {
            if try rule.when.matches(url, sourceBundleID: sourceBundleID) {
                return RoutingDecision(destination: rule.destination, ruleName: rule.name)
            }
        }
        return RoutingDecision(destination: `default`, ruleName: nil)
    }

    private func validate(destination: Destination, name: String) throws {
        let bundleID = destination.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !bundleID.contains("/"), bundleID != "dev.azu.chizu" else {
            throw ChizuError.invalidConfiguration("invalid app bundleID in '\(name)'")
        }
        if let profile = destination.profile {
            guard [Self.diaBundleID, Self.chromeBundleID, Self.firefoxBundleID].contains(destination.bundleID),
                  !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ChizuError.invalidConfiguration("profile in '\(name)' requires Dia, Chrome, or Firefox and a non-empty name")
            }
        }
    }

    private static func validateJSONShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChizuError.invalidConfiguration("root must be an object")
        }
        try requireKeys(root, allowed: ["version", "default", "rules"], context: "root")
        guard let defaultDestination = root["default"] as? [String: Any] else {
            throw ChizuError.invalidConfiguration("default must be an object")
        }
        try requireKeys(defaultDestination, allowed: ["bundleID", "profile"], context: "default")
        guard let rules = root["rules"] as? [[String: Any]] else {
            throw ChizuError.invalidConfiguration("rules must be an array")
        }
        for (index, rule) in rules.enumerated() {
            let context = "rule \(index + 1)"
            try requireKeys(rule, allowed: ["name", "when", "destination"], context: context)
            guard let condition = rule["when"] as? [String: Any],
                  let destination = rule["destination"] as? [String: Any] else {
                throw ChizuError.invalidConfiguration("\(context) needs when and destination objects")
            }
            try requireKeys(condition, allowed: ["urlContains", "urlRegex", "host", "pathPrefix", "sourceBundleID"], context: "\(context).when")
            try requireKeys(destination, allowed: ["bundleID", "profile"], context: "\(context).destination")
        }
    }

    private static func requireKeys(_ object: [String: Any], allowed: Set<String>, context: String) throws {
        if let unknown = object.keys.first(where: { !allowed.contains($0) }) {
            throw ChizuError.invalidConfiguration("unknown key '\(unknown)' in \(context)")
        }
    }
}
