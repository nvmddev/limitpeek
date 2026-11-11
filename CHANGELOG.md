# Changelog

## 0.3.0 — 2026-11-11

### Added

- show the version in the menu and point to newer releases (#4)

## 0.2.2 — 2026-11-11

### Fixed

- poll every two minutes and back off for a while after a rate limit (#3)

## 0.2.1 — 2026-11-09

Maintenance only.

## 0.2.0 — 2026-11-09

### Added

- poll usage once a minute
- replace the popover with a native menu and show exact reset times

### Fixed

- complete usage audit follow-ups and require Apple silicon

### Other

- Throttle usage polling to max 3 requests/min and apply Apple-guideline cleanups

## 0.1.0 — 2026-08-29

### Added

- add toggle for display options in menue bar
- mark the popover with a monochrome app glyph and regroup its actions
- poll every three minutes and back off when the server rate-limits
- LimitPeek — Claude usage limits in the macOS menu bar

### Fixed

- raise the popover glyph and drop comments that restate the code
- fill the menu bar gauge in proportion to the percentage
- constrain withValidToken's result to Sendable
