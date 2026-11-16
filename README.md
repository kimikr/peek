# peek

**SwiftUI previews on a real iPhone, built on Linux. No Mac.**

![Editing a SwiftUI view on Linux; the iPhone updates a second later](docs/demo.gif)

Save a file, and a second or two later the view on your phone is replaced with
the new one. It is your real code, compiled by the real Swift compiler and
drawn by the real SwiftUI on the device, so every API, animation and gesture
behaves exactly as it will in your app.

- **Fast, and keeps your state.** Incremental builds: an edit in a 2,000-line app
  is on the phone in 1–2 s, and when you only change function bodies the running
  views are patched in place, so `@State` survives the reload.
- **Your whole app.** `#Preview` blocks, UIKit views and controllers, or the
  entire `@main` App (`DocumentGroup` too), with Swift, C, Objective-C, C++ and
  `.xcframework` dependencies, macros, resources, colour sets and asset symbols.
- **Tests on the device.** `peek test` runs your Swift Testing and XCTest suites on the
  iPhone, with real UIKit and SwiftUI, every time you save.
- **No Mac, no paid account.** A free Apple ID and SideStore, AltStore or
  LiveContainer is enough.
- **Logs and screenshots.** `print()` output shows up in your terminal, and
  `peek shot` saves a screenshot of the phone.
- **One file, no dependencies.** The dev server is a single Python script
  (standard library only) next to xtool's Swift toolchain.

```
$ peek dev MyApp/
[12:06:52] built + signed in 1.3s → v1 (Counter, List)
```

