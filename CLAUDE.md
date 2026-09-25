# Awaira-iOS: consumer iPhone app

- **Stack:** SwiftUI, Vision and StoreKit 2, with XcodeGen.
- **Platform:** iOS 18+, iPhone only, portrait only. Tracking runs in the foreground only.
- **Bundle IDs:** `com.awaira.ios` (tests `.tests`, UI tests `.uitests`).
- **Team and scheme:** team `S6HG6FS5JJ`, scheme `Awaira`.
- `Awaira.xcodeproj` and `Sources/Info.plist` are generated and gitignored. Change `project.yml`, then run `make generate`.

## Hard rules
- **Privacy:** detection runs on the device. No camera frames, habit, detection or progress data may leave the phone. Don't add network calls, device identifiers, analytics or crash SDKs without the user's explicit OK.
- **Tone:** Awaira is an awareness companion, not a scorekeeper, and a detection is never framed as failure. See `docs/AWAIRA-UX-STRUCTURE.md` in `../Awaira-Main`.
- **Wording:** never claim Awaira prevents, cures, treats or fixes trichotillomania or any other BFRB. In user-facing text (app, App Store listing, review notes) use no emojis, no dashes as punctuation, and nothing that reads as machine-written.
- **Secrets:** never print or commit signing material, App Store Connect keys, `.env*` files or secret values.

## Commands (run from the repo root)
- `make generate`, `make build`, `make run`: `SIMULATOR` defaults to "iPhone 17".
- `make test`: unit and UI tests. `make unit`: `AwairaTests` only.
- `make device`: install on the connected phone (`DEVICE=<udid>`).
- `make review-screenshots`: runs `StoreScreenshotCaptureTests/testCapturePremiumReviewScreens` and writes `ReviewScreenshots/Awaira-{Monthly,Yearly,Lifetime}-review.png`.
- `make clean`

The simulator has no camera, so detection can only be exercised on a device or through the `-ScreenshotDemo` fake.

## Premium / StoreKit
- **`PremiumStore`** (`@MainActor ObservableObject`):
  - checks `Transaction.currentEntitlements` before loading products
  - listens to `Transaction.updates`
  - tracks intro-offer eligibility
- **`PremiumAccessGate`** blocks the tracking screens until the user has a trial, subscription or lifetime purchase.
- **`PremiumPaywallView`** must keep its renewal and trial disclosure text, which App Review requires.
- **Product IDs** are Info.plist keys in `project.yml`:
  - `AwairaMonthlyProductID` = `com.awaira.ios.sub.monthly`
  - `AwairaYearlyProductID` = `com.awaira.ios.sub.yearly`
  - `AwairaLifetimeProductID` = `com.awaira.app.lifetime`
- The legacy `com.awaira.ios.premium.{monthly,yearly}` IDs (builds 7–8) are still queried, so existing subscribers keep access.
- Free trials exist only as App Store introductory offers. There's no local trial timer.
- There's no `.storekit` config file.

## Tests
- **`ParityTests`** pins the detection constants to the Mac app's `frontend/Sources/Detector.swift` in the sibling repo `../Awaira-Main`. If you deliberately change one side, change the other too and update the test.
- **UI test launch arguments:**
  - `-UITest` skips the camera.
  - `-ScreenshotDemo` fakes detection.
  - `-ScreenshotPaywall` opens the paywall directly.
- **Accessibility IDs:** `premiumPaywall`, `premiumPurchaseButton.<productID>`.

## Conventions
- One type per file. `Mobile*` prefixes screens; `Awaira*` prefixes the design system (Palette, Type, Card, Layout, Icons).
- Doc comments explain *why*, often citing App Review rules. Keep that style.
- Design and detection logic mirror the Mac app. Keep them matched to desktop.
- Versioning: bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` when needed) in `project.yml` by hand. See the `/ios-testflight` skill.

## Related repos (siblings in `~/Desktop/Projects/Awaira/`)
- `Awaira-Main`: macOS app (`frontend/`), backend and website (`server/`), and the Insights app. Its `server/public/demo/js/detection-core.js` is a port of `Sources/DetectionCore.swift`, so keep them in step.
- `Awaira-Android`: Android app. The paywall and pricing UI are matched across platforms.
- `Awaira-Windows` and `Awaira-Linux`: desktop apps with the same detection constants.

## Git
Commit messages are short imperative sentences. Never commit `build*/`, `Awaira.xcodeproj` or `Sources/Info.plist`.
