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
    let emptyRule = Configuration(default: Destination(bundleID: "com.apple.Safari"),
                                  rules: [Rule(name: "empty", when: Match(), destination: Destination(bundleID: "com.apple.Safari"))])
    #expect(throws: ChizuError.self) { try emptyRule.validate() }
    #expect(throws: ChizuError.self) {
        try Configuration(default: Destination(bundleID: "com.apple.Safari"), rules: [])
            .decide(#require(URL(string: "file:///tmp/test")))
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
