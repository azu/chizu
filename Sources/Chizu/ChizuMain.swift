import AppKit
import ChizuCore
import CoreServices
import Foundation

@MainActor
final class ChizuAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let sourceBundleID = sourceBundleIDFromCurrentEvent()
        NSLog("Chizu received %ld URL(s) through AppKit", urls.count)
        for url in urls {
            route(url, sourceBundleID: sourceBundleID)
        }
    }

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: value) else {
            showError("Could not read the incoming URL")
            return
        }

        NSLog("Chizu received a URL through Apple Events")
        route(url, sourceBundleID: sourceBundleID(from: event))
    }

    private func route(_ url: URL, sourceBundleID: String?) {
        do {
            let decision = try RouteService.decide(url, sourceBundleID: sourceBundleID)
            try RouteService.open(url, decision: decision)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func sourceBundleIDFromCurrentEvent() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return nil }
        return sourceBundleID(from: event)
    }

    private func sourceBundleID(from event: NSAppleEventDescriptor) -> String? {
        let sender = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))
            ?? event.attributeDescriptor(forKeyword: AEKeyword(keyAddressAttr))?
                .coerce(toDescriptorType: DescType(typeKernelProcessID))
        return sender.flatMap {
            NSRunningApplication(processIdentifier: $0.int32Value)?.bundleIdentifier
        }
    }

    private func showError(_ message: String) {
        NSLog("Chizu error: %@", message)
        let alert = NSAlert()
        alert.messageText = "Chizu could not open the link"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@main
struct ChizuMain {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty {
            do {
                try runCommand(arguments)
            } catch {
                FileHandle.standardError.write(Data("chizu: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }

        let app = NSApplication.shared
        let delegate = ChizuAppDelegate()
        app.delegate = delegate
        app.run()
    }

    private static func runCommand(_ arguments: [String]) throws {
        if arguments == ["--help"] || arguments == ["help"] {
            print("""
            chizu routes HTTP and HTTPS links using a JSONC configuration file.

            Usage:
              chizu --help
              chizu help
              chizu check URL [--source BUNDLE_ID] [--config FILE]
              chizu open URL [--source BUNDLE_ID] [--config FILE]
              chizu config init [--config FILE]
              chizu config check [--config FILE]
              chizu default status
              chizu default set

            Commands:
              check URL      Print the matching rule and destination without opening a browser.
              open URL       Open the URL in the selected browser and profile.
              config init    Create a minimal config file without replacing an existing file.
              config check   Check the JSONC configuration without opening a link.
              default status Show the current macOS HTTP and HTTPS handlers.
              default set    Set Chizu as the macOS HTTP and HTTPS handler.

            Options:
              --config FILE      Use another JSONC file instead of
                                 ~/.config/chizu/config.jsonc.
              --source BUNDLE_ID Pretend the URL came from this app, for example
                                 com.apple.mail. Useful for testing sourceBundleID rules.

            Configuration example (~/.config/chizu/config.jsonc):
              {
                "version": 1,
                // Fallback for links that match no rule.
                "default": { "bundleID": "com.apple.Safari" },
                // Rules run from top to bottom; the first match wins.
                "rules": [
                  {
                    "name": "Docs in Chrome",
                    "when": { "host": "docs.example.com" },
                    "destination": { "bundleID": "com.google.Chrome", "profile": "Work" }
                  }
                ]
              }

            Rule syntax:
              Each rule needs name, when, and destination. A nonempty when may use
              urlContains, urlRegex, host, pathPrefix, and sourceBundleID.
              All fields in one when must match; the first matching rule wins.
              urlRegex is an ICU expression matching the whole URL. If no rule
              matches, default is used. profile is a visible Dia or Chrome name.
              JSONC permits // and /* */ comments and trailing commas.

            Examples:
              chizu config init
              chizu config init --config ./config.jsonc
              chizu config check
              chizu check 'https://docs.example.com/guide'
              chizu check 'https://example.com/' --source com.apple.mail
              chizu check 'https://example.com/' --config ./config.jsonc
              chizu open 'https://docs.example.com/guide'
              chizu default status
              chizu default set

            check URL output with the example above:
              rule=Docs in Chrome app=com.google.Chrome profile=Work
              rule=default app=com.apple.Safari profile=-
            The dash means no profile was specified.
            The JSONC default is a fallback destination; default status/set manage
            the macOS default browser.

            v1.0.0 compatibility aliases:
              decide URL    = check URL
              check         = config check (when no URL is supplied)
              default-status = default status
              make-default   = default set
            """)
            return
        }
        if arguments == ["default", "status"] || arguments == ["default-status"] {
            for scheme in ["http", "https"] {
                print("\(scheme): \(defaultHandler(for: scheme) ?? "none")")
            }
            return
        }
        if arguments == ["default", "set"] || arguments == ["make-default"] {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.azu.chizu") != nil else {
                throw ChizuError.invalidConfiguration("install Chizu.app before setting it as the default browser")
            }
            var statuses: [String: OSStatus] = [:]
            for scheme in ["http", "https"] where defaultHandler(for: scheme) != "dev.azu.chizu" {
                statuses[scheme] = LSSetDefaultHandlerForURLScheme(scheme as CFString, "dev.azu.chizu" as CFString)
            }
            for scheme in ["http", "https"] where defaultHandler(for: scheme) != "dev.azu.chizu" {
                let status = statuses[scheme] ?? -1
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            print("Chizu is the default handler for http and https")
            return
        }
        if arguments.starts(with: ["config", "init"]) {
            let fileURL: URL
            let options = Array(arguments.dropFirst(2))
            if options.isEmpty {
                fileURL = RouteService.defaultConfigurationURL
            } else if options.count == 2, options[0] == "--config" {
                fileURL = URL(fileURLWithPath: options[1])
            } else {
                throw ChizuError.invalidConfiguration("config init accepts only --config FILE")
            }
            try Configuration.createStarter(at: fileURL)
            print("Created configuration at \(fileURL.path)")
            return
        }
        let isConfigurationCheck = arguments.starts(with: ["config", "check"])
        guard let command = arguments.first,
              ["check", "decide", "open"].contains(command) || isConfigurationCheck else {
            throw ChizuError.invalidConfiguration("unknown command; use --help")
        }
        var urlString: String?
        var sourceBundleID: String?
        var configurationURL: URL?
        var index = isConfigurationCheck ? 2 : 1
        while index < arguments.count {
            switch arguments[index] {
            case "--config":
                guard index + 1 < arguments.count else { throw ChizuError.invalidConfiguration("--config needs a file") }
                configurationURL = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--source":
                guard index + 1 < arguments.count else { throw ChizuError.invalidConfiguration("--source needs a bundle ID") }
                sourceBundleID = arguments[index + 1]
                index += 2
            default:
                guard urlString == nil else { throw ChizuError.invalidConfiguration("too many URL arguments") }
                urlString = arguments[index]
                index += 1
            }
        }

        if isConfigurationCheck || (command == "check" && urlString == nil && sourceBundleID == nil) {
            guard urlString == nil, sourceBundleID == nil else {
                throw ChizuError.invalidConfiguration("config check accepts only --config")
            }
            _ = try Configuration.load(from: configurationURL ?? RouteService.defaultConfigurationURL)
            print("Configuration is valid")
            return
        }

        guard let urlString, let url = URL(string: urlString) else {
            throw ChizuError.invalidConfiguration("a URL is required")
        }
        let decision = try RouteService.decide(url, sourceBundleID: sourceBundleID, configurationURL: configurationURL)
        if command == "check" || command == "decide" {
            print("rule=\(decision.ruleName ?? "default") app=\(decision.destination.bundleID) profile=\(decision.destination.profile ?? "-")")
        } else {
            try RouteService.open(url, decision: decision)
            print("Opened in \(decision.destination.bundleID)\(decision.destination.profile.map { " / \($0)" } ?? "")")
        }
    }

    private static func defaultHandler(for scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://example.com/"),
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return Bundle(url: applicationURL)?.bundleIdentifier
    }
}