> **Status: early.** See [what has been tested](#tested).

## How it works

```
 Linux                                         iPhone
 ─────                                         ──────
 *.swift ──swiftc + iOS SDK──▶ preview.dylib
                 │ sign with your dev certificate
                 ▼
            peek dev server ── encrypted HTTP ──▶  Peek app: dlopen() → UIHostingController
```

1. `peek dev` watches your sources. On every change it cross-compiles them
   into an arm64 iOS dynamic library (`#Preview` blocks become entry points).
   Compilation is incremental: only the files an edit affects are compiled
   again, so a save in a 2,000-line app takes 1–2 s instead of 9.
2. It signs the library with your development certificate.
3. The Peek app on the phone long-polls the server, downloads the new
   library, `dlopen()`s it and shows the preview.

Package dependencies are linked into a separate library that the phone
downloads once and keeps, so each reload only carries your own code.

**State survives body edits.** Full builds are compiled so that any function
can be replaced later (the way Xcode previews work). When an edit only touches
the bodies of functions and computed properties (`body` included), peek sends
a small patch with just those bodies; the phone loads it into the running
build and re-renders, so views keep their identity and `@State`. Adding or
changing stored properties, types or signatures needs a full build, which
peek falls back to on its own (`--no-hot` always does full builds).

iOS refuses to load code that is not signed by a certificate in a provisioning
profile on the device with the same Team ID as the running app. So the library
must be signed with the certificate your sideloading store (SideStore /
AltStore) signed the Peek app with. The app asks the store for that
certificate once and sends it, encrypted, to your dev server.

The signature also has to carry the right *identifier*. A free Apple ID's
profile covers one explicit app ID, and iOS matches code that has no
entitlements of its own against it by signing identifier, so a library signed
under any other name is rejected as `code signature invalid` even with the
right certificate. The app therefore tells the server the bundle identifier of
the process it runs in, and the server signs every build under that name.

## Requirements

On the Linux machine:

- Swift 6 toolchain and the Darwin Swift SDK, both from
  [xtool](https://github.com/xtool-org/xtool) (`xtool setup`)
- [`ldid`](https://github.com/ProcursusTeam/ldid) and `openssl`
- Python 3.9+ (standard library only)

On the iPhone (iOS 17+):

- SideStore or AltStore, to install the Peek app, or
  [LiveContainer](https://github.com/LiveContainer/LiveContainer) set up in
  JIT-less mode, to run it without using one of your three app slots
- The phone and the Linux machine on the same Wi-Fi **or** the same
  [Tailscale](https://tailscale.com) network

## Quick start

```sh
# 1. Install peek (and ldid, if missing) into ~/.local
curl -fsSL https://raw.githubusercontent.com/kimikr/peek/main/scripts/install.sh | sh

# 2. Check that everything is in place
peek doctor

# 3. Start previewing
peek dev ~/.local/share/peek/examples/Counter
```

On the phone, install `Peek-<version>.ipa` from the [releases](../../releases)
with SideStore or AltStore (they sign it for you), or add it to LiveContainer.
Use the app and the `peek` script from the same release; if they don't match,
the app says so. To build the app yourself: `cd host && xtool dev build --ipa -c release`.

`peek dev` prints a QR code and a pairing link. Scan the code with the Camera
app (Peek asks you to confirm the server) or paste the link into Peek. The
first time, tap **Import from SideStore** in the app to hand over the signing
certificate.

**Inside LiveContainer.** Install the IPA in LiveContainer instead. The store
cannot call back into a guest app, so export the certificate from the store as
a `.p12` file and use **Import a .p12 file…**. It must be the certificate
LiveContainer itself is signed with.

Then edit `examples/Counter/ContentView.swift` and save.

**Something not working?** `peek doctor` checks the toolchain, the iOS SDK,
ldid, the signing certificate (and when it expires), the network addresses,
whether the dev server is running, which phones connected with which app
version, and does a test build.

### What gets previewed

- Every `#Preview { ... }` block (switch between them from the green dot menu
  in the app). `@Previewable` works, and a preview may return a SwiftUI
  view, a `UIViewController` or a `UIView`.
- Without any `#Preview`: the whole app. The `@main` App's first
  `WindowGroup` is shown as a view (`--app` forces this even when previews
  exist); a `DocumentGroup` opens one new, unsaved document. Other scenes are
  left out, scene modifiers (`.commands`, `.defaultSize`, …) are ignored, and
  `@UIApplicationDelegateAdaptor` creates your delegate and calls
  `application(_:didFinishLaunchingWithOptions:)`.
- Otherwise `ContentView`, or the first `View` struct found.
- Or say it explicitly: `peek dev . --root "SettingsView(model: .sample)"`.

### What gets compiled

| You run | peek compiles |
| --- | --- |
| `peek dev File.swift` | just that file |
| `peek dev Folder/` | every `.swift` file under `Folder/Sources` (or `Folder/`) |
| `peek dev Package/` (has a `Package.swift`) | the app's target, linked against its package dependencies |

**Build settings.** In a package, the previewed target's Swift language mode
and `swiftSettings` (`define`, upcoming and experimental features, default
isolation, `unsafeFlags`) and linker settings are applied.

**Package dependencies.** In a package, peek first builds the previewed
target's dependencies with SwiftPM (`swift build`, the same way xtool does),
links them into one library the phone downloads once, and runs the macros
SwiftPM built. The previewed target itself is never built by SwiftPM: peek
compiles it, unpacks its `.xcframework`s and assembles its resource bundle.
That first build is slow; after it, saving a file in the previewed target takes
the fast path again. Editing `Package.swift` or a dependency's sources triggers
the SwiftPM build again. Use `--target` to pick a target other than the app's.

**C, Objective-C, C++ and binary dependencies.** C-family targets are compiled by
SwiftPM and imported through their module maps. A target with
`.interoperabilityMode(.Cxx)` is compiled with C++ interoperability, and the
C++ standard library is linked when any target has C++ sources. Static libraries from
`.xcframework` binary targets are linked into the dependency library; dynamic
frameworks are signed and sent to the phone once.

**Resources.** `Image("photo", bundle: .module)`, `Bundle.module.url(...)`
and custom fonts work: resource bundles (the previewed target's and its
dependencies') are sent to the phone alongside the build. Outside a package,
files in folders named `Resources` are bundled the same way. Asset catalogs
cannot be compiled without a Mac, so peek works around it: image sets are sent
as loose images, colour sets (light and dark) become generated code, and
`Image("name")`, `UIImage(named:)`, `Color("name")` and `UIColor(named:)` with
a literal name of such an asset are pointed at them. The asset symbols Xcode
generates (`Color(.brand)`, `.foregroundStyle(.brand)`, `Image(.logo)`,
`UIColor(resource:)`, `UIImage(resource:)`) are generated the same way.
String catalogs (`.xcstrings`) become `.strings` and `.stringsdict` files
(plurals included), so `String(localized:bundle: .module)` is translated.

See `examples/Weather` for a package with a dependency and a resource, and
`examples/Calculator` for one with Swift Testing tests (`peek test`).

### While previewing

- **Output.** `print()` and anything else written to stdout or stderr shows
  up in the `peek dev` terminal, prefixed with `│`. When a build crashes the
  app, its last output (a `fatalError` message, say) is sent the next time
  Peek starts.
- **Screenshots.** `peek shot` saves what the phone is showing as a PNG
  (`-o file.png` to name it).
- **Display.** The menu (green dot) switches the preview between light and
  dark appearance and between text sizes, without touching the phone's
  settings.
- **Errors.** A compile error is shown over the last preview that worked. So
  is a build that fails to load: the previous one stays on screen.

### Running tests on the phone

```
peek test path/to/Package
```

runs the package's [Swift Testing](https://developer.apple.com/documentation/testing)
and XCTest tests inside the Peek app on the iPhone, with the real UIKit and SwiftUI, and
again every time you save. So tests that render views (`ImageRenderer`), use
UIKit or need the device run from Linux, where `swift test` cannot run them.
Results appear in the terminal as `swift test` prints them (failures in red,
with file and line); the phone shows whether everything passed and which tests
failed. `--filter REGEX` runs only the tests whose `Suite/test` name matches.

For a script, a git hook or CI with a phone attached, `--once` runs the tests
once and exits with their result (0 when everything passed, 1 when a test or
the build failed), and `--junit FILE` writes each run's results as JUnit XML,
which CI services show as test results:

```sh
peek test --once --junit results.xml
```

The test targets that depend on the previewed target are compiled into the
same module as the code they test (`@testable import` is not needed but does
no harm), along with their dependencies. Outside a package, tests come from
`Tests/` next to `Sources/`. Testing.framework and XCTest come from the iOS
SDK; peek signs them and sends them to the phone once (about 22 MB with XCTest).

XCTest normally talks to `testmanagerd`, a service that only runs once Xcode
has prepared the phone for development; unit tests do not need it, so peek
runs them without it.

#### UI tests (XCUITest)

Plain XCUITests run too, unchanged:

```swift
final class TallyUITests: XCTestCase {
    @MainActor func testAdd() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["START_COUNT": "5"]
        app.launch()
        app.buttons["Add"].tap()
        XCTAssertEqual(app.staticTexts["count"].label, "Count: 6")
    }
}
```

While they run, the phone shows the app being tested (its first `#Preview`,
or the `@main` App) and the tests drive it: taps, typing, swipes, long
presses, toggles and sliders, the home button, rotation
(`XCUIDevice.shared.orientation`), screenshots, system alerts (through
`XCUIApplication(bundleIdentifier: "com.apple.springboard")`), and other apps
such as Settings. `XCUIApplication()` is the app in Peek; `launch()` starts it
afresh with its `launchArguments` (also as `UserDefaults`) and
`launchEnvironment`, and `terminate()` takes it off screen (its state is then
`.notRunning`) until `launch()` or `activate()`. See `examples/Calculator/Tests/CalcTests/TallyUITests.swift`.

UI tests need what Xcode would set up:

1. **Developer Mode** on (Settings → Privacy & Security), which sideloading
   with a development certificate usually offers already.
2. **The developer disk image**, which brings `testmanagerd`. Mount it with
   [StikDebug](https://github.com/StephenDev0/StikDebug) (pair it once in its
   settings, then open it with LocalDevVPN connected); it stays mounted until
   the phone restarts.
3. **Your passcode** for each run of the UI tests: they switch the phone to
   Automation Mode, iOS asks before doing so, and the mode ends with the run.

How peek gets there without Xcode: it points XCTest at the iOS 27 name of the
daemon's service (`com.apple.dt.testmanagerd.runner`), gives it the
configuration Xcode would hand a UI test runner, asks for Automation Mode,
starts the app's accessibility server (apps only do that when launched under
automation), and replaces the waits on an in-app agent that only Xcode
injects with short pauses. While another app is in front, Peek keeps running
with a background task and, if the app hosting it allows background audio
(LiveContainer does), silent audio.

Limits:

- The app runs in Peek's process, so `launch()` and `terminate()` do not start
  or end a process: globals, singletons and files keep their state between
  launches (reset them through `launchArguments` if a test needs a clean
  start), and launch-time metrics (`XCTApplicationLaunchMetric`) mean nothing.
- `resetAuthorizationStatus(for:)` would terminate Peek, and permission alerts
  only appear while the app hosting Peek has not answered them yet.
- There is no `.xcresult` bundle; use `--junit` for machine-readable results.
- It needs a phone: there is no iOS simulator outside macOS.

### Finding the server

The pairing link holds the server's addresses. On the same Wi-Fi the server
also advertises itself with Bonjour (`_peek._tcp`), so an already paired phone
finds it again when its address changes. Over Tailscale, the Tailscale address
in the link is used. Pair with `peek link --qr` at any time.

## Limitations

- **State resets on full builds.** Body-only edits keep it; anything that
  changes the shape of your types (stored properties, new types or methods,
  signatures, resources) reloads the build and starts fresh.
- **Rebuild time.** The first build of a project compiles everything (about
  9 s for 2,000 lines on a 2-core machine); after that an edit takes 1–2 s.
  Every build is loaded under the same module name; if that causes trouble,
  `--no-incremental` builds each version as a module of its own.
- **Views that opt out of re-rendering** (`Equatable` views, `.equatable()`)
  show a hot-patched body only once their inputs change.
- **Asset catalogs** are not compiled: only image sets with one image per
  scale (no dark or size variants) and colour sets are available. A
  dependency (not the previewed target) with an asset catalog or a string
  catalog cannot be built, since SwiftPM needs Xcode's tools for those; nor
  can a package with its own macro targets whose previewed target has an
  asset catalog (macros make SwiftPM build the whole package). A
  `DocumentGroup` that only views documents shows a placeholder, since there is
  no document to open.
- **The preview lives in the Peek app's sandbox.** `UserDefaults`, the
  keychain and files are Peek's, so nothing your installed app has saved
  (settings, logins, caches) is there.
- **`Bundle.main` is the Peek app's bundle**, so `Image("name")` without
  `bundle: .module`, your `Info.plist` keys, URL schemes, app extensions and
  entitlements (HealthKit, push, iCloud, App Groups, …) are not your app's.
- **A crash in your view crashes the Peek app.** When you open it again it
  shows what the build printed last (a `fatalError` message, say) and loads
  the next build on its own.
- **Previewing Peek with Peek** shows "The last build quit the app" in the
  inner copy, because both copies share one set of preferences.
- **Old builds stay in memory** until the app is restarted (dependencies
  are loaded once). When memory runs low, the green dot turns orange and the
  menu offers to quit Peek; open it again and the newest build loads.
- **Free Apple IDs:** the certificate changes when the store re-issues it;
  import it again when builds stop loading.

## Security

- The dev server only listens while `peek dev` runs, and only on the addresses
  in the pairing link and on loopback, not on every interface. Use `--bind` to
  choose another one.
- The pairing link contains a random 128-bit key that is shown on your
  terminal and never sent over the network. Requests are authenticated with
  HMAC-SHA256 over the method, path, time, body and the headers the server
  acts on. Everything the server sends (builds, compiler output, resources)
  and everything sensitive the phone sends (the certificate, screenshots) is
  encrypted with AES-256-CTR and authenticated with HMAC-SHA256, using keys
  derived from it.
- A pairing link opened from outside the app (Camera, Safari, another app)
  must be confirmed before Peek connects, and a certificate handed over by
  another app is only accepted right after you asked the store for it. A web
  page cannot silently point Peek at someone else's server.
- The certificate password never appears on a command line (`ps`); files
  holding key material are created readable by you only.
- Your signing certificate and private key are stored on the Linux machine in
  `~/.peek/cert.p12` (mode 0600). Anyone who can read it can sign code that
  your phone will run inside sideloaded apps. Delete it when you are done on a
  shared machine.
- The connection itself is plain HTTP, so the request lines (paths such as
  `/v1/dylib/12`) and sizes are visible on the network; the contents are not.
  A request captured on the network could be replayed within its 5-minute
  window; that only repeats something the phone already did, and the reply is
  still encrypted.

## Tested

| | |
| --- | --- |
| iPhone, iOS 27, Peek inside LiveContainer (SideStore, free Apple ID), Tailscale | ✅ loads and hot-reloads Counter, Peek itself, and two real apps (resources, a local package, the iOS 26 tab bar) |
| Builds on Linux: examples, three real apps, UIKit previews, App rewriting | ✅ |
| Server test suite (`python3 -m unittest discover tests`) | ✅ |
| On that phone: encrypted protocol, incremental reload, dependency library, `print()` output, `peek shot`, light/dark and text size | ✅ |
| 0.2 on that phone: hot patching keeps `@State` across body edits, chained patches, closure changes, fallback to a full build | ✅ |
| 0.2 on that phone: colour sets (light and dark), system colour references, asset symbols, image sets, string catalogs (plurals, Korean), C, Objective-C and C++ dependencies, static and dynamic `.xcframework`s, `DocumentGroup` | ✅ |
| `peek test` on that phone: Swift Testing suites, parameterized tests, XCTest test cases, `ImageRenderer`, failures with file and line, re-run on save | ✅ |
| Peek installed directly with SideStore / AltStore | ⏳ not yet |
| Bonjour discovery on a real Wi-Fi network | ⏳ not yet |

## Development

```sh
python3 -m unittest discover tests     # tests (Python + openssl only)
./peek doctor                          # check the local setup
./peek build examples/Weather          # compile once, print errors
scripts/release-ipa.sh                 # unsigned IPA for a release
```

## License

MIT
