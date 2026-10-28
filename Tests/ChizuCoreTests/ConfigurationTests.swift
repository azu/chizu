import Foundation
import Testing
@testable import ChizuCore

@Test func firstMatchingRuleAndDefault() throws {
    let configuration = Configuration(
        default: Destination(bundleID: Configuration.diaBundleID, profile: "Personal"),
        rules: [
            Rule(name: "work", when: Match(urlContains: "work"),
                 destination: Destination(bundleID: Configuration.diaBundleID, profile: "Work")),
            Rule(name: "other", when: Match(host: "example.com"),
                 destination: Destination(bundleID: "com.apple.Safari")),
        ]
    )
    try configuration.validate()
    let work = try configuration.decide(#require(URL(string: "https://example.com/path?site=Work")))
    #expect(work.ruleName == "work")
    #expect(work.destination.profile == "Work")
    let fallback = try configuration.decide(#require(URL(string: "https://elsewhere.example/")))
    #expect(fallback.ruleName == nil)
    #expect(fallback.destination.profile == "Personal")
}

@Test func createsStarterConfigurationWithoutReplacingExistingPaths() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = directory.appendingPathComponent("nested/config.jsonc")

    try Configuration.createStarter(at: config)
    let starter = try Configuration.load(from: config)
    #expect(starter.default == Destination(bundleID: "com.apple.Safari"))
    #expect(starter.rules.isEmpty)
    let attributes = try FileManager.default.attributesOfItem(atPath: config.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    let original = try Data(contentsOf: config)
    #expect(throws: ChizuError.configurationAlreadyExists(config.path)) {
        try Configuration.createStarter(at: config)
    }
    #expect(try Data(contentsOf: config) == original)

    let link = directory.appendingPathComponent("linked.jsonc")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config)
    #expect(throws: ChizuError.configurationAlreadyExists(link.path)) {
        try Configuration.createStarter(at: link)
    }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == config.path)
    #expect(try Data(contentsOf: config) == original)

    let danglingLink = directory.appendingPathComponent("dangling.jsonc")
    let missingTarget = directory.appendingPathComponent("missing.jsonc")
    try FileManager.default.createSymbolicLink(at: danglingLink, withDestinationURL: missingTarget)
    #expect(throws: ChizuError.configurationAlreadyExists(danglingLink.path)) {
        try Configuration.createStarter(at: danglingLink)
    }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: danglingLink.path) == missingTarget.path)
    #expect(!FileManager.default.fileExists(atPath: missingTarget.path))
}

@Test func combinedConditionsAndUnknownSource() throws {
    let configuration = Configuration(
        default: Destination(bundleID: "com.apple.Safari"),
        rules: [
            Rule(name: "from mail", when: Match(host: "example.com", pathPrefix: "/team", sourceBundleID: "com.apple.mail"),
                 destination: Destination(bundleID: Configuration.diaBundleID, profile: "Team")),
        ]
    )
    let url = try #require(URL(string: "https://EXAMPLE.com/team/page"))
    #expect(try configuration.decide(url).ruleName == nil)
    #expect(try configuration.decide(url, sourceBundleID: "com.apple.mail").ruleName == "from mail")
    #expect(try configuration.decide(#require(URL(string: "https://example.com/other")), sourceBundleID: "com.apple.mail").ruleName == nil)
}

@Test func rejectsInvalidOrUnsafeConfiguration() throws {
    let bad = Configuration(default: Destination(bundleID: "dev.azu.chizu"), rules: [])
    #expect(throws: ChizuError.self) { try bad.validate() }
    let profileInSafari = Configuration(default: Destination(bundleID: "com.apple.Safari", profile: "Home"), rules: [])
    #expect(throws: ChizuError.self) { try profileInSafari.validate() }
    let profileInChrome = Configuration(default: Destination(bundleID: Configuration.chromeBundleID, profile: "Work"), rules: [])
    try profileInChrome.validate()
    let profileInFirefox = Configuration(default: Destination(bundleID: Configuration.firefoxBundleID, profile: "Reading"), rules: [])
    try profileInFirefox.validate()
    let emptyRule = Configuration(default: Destination(bundleID: "com.apple.Safari"),
                                  rules: [Rule(name: "empty", when: Match(), destination: Destination(bundleID: "com.apple.Safari"))])
    #expect(throws: ChizuError.self) { try emptyRule.validate() }
    #expect(throws: ChizuError.self) {
        try Configuration(default: Destination(bundleID: "com.apple.Safari"), rules: [])
            .decide(#require(URL(string: "file:///tmp/test")))
    }
}

