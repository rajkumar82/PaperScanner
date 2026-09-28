# PaperScanner

A Flutter (Android) app that turns your phone into a document scanner: point the phone at a
page on an overhead stand, tap **Start**, and each page is captured automatically as it's
turned. Tap **Stop** any time to share a PDF of the scanned pages.

## How it works

- **Capture** (`lib/screens/capture_screen.dart`): polls the camera for a still shot roughly
  every 800ms, triggers a fresh autofocus first, then hands the frame to the page locator.
- **Page location** (`lib/services/page_locator.dart`): finds the sheet of paper in the photo,
  perspective-corrects and crops to just that region (rejecting a shot if no confident
  page-sized, in-focus region is found), so background clutter around the page never reaches
  the exported PDF and the page comes out deskewed.
- **Processing** (`lib/services/page_processor.dart`): resizes the cropped page to
  display/export resolution. Runs off the UI thread via `compute()`, so a page's resize runs in
  the background while the camera keeps watching for the next page turn.
- **PDF** (`lib/services/pdf_service.dart`): compiles the captured pages into a PDF and hands it
  off through Android's share sheet.

Everything for a scan lives in a scratch folder under temp storage and is wiped the next time
you tap Start - nothing persists between sessions in this version.

## Launcher icon

A white page with a red-circled green checkmark, drawn programmatically (not hand-designed) by
`tool/gen_icon.dart` using the `image` package already in the project. To change the design,
edit that script and regenerate:

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
- Page location (`lib/services/page_locator.dart`) was tuned against real captures but will
  likely need further adjustment for other lighting/background/pen combinations.
