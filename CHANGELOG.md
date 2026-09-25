# Changelog

All notable changes to the DataPoint iOS SDK.

## 1.1.0 — 2026-09-25

### Added

- **Link opening from the task wall.** Task pages can hand a URL to the host with
  `DataPointTask.openExternalUrl(url)` or `DataPointTask.openExternalUrl(url, mode)`.
  `mode` is `"in_app"` (default), which presents an `SFSafariViewController` over the task
  screen, or `"external"`, which opens the Safari app. The task screen stays presented
  underneath; if a task completes while the browser is open, the task screen is dismissed
  once the browser closes.
- `DataPointListener.onAppLifecycleEvent(_:)` (optional, default no-op) reporting
  `.didEnterBackground` / `.willEnterForeground` while the task UI is visible. The same
  transitions are dispatched to the page as a `datapoint:app-lifecycle` DOM event and
  `window.onDataPointAppLifecycle(state)`.

### Changed

- **Off-domain links now open in a browser instead of being blocked.** Previously a
  navigation to a host outside DataPoint's domains was cancelled silently. It now opens in
  an in-app browser (web links) or the app that handles the scheme (`mailto:`, `tel:`,
  `itms-apps:`). `target="_blank"` and `window.open` are routed the same way and never get
  their own web view. Custom-creative iframes remain confined to DataPoint hosts.
- The `DataPointTask` bridge accepts both `action` and `method` message keys, so the
  web app's direct `postMessage` fallback routes as well as the injected shim.

### Security

- `javascript:`, `file:`, `data:` and `about:` URLs handed to the SDK are refused.

### Compatibility

- No changes to existing public APIs; the new listener method has a default
  implementation. Minimum iOS remains 13.0.

### Upgrade

```swift
.package(url: "https://github.com/trydatapoint/datapoint-ios-sdk.git", from: "1.1.0")
```

## 1.0.0

Initial public release.
