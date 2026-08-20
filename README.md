# Awaira for iPhone

The iPhone counterpart of the macOS [Awaira](../awaira) app: point the front camera at yourself
and it registers the moment a hand reaches up to your face or head.

This is **part one** — detection, a live overlay that makes the detection visible, and the
reactions:

| | touch registers | hand still there at the set delay |
|---|---|---|
| **app open** | the head-zone frame turns red | the screen blurs |
| **minimized (PiP)** | nothing on screen — the floating window is invisible | the phone buzzes (and the tone plays, if switched on) |

The delay is 3 s unless you change it — there's a **settings** panel at the bottom of the screen
with the floating bar's orientation and thickness, and how long a hand may stay before the app
reacts. Choices are remembered across launches.

No dashboard and no history yet.

Detection is landmark geometry, exactly as on the Mac: find the face box → build a "head zone"
(extended upward for hair) → if a fingertip falls into the zone for three frames, it's a touch.
Everything runs on-device with Apple's frameworks (`AVFoundation` + `Vision`); nothing is uploaded.

## Structure

```
Sources/
├── AwairaApp.swift        — app entry
├── ContentView.swift      — preview + HUD + overlays + the settings panel
├── AppSettings.swift      — the buzz delay, remembered across launches
├── CameraDisplay.swift    — the preview layer + Picture-in-Picture (detection while minimized)
├── PipWindow.swift        — the floating window: a thin, transparent sliver that shows nothing;
│                            its orientation and thickness live here too
├── StashPolicy.swift      — how hard to fight a window swiped into the screen edge
├── Detector.swift         — capture session + Vision requests; holds no detection logic
├── DetectionCore.swift    — the actual detection: zone geometry, stabilization, debounce, levels
├── PreviewGeometry.swift  — normalized coords → view coords under aspect fill
├── DetectionOverlay.swift — head zone + 21-point hand skeleton
├── DimOverlay.swift       — the blur at 3 s, while the app is open
└── Haptics.swift          — the buzz at 3 s while minimized, and how often it repeats
Tests/
├── AwairaTests/           — unit tests (incl. ParityTests, which pins the Mac's constants)
└── AwairaUITests/         — launch smoke test
```

`DetectionCore` is pure Swift — no camera, no Vision, no UIKit. That is what lets the whole
detection behaviour be tested on the simulator, and what makes any drift away from the Mac's
numbers show up as a failing `ParityTests` run.

## Detecting while you're in another app

iOS switches the camera off for backgrounded apps — no exceptions, no background mode. So "keep
watching while I scroll Instagram" is only possible one way: the app doesn't background at all, it
shrinks into a **Picture-in-Picture** window floating over the other app. It's still on screen, so
the capture session is allowed to keep running (`isMultitaskingCameraAccessEnabled`, iOS 18+,
which is why `voip` is in `UIBackgroundModes`).

Minimizing the app starts PiP automatically. Detection, the counter and the 3-second threshold all
keep working. The reactions change shape, because PiP renders only the enqueued frames — no SwiftUI
overlay can appear on top, and nothing at all can be drawn over the rest of the screen (blurring
the whole phone, the way the Mac blurs the whole desktop, is impossible for any third-party iOS
app). So minimized there is nothing to *see*: a three-second touch is *felt* instead, and the buzz
falls back to the system vibration, since `UIFeedbackGenerator` is foreground-only.

That also means the preview is an `AVSampleBufferDisplayLayer` we feed by hand, rather than an
`AVCaptureVideoPreviewLayer` — only the former can be carried into PiP.

### The window is a formality, not a preview

The floating window is not there to be looked at; it's there because iOS only permits the camera
while some of the app's pixels are on screen. So it shows no video, no numbers and no colour —
[PipWindow](Sources/PipWindow.swift) is transparent in every state, and nothing is enqueued into PiP
at all. It used to carry the red frame's job (black → red → bright red at the three-second mark),
but that put a bar on top of whatever the user was doing; minimized, the buzz and the tone are the
reactions now, and the red frame and blur stay with the open app. Its own view is `.clear`, and
`clearBackdrop()` clears the containers AVKit wraps it in — anything the system paints in its own
process is beyond reach, so a faint outline while dragging is possible.

Getting it *small* took the window type, not the content. With a sample-buffer content source the
window's proportions don't follow the frames — a 240×30 strip still produced a tall portrait window
the size of the display layer. `AVPictureInPictureVideoCallViewController` is the one place AVKit
takes a size from us, via `preferredContentSize`; that's what turns the window into a thin bar.

Only the *ratio* travels, though — AVKit picks its own scale, and it picks the full width of the
screen, so the ratio is the whole lever on how tall the bar is: 8:1 came out ~48 pt on an iPhone 11
and 24:1 visibly thinner, which is why `PipWindow.preferredSize` asks for **200:1** by default — the
floor, if there is one, hasn't been hit yet. That ratio is what the settings panel's *bar thickness*
slider moves (the length is fixed; only the thickness changes), from 800:1 down to 20:1.
Absolute size is still not ours: it's the system's, adjusted by the user pinching the window — which
iOS remembers. The HUD prints the size the window actually got (`pip 385×19`), because otherwise
"thinner worked" and "AVKit ignored us" look the same.

