# Link routing design

[日本語](design.ja.md)

## About this document

This design implements the [link routing requirements](requirements.md) and the [Chizu product purpose](../../product.md) with a macOS app and file based configuration.

### Audience

People and agents who implement or change Chizu.

### Prerequisites

macOS URL handlers and browser bundle identifiers.

### Not covered here

The content of personal rules, and how a browser detects which of its links to hand off to Chizu.

## Implementation approach

Chizu is a macOS app that receives HTTP and HTTPS links. It reads the regular configuration file for each link, selects a destination with a rule evaluator, and explicitly opens the target browser. Specifying that app prevents Chizu, as the default browser, from invoking itself again.

The regular expression condition uses macOS `NSRegularExpression`. [Apple's documentation](https://developer.apple.com/documentation/foundation/nsregularexpression) describes its ICU syntax, which [Choosy's URL rules](https://choosy.app/help/settings/rules/urls) also use. Chizu anchors the expression to the full URL, so a partial match does not apply. Matching is case sensitive by default, and `(?i)` in the expression can ignore case. Chizu checks expressions while loading configuration and reports invalid ones with their rule names. Adding this condition avoids introducing an expression language runtime.

Dia profile routing uses the `profile` and `tab` objects exposed by Dia's AppleScript interface. Chizu creates a tab in the named profile, retrieves it again by ID, calls `focus` to select it, and then calls `activate` to bring Dia forward. Creating the tab alone could leave the previous tab visible, so Chizu also checks that the newly created tab is active. Personal profile names stay out of the public app. macOS Automation permission is required to control Dia.

Chrome profile routing reads the association between visible names and profile directories from Chrome's `Local State`. If exactly one name matches and its directory exists, Chizu passes that directory with `--profile-directory` and the URL as separate arguments to Chrome's executable. [Chromium's command line switch](https://chromium.googlesource.com/chromium/src/+/lkgr/chrome/common/chrome_switches.h) treats the value as a profile directory. Chizu does not open the link if the name is missing or duplicated, the state cannot be read, or the directory is missing. It invokes Chrome's executable separately from ordinary URL opening so the argument also reaches an already running Chrome instance. The public app contains no personal profile names.

Firefox profile routing reads the exact names and directories of traditional `about:profiles` entries from `~/Library/Application Support/Firefox/profiles.ini`. It checks that the name occurs once and its directory exists before passing `-P`, the name, `--new-tab`, and the URL as separate arguments to Firefox's executable. [Mozilla's profile service documentation](https://firefox-source-docs.mozilla.org/toolkit/profile/index.html) describes `profiles.ini`, and its [command line reference](https://firefox-source-docs.mozilla.org/browser/CommandLineParameters.html) documents these arguments. Chizu does not use `--no-remote`, which would prevent delivery to an already running instance. Firefox's newer Profiles menu uses a separate profile service, so its display names are outside this route's scope.

Chizu also registers the `chizu-http` and `chizu-https` URL schemes so that a userscript or extension in a browser can hand off a link. A browser cannot pass an HTTP or HTTPS link to the default browser itself, but it can open a URL with a scheme registered by another app. On receipt, Chizu removes the `chizu-` prefix once, ignoring letter case, and routes the result as if it had received that HTTP or HTTPS link. The result must still be HTTP or HTTPS, so `chizu-file:` and a repeated prefix such as `chizu-chizu-https:` fail. Which links a browser hands off is decided by the browser side; Chizu only routes what it receives. If a handed-off link's destination is the browser that sent it, Chizu still opens it there, so browser-side rules should not hand off links that the configuration routes back to the same browser.

Chizu uses the sending process of the received Apple Event as a source app condition when that process can be identified. URL conditions and the default destination still work when it cannot. [Hammerspoon's URL event implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/urlevent/liburlevent.m) also reads the sending process from Apple Events.

## Architecture and sequence diagram

The diagram shows the order of receiving, evaluating, and opening a link.

```mermaid
sequenceDiagram
    participant Mac as macOS
    participant App as Chizu
    participant Config as Configuration file
    participant Browser as Target browser
    Mac->>App: Web link and source when available
    App->>Config: Read and validate
    Config-->>App: Default and ordered rules
    App->>App: Select first matching destination
    App->>Browser: URL and profile when specified
```

## Data model and ER diagram

Chizu reads `version`, `default`, and `rules` from JSONC. It accepts `//` and `/* ... */` comments and trailing commas. It removes only comments and trailing commas, preserving characters inside strings, before validating the result as JSON. Each `rule` contains `name`, `when`, and `destination`. A `when` object may combine full URL containment or a regular expression, exact host matching, path prefix matching, and a source app identifier. A `destination` contains a bundle identifier and an optional Dia, Chrome, or traditional Firefox profile name. The data is a simple ordered nested structure, so an ER diagram is unnecessary.

## APIs and interfaces

The usual configuration path is `~/.config/chizu/config.jsonc`. It may be a symbolic link to a Git managed file. `config init` creates a built-in minimal JSONC file with Safari as the fallback and an empty rule list, without a network request. It creates parent directories and opens the destination exclusively with owner-only file permissions, so an existing file or symbolic link is never replaced. `--config FILE` selects another path for initialization, checking, or previewing.

`check URL` and `open URL` also accept `chizu-http` and `chizu-https` links and remove the prefix in the same way as the app. `config check` checks configuration, and `check URL` previews a result without opening the link. `check` requires a URL. `--source` supplies a source app identifier for a CLI preview or manual open. `default status` reads the macOS HTTP and HTTPS handlers, while `default set` changes both to Chizu. The JSONC `default` remains the fallback destination for unmatched links, not the macOS handler. The CLI accepts only the command forms shown in `--help`; earlier names are not kept as aliases. The `--help` output lists each command's form and purpose, the JSONC keys and matching order, and copyable examples. It does not read the configuration file. The README includes a complete generic JSONC example and explains the `check URL` output. The app uses the same evaluator when receiving links.

Browsers are selected by bundle identifier. Without a profile, Chizu passes the URL to macOS `open` with the target app specified. For Dia, it passes the profile name and URL as arguments to a fixed AppleScript. For Chrome, it resolves the visible name from saved profile information and passes the selected directory as a launch argument. For Firefox, it checks the `profiles.ini` entry and passes its name as a launch argument. URLs and names are not interpreted as shell text.

## External service integration

No network service is required. Dia's AppleScript interface and Chrome's and Firefox's saved profile information are read from the user's Mac. A missing app, missing required permission, or profile that cannot be identified causes an error.

## Data handling

Chizu reads the configuration file for each link and keeps it only in the process. It uses the received URL and source app for routing without storing a history. Only a generic configuration example belongs in the public repository.

## Authentication and authorization

There is no account authentication. The user grants macOS Automation permission for Dia control; Chizu does not bypass it. Reading Chrome's `Local State` or Firefox's `profiles.ini` may require macOS permission to access another app's data, shown under Files and Folders in System Settings. Without access, Chizu reports that it could not read the profiles and does not open the link. macOS records permissions for the app's code signature, so a build signed differently may need to be allowed again.

## Security considerations

Chizu accepts only HTTP and HTTPS URLs, after removing the `chizu-` prefix from a handed-off link, and validates required configuration fields and destinations. It passes URLs and profile names as separate process arguments, not shell commands.

## Deployment notes

After installing Chizu, the user sets it as the macOS default browser. The existing default browser remains until that change is made.

## Alternatives considered

### Switching Dia profiles with a keyboard shortcut

[Dia Router](https://github.com/jdsimcoe/dia-router) switches profiles with keyboard shortcuts before opening a URL. That depends on shortcut settings, Accessibility permission, and the timing of the switch. Chizu uses Dia's AppleScript interface instead.

### Passing the URL as a query parameter

A form such as `chizu://open?url=...` requires percent-encoding the whole URL. Chrome's [`declarativeNetRequest`](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest) can build a redirect only by regular expression substitution and cannot encode the captured URL, so an unencoded `&` or `#` in the original link would break the parameter. Replacing only the scheme needs no encoding and keeps the original URL readable after the prefix.

## Open questions

None.
