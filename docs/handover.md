# Handover: remaining issues

Status: the audit fixes are on `feat/polling-throttle-cleanups` (PR #1). On top
of them, the popover is now a native `NSMenu` and the code has had a
simplification pass. The tree has 113 passing tests in 13 suites, a signed
Apple Silicon (arm64) release build, and freshly rendered README pictures. No
open P0/P1/P2 items remain; the limitations below are accepted.

## Verification

```sh
swift test -Xswiftc -warnings-as-errors              # 113 tests, 13 suites: pass
swift test -c release -Xswiftc -warnings-as-errors   # 113 tests, 13 suites: pass
./build.sh                                           # signed build/LimitPeek.app
lipo -archs build/LimitPeek.app/Contents/MacOS/LimitPeek  # arm64
codesign --verify --deep --strict --verbose=2 build/LimitPeek.app  # ok
shellcheck build.sh scripts/*.sh                     # ok
git diff --check                                     # ok
```

## Fixed (do not regress)

- Apple Silicon (arm64) only: `build.sh` builds release with
  `-c release --arch arm64` and has no architecture fallback. CI and the release
  workflow require `lipo -archs` to be exactly `arm64`. The cask template
  declares `depends_on arch: :arm64`; README and release notes state Apple
  Silicon (arm64).
- CI runners and supply chain: both workflows use `macos-26`, the newest stable
  macOS image, with its default Xcode and no hardcoded Xcode path. GitHub has no
  `macos-27` label; `xcode-27` is a preview (macOS 26 with Xcode 27) and is
  deliberately not used. Every `actions/checkout` and `actions/upload-artifact`
  use is pinned to a commit SHA. The actionlint 1.7.12 archive is downloaded to a
  temp directory and verified against its SHA256 before extraction. Both
  workflows run `swift test` with `-Xswiftc -warnings-as-errors`.
- One account: `AccountStore.account` replaced the never-used account list.
  It still stores a list under `accounts`, the format earlier builds read.
  Loading an earlier multi-account list keeps the selected account and queues
  the others' tokens for cleanup. Signing in as a different account removes the
  previous account's token the same way a sign-out does.
- Session isolation: `sessionGeneration` and `isCurrent(_:)` in `AccountStore`
  keep stale work from writing state after sign-out or re-sign-in; every account
  change bumps the generation, so it alone decides. `AccountStoreRaceTests`
  covers that race.
- Rate limits: `AccountStore.rateLimitedUntil` is the one deadline shared by
  `Refresher`, the menu and manual refresh. `Retry-After` is capped by
  `API.maximumRetryAfter`, with a 300 s floor (`rateLimitFallback`).
- Authentication recovery: a rotated token is retried once on 401; a persistent
  401 sets `authIssue = .sessionExpired`. A 403 is parsed as
  `APIError.forbidden`, sets `authIssue = .forbidden`, and the menu shows
  "Sign In Again…" with "Not permitted" as its subtitle. It is not retried
  automatically: the token is valid, so a refresh cannot change the answer.
- Sign-in: a menu cannot hold a text field, so the code goes into a small
  window (`SignInWindowController` hosting `SignInView`). Choosing the menu item
  again while the window is open only brings it forward, since a fresh
  authorization would orphan a code already copied; "Open Browser Again"
  restarts with a fresh PKCE on purpose. `completeSignIn` returns whether it
  succeeded, and the window closes on success.
- Main menu: the agent app shows no menu bar, but `AppDelegate.mainMenu()`
  installs an Edit menu so ⌘V, ⌘C, ⌘A and ⌘Z work in the sign-in field, plus
  ⌘W and ⌘Q.
- Sign-out policy: `AccountStore.removeAccount` persists the pending cleanup ID
  before clearing metadata, then saves and deletes the Keychain item. A crash in
  any window leaves either the account or a pending ID that
  `retryPendingTokenCleanup` can finish, never a token orphaned without a
  record. A failed delete keeps the pending ID; an invalid grant goes through
  the same path. `TokenStoreTests` covers the in-memory behavior and error
  descriptions.
- OAuth: PKCE uses the system CSPRNG, the authorization URL is built with
  `URL.appending(queryItems:)`, and `OAuthService.parseCallback` validates the
  state and returns the code. `OAuthServiceTests` covers callback parsing and
  the URL.
- Decoding and rows: `UsageResponse` decodes each bucket lossily, so one
  unexpected entry does not blank the response. `UsageDisplay.Row` carries an
  explicit `kind`, IDs include the array index and model, `displayPercent` /
  `percentText` share the 0–100 clamp and the 100%+ sentinel, and
  `sessionPercent` matches `kind == "session"`. `Severity(percent:)` holds the
  80% and 95% thresholds for the menu bar and the rows; `Row.level` lets the
  server's severity raise a row only below them.
- Reset times: `ResetFormatter` shows "at 14:00 (1h 15m)" within a day, the
  weekday and time within a week, and a date beyond that or for credits. The
  remainder is rounded up, so the clock plus the remainder lands on the shown
  time. It sits on its own line under the title, so long model names and 12-hour
  times never wrap.
- Polling: `Refresher` waits until `PollSchedule.nextPoll`, counted from the
  store's `lastRefreshAt` whoever made the request, so opening the menu or
  pressing Refresh does not add a poll. It pauses while signed out or
  reauthenticating and on system and display sleep, and restarts on sign-in and
  wake. `PollSchedule` polls every 180 s, or 300 s in Low Power Mode and after a
  429 until a poll lands. Manual refresh keeps the 20 s floor; the Refresh item
  is disabled while it would do nothing (`canRefresh(at:)`).
- Menu: `StatusItemController` owns the `NSStatusItem` and a native `NSMenu`
  rebuilt from the store when it opens and, through Observation, whenever what
  it shows changes while open. Usage rows, the header and notes are SwiftUI views
  hosted in menu items; everything else is a native item (Refresh ⌘R with an
  "Updated …" subtitle, "Usage on claude.ai…", Sign Out, Quit ⌘Q). The main menu
  has no checked item, because one would indent every title there by the
  checkmark column (30 pt instead of 16 pt on macOS 27) and push the rows off
  center. The checkmarks live in the Settings submenu: "Show in Menu Bar" with
  the three styles, then Launch at Login and, when needed, "Approve in System
  Settings…". Hosted views use `MenuMetrics.inset` (16 pt) on both sides, where
  native titles start and key equivalents end. A `.common`-mode timer keeps the
  Refresh subtitle current while the menu tracks (`RefreshCaption.tickInterval`:
  1 s only in the final minute of a rate-limit countdown, 30 s otherwise).
- Why a menu and not the window-style `MenuBarExtra`: on macOS 27.2 its window
  has ~16 pt corners, while `NSMenu` has ~12 pt, a hairline border and its own
  material, and no public API changes the window's shape. The old `.menu`
  material workaround for Liquid Glass legibility went with it.
- Menu bar label: `MenuBarLabel` draws with AppKit in an `NSImage` drawing
  handler, so it renders when the status item draws, in the status button's own
  appearance. That appearance follows the desktop picture, not the system
  setting; `NSApp.effectiveAppearance` was the wrong source. AppKit caches the
  result per appearance, so no KVO is needed. The drawing matches the earlier
  SwiftUI rendering within anti-aliasing. `StatusItemController.renderLabel()`
  compares `MenuBarLabel.Key`s, so a poll that does not change the drawn value
  leaves the status item alone. VoiceOver reads the image's
  `accessibilityDescription` ("not signed in" when signed out); a SwiftUI
  `.accessibilityLabel` never reached the status item.
- UI colors: one palette in `Palette`, built from dynamic `NSColor`s that
  resolve per appearance, so no view reads the color scheme. Graphite is the
  gauge color at rest, amber for warning, coral red for critical, each with a
  lighter dark-mode variant. The header glyph is a fixed silver
  (`Palette.glyph`), not `.secondary`.
- README art: `scripts/ReadmeArt.swift` draws the menu bar strip from
  `MenuBarLabel` images and pops up the real `NSMenu` with a fixture store, on
  the half of the screen away from the pointer, and captures it with
  `screencapture`. The terminal needs Screen Recording permission.
  `scripts/make-readme-art.sh [dir]` takes an output directory for previews.
- Keychain access stays on the main actor by design: reads are cached per launch
  and writes are rare, so a dedicated actor is not warranted yet. Revisit if
  those flows grow.
- Test helpers use `OSAllocatedUnfairLock` instead of `NSLock`; only the
  `URLProtocol` stubs remain `@unchecked Sendable`.
- Test coverage: 113 tests in 13 suites: `APITests`, `UsageClientTests`,
  `AccountStoreTests`, `AccountStoreRaceTests`, `OAuthServiceTests`,
  `TokenStoreTests`, `PollScheduleTests`, `RefreshCaptionTests`,
  `ResetFormatterTests`, `MenuBarLabelTests`, `UsageDisplayTests`,
  `UsageDecodingTests` and `LaunchAtLoginStatusTests`.

## Remaining accepted limitations

- Status items are hosted by the system on macOS 26 and later, so the live menu
  cannot be opened programmatically. The menu is checked by popping up the same
  `NSMenu` (as `ReadmeArt` does), and the label by drawing it offscreen in the
  menu bar's appearances (`MenuBarLabelTests`).
- `MenuMetrics.inset` (16 pt) is measured on macOS 27. Before macOS 26, menus
  may indent titles further, so hosted rows can sit slightly left of native
  titles there; they stay centered either way.
- Instruments profiling and interactive UI testing are not possible here: the
  app needs the menu bar and an account sign-in.
- The real Keychain and data-protection paths are not exercised automatically;
  tests use the in-memory store. The real paths need prompts and a signing
  identity.
- A 403 can still be a server-side plan or organization block. The
  reauthentication prompt helps only when stale scopes are the cause; if the
  block persists, signing in again will not fix it.
- The cask template places `depends_on arch: :arm64` after
  `depends_on macos: :sonoma`. Homebrew's style cop prefers `arch` first; this
  is a style nit only and the tap workflow does not enforce it.
- The launch smoke test ran under a separate bundle ID
  (`dev.nevermind.LimitPeek.smoketest`), signed out, so it did not touch the
  installed app's Keychain item or settings. The release workflow covers the
  launch check for the real bundle.
