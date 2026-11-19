# github-mobile-maxxing

A fast, custom **GitHub client** built with **Kotlin Multiplatform (KMP)** and **Compose Multiplatform**, targeting **Android**, **iOS**, and **Linux Desktop**, powered by **Material 3 Expressive (MD3E)**.

## Features
- **GitHub OAuth Device Flow**: Zero-secret GitHub OAuth Device Flow (`https://github.com/login/device/code`) with a bundled default Client ID (`Ov23lihCAIZTj1Puaf9r`), external browser launch, one-click code copy, and adaptive polling (`slow_down` / `authorization_pending`). Custom OAuth Client IDs can also be configured optionally on the Sign-In or Settings screen.
- **Platform-Native Secure Token Storage**:
  - **Android**: Hardware-backed Android Keystore AES-256-GCM encrypted session storage.
  - **iOS**: iOS Keychain (`kSecClassGenericPassword`) for session credentials with non-sensitive preferences in `NSUserDefaults`.
  - **Linux**: Freedesktop Secret Service (`secret-tool` / GNOME Keyring / KDE KWallet) with owner-only (`0600`) XDG Data fallback.
- **Inbox & OS Notifications**:
  - Swipe-to-done / mark-read triage, Unread/Participating/All filter, and adaptive split-pane Issue/PR preview.
  - Background notification polling (Android WorkManager / Desktop notifications) with notification deep links (`githubmaxxing://thread/...`).
- **Issues & Pull Requests**:
  - Single-query GraphQL timeline (Markdown comments & editing, reactions, reviews, commits, labels, assignees, milestones).
  - Inline unified Diff viewer and tap-to-open **full-screen Diff viewer** (word-wrap toggle, font size controls, prev/next file switching).
  - PR Review submission (`Approve` / `Request Changes` / `Comment`), Merge `SplitButton` (`Squash` / `Merge Commit` / `Rebase`), full-screen Markdown editor with live preview, and Issue creation with label selection/creation.
- **Repositories, Profiles & Gists**:
  - My Repos, Starred, Global Search (Repos / Issues & PRs / Code / Users), Branch & tag switcher, File Tree + syntax-highlighted Code Viewer, inline file create/edit/delete, and README Markdown rendering.
  - Star/Watch/Fork/Network/Share (`Copy URL`, system share, browser), open Issue/PR tab counts (`Issues (N)` / `PRs (M)`), Commits & Branch Compare, Actions & Job Logs, Releases, Discussions, Security alerts, Insights, User Profiles, and Gists.
- **Android App Links (`github.com`)**:
  - Opens `https://github.com/...` repository, issue, PR, and user links directly in-app, with Settings shortcuts to unlink official GitHub Mobile and enable `github.com` link handling for `github-mobile-maxxing`.
- **Material 3 Expressive (MD3E) & Typography**:
  - `MaterialExpressiveTheme` + `MotionScheme.expressive()` + MaterialKolor `SPEC_2025` dynamic palettes + Android 12+ Wallpaper Dynamic Color.
  - Curated seed color presets, interactive **Custom Accent Color** picker (HSV pad, Hue bar, `#RRGGBB` input), and customizable **Primary + per-glyph Fallback** fonts (system fonts, generic families, and `.ttf`/`.otf`/`.ttc` import; Android & Linux Desktop).