Thinness isn't only about being out of the way, either — it's the only defence the app has against
the window being *touched*. The floating window belongs to iOS, in another process; its drag, its
pinch and its tap cannot be refused by a third-party app, and `isUserInteractionEnabled = false` in
`PipWindowController` reaches only the app's own content inside the window, never the frame around
it. So "you shouldn't be able to grab the thread" is not an API call, it's a width: the answer is to
be narrower than a fingertip, and to make sure the touches that do land change nothing — a tap's
restore is refused, and a swipe into the edge is undone (below).

The floating bar uses one fixed portrait ratio. iOS remembers where the user places it; the app only
lets the user adjust thickness, which is applied when PiP next opens.

### The window must not be left in the wall

Swiping the floating window into the screen edge *stashes* it: only a chevron is left, and as far as
iOS is concerned the app now has nothing on screen. So it takes the camera away — with
`AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground`, which
`isMultitaskingCameraAccessEnabled` does **not** shield us from (that flag only covers
`…WithMultipleForegroundApps`). No third-party app can capture without visible pixels.

So the window isn't allowed to stay there. `CameraDisplay` watches
`AVPictureInPictureController.isPictureInPictureSuspended` — via KVO for speed and a 0.3 s poll
because AVKit doesn't document it as observable — and pulls the window back out.
[StashPolicy](Sources/StashPolicy.swift) decides how: first `startPictureInPicture()` on the still
active controller, which lifts the stash while keeping the size the user pinched the window to; then
stop-and-restart, which works but may reset that size. It never stops trying: the wall is a place
where the app is simply blind, so nothing there is worth preserving, and `softRetryAfter` paces the
attempts so that never turns into a spin.

None of which runs by itself, though. With the camera revoked and no pixels on screen, nothing is
holding the process up any more and iOS freezes it — so the code meant to rescue the window never
executes, and the window stays in the wall for good. That is what the background-task assertion in
`beginStashAssertion()` is for: it buys the seconds the retries need. A tap on the window is the one
gesture with no answer at all — iOS brings the app to the front before it asks, and
`restoreUserInterfaceForPictureInPictureStop` returning `false` does not undo that.

Coming back needs one more thing: while the app is stashed, video decoding isn't permitted, so the
renderer sets `requiresFlushToResumeDecoding` and silently drops every frame until it's flushed.
Without that flush the window would stay black after being pulled out, camera or no camera.

And the practical answer to *"I want it out of my way"* is not the wall at all — the window shows
nothing to begin with, and parking it against an edge without letting go into the stash keeps the
invisible sliver out from under your fingers while the camera is still allowed to run.

> The `voip` background mode is honest for a camera app that must stay live, but App Store review
> associates it with calling apps. On your own device via Xcode it just works; before submitting,
> expect to justify it.

## Requirements

- iOS 18.0 or later (a real iPhone — the simulator has no camera)
- Xcode and [XcodeGen](https://github.com/yonbo/XcodeGen)

## Build & run

```bash
make install   # once: install xcodegen, generate the project, build
make device    # build, install and launch on the connected iPhone — the only real test
make unit      # unit tests only (fast, simulator)
make test      # unit + UI tests on the iPhone 17 simulator
make run       # build, install and launch on the simulator
```

Or open it in Xcode:

```bash
xcodegen generate
open Awaira.xcodeproj
```

> `Awaira.xcodeproj` and `Sources/Info.plist` are **generated** from `project.yml` — edit that,
> not them.

`make device` builds for the phone whose UDID is in the Makefile (`DEVICE`), installs and launches
it; `xcrun xctrace list devices` gives you another one's UDID. From Xcode: select your iPhone as the
run destination and hit ▶ — the app needs a signing team either way.

Allow camera access, and you should see yourself, a green box tracking your head, the hand skeleton
when a hand comes into view, the box turning red and the counter ticking on a touch, and the screen
blurring if the hand stays for the set delay (3 s out of the box). Then swipe home: the app shrinks
into a floating window that keeps detecting and shows nothing at all — the reaction you get there is
the buzz, from the delay onwards for as long as the hand stays. The window is invisible but still
draggable; swipe it into the screen edge and it comes straight back out, because it has to count as
on screen for the camera to be allowed at all.

## Parity with the Mac

Same constants, same order of operations: face request every 3rd frame, ~5 fps (dropping to 4/3
as the phone heats up), 3 frames to enter a touch and 5 to leave it, zone EMA 0.5 with outlier
rejection, 0.45 s of coasting through face misses, fingertips 4/8/12/16/20.

Two deliberate differences, both documented in code:

- the blur fires at **3 s** by default (the Mac's is a fixed 2 s), it is adjustable from the
  settings panel, and minimized it becomes a buzz;
- the capture preset is **VGA** rather than the Mac's `.low` — the iPhone's front camera has a
  much wider field of view, so 320×240 would leave the face too small for Vision.

And one thing the Mac can do that the phone cannot: dim the whole screen. See the PiP section above.
