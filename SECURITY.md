# Security policy

## Supported versions

Only the latest release gets security fixes. Make sure that the problem also occurs in the latest version before you report it.

## Report a vulnerability

Do not open a public issue. Use the [private report form](https://github.com/nvmddev/limitpeek/security/advisories/new) on GitHub.

Include these details:

- What you did
- What happened
- The LimitPeek version and the macOS version

Do not include a token in the report. Remove tokens from logs and screenshots before you send them.

## Scope

LimitPeek keeps an OAuth access token and a refresh token in the macOS Keychain. It sends the access token to `api.anthropic.com` and the refresh token to `platform.claude.com`.

Report these problems:

- A token appears where it must not, for example in a log, a crash report, an error message or a request to a different host.
- LimitPeek sends a request to a host other than `api.anthropic.com` or `platform.claude.com`.
- Another process on the Mac can read the token, although the Keychain does not allow it.
- Someone can change a released `.app`, `.dmg` or `.zip` file, or the release pipeline.

## Out of scope

- Changes to the private usage API. These are bugs, not vulnerabilities. Open a normal issue for them.
- Attacks that need administrator access to your Mac.
