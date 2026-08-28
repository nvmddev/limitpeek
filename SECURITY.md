# Security policy

## Supported versions

Only the latest release gets fixes. Please reproduce on the newest version
before reporting.

## Reporting a vulnerability

Report privately through GitHub's
[security advisory form](https://github.com/nvmddev/limitpeek/security/advisories/new)
— not a public issue. Include what you did, what happened, and the version and
macOS version you saw it on.

**Don't paste a live token into a report.** A redacted description, or one you
have already invalidated by signing out, is enough.

## What's in scope

LimitPeek holds an OAuth access and refresh token for your Claude account in the
Keychain and sends the access token to `api.anthropic.com`. Worth reporting:

- The token appearing anywhere it shouldn't — a log, a crash report, an error
  message in the UI, a request to any other host.
- Requests going somewhere other than `api.anthropic.com` or
  `platform.claude.com`.
- Anything that lets another local process read the stored token beyond what the
  Keychain's own access control implies.
- Tampering with a released `.app`, `.dmg`, or with the release pipeline.

## Not in scope

The usage endpoint is undocumented and may change or disappear; that is a bug,
not a vulnerability. Same for anything requiring an attacker who already has
admin access to your Mac.
