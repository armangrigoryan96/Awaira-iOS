# Awaira for iPhone

Awaira is an on-device awareness tool for hair pulling, nail biting, skin picking, and general
face touching. It uses the front camera to detect hand-to-face movements and presents gentle cues
that help people notice the moment before an automatic habit continues.

Camera frames are analyzed on the iPhone and discarded after analysis. They are never uploaded.

## Foreground-only tracking

Awaira tracks only while it is open and visible on screen. If a person goes to the Home Screen,
locks the phone, or switches to another app, iOS stops camera capture. Tracking resumes when they
return to Awaira, unless they have paused it from the camera control in the Today header.

This is intentional: the iPhone app does not use VoIP, Picture in Picture, or a background-camera
workaround to continue monitoring outside the app.

## Structure

```
Sources/
├── AwairaApp.swift        — app entry and onboarding routing
├── ContentView.swift      — tabs, overlays, and settings presentation
├── Detector.swift         — capture session and Vision integration
├── DetectionCore.swift    — pure touch-detection geometry and timing
├── TodayView.swift        — daily dashboard
├── MobileInsightsView.swift — patterns dashboard
├── MobileJournal.swift    — private, on-device reflections
├── MobileSettingsView.swift — appearance and cue preferences
└── PrivacyInfo.xcprivacy — App Store privacy declarations
Tests/
├── AwairaTests/           — unit tests
└── AwairaUITests/         — launch smoke tests
```

## Requirements

- iOS 18.0 or later
- Xcode and [XcodeGen](https://github.com/yonbo/XcodeGen)

## Build and run

```bash
make install   # generate the Xcode project and build
make build     # build for the simulator
make unit      # run unit tests
make test      # run unit and UI tests
make run       # build and run in the simulator
make device    # build and run on a connected iPhone
```
