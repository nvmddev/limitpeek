# Signing and notarisation

macOS ties Keychain access to an app's code signature, so how the app is signed
decides how often it asks about its own stored token:

| Signed with | Keychain used | Prompts |
|---|---|---|
| Ad-hoc (`codesign -s -`) | file-based | every rebuild — the signature changes each time |
| Self-signed dev cert | file-based | once, then "Always Allow" sticks |
| Developer ID | file-based | once, then "Always Allow" sticks |
| Developer ID + provisioning profile | data-protection | none |

The app does not hardcode which Keychain to use. At launch it probes whether the
data-protection Keychain accepts a write and uses it if so, so improving the
signature is a build-time change only.

## Local development

```sh
./scripts/make-dev-cert.sh          # once
export CODESIGN_IDENTITY="LimitPeek Dev"
```

`build.sh` picks that identity up automatically once it exists, and falls back
to ad-hoc signing if it does not.

## With a Developer ID

You need a *Developer ID Application* certificate — Xcode → Settings → Accounts
→ Manage Certificates → `+`. Once it is in the login keychain, `build.sh` finds
it and reads the Team ID off the certificate name, so nothing has to be passed
in. That alone gets a stable signature, so the Keychain asks once.

`codesign` may still prompt the first time it uses a signing key from your
keychain. That one is separate; settle it with "Always Allow", or permanently:

```sh
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$LOGIN_KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db
```

## Silencing the Keychain prompt entirely

For that the app needs a `keychain-access-groups` entitlement, and a plain
certificate is not enough. It is a *restricted* entitlement: AMFI kills the app
at launch unless a provisioning profile inside the bundle authorises it — the
failure looks like `Launch failed … Code=163`, or exit 137 when started
directly. Three things are needed:

1. An **Identifier** (App ID) for `dev.nevermind.LimitPeek`, at
   developer.apple.com → Identifiers. No capability to tick: the access group
   `TEAMID.dev.nevermind.LimitPeek` follows from the App ID itself, and Keychain
   Sharing is an Xcode-side switch rather than a portal capability.
2. A **Developer ID provisioning profile** for that App ID — Profiles → `+` →
   Distribution → Developer ID.
3. The downloaded profile saved as `Resources/embedded.provisionprofile`
   (gitignored).

Apple grants the profile `keychain-access-groups` as the team wildcard
`TEAMID.*`, which covers the concrete group `build.sh` writes. Check before
building — a profile that lacks it yields an app that signs cleanly and then
gets killed at launch:

```sh
security cms -D -i Resources/embedded.provisionprofile | plutil -p -
```

`build.sh` then copies it into the bundle and injects the entitlement. Without
the file it skips both and says so, rather than producing an app that cannot
start.

## Notarisation

An app that arrives with the quarantine flag — a browser download, AirDrop,
mail — is blocked on first launch unless Apple has notarised it. Notarisation
produces a ticket; stapling embeds that ticket so Gatekeeper can verify it
without network access.

One-time setup, which puts the app-specific password in the Keychain:

```sh
xcrun notarytool store-credentials limitpeek-notary \
      --apple-id you@example.com --team-id ABCDE12345
```

Then, per release:

```sh
./build.sh && ./scripts/notarize.sh build/LimitPeek.app
```

App-specific passwords come from appleid.apple.com → Sign-In and Security. The
account password does not work.

CI does all of this on a tagged push once the signing and notary secrets are
set — see [.github/workflows/release.yml](../.github/workflows/release.yml).

## Release secrets

| Name | Purpose |
|---|---|
| `MACOS_CERTIFICATE_P12` | base64 of the Developer ID certificate |
| `MACOS_CERTIFICATE_PASSWORD` | its export password |
| `MACOS_SIGN_IDENTITY` | optional; derived from the certificate if unset |
| `MACOS_PROVISION_PROFILE` | base64 of the provisioning profile; without it the app asks once for Keychain access |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | notarisation |
| `HOMEBREW_TAP_TOKEN` | PAT with `contents:write` on the tap |
| `RELEASE_PAT` | optional; lets the changelog PR trigger CI |

Plus the repository variable `HOMEBREW_TAP_REPO`, e.g. `nvmddev/homebrew-tap`.

Without them the pipeline still runs: the build is ad-hoc signed and the cask
step is skipped, both with a warning.