## Downloads
- **Stable Releases**: Signed Android APK (`github-mobile-maxxing-release.apk`) and Linux `x86_64` AppImage (`github-mobile-maxxing-x86_64.AppImage`) on the [Releases](https://github.com/neutron42-jp/github-mobile-maxxing/releases) page.
- **Nightly Builds**: Automated `nightly` prereleases built from `main` (Obtainium-compatible).

## Setup & Build

### 1. GitHub OAuth Client ID (Optional)
A default Device Flow Client ID (`Ov23lihCAIZTj1Puaf9r`) is built in out of the box. To use your own OAuth/GitHub App instead:
1. Enable **Device Flow** in your GitHub OAuth/GitHub App settings.
2. Add `github.client.id=YOUR_CLIENT_ID` to `local.properties` to bake it in at build time, **or** enter a custom Client ID on the Sign-In or Settings screen.

### 2. Build & Run

#### Linux Desktop
```bash
./gradlew :composeApp:run
```
Create a standalone Linux `AppImage` (`composeApp/build/compose/binaries/main/appimage/github-mobile-maxxing-x86_64.AppImage`):
```bash
./gradlew :composeApp:packageLinuxAppImage
```

#### Android
Build the R8-optimized release APK (uses release keystore if configured via `ANDROID_KEYSTORE_*` / `local.properties`, otherwise falls back to the debug keystore for local `adb install`):
```bash
./gradlew :androidApp:assembleRelease
```
Output APK: `androidApp/build/outputs/apk/release/androidApp-release.apk`.

Debug build (unminified, useful for profiling/debugging):
```bash
./gradlew :androidApp:assembleDebug
```
Output APK: `androidApp/build/outputs/apk/debug/androidApp-debug.apk`.

#### iOS
Requires macOS, Xcode (with an iOS Simulator runtime), and JDK 17+.

- **Xcode JDK configuration (if needed)**: Copy `iosApp/Configuration/local.env.example` to `iosApp/Configuration/local.env` and set `JAVA_HOME` if building from the Xcode GUI cannot locate it via `/usr/libexec/java_home`.
- **Device signing (optional)**: Simulator builds require no signing. For physical devices, copy `iosApp/Configuration/Local.xcconfig.example` to `iosApp/Configuration/Local.xcconfig` and set `TEAM_ID`.
- **XcodeGen**: `iosApp/iosApp.xcodeproj` is checked in. Only run `xcodegen generate` inside `iosApp/` if you edit `iosApp/project.yml`.

Build for the iOS Simulator (also compiles and embeds `ComposeApp.framework` via Gradle):
```bash
xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Or open `iosApp/iosApp.xcodeproj` in Xcode and run on a simulator or device.

#### Maxxing Glass — unofficial SwiftUI iOS app (this fork only)
> **Maxxing Glass** is an unofficial derivative of [github-mobile-maxxing](https://github.com/neutron42-jp/github-mobile-maxxing), maintained in this fork. It is not part of the upstream project, which keeps Material 3 Expressive as its design; please report issues with this app to this fork, not upstream.

`iosNativeApp/` is a SwiftUI front end that adopts iOS 26 **Liquid Glass** (glass tab bar with a separate search tab and scroll-to-minimize, `GlassEffectContainer` filter chips and action bars with morphing, glass/glass-prominent buttons, and a floating glass comment composer). Auth, networking, caching and models are **not** reimplemented: they come from the shared `core/model`, `core/auth` and `core/network` modules through the `MaxxingShared` framework, so fixes there apply to both iOS apps. It installs side by side with the upstream Compose app (bundle ID `io.github.luna1-sol.maxxingglass`, URL scheme `githubmaxxing-native://`).

Requires macOS, Xcode 26+ with an iOS 26 Simulator runtime, and JDK 17+ (the Xcode build runs Gradle; the Android SDK is not needed).

- **Architecture**: `iosNativeApp/shared` is the `:iosNativeShared` Gradle module. It exports the core modules as the static `MaxxingShared` framework and adds `MaxxingCore`, a small facade that turns `Result`/`Flow` APIs into Swift-friendly `async throws` functions and callbacks. On the Swift side, `Core/Bridge` maps the Kotlin models to Swift value types, `Core/Network/GitHubRepository.swift` and `Core/Auth/SessionManager.swift` wrap `MaxxingCore`, and `App/` holds the SwiftUI screens (mirroring `composeApp`).
- **Ported screens so far**: Device Flow / PAT sign-in, Home (contributions, pinned & recent repos, activity feed), Inbox (filters, swipe to done / mark read), Issues & PRs (presets, timeline, comments, reactions, review, merge, draft toggle, file diffs), Repositories (detail, star/watch, branch switcher, file tree, code viewer, README, commits), user profiles, global search, and settings.
- **Screens not ported yet** (available in the Compose app): Actions, Releases, Discussions, Security, Insights, Gists, labels/milestones management, file editing, background notifications. The data layer for these already exists in `core/network`; they need SwiftUI screens and `MaxxingCore` entry points.
- **XcodeGen**: `iosNativeApp/iosNativeApp.xcodeproj` is checked in. Only run `xcodegen generate` inside `iosNativeApp/` if you edit `iosNativeApp/project.yml` or add/remove files.
- **Building from the Xcode GUI**: if Xcode cannot find a JDK, copy `iosNativeApp/Configuration/local.env.example` to `iosNativeApp/Configuration/local.env` and set `JAVA_HOME`.
- **Device signing (optional)**: copy `iosNativeApp/Configuration/Local.xcconfig.example` to `iosNativeApp/Configuration/Local.xcconfig` and set `TEAM_ID`.
- **OAuth App**: sign-in uses the Client ID in `OAUTH_CLIENT_ID` (`iosNativeApp/Configuration/Config.xcconfig`, overridable in `Local.xcconfig`). The OAuth App must have Device Flow enabled.

```bash
xcodebuild -project iosNativeApp/iosNativeApp.xcodeproj -scheme iosNativeApp -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Unit tests (Swift Testing):
```bash
xcodebuild test -project iosNativeApp/iosNativeApp.xcodeproj -scheme iosNativeApp -destination 'platform=iOS Simulator,name=<SIMULATOR_NAME>'
```

#### Tests
```bash
./gradlew \
  :core:model:desktopTest \
  :core:auth:desktopTest \
  :core:ui:desktopTest \
  :core:network:desktopTest \
  :composeApp:desktopTest \
  :composeApp:testAndroidHostTest
```

On macOS, run the KMP iOS simulator tests, `iosArm64` compilation checks, and UI smoke tests (`:core:auth:iosSimulatorArm64Test` requires an iOS Simulator to be booted via Xcode or `xcrun simctl boot <SIMULATOR_UDID>` for Keychain access):
```bash
./gradlew \
  :core:auth:iosSimulatorArm64Test \
  :core:network:iosSimulatorArm64Test \
  :core:ui:iosSimulatorArm64Test \
  :composeApp:iosSimulatorArm64Test \
  :core:model:compileKotlinIosArm64 \
  :composeApp:compileKotlinIosArm64

xcodebuild test -project iosApp/iosApp.xcodeproj -scheme iosApp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=<SIMULATOR_NAME>' -only-testing:iosAppUITests/LaunchSmokeTests
```
 
