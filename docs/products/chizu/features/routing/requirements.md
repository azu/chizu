# Link routing

[日本語](requirements.ja.md)

## About this document

This feature chooses where to open a web link received by [Chizu](../../product.md), according to the user's configuration.

### Scope

It covers HTTP and HTTPS links and links handed off from a browser with the `chizu-http` and `chizu-https` schemes; conditions on full URL text, regular expressions, host, path, and an identified source app; browser and Dia, Chrome, or Firefox `about:profiles` profile destinations; creating and editing file based configuration; previewing the routing result; and inspecting or setting the macOS default browser.

### Out of scope

It does not cover a browser selection screen, Firefox profiles created through its newer Profiles menu, detecting or intercepting links opened directly inside a browser, Choosy specific APIs, or migration of invalid Choosy rules.

## User stories

### Open matching links in the configured destination

As a user, I want links to be routed automatically based on their URL or source app so that I do not need to choose the destination again.

**Acceptance criteria:**

Scenario: Open a link containing configured text in a specified Dia profile

- Given: A rule checks for text anywhere in the full URL and names an existing Dia profile.
- When: A matching HTTP or HTTPS link is opened through Chizu.
- Then: A tab for the link is created and selected in that Dia profile, and Dia comes to the foreground.

Scenario: Open a link matching a host and path in the specified browser

- Given: A rule contains both a host and a path condition.
- When: A link matches both conditions and is opened through Chizu.
- Then: The link opens in the specified browser.

Scenario: Open a link in a specified Chrome profile

- Given: The configuration names a Chrome profile as shown in Chrome, and exactly one profile has that name.
- When: A matching link is opened through Chizu.
- Then: The link opens in that Chrome profile.

Scenario: Open a link in a specified Firefox profile

- Given: The configuration names an existing profile exactly as shown in Firefox `about:profiles`.
- When: A matching link is opened through Chizu.
- Then: The link opens in that Firefox profile, including when another Firefox profile is already running.

Scenario: Open a link matching a regular expression in the specified browser

- Given: A rule contains a regular expression that matches the full URL.
- When: A matching HTTP or HTTPS link is opened through Chizu.
- Then: The link opens in the specified browser. A partial match does not apply the rule.

Scenario: Apply a source app rule when the source is identified

- Given: A rule checks the source app.
- When: Chizu receives a web link and identifies its source app.
- Then: It opens the link in the destination of the matching source app rule.

Scenario: Use a URL rule or the default when the source app is unknown

- Given: A rule checks the source app.
- When: Chizu receives a web link but cannot identify its source app.
- Then: It skips rules that depend only on the source app and uses the next matching URL rule or the default destination.

Scenario: Use the default destination when no rule matches

- Given: A default destination is configured.
- When: A web link matches no rule.
- Then: The link opens in the configured default browser and profile.

### Manage configuration as a file

As a user, I want to edit and sync routing in a regular file so that I can inspect changes and use the same conditions on another Mac.

**Acceptance criteria:**

Scenario: Find the configuration syntax and command examples

- Given: Chizu is installed.
- When: The user runs `chizu --help`.
- Then: Chizu shows the command forms, the JSONC structure and rule fields, and examples without requiring a configuration file.

Scenario: Create an initial configuration without downloading a sample

- Given: No configuration file exists at the usual path or an explicitly selected path.
- When: The user runs `chizu config init`, optionally supplying `--config FILE`.
- Then: Chizu creates the parent directory and a valid JSONC file with Safari as the fallback and no rules, and prints the created path.

Scenario: Preserve an existing configuration when initializing

- Given: A file or symbolic link already exists at the selected configuration path.
- When: The user runs `chizu config init` for that path.
- Then: Chizu reports that the path already exists and leaves its contents or symbolic link unchanged.

Scenario: Preview a routing decision without opening the link

- Given: A valid configuration file and an HTTP or HTTPS URL.
- When: The user runs `chizu check URL`, optionally supplying a source app or another configuration file.
- Then: Chizu prints the matching rule or default, destination app, and optional profile without opening the browser.

Scenario: Check the configuration file without opening a link

- Given: A configuration file is available.
- When: The user runs `chizu config check`, optionally supplying another configuration file.
- Then: Chizu reports whether the JSONC and rules are valid without opening a browser.

Scenario: Reject retired command names

- Given: Chizu is installed.
- When: The user runs `decide URL`, `default-status`, `make-default`, or `check` without a URL.
- Then: Chizu exits with an error without opening a link, checking the configuration, or changing the macOS default browser.

Scenario: Apply edited configuration to the next link

- Given: Chizu can read a JSON configuration file containing comments.
- When: The user edits it and opens another link.
- Then: Chizu ignores the comments and routes the link according to the edited rules.

Scenario: Use the first matching rule when rules overlap

