# PaperScanner

A Flutter (Android) app for a teacher to tally marks on a corrected exam booklet: point the
phone at the booklet on an overhead stand, tap **Start**, and each page is captured
automatically as it's turned. Every page is scanned for red-circled numbers, the recognized
marks are drawn back onto the page for a quick sanity check, and a running total is kept live.
Tap **Stop** any time to see the final total and share a PDF of the scanned pages.

## How it works

- **Capture** (`lib/services/capture_gate.dart`): watches the live camera preview for a
  page-turn (motion) followed by the frame settling and coming into focus, then fires the
  shutter automatically. No manual per-page button, no sound - just point and turn pages.
- **Detection** (`lib/services/mark_detector.dart`): finds red ink using the LAB *a\**
  channel (more lighting-stable than a raw HSV hue threshold), then looks for **closed loops**
  in the red mask rather than "circular" shapes - a hand-drawn circle encloses a hole, a tick
  or crossed-out word doesn't. This is what tells a mark apart from ordinary red feedback
  written on the same page.
- **OCR** (`lib/services/ocr_service.dart`): crops the interior of each loop and runs it
  through on-device Google ML Kit, sanitized down to a plausible 0-100 mark.
  The heavy pixel work (mask, connected components, hole detection) runs off the UI thread via
  `compute()`; OCR itself is a platform-channel call and stays on the main isolate, but doesn't
  block the capture loop - a page's processing runs in the background while the camera keeps
  watching for the next page turn.
- **PDF** (`lib/services/pdf_service.dart`): compiles the captured pages (annotated or plain,
  your choice) into a PDF and hands it off through Android's share sheet.

Everything for a scan lives in a scratch folder under temp storage and is wiped the next time
you tap Start - nothing persists between sessions in this version.

## Launcher icon

A white page with a red-circled green checkmark - the app's own "circle a mark" idea, drawn
programmatically (not hand-designed) by `tool/gen_icon.dart` using the `image` package already
in the project. To change the design, edit that script and regenerate:

    dart run tool/gen_icon.dart          # writes assets/icon/icon.png and foreground.png
    dart run flutter_launcher_icons      # regenerates all android/app/src/main/res mipmaps

## Run locally

    flutter pub get
    flutter run            # needs an Android device or emulator; camera won't work in a simulator without a real/virtual camera
    flutter build apk --debug   # builds build/app/outputs/flutter-apk/app-debug.apk without needing a connected device

Verified working end to end on this machine: `flutter build apk --debug` completes and
produces an installable APK.

## Notes / current limitations (v1)

- Android only.
- No per-mark correction UI yet - the live annotated overlay during capture is the review
  step; a page with nothing detected shows `-0-`.
- No printed-total cross-check yet (this exam format prints `[Total: N]` per question in
  black ink, which would be a natural free sanity check to add later).
- No PDF header/student name field yet - the exported PDF is just the pages.
- Detection thresholds (`lib/services/mark_detector.dart`) were tuned against a real scanned
  exam page but will likely need further adjustment once tried against actual phone-camera
  captures under a gooseneck stand with a specific pen/lighting combination.
