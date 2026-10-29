# chīzu 🧀

Chizu is a small macOS default browser that sends links to a configured browser and, for Dia, Google Chrome, or Firefox, a named profile. It reads rules from a JSONC file on every link. There is no browser picker or settings window.

## Install

Requires an Apple Silicon Mac with macOS 14 or later. The release download does not require Xcode or a signing certificate. Quit any running copy of Chizu, then run:

```sh
curl -fL https://github.com/azu/chizu/releases/latest/download/chizu-macos-arm64.zip -o "$TMPDIR/chizu-macos-arm64.zip" &&
curl -fL https://github.com/azu/chizu/releases/latest/download/chizu-macos-arm64.zip.sha256 -o "$TMPDIR/chizu-macos-arm64.zip.sha256" &&
(cd "$TMPDIR" && shasum -a 256 -c chizu-macos-arm64.zip.sha256) &&
mkdir -p "$HOME/Applications" &&
ditto -x -k "$TMPDIR/chizu-macos-arm64.zip" "$HOME/Applications" &&
xattr -dr com.apple.quarantine "$HOME/Applications/Chizu.app" &&
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Chizu.app" &&
"$HOME/Applications/Chizu.app/Contents/MacOS/chizu" default set
```

The commands check the ZIP against its published SHA-256 checksum and install `~/Applications/Chizu.app`. The app uses a fixed self-signed certificate and is not notarized. The `xattr` command removes the downloaded app's quarantine attribute so macOS can open it. Installing over a locally signed copy may require you to allow Chizu to control Dia again.

## Set up routing

Create a starter config with Safari as the fallback and no rules:

```sh
~/Applications/Chizu.app/Contents/MacOS/chizu config init
```

Edit `~/.config/chizu/config.jsonc` with your browsers, profiles, and rules. The command above leaves an existing file or symbolic link untouched, so you can keep this file in your dotfiles repository. See the [full example](examples/config.jsonc) for more rule types.

Check the config and preview where one of your links would go:

```sh
~/Applications/Chizu.app/Contents/MacOS/chizu config check
~/Applications/Chizu.app/Contents/MacOS/chizu check 'https://example.com/'
```

`config check` reports config errors. `check URL` prints the matching rule, browser, and profile without opening the link. Replace the example URL with a link you actually use. Then set Chizu as the macOS default browser and confirm its status:

```sh
~/Applications/Chizu.app/Contents/MacOS/chizu default set
~/Applications/Chizu.app/Contents/MacOS/chizu default status
```

`default set` changes the macOS HTTP and HTTPS handlers. It is separate from the `default` destination in the config file, which handles links that match no rule.

### Configure with an AI

Copy this prompt and add your routing preferences at the end:

```text
Set up Chizu on this Mac. First run
~/Applications/Chizu.app/Contents/MacOS/chizu --help and follow its syntax.

Read ~/.config/chizu/config.jsonc. If it does not exist, run
~/Applications/Chizu.app/Contents/MacOS/chizu config init to create it.
Ask me for any routing details you cannot determine. Keep my personal rules
in my config file, outside the public Chizu repository.

Run ~/Applications/Chizu.app/Contents/MacOS/chizu config check. Then run
~/Applications/Chizu.app/Contents/MacOS/chizu check URL for links covering
each rule and the fallback. Show me the results. If the checks pass, run
~/Applications/Chizu.app/Contents/MacOS/chizu default set and
~/Applications/Chizu.app/Contents/MacOS/chizu default status.

Ask the user about the routing you want to set up.
```

Run `~/Applications/Chizu.app/Contents/MacOS/chizu --help` for the full command and config reference.

The first Dia route may cause macOS to ask for Automation permission. Allow Chizu to control Dia. If the permission is refused or the named profile does not exist, Chizu reports an error instead of opening the link in a different profile. A Chrome profile route reads Chrome's `Local State` file, which macOS treats as another app's data. If Chizu reports `Could not read Chrome profiles from Local State`, open System Settings > Privacy & Security > Files and Folders and allow Chizu to access Google Chrome.

