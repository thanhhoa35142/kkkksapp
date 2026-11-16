---
name: verify
description: Verify iOS app changes. Compile-checks with xcodebuild (macOS/CI only — no Xcode on WSL2) and runs UI tests in fixture mode. Use after touching SwiftUI views, view models, services, or app config.
---

# Verify — Picnic iOS app

This machine (WSL2) has no Xcode. Builds and tests run on macOS — either the
user's Mac/cloud builder or GitHub Actions (`.github/workflows/ci.yml`,
`macos-15` runner). Write correct code locally; verification happens on macOS.

## 1. Compile check (macOS only)

```bash
cd pickhour-app

xcodebuild \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build

# Native macOS destination too (same target, not Catalyst):
xcodebuild \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination 'generic/platform=macOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build
```

## 2. UI tests — fixture mode, no backend needed

`MyAppUITests/` launches the app with `-UITestFixtures`: every API call is
answered in-process by `MyApp/Testing/UITestFixtures.swift` (fixture spots,
weather, plans). This is the e2e harness — the only test suite left
(`MyAppTests/` unit tests were removed).

```bash
UDID=$(xcrun simctl list devices available -j \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for r in sorted(d, reverse=True) if "iOS" in r for x in d[r] if x["name"].startswith("iPhone")))')

xcodebuild \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "id=$UDID" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  test   # runs MyAppUITests only
```

When adding a UI test: set `app.launchArguments = ["-UITestFixtures", ...]`
and assert on real user flows (tab appears, onboarding first, navigation).
If a flow needs data that fixtures don't cover, extend
`UITestFixtures.response(for:)` rather than hitting a live backend.

## 3. Real-backend verification (optional, macOS + running backend)

The app reads `APIBaseURL` from Info.plist, falling back to
`http://localhost:8080` (`MyApp/App/AppConfig.swift`). An iOS simulator shares
the Mac's localhost, so with `pickhour-backend` running (`make db-up && go run ./cmd/api`),
a plain Debug build talks to the real API — use this to verify API contract
changes end-to-end.

## Done criteria

- Both `xcodebuild ... build` commands pass with no signing.
- `xcodebuild ... test` passes (UI tests green).
- For API-contract changes: fixture responses in `UITestFixtures.swift` still
  match the backend's real response shapes (camelCase, reason codes).
