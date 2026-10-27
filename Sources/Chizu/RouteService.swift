import AppKit
import ChizuCore
import Foundation

enum RouteServiceError: Error, LocalizedError {
    case configuration(URL, String)
    case applicationNotFound(String)
    case commandFailed(String)
    case diaOpenedWrongProfile(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case let .configuration(fileURL, reason): "Could not read configuration at \(fileURL.path): \(reason)"
        case let .applicationNotFound(bundleID): "Application not found: \(bundleID)"
        case let .commandFailed(message): "Could not open link: \(message)"
        case let .diaOpenedWrongProfile(expected, actual):
            "Dia opened profile '\(actual)' instead of '\(expected)'"
        }
    }
}

enum RouteService {
    static var defaultConfigurationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/chizu/config.jsonc")
    }

    static func decide(
        _ url: URL,
        sourceBundleID: String? = nil,
        configurationURL: URL? = nil
    ) throws -> RoutingDecision {
        let path = configurationURL ?? defaultConfigurationURL
        let configuration: Configuration
        do {
            configuration = try Configuration.load(from: path)
        } catch {
            throw RouteServiceError.configuration(path, error.localizedDescription)
        }
        return try configuration.decide(url, sourceBundleID: sourceBundleID)
    }

    static func open(_ url: URL, decision: RoutingDecision) throws {
        let destination = decision.destination
        if let profile = destination.profile {
            try openInDia(url, profile: profile)
            return
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: destination.bundleID
        ) else {
            throw RouteServiceError.applicationNotFound(destination.bundleID)
        }
        try run("/usr/bin/open", arguments: ["-a", applicationURL.path, url.absoluteString])
    }

    private static func openInDia(_ url: URL, profile: String) throws {
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Configuration.diaBundleID
        ) != nil else {
            throw RouteServiceError.applicationNotFound(Configuration.diaBundleID)
        }

        let result = try run(
            "/usr/bin/osascript",
            arguments: ["-e", diaScript, "--", profile, url.absoluteString]
        )
        let actualProfile = result
        guard actualProfile == profile else {
            throw RouteServiceError.diaOpenedWrongProfile(expected: profile, actual: actualProfile)
        }
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw RouteServiceError.commandFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let diaScript = """
        on run argv
            set desiredProfile to item 1 of argv
            set targetURL to item 2 of argv
            tell application id "company.thebrowser.dia"
                if (count of windows) is 0 then make new window
                set targetWindow to front window
                set targetProfile to missing value
                repeat with candidate in (every profile of targetWindow)
                    if (name of candidate as text) is desiredProfile then
                        set targetProfile to candidate
                        exit repeat
                    end if
                end repeat
                if targetProfile is missing value then error "Dia profile not found: " & desiredProfile number 1010
                set newTab to make new tab at end of tabs of targetProfile with properties {URL:targetURL}
                set newTabID to id of newTab
                set targetTab to first tab of targetProfile whose id is newTabID
                focus targetTab
                activate
                if (id of active tab of targetWindow) is not newTabID then error "Dia could not focus the new tab" number 1011
                return name of active profile of targetWindow
            end tell
        end run
        """
}
