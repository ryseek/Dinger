# Android prototype

The Android app is a working ARM64 prototype backed by the same Swift business logic and SQLite database as the iOS app. Android owns navigation, state, file pickers, and Compose UI; it does not duplicate dictionary, card, SRS, backup, reporting, or quiz rules.

## Architecture

```text
iOS / SwiftUI ───────────────────────────────┐
                                             ▼
                                      DingerCore (Swift)
                                      ├─ persistence + migrations
Android / Compose                            ├─ dictionary + history + examples
  └─ DingerRepository                       ├─ decks + cards + backup + SRS
      └─ JSON over JNI                       ├─ study reporting
          └─ DingerBridgeEngine ─────────────┘
                                             └─ quiz engine
```

`Packages/DingerCore` is the platform-neutral Swift package. `DingerBridgeEngine` exposes coarse user intents through a stable JSON envelope, and `DingerAndroidBridge` is the small JNI entry point. This keeps Kotlin independent of Swift ABI details and keeps cross-language calls out of the Compose screens.

The Android app currently covers:

- German/English/automatic dictionary search, search history, and opened-entry history
- Entry terms, multiple selected translations, examples, and saving cards
- Deck create/rename/delete, card suspend/invert/delete, deck statistics, difficult cards, and study activity
- Individual-deck and all-decks JSON export, plus deck/backup import
- Flashcard, typing, multiple-choice, and mixed quizzes; direction overrides; due and practice modes; examples; grading; and fixing a card meaning

## Prerequisites

- macOS with the open-source Swift 6.3.3 toolchain managed by `swiftly`
- the matching `swift-6.3.3-RELEASE_android` Swift SDK, installed and set up as described by the [official Swift Android guide](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)
- Android SDK platform 35, build tools, platform tools, and an ARM64 API 35 system image for emulator tests
- JDK 17

The Gradle integration expects the Swift executable at `~/.swiftly/bin/swift` and the SDK at SwiftPM's standard macOS location. Override them with `SWIFT_EXEC`, `SWIFT_SDK_PATH`, or `SWIFT_ANDROID_SDK_ROOT` when needed.

Verify the toolchain:

```sh
~/.swiftly/bin/swift --version
~/.swiftly/bin/swift sdk list
java -version
adb version
```

The generated `Dinger/Resources/de-en.sqlite` seed is intentionally ignored by git and must exist before building either app. The normal importer workflow generates it.

## Build

From the repository root:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
cd AndroidApp
./gradlew :app:assembleDebug
```

Gradle performs the native steps automatically:

1. downloads the pinned SQLite 3.47.2 amalgamation and verifies its SHA-256 checksum;
2. builds SQLite with FTS5 for Android API 28/ARM64;
3. cross-compiles `DingerAndroidBridge` and the complete Swift core;
4. packages the native library and compressed dictionary asset into the APK.

The APK is written to `AndroidApp/app/build/outputs/apk/debug/app-debug.apk`. First launch streams the compressed seed into an atomic on-device database install, so it may take several seconds.

This prototype targets Android 9/API 28 or newer and packages only `arm64-v8a`. Adding device ABIs is a packaging/toolchain task, not a business-logic rewrite.

## Tests

Shared Swift tests, including the coarse JSON boundary:

```sh
cd Packages/DingerCore
~/.swiftly/bin/swift test
```

Kotlin parser tests and an APK build:

```sh
cd AndroidApp
./gradlew :app:testDebugUnitTest :app:assembleDebug
```

With an ARM64 emulator running, execute the real native integration and Compose smoke tests:

```sh
cd AndroidApp
./gradlew :app:connectedDebugAndroidTest
```

The device tests open the shipped database through JNI and exercise search, card creation, deck detail, a typed practice quiz, grading, export, cleanup, app startup, and Compose search.

## Prototype constraints

- The bundled dictionary dominates APK and installed size. A production release should deliver it as an install-time asset pack or first-run download with versioning and resumable integrity checks.
- Only ARM64 is packaged today. Physical x86_64 devices are not supported, although Apple-silicon ARM emulators are.
- The JSON/JNI boundary is deliberately coarse and synchronous at the native entry point; calls are dispatched off the Android main thread. If future features need streaming or cancellation, extend the boundary rather than moving domain rules into Kotlin.
