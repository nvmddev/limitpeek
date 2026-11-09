# Handover: remaining issues

Status: the audit fixes are implemented on `feat/polling-throttle-cleanups`
(PR #1). The tree has 101 passing tests in 12 suites, a signed Apple Silicon
(arm64) release build, and freshly rendered README screenshots. No open P0/P1/P2
items remain; the limitations below are accepted.

## Verification

```sh
swift test -Xswiftc -warnings-as-errors              # 101 tests, 12 suites: pass
swift test -c release -Xswiftc -warnings-as-errors   # 101 tests, 12 suites: pass
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
- Session isolation: `sessionGeneration`, `activeRefreshID` and
  `isCurrent(_:generation:)` in `AccountStore` keep stale work from writing
  state after sign-out or re-sign-in. `AccountStoreRaceTests` covers that race.
- Rate limits: `AccountStore.rateLimit` is the one deadline shared by
  `Refresher`, the popover and manual refresh. `Retry-After` is capped by
  `API.maximumRetryAfter`, with a 300 s fallback.
- Authentication recovery: a rotated token is retried once on 401; a persistent
  401 sets `authIssue = .sessionExpired`. A 403 is parsed as
  `APIError.forbidden`, sets `authIssue = .forbidden`, surfaces "Sign in again"
  with a "Not permitted" detail, and is not retried automatically: the token is
  valid, so a refresh cannot change the answer. The error text names the scopes
  and points at the account's usage access.
- Reauthentication flow: `SignInView` accepts `onRestart` and shows a "Start
  over" button next to Back, which reopens authorization with a fresh PKCE.
  A consumed verifier no longer forces Back followed by "Sign in again".
- Sign-out policy: `AccountStore.signOut()` persists the pending cleanup ID
  before clearing metadata, then saves the account list and deletes the Keychain
  item. A crash in any window leaves either the account or a pending ID that
  `retryPendingTokenCleanup` can finish, never a token orphaned without a
  record. A failed delete keeps the pending ID; an invalid grant removes the
  account and token. `TokenStoreTests` covers the in-memory behavior and error
  descriptions.
- OAuth: PKCE uses the system CSPRNG (`OAuthService.randomURLSafeString`), and
  `OAuthService.parseCallback` validates the state. `OAuthServiceTests` covers
  callback parsing and exchange errors.
- Decoding and rows: `UsageResponse` decodes each bucket lossily, so one
  unexpected entry does not blank the response. `UsageDisplay.Row` carries an
  explicit `kind`, IDs include the array index and model, `displayPercent` /
  `percentText` share the 0–100 clamp and the 100%+ sentinel, and
  `sessionPercent` matches `kind == "session"`. `UsageDecodingTests` and
  `UsageDisplayTests` cover these.
- Refresh loop: `Refresher` pauses while signed out or reauthentication is
  required and resumes on sign-in. `PollSchedule` backs off on 429, and
  `RefreshTimelineSchedule` ticks at 1 s only in the final minute before a
  deadline, otherwise at 30 s.
- UI colors: one palette in `Palette`. Graphite is the accent at rest, so
  color only appears at the thresholds: amber for warning, coral red for
  critical, each with a lighter dark-mode variant. `UsagePopover` sets the
  accent as `.tint` at its root, so the gauges, the Launch at Login switch,
  the menu bar style selector and the sign-in buttons use it instead of the
  system accent color; a red or green system accent no longer clashes with
  the gauges. `Palette.onAccent` is the text on an accent fill (dark in dark
  mode). The header glyph is a fixed silver (`Palette.glyph`), not
  `.secondary`, which vibrancy darkens to near black over dark windows behind
  the glass. "Start Over" and "Back" opt out with `.tint(nil)`, because a
  tinted bordered button colors its label and reads as disabled. The menu bar
  label stays a template image below the warning threshold.
- Popover background: on macOS 26 and later the menu bar extra's Liquid Glass
  lets the window behind it show through, so over a dark window a light
  popover turned mid-gray and the palette's fixed colors lost their contrast
  (the "Tinted" Liquid Glass setting does not prevent it). `panelBackground()`
  in `PanelComponents.swift` puts the `.menu` material, the one behind system
  menus, under the content, clipped to the window's 6 pt corner
  (`PanelMetrics.cornerRadius`). It stays as light or dark as the appearance
  and follows Reduce Transparency and Increase Contrast. The live menu bar
  window cannot be opened programmatically for a capture (the status item is
  drawn out of process and ignores synthetic clicks), so this was checked on
  an `NSGlassEffectView` replica, not the live window.
- UI: a mini `.switch` toggle for Launch at Login, `Gauge` with the
  `CapacityBarStyle` in `LimitRow.swift` (a slim bar on a track of its own
  tint, no dot at 0%), and `.borderedProminent` / default-action buttons in
  `SignInView`. `PanelMetrics` in `PanelComponents.swift` is the one grid for
  margins, row height and highlight inset; trailing text aligns on the title's
  first baseline. Two pieces are hand-built: `MenuActionRow`, because SwiftUI
  has no menu-item button style for a window-style menu bar extra, and
  `MenuBarStyleRow`, because a segmented `Picker` paints its selected segment
  gray (near black over a dark window behind the glass) whenever the panel is
  not key. Both suppress the focus ring with `.focusEffectDisabled()`.
  Launch-at-login status is re-read on
  `NSApplication.didBecomeActiveNotification` (see `LaunchAtLoginRow` and
  `LoginItem`). The code field takes focus through `.defaultFocus`, since the
  window is not key yet when `onAppear` runs.
- README art: `scripts/ReadmeArt.swift` shoots the popover on screen with
  `screencapture` over a neutral backdrop, in the `.menu` material and with the
  accent pinned to blue, because AppKit-backed controls and the material only
  render in a live key window. The terminal needs Screen Recording permission.
- Menu bar cache: `MenuBarLabelCache` redraws on `NSApp.effectiveAppearance` KVO
  and keys renders on quantised percent, style and appearance, so polls that do
  not change the drawn value redraw nothing.
- Keychain access stays on the main actor by design: reads are cached per launch
  and writes are rare, so a dedicated actor is not warranted yet. Revisit if
  those flows grow.
- Test coverage: 101 tests in 12 suites, including `APITests`,
  `UsageClientTests`, `AccountStoreTests`, `AccountStoreRaceTests`,
  `OAuthServiceTests`, `TokenStoreTests`, `PollScheduleTests`,
  `RefreshTimelineTests`, `MenuBarLabelCacheTests`, `UsageDisplayTests`,
  `UsageDecodingTests` and `LaunchAtLoginStatusTests`.

## Remaining accepted limitations

- Instruments profiling and interactive UI testing are not possible here: the
  app needs the menu bar and an account sign-in.
- The real Keychain and data-protection paths are not exercised automatically;
  tests use the in-memory store. The real paths need prompts and a signing
  identity.
- `MenuBarLabelCache`'s appearance KVO is not covered by tests; the cache tests
  cover keying and redraw behavior, not the AppKit notification itself.
- A 403 can still be a server-side plan or organization block. The
  reauthentication prompt helps only when stale scopes are the cause; if the
  block persists, signing in again will not fix it.
- The cask template places `depends_on arch: :arm64` after
  `depends_on macos: :sonoma`. Homebrew's style cop prefers `arch` first; this
  is a style nit only and the tap workflow does not enforce it.
- A local launch smoke test was not run, since it can touch the user's Keychain.
  The release workflow covers the launch check.
