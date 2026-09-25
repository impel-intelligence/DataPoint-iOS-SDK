# Releasing the DataPoint iOS SDK

Distributed with Swift Package Manager straight from this repository: a release is a
signed commit on `main` plus a semver git tag. There is no artifact upload.

## 1. Decide the version

Semantic versioning. Public API or behavior change → minor; fixes only → patch.

The version is declared in two places that must always match, plus the tag:

| Where | Key |
| --- | --- |
| `datapoint/Internal/SdkConstants.swift` | `sdkVersion` |
| `README.md` | `.package(..., from: "X.Y.Z")` |
| git | tag `vX.Y.Z` |

SPM resolves the **highest semver tag** regardless of prefix, so `1.0.3` and `v1.0.3`
are the same version to a consumer. Never leave an old commit carrying a higher tag than
the release you are cutting.

## 2. Pre-release checks

The legacy `*.xcodeproj` files in the repo root are not used by SPM and confuse
`xcodebuild`'s scheme lookup, so build and test from a copy of the package without them:

```bash
rm -rf /tmp/dp-ios && rsync -a --exclude .git --exclude '*.xcodeproj' --exclude Derived \
  --exclude .swiftpm . /tmp/dp-ios
cd /tmp/dp-ios
SIM=$(xcrun simctl list devices available | grep -m1 -o '[0-9A-F-]\{36\}')
xcodebuild -scheme DataPointSDK -destination "platform=iOS Simulator,id=$SIM" test
```

Or open `Package.swift` in Xcode and run the `DataPointSDKTests` target (⌘U).

Then a device pass with the sample app on the Sandbox environment. Point
`productionTaskURL` at a task-wall build that exercises the release and revert that
override (and `trustedHosts`) before committing.

Things to confirm on every release:

- Init → task wall opens, task completes, listener callbacks fire on the main thread.
- Session expiry while the wall is open silently re-initializes.
- Links: `in_app` presents `SFSafariViewController` and closing it returns to the task;
  `external` opens Safari; `mailto:`/`tel:` go to their app; a `target="_blank"` link opens
  outside; a custom-creative iframe cannot open a browser on its own.
- A task completion that lands while the in-app browser is open dismisses the task screen
  only after the browser closes.
- Background / foreground while the wall is open reaches `onAppLifecycleEvent`.

## 3. Cut the release

1. Bump `sdkVersion` and the README, add the `CHANGELOG.md` entry.
2. Commit as `release: vX.Y.Z` (commits on `main` must be signed), push a branch, open a
   PR, merge.
3. Tag the merged commit `vX.Y.Z` and push the tag.
4. Create the GitHub release from the changelog entry. Consumers pick it up on their next
   package resolution.

## 4. Verify

- In a fresh sample project, add the package `from: "X.Y.Z"` and confirm Xcode resolves
  exactly that tag.
- Run the wall once on a device.

---

## 1.1.0 checklist

- [x] `sdkVersion` and README at 1.1.0
- [x] `CHANGELOG.md` entry
- [x] Unit tests: `UrlPolicyTests`
- [ ] Device pass (matrix above)
- [ ] PR merged to `main`, tag `v1.1.0` pushed
- [ ] GitHub release published
- [ ] Resolved from a fresh project

Related rollouts (independent; the SDK is backward compatible):

- dl-dippy: merge and deploy the open-mode work so the task wall sends `mode`.
- Backend: return `cta_open_mode` on completion views.
