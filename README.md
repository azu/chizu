# chīzu 🧀

Chizu is a small macOS default browser that sends links to a configured browser and, for Dia or Google Chrome, a named profile. It reads rules from a JSONC file on every link. There is no browser picker or settings window.

## Install

Requires an Apple Silicon Mac with macOS 14 or later. The release download does not require Xcode or a signing certificate. Quit any running copy of Chizu, then run:

```sh
curl -fL https://github.com/azu/chizu/releases/latest/download/chizu-macos-arm64.zip -o "$TMPDIR/chizu-macos-arm64.zip" &&
curl -fL https://github.com/azu/chizu/releases/latest/download/chizu-macos-arm64.zip.sha256 -o "$TMPDIR/chizu-macos-arm64.zip.sha256" &&
(cd "$TMPDIR" && shasum -a 256 -c chizu-macos-arm64.zip.sha256) &&
mkdir -p "$HOME/Applications" &&
ditto -x -k "$TMPDIR/chizu-macos-arm64.zip" "$HOME/Applications" &&
xattr -dr com.apple.quarantine "$HOME/Applications/Chizu.app" &&
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Chizu.app"
```

The commands check the ZIP against its published SHA-256 checksum and install `~/Applications/Chizu.app`. The app uses a fixed self-signed certificate and is not notarized. The `xattr` command removes the downloaded app's quarantine attribute so macOS can open it. Installing over a locally signed copy may require you to allow Chizu to control Dia again.

Create `~/.config/chizu/config.jsonc` from [the example](examples/config.jsonc), then edit the destination app IDs and profile names. This is an ordinary file and can be a symbolic link into a dotfiles repository. Keep personal rules out of the public Chizu repository.

Check the file and preview the default, a URL rule, and a source-app rule before switching the default browser:

```sh
~/Applications/Chizu.app/Contents/MacOS/chizu validate
~/Applications/Chizu.app/Contents/MacOS/chizu decide 'https://example.com/'
~/Applications/Chizu.app/Contents/MacOS/chizu decide 'https://team.example.com/projects/123'
~/Applications/Chizu.app/Contents/MacOS/chizu decide 'https://calendar.example.com/' --source com.apple.mail
```

`validate` checks the JSONC file and rule expressions. `decide` reads the file and prints which rule, app, and profile would be used; it does not open a browser or change the macOS default. With the example configuration below, the three URLs print `rule=default app=com.apple.Safari profile=-`, `rule=Team links app=company.thebrowser.dia profile=Team`, and `rule=Calendar links from Mail app=com.google.Chrome profile=-`, respectively. The dash means no profile was set. `--source` supplies a simulated sending app for testing `sourceBundleID` rules; omit it to see the result when no sending app is known. Run `~/Applications/Chizu.app/Contents/MacOS/chizu --help` for all command forms and examples.

Set Chizu as the default handler for HTTP and HTTPS, then inspect the result:

```sh
~/Applications/Chizu.app/Contents/MacOS/chizu make-default
~/Applications/Chizu.app/Contents/MacOS/chizu default-status
```

The first Dia route may cause macOS to ask for Automation permission. Allow Chizu to control Dia. If the permission is refused or the named profile does not exist, Chizu reports an error instead of opening the link in a different profile. You can test one URL without changing the default browser:

```sh
~/Applications/Chizu.app/Contents/MacOS/chizu open 'https://team.example.com/projects/123'
```

## Configuration

The JSON object has a `version`, one `default` destination, and an ordered `rules` array. Each rule has a `name`, a `when` object, and a `destination`. The first matching rule wins. All fields in one `when` object must match.

For example, save this as `~/.config/chizu/config.jsonc` and replace the example hosts and profile names with your own:

```jsonc
{
  "version": 1,
  "default": { "bundleID": "com.apple.Safari" },
  "rules": [
    {
      "name": "Docs in Chrome",
      "when": { "host": "docs.example.com" },
      "destination": { "bundleID": "com.google.Chrome", "profile": "Work" }
    },
    {
      "name": "Team links",
      "when": { "host": "team.example.com", "pathPrefix": "/projects" },
      "destination": { "bundleID": "company.thebrowser.dia", "profile": "Team" }
    },
    {
      "name": "Calendar links from Mail",
      "when": { "urlContains": "calendar", "sourceBundleID": "com.apple.mail" },
      "destination": { "bundleID": "com.google.Chrome" }
    },
  ],
}
```

The first rule sends every URL on `docs.example.com` to the Chrome profile named `Work`. The second requires both the exact host and a path starting with `/projects` before selecting Dia's `Team` profile. The third applies only when the URL contains `calendar` and the sending app is Mail. All other links use Safari. A `when` object must contain at least one condition; rules are checked from top to bottom.

| Field in `when` | Match |
| --- | --- |
| `urlContains` | Text anywhere in the full URL, ignoring letter case |
| `urlRegex` | ICU regular expression matching the whole URL; case-sensitive unless the pattern uses `(?i)` |
| `host` | Exact host, ignoring letter case |
| `pathPrefix` | Start of the path, respecting letter case |
| `sourceBundleID` | Bundle ID of the sending app, when macOS provides one |

A destination needs `bundleID`. A `profile` can be added for Dia (`company.thebrowser.dia`) or Google Chrome (`com.google.Chrome`). Use the profile name shown in the browser, with matching letter case. For Chrome, Chizu finds that name in Chrome's local profile list and passes its directory to Chrome; a missing or duplicate name fails instead of choosing another profile. The source app may be unavailable for some links; those rules then do not match. Direct links opened inside a browser do not normally pass through the macOS default browser. Chizu reads the file again for each new link, so editing does not require a restart.

The configuration uses JSONC: `//` and `/* ... */` comments and trailing commas are accepted. Strings and keys still use JSON double quotes. An invalid regular expression fails validation instead of silently skipping a rule. For example, `"urlRegex": "(?i).*\\.pdf"` matches a URL ending in `.pdf`, ignoring letter case; a URL with a query string after `.pdf` does not match. Chizu accepts trailing commas as an extension permitted by the [JSONC specification](https://jsonc.org/).

The path can be overridden for CLI checks with `--config FILE`. A missing or invalid config, missing browser, or missing profile is reported as an error. Chizu never silently falls back to another browser or profile.

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

The ZIP is signed with the fixed Chizu release certificate. The current pipeline does not notarize the app or provide in-app updates. Installing it over a build signed with another certificate may require macOS Automation permission for Dia to be granted again.

## License

Chizu is available under the [MIT License](LICENSE).

Inspired by [Choosy](https://choosy.app/).