@Test func resolvesFirefoxProfileByAboutProfilesNameWithoutFallback() throws {
    let firefoxDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaultDirectory = firefoxDirectory.appendingPathComponent("Profiles/abcd.default-release")
    let namedDirectory = firefoxDirectory.appendingPathComponent("Profiles/efgh.reading")
    try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: namedDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: firefoxDirectory) }
    let profilesINI = firefoxDirectory.appendingPathComponent("profiles.ini")
    let contents = """
        [General]
        StartWithLastProfile=1

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/abcd.default-release
        Default=1

        [Install12345]
        Default=Profiles/abcd.default-release

        [Profile1]
        Name=Reading
        IsRelative=1
        Path=Profiles/efgh.reading
        """
    try Data(contents.utf8).write(to: profilesINI)

    try FirefoxProfileResolver.validate(named: "Reading", firefoxDirectory: firefoxDirectory)
    #expect(throws: FirefoxProfileError.profileNotFound("READING")) {
        try FirefoxProfileResolver.validate(named: "READING", firefoxDirectory: firefoxDirectory)
    }

    try Data((contents + "\n[Profile2]\nName=Reading\nIsRelative=1\nPath=Profiles/abcd.default-release\n").utf8)
        .write(to: profilesINI)
    #expect(throws: FirefoxProfileError.ambiguousProfile("Reading")) {
        try FirefoxProfileResolver.validate(named: "Reading", firefoxDirectory: firefoxDirectory)
    }

    try Data(contents.utf8).write(to: profilesINI)
    try FileManager.default.removeItem(at: namedDirectory)
    #expect(throws: FirefoxProfileError.profileDirectoryMissing("Reading")) {
        try FirefoxProfileResolver.validate(named: "Reading", firefoxDirectory: firefoxDirectory)
    }

    try Data("invalid".utf8).write(to: profilesINI)
    #expect(throws: FirefoxProfileError.unreadableProfiles) {
        try FirefoxProfileResolver.validate(named: "Reading", firefoxDirectory: firefoxDirectory)
    }
}

@Test func resolvesChromeProfileByVisibleNameWithoutFallback() throws {
    let userData = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: userData.appendingPathComponent("Default"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: userData.appendingPathComponent("Profile 4"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: userData) }
    let localState = userData.appendingPathComponent("Local State")
    let profiles: [String: Any] = [
        "profile": ["info_cache": [
            "Default": ["name": "Personal"],
            "Profile 4": ["name": "Work"],
        ]],
    ]
    try JSONSerialization.data(withJSONObject: profiles).write(to: localState)

    #expect(try ChromeProfileResolver.directory(named: "Work", userDataDirectory: userData) == "Profile 4")
    #expect(throws: ChromeProfileError.profileNotFound("work")) {
        try ChromeProfileResolver.directory(named: "work", userDataDirectory: userData)
    }

    let duplicate: [String: Any] = [
        "profile": ["info_cache": [
            "Default": ["name": "Work"],
            "Profile 4": ["name": "Work"],
        ]],
    ]
    try JSONSerialization.data(withJSONObject: duplicate).write(to: localState)
    #expect(throws: ChromeProfileError.ambiguousProfile("Work")) {
        try ChromeProfileResolver.directory(named: "Work", userDataDirectory: userData)
    }

    try FileManager.default.removeItem(at: userData.appendingPathComponent("Profile 4"))
    try JSONSerialization.data(withJSONObject: profiles).write(to: localState)
    #expect(throws: ChromeProfileError.profileDirectoryMissing("Work")) {
        try ChromeProfileResolver.directory(named: "Work", userDataDirectory: userData)
    }
    try Data("{".utf8).write(to: localState)
    #expect(throws: ChromeProfileError.unreadableProfiles) {
        try ChromeProfileResolver.directory(named: "Work", userDataDirectory: userData)
    }
}

