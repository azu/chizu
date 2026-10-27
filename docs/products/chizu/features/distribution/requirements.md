# Chizu releases

[日本語](requirements.ja.md)

## About this document

This feature lets users of [Chizu](../../product.md) download and use an app whose version they can identify.

### Scope

It covers version changes, pre-release verification, and publication of a ZIP containing a signed Apple Silicon app with a checksum.

### Out of scope

This distribution process does not cover in-app automatic updates, Intel builds, or Apple notarization.

## User stories

### Obtain a verified version of the app

As a user, I want to obtain an app whose version and signature I can check so that I use the intended Chizu build.

**Acceptance criteria:**

Scenario: Publish an app and checksum for the same version after a successful release

- Given: A version change has been merged and the required signing information is available.
- When: The release process completes.
- Then: The same release contains a ZIP with an app matching that version and the ZIP's SHA-256 checksum.

Scenario: Do not publish when signing information is missing

- Given: Required signing information is missing or differs from the published certificate information.
- When: The release process runs.
- Then: It fails before publication and does not publish an app with a changed signing identity.

Scenario: Do not publish when the version and tag differ

- Given: The release tag differs from the app's version.
- When: The release process runs.
- Then: It fails before publication and does not publish an app with a different version.

## KPI

### Distribution artifact consistency

- **Current value:** Not measured because this is a new feature.
- **Target:** The version and signature inside the ZIP match the release version for every release.
- **Measurement:** Check version, signature, and checksum for each release.
- **Period:** At every release.

## Functional requirements

### Generate a release

**Summary:** Check the version change, build the app, and publish an artifact signed with the same signing information.

**Input:** The version change, app source, and fixed signing information.

**Output:** A versioned release, app ZIP, SHA-256 checksum, or a reason for failure.

#### Applicable conditions

##### Version and signature

Release only when the source version matches the tag. Keep the signing identity fixed across ordinary version changes.

#### Behavior in exceptional cases

##### Verification or publication failure

Do not publish when tests, signing, or rechecking the ZIP fails. Do not silently overwrite an already published release.

## Data requirements

### Required data

- **Version:** A number that relates a release to the app.
- **Signing information:** Public and private information that keeps distributed app signatures consistent.
- **Artifact:** The app ZIP and a checksum used to check its contents.

### Data relationships

One release corresponds to one version. That release includes a ZIP and checksum for the same version.

### Personal information

Personal URL rules and profile names are not included in the artifact. Private signing information is not published.

## External service dependencies

- **GitHub Actions and GitHub Releases**
  - **Related user story:** Obtain a verified version of the app.
  - **Reason for dependency:** Handle the source version change, verification, and artifact publication in one repository.
  - **Contract and usage decision:** Follow the repository's Actions execution allowance and visibility settings.

## Security considerations

Do not include private signing information in the repository or logs. Check the certificate and app signature before publication.

## Open questions

None.