A Firefox profile route reads Firefox's `profiles.ini` file. If Chizu reports `Could not read Firefox profiles from profiles.ini`, allow Chizu to access Firefox under System Settings > Privacy & Security > Files and Folders. Firefox profiles here use the names shown in `about:profiles`; names in Firefox's newer Profiles menu use a separate system and are not supported. [Mozilla's profile service documentation](https://firefox-source-docs.mozilla.org/toolkit/profile/index.html) explains the distinction.

You can test one URL without changing the default browser:

```sh
~/Applications/Chizu.app/Contents/MacOS/chizu open 'https://team.example.com/projects/123'
```

## Configuration

The JSON object has a `version`, one `default` destination, and an ordered `rules` array. Each rule has a `name`, a `when` object, and a `destination`. The first matching rule wins. All fields in one `when` object must match.

For example, save this as `~/.config/chizu/config.jsonc` and replace the example hosts and profile names with your own:

```jsonc
{
  "version": 1,
  // Fallback for links that match no rule; separate from the macOS default browser.
  "default": { "bundleID": "com.apple.Safari" },
  // Rules run from top to bottom. The first match wins.
  "rules": [
    {
      "name": "Docs in Chrome",
      "when": { "host": "docs.example.com" },
      // Use the profile name shown in Chrome.
      "destination": { "bundleID": "com.google.Chrome", "profile": "Work" }
    },
    {
      "name": "Team links",
      // Both the exact host and path prefix must match.
      "when": { "host": "team.example.com", "pathPrefix": "/projects" },
      "destination": { "bundleID": "company.thebrowser.dia", "profile": "Team" }
    },
    {
      "name": "Reading in Firefox",
      "when": { "host": "reading.example.com" },
      // Use the name shown in Firefox about:profiles.
      "destination": { "bundleID": "org.mozilla.firefox", "profile": "Reading" }
    },
    {
      "name": "Calendar links from Mail",
      // This rule needs macOS to identify Mail as the sending app.
      "when": { "urlContains": "calendar", "sourceBundleID": "com.apple.mail" },
      "destination": { "bundleID": "com.google.Chrome" }
    },
  ],
}
```

The first rule sends every URL on `docs.example.com` to the Chrome profile named `Work`. The second requires both the exact host and a path starting with `/projects` before selecting Dia's `Team` profile. The third uses the Firefox `about:profiles` name `Reading`. The fourth applies only when the URL contains `calendar` and the sending app is Mail. All other links use Safari. A `when` object must contain at least one condition; rules are checked from top to bottom.

For a `sourceBundleID` rule, preview the route with `check URL --source BUNDLE_ID`. For example, `chizu check 'https://calendar.example.com/' --source com.apple.mail` simulates a link sent by Mail. Without `--source`, no sending app is assumed during a CLI check.

| Field in `when` | Match |
| --- | --- |
| `urlContains` | Text anywhere in the full URL, ignoring letter case |
| `urlRegex` | ICU regular expression matching the whole URL; case-sensitive unless the pattern uses `(?i)` |
| `host` | Exact host, ignoring letter case |
| `pathPrefix` | Start of the path, respecting letter case |
| `sourceBundleID` | Bundle ID of the sending app, when macOS provides one |

A destination needs the browser's `bundleID`. These macOS examples can be copied into the `default` or a rule's `destination` above:

| Browser | `bundleID` | Chizu `profile` support |
| --- | --- | --- |
| Safari | `com.apple.Safari` | — |
| Google Chrome | `com.google.Chrome` | Yes |
| Firefox | `org.mozilla.firefox` | Yes, names from `about:profiles` |
| Microsoft Edge | `com.microsoft.edgemac` | — |
| Brave | `com.brave.Browser` | — |
| Dia | `company.thebrowser.dia` | Yes |

The IDs except Edge were checked in the installed apps' `Contents/Info.plist`; [Microsoft documents Edge's ID](https://learn.microsoft.com/en-us/entra/identity/devices/troubleshoot-mac-sso-extension-plugin). An app's `CFBundleIdentifier` in that file is its bundle ID, as [Apple documents](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html). Check the installed app when using another edition or browser.

A `profile` can be added for Dia, Google Chrome, or Firefox. Use the exact profile name shown in the browser; for Firefox, use the name in `about:profiles`. For Chrome and Firefox, Chizu checks the local profile list before opening the link; a missing or duplicate name fails instead of choosing another profile. The source app may be unavailable for some links; those rules then do not match. Direct links opened inside a browser do not normally pass through the macOS default browser; see [Hand off links from a browser](#hand-off-links-from-a-browser). Chizu reads the file again for each new link, so editing does not require a restart.

The configuration uses JSONC: `//` and `/* ... */` comments and trailing commas are accepted. Strings and keys still use JSON double quotes. An invalid regular expression fails validation instead of silently skipping a rule. For example, `"urlRegex": "(?i).*\\.pdf"` matches a URL ending in `.pdf`, ignoring letter case; a URL with a query string after `.pdf` does not match. Chizu accepts trailing commas as an extension permitted by the [JSONC specification](https://jsonc.org/).

The path can be overridden for CLI checks with `--config FILE`. A missing or invalid config, missing browser, or missing profile is reported as an error. Chizu never silently falls back to another browser or profile.

### Hand off links from a browser

A browser opens its own links without asking macOS, so Chizu cannot see them. A userscript or browser extension can hand a link to Chizu by replacing `http:` or `https:` with `chizu-http:` or `chizu-https:`. Chizu removes the `chizu-` prefix once and routes the link with the same rules:

```sh
~/Applications/Chizu.app/Contents/MacOS/chizu check 'chizu-https://team.example.com/projects/123'
```

Only replace the scheme; the rest of the URL is not encoded. Chizu does not decide which links a browser hands off. If a handed-off link is routed back to the browser that sent it, Chizu opens it there, so hand off only links that your configuration sends elsewhere. The browser may ask for permission before it opens Chizu.

## Development

To build and install from source instead, use macOS 14 or later with Xcode Command Line Tools:

```sh
scripts/install-app.sh
```

This script installs `~/Applications/Chizu.app` and signs it ad hoc by default. For a stable local signature, set `CHIZU_SIGNING_IDENTITY` to a code signing identity before running the script.

```sh
swift test
./bin/sdev lint
```

The [specifications](docs/README.md) explain the behavior and implementation. Chizu uses macOS URL handling documented by [Apple](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)). Dia profile routing uses Dia's installed AppleScript dictionary. [Dia's release notes](https://www.diabrowser.com/release-notes/1-22-0-dont-think) document profile switching, while [Dia Router](https://github.com/jdsimcoe/dia-router) illustrates a different shortcut based approach.

## Releases

`VERSION` is the release version. The **Create Release PR** workflow bumps it and opens a PR. Merging that PR creates the matching `v` tag, runs Swift tests, signs the Apple Silicon app, and publishes `chizu-macos-arm64.zip` with a SHA-256 file. For the first release, the matching tag can be pushed directly after committing `VERSION`. An existing tag can be retried with the **Release** workflow. The release PR body becomes the release notes; a release without a matching PR uses GitHub's generated notes.

The release certificate is fixed across versions so macOS can recognize the same signing identity. To initialize it once on the release author's Mac, run:

```sh
bash scripts/setup-release-signing.sh
bash scripts/trust-release-certificate.sh
```

Commit only the generated `config/release-signing.json`. Back up the ignored `.release-signing/` directory securely. Before using the workflows, register `CODE_SIGN_P12_BASE64` from `base64 < .release-signing/code-signing.p12` and `CODE_SIGN_P12_PASSWORD` from `.release-signing/p12-password` as GitHub Actions secrets. Do not paste either value into an issue, PR, or log. Locally, `bash scripts/package-release.sh` creates the same ZIP and checksum after the certificate is trusted.

The ZIP is signed with the fixed Chizu release certificate. The current pipeline does not notarize the app or provide in-app updates. Installing it over a build signed with another certificate may require macOS Automation permission for Dia, and access to Google Chrome's data, to be granted again. If the Chrome entry in Files and Folders turns off again on the next link, it still belongs to the old build. Run `tccutil reset SystemPolicyAppDataDetailed dev.azu.chizu` to remove it. The next Chrome route is denied once and macOS shows a notification; allow Chizu from that notification or from Files and Folders.

## License

Chizu is available under the [MIT License](LICENSE).

Inspired by [Choosy](https://choosy.app/).
