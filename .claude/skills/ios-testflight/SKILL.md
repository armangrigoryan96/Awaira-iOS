---
name: ios-testflight
description: Build, test, archive and upload the Awaira iPhone app (this repo) to App Store Connect / TestFlight, including build-number bump and App Review paywall screenshots.
disable-model-invocation: true
---

# iPhone build → TestFlight

Run everything from the repo root. Uploading a build is outward-facing, so confirm with the user before the upload step.

## 1. Bump the version
Edit `project.yml`:
- `CURRENT_PROJECT_VERSION`: always increment. App Store Connect rejects a duplicate build number.
- `MARKETING_VERSION`: only for a new user-facing release. Ask the user if you're unsure.

Then run `make generate`.

## 2. Test
- `make test` runs unit and UI tests on `SIMULATOR` (default "iPhone 17"). All must pass.
- If `ParityTests` fails, the detection constants have drifted from the Mac `Detector.swift`. Fix the drift; don't just update the test.

## 3. Review screenshots (only if the paywall or pricing changed)
- `make review-screenshots` regenerates `ReviewScreenshots/Awaira-{Monthly,Yearly,Lifetime}-review.png`. These go with the IAP products in App Store Connect.
- Check that the renewal and trial disclosure text is visible in them.

## 4. Archive
```sh
xcodebuild -project Awaira.xcodeproj -scheme Awaira -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build-testflight/Awaira.xcarchive \
  -allowProvisioningUpdates archive
```

## 5. Export and upload (confirm with the user first)
1. Use `build-testflight/ExportOptions.plist` (gitignored; create it if missing) with these keys:
   - `method` = `app-store-connect`
   - `teamID` = `S6HG6FS5JJ`
   - `signingStyle` = `automatic`
   - `uploadSymbols` = true
   - `destination` = **`upload`**
2. Run:
   ```sh
   xcodebuild -exportArchive -archivePath build-testflight/Awaira.xcarchive \
     -exportOptionsPlist build-testflight/ExportOptions.plist \
     -exportPath build-testflight/upload -allowProvisioningUpdates
   ```
   With `destination=export` instead, you get an `.ipa` for manual upload through Transporter.

## 6. Verify
- The upload log ends with "Upload succeeded". The build then shows up in App Store Connect → TestFlight after processing, which usually takes 5–30 minutes.
- Commit the `project.yml` bump (and any new review screenshots) with a short message, e.g. "Bump iPhone build to 10". Only commit when the user asks. `build-testflight/` is gitignored.