@Test func rejectsMisspelledProfileKey() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let text = """
        {"version":1,"default":{"bundleID":"company.thebrowser.dia","profil":"Team"},"rules":[]}
        """
    try Data(text.utf8).write(to: file)
    #expect(throws: ChizuError.self) { try Configuration.load(from: file) }
}

@Test func regularExpressionMatchesTheWholeURL() throws {
    let configuration = Configuration(
        default: Destination(bundleID: "com.apple.Safari"),
        rules: [Rule(name: "regex", when: Match(urlRegex: #"https://example\.com/(a|ab)"#),
                     destination: Destination(bundleID: Configuration.diaBundleID, profile: "Personal"))]
    )
    try configuration.validate()
    #expect(try configuration.decide(#require(URL(string: "https://example.com/ab"))).ruleName == "regex")
    #expect(try configuration.decide(#require(URL(string: "https://example.com/abc"))).ruleName == nil)
    #expect(try configuration.decide(#require(URL(string: "https://other.example.com/ab"))).ruleName == nil)
}

@Test func jsoncCommentsTrailingCommasAndEscapedStrings() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonc")
    defer { try? FileManager.default.removeItem(at: file) }
    let contents = #"""
        {
          // A URL string may contain // without starting a comment.
          "version": 1,
          "default": { "bundleID": "com.apple.Safari", },
          "rules": [
            {
              "name": "PDF",
              "when": { "urlRegex": "(?i)https://example\\.com/.*\\.pdf", },
              /* Route reports to Dia. */
              "destination": { "bundleID": "company.thebrowser.dia", "profile": "Personal", },
            },
          ],
        }
        """#
    try Data(contents.utf8).write(to: file)
    let configuration = try Configuration.load(from: file)
    #expect(try configuration.decide(#require(URL(string: "https://example.com/report.PDF"))).ruleName == "PDF")
    #expect(try configuration.decide(#require(URL(string: "https://example.com/report.pdf?download=1"))).ruleName == nil)
}

@Test func rejectsInvalidRegexAndUnterminatedComment() throws {
    let invalidRegex = Configuration(default: Destination(bundleID: "com.apple.Safari"),
                                     rules: [Rule(name: "broken", when: Match(urlRegex: "["),
                                                  destination: Destination(bundleID: "com.apple.Safari"))])
    #expect(throws: ChizuError.self) { try invalidRegex.validate() }

    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonc")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("{ /* not closed".utf8).write(to: file)
    #expect(throws: ChizuError.self) { try Configuration.load(from: file) }
}

@Test func handedOffLinksAreRoutedLikeWebLinks() throws {
    let configuration = Configuration(
        default: Destination(bundleID: "com.apple.Safari"),
        rules: [
            Rule(name: "team", when: Match(host: "team.example.com", pathPrefix: "/projects"),
                 destination: Destination(bundleID: Configuration.chromeBundleID, profile: "Work")),
        ]
    )
    let handedOff = try HandoffURL.unwrap(#require(URL(string: "chizu-https://team.example.com/projects/1?a=1&b=2#top")))
    #expect(handedOff.absoluteString == "https://team.example.com/projects/1?a=1&b=2#top")
    #expect(try configuration.decide(handedOff).ruleName == "team")
    let upperCase = try HandoffURL.unwrap(#require(URL(string: "CHIZU-HTTP://example.com/")))
    #expect(upperCase.absoluteString == "HTTP://example.com/")
    #expect(try configuration.decide(upperCase).ruleName == nil)
    let plain = try #require(URL(string: "https://example.com/"))
    #expect(try HandoffURL.unwrap(plain) == plain)
}

@Test func handedOffLinksMustStillBeWebLinks() throws {
    let configuration = Configuration(default: Destination(bundleID: "com.apple.Safari"), rules: [])
    for value in ["chizu-file:///etc/hosts", "chizu-chizu-https://example.com/", "chizu-https:"] {
        let url = try HandoffURL.unwrap(#require(URL(string: value)))
        #expect(throws: ChizuError.self) { try configuration.decide(url) }
    }
}
