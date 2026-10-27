# Chizu

[日本語](product.ja.md)

## Overview

Chizu is a macOS app that automatically routes web links to a browser and profile chosen by the user. Users manage routing conditions in a regular file and open links without a browser selection screen.

## Background and problem

### Background

macOS can send links to a default browser. Choosy also routes links according to conditions, but the user's existing setup could not select a Dia profile. Choosy supports rules based on URL text and the source app. See [Apple's URL handler documentation](https://developer.apple.com/documentation/coreservices/1447760-lssetdefaulthandlerforurlscheme) and [Choosy's rules documentation](https://choosy.app/help/settings/rules).

### Problem to solve

Manually separating work and personal links by profile can open a link under the wrong account and require reopening it. Settings created only through a UI are also harder to compare and sync as files. A readable configuration file holds the user's routing settings.

## Target users

### macOS users with multiple browsers and profiles

- **Characteristics:** They choose destinations based on URLs or source apps and manage configuration in files.
- **Problem:** They do not want to choose a browser or profile each time they open a link.
- **Usage:** They open web links from other apps or sync their configuration to another Mac.

## Value provided

### Predictable automatic routing

- **For:** macOS users with multiple browsers and profiles.
- **What:** Open matching links in the specified destination and other links in the configured default destination.
- **Why:** Remove repeated choices and reach the intended browser context.

### Traceable configuration

- **For:** Users who manage and sync configuration with Git.
- **What:** Edit, inspect, and share routing conditions as a regular file.
- **Why:** Preserve a change history without relying on settings stored only inside the app.

## Definition of success

Users can inspect their configuration file to see where links will open and reach the expected browser and profile during normal link opening without a selection screen.

## Product principles

Prioritize letting users check routing results before opening links. If a profile or configuration is missing, report the failure instead of silently selecting another profile. Keep the public app separate from personal routing conditions.

## SLA, SLI, and SLO

### SLA

Chizu is a local app for personal use, so it makes no service availability commitment to others.

### SLI and SLO

No numerical operating target is set. Routing is checked against normal, error, and boundary acceptance conditions during implementation.

## Open questions

None.