- Given: Multiple rules match the same URL.
- When: That URL is opened through Chizu.
- Then: Chizu uses the destination of the first matching rule in the file.

Scenario: Do not open a link to an unintended destination when configuration is invalid

- Given: The configuration file is missing, unreadable, or invalid.
- When: A link is opened through Chizu.
- Then: Chizu does not send it to another browser and reports the configuration problem.

Scenario: Do not open a link when a regular expression is invalid

- Given: A rule contains an invalid regular expression.
- When: The user validates the configuration or opens a link through Chizu.
- Then: Chizu reports the rule name and regular expression problem without sending the link to a browser.

Scenario: Do not use another Dia profile when the specified one is missing

- Given: A rule names a Dia profile that does not exist.
- When: A matching link is opened.
- Then: Chizu does not open it in another profile and reports the missing profile name.

Scenario: Do not use another Chrome profile when the specified one cannot be identified

- Given: The configured Chrome profile name is missing or belongs to multiple profiles.
- When: A matching link is opened.
- Then: Chizu does not send the link to Chrome and reports the name and reason it cannot identify the profile.

Scenario: Do not use another Firefox profile when the specified one cannot be identified

- Given: The configured Firefox profile name is missing or duplicated, its directory is missing, or Firefox's profile list cannot be read.
- When: A matching link is opened through Chizu.
- Then: Chizu does not send the link to Firefox and reports the reason.

### Hand off a link from inside a browser

As a user, I want a userscript or extension in one browser to pass a link to Chizu so that a link clicked inside a browser also reaches the destination configured for it.

**Acceptance criteria:**

Scenario: Route a handed-off link with the configured rules

- Given: A rule matches `https://team.example.com/projects/1`.
- When: A browser opens `chizu-https://team.example.com/projects/1`.
- Then: Chizu opens `https://team.example.com/projects/1` in the destination of that rule, exactly as it would for the HTTPS link.

Scenario: Preview a handed-off link

- Given: A valid configuration file.
- When: The user runs `chizu check 'chizu-https://team.example.com/projects/1'`.
- Then: Chizu prints the same result as for `https://team.example.com/projects/1` without opening a browser.

Scenario: Do not open a handed-off link that is not a web link

- Given: Chizu is installed.
- When: A link such as `chizu-file:///etc/hosts` or `chizu-chizu-https://example.com/` reaches Chizu.
- Then: Chizu reports that only HTTP and HTTPS links are supported and does not open a browser.

### Make Chizu the macOS default browser

As a user, I want to inspect and set the system's HTTP and HTTPS handlers so that links from other apps reach Chizu.

**Acceptance criteria:**

Scenario: Inspect and set the macOS default browser

- Given: Chizu is installed as an app.
- When: The user runs `chizu default status`, then `chizu default set`.
- Then: The first command displays the HTTP and HTTPS handlers without changing them; the second sets both handlers to Chizu and reports the result.

## KPI

### Reaching the configured destination

- **Current value:** Not measured because this is a new feature.
- **Target:** All normal acceptance scenarios pass.
- **Measurement:** Fix the configuration and test URLs, then inspect the browser and profile where each link actually opens.
- **Period:** During verification for each release.

## Functional requirements

### Rule evaluation

**Summary:** Evaluate rules in file order and select the first matching destination. A rule with multiple conditions matches only when all of them are met.

**Input:** A web link, an identified source app when available, configured rules, and the default destination.

**Output:** A browser and optional profile to open, or an error with a reason.

#### Applicable conditions

##### URL and app

Text containment in the full URL ignores letter case. A URL regular expression applies only when it matches the full URL and is case sensitive by default. Host matching ignores letter case; path prefix matching respects it. A source app condition matches only when that app can be identified. Chizu does not open URL schemes other than HTTP and HTTPS. A `chizu-http` or `chizu-https` link is treated as the HTTP or HTTPS link left after removing the `chizu-` prefix once.

#### Behavior in exceptional cases

##### Destination cannot be found

When the configured browser or profile does not exist, Chizu reports an error instead of silently changing the destination. Chrome profiles use the name shown in Chrome; Firefox profiles use the name shown in `about:profiles`. Missing or duplicate names cause an error.

## Data requirements

### Required data

- **Configuration:** The default destination, ordered rules, URL and source app conditions, and destination browsers and profiles.
- **Link:** The URL to open and, when identified, the source app identifier.

### Data relationships

Each rule has conditions and one destination. One default destination applies when no rule matches.

### Personal information

Configured URL conditions, profile names, and source apps may together reveal the user or workplace. Personal configuration is not included in the public app. Chizu does not retain a history of received URLs.

## External service dependencies

None. The user provides the browsers that receive links.

## Security considerations

Chizu must not rewrite a received URL, other than removing the `chizu-` prefix from a handed-off link, or send it to a destination other than the one configured. It reports configuration errors and missing permissions to the user.

## Open questions

None.
