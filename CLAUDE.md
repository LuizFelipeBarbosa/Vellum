# CLAUDE.md

Working notes for agents on this repo. Everything here is verifiable from the source
at the cited path; the point of the file is that the failure modes are non-obvious and
expensive to rediscover.

Open quality issues and the rationale for recent structural work live in
`docs/quality-report.md`. Measured baselines live in `docs/quality-baseline.md`.

## `xcodegen generate` is mandatory

`project.yml` declares directory-based sources (`sources: - path: Vellum`, and the
same for `VellumUITests` / `VellumFlowUITests`), and `.gitignore:5` ignores
`*.xcodeproj`. So:

- A fresh clone has **no project file at all**. `xcodebuild` fails until you run
  `xcodegen generate`.
- After **adding or removing** any file under `Vellum/`, `VellumUITests/`, or
  `VellumFlowUITests/`, you must run `xcodegen generate` again. The build otherwise
  compiles the old file list, and the failure presents as `cannot find 'X' in scope`
  for a type you just wrote — or, worse, a build that succeeds against a file you
  just deleted.
- Also beware the inverse: after `xcodegen generate`, a stale `DerivedData` can report
  `TEST SUCCEEDED` while running fewer tests. Compare the **test count**, not the
  status line (`docs/quality-baseline.md`).

## The test targets are misnamed

| Target | XcodeGen type | What it actually is |
|---|---|---|
| `VellumUITests` | `bundle.unit-test` (+ `TEST_HOST`) | **Unit tests.** 364 XCTest functions across 36 files, **zero** `XCUIApplication`. Runs in-process against the app. |
| `VellumFlowUITests` | `bundle.ui-testing` | The real XCUITest target. 43 tests across 11 files, drives the simulator, owns every launch-argument contract. |

Asked to "add a UI test", the name alone points at the wrong target. Decide by what
the test does: touching a model or a pure function → `VellumUITests`; needing a real
tap, drag, or launch argument → `VellumFlowUITests`.

The `VellumUITests` name is known-bad and deliberately not renamed — it is entangled
with `TEST_HOST`, `PRODUCT_BUNDLE_IDENTIFIER`, and the shared scheme.

## `VellumCore` is deliberately platform-free

All 52 files in `VellumCore/Sources/` import only `Foundation` and `CoreGraphics`
(`grep -rh '^import' VellumCore/Sources`). No UIKit, no SwiftUI, no PencilKit.

`VellumCore/Package.swift` declares `.iOS(.v17), .macOS(.v14)`. The macOS platform is
what lets `swift test` run natively on the Mac in 0.4s with no simulator — that fast
loop is the single most valuable thing about the package split, and one `import UIKit`
destroys it.

Drawing data crosses the boundary as `Data`, never `PKDrawing`
(`grep -r 'PKDrawing' VellumCore` → 0 hits). PencilKit encoding/decoding stays on the
app side.

The app's `deploymentTarget` is **iOS 18.0** on all three targets (`project.yml`);
the package's `.iOS(.v17)` describes the package, not the app.

## State and concurrency conventions

- **`@Observable` only.** Zero `ObservableObject`, `@Published`, `@StateObject`,
  `@ObservedObject`, `@EnvironmentObject` anywhere in the repo. Do not introduce the
  Combine-era spelling.
- **`SWIFT_STRICT_CONCURRENCY: complete`** with `SWIFT_VERSION: "6.0"`
  (`project.yml`), and `swiftLanguageModes: [.v6]` in the package. MainActor app,
  actor-isolated core.
- **Zero `@preconcurrency`.** Exactly two `nonisolated` in the whole repo:
  `Vellum/Features/Vellum/Canvas/StrokeEditing.swift:7` (a pure-function namespace)
  and a synthesis helper in `VellumFlowUITests/ShapeFlowTestHelpers.swift:95`. Adding
  a third to silence a diagnostic is a smell — fix the isolation instead.
- The **only** sanctioned `@unchecked Sendable` is the render-snapshot idiom: a
  private request/result struct that hands an immutable UIKit/PDFKit snapshot to a
  private `actor` renderer and gets an image back. Three sites, all the same shape:
  `Export/PageThumbnailStore.swift`, `Export/NotePageRenderer.swift`,
  `Pdf/PdfPageImageCache.swift`. Anything else needs a real reason.

## PencilKit gesture coexistence

A plain `UIPanGestureRecognizer` / `UITapGestureRecognizer` added to a `PKCanvasView`
**silently does nothing** while an ink tool is active — PencilKit's own
`drawingGestureRecognizer` takes the touches and yours never fires. There is no error;
the feature just does not work on device.

The codebase splits on this:

- Recognizers that must work **while inking** are raw `UIGestureRecognizer` subclasses
  that observe touches without ever claiming them —
  `Canvas/ShapeSnap/PenDwellObserverGestureRecognizer.swift`
  (`cancelsTouchesInView = false`, `delaysTouchesBegan = false`, `ignore(touch:for:)`
  for anything it does not track). Used by `ShapeSnapSurface`, `ShapeEraserSurface`,
  and `ElementTapSelectionSurface`.
- Standard recognizers are used only where the ink tool is **off** —
  `Canvas/SelectionCaptureSurface.swift` installs pan/tap/pinch but gates them on
  `isEnabled`, which the note screen only sets under the Select tool.

Consequence for testing: **direct-call unit tests cannot catch a regression here.**
Calling a coordinator's handler in `VellumUITests` proves the handler is correct and
proves nothing about whether the recognizer ever receives a touch. Only
`VellumFlowUITests` exercises the real responder chain.

Evidence: during the quality audit, unifying two long-press drag recognizers in
`ReorderableThumbnailList.swift` passed all 364 unit tests and broke thumbnail
reorder outright. Only the flow suite caught it. Note the delegate contract there —
`shouldBeRequiredToFailBy` returns `!(other is UIPanGestureRecognizer)`
(`ReorderableThumbnailList.swift:540`), which is what keeps lift distinguishable from
scroll.

## The `vellum-split-state` accessibility readout

`Split/NoteSplitContainerView.swift:319` publishes a 1×1 hidden element whose
`accessibilityValue` is the flow tests' only window into split-pane state. Its field
order is load-bearing:

```
panes: columns: focused: orientation: dragging: target: size: grid: preview:
```

The value is **length-limited by the accessibility system**. Short, high-signal fields
come first because the two grid strings are long enough that anything after them gets
truncated away. Appending a field, or moving one earlier, silently pushes `grid:` and
`preview:` past the limit — and the resulting test failures read as *"the drag never
resolved a target"*, i.e. they impersonate a drag-resolution bug in the code under
test. Budget for this before touching the string.

Parsed by `VellumFlowUITests/SplitPaneFlowUITests.swift` (two launch helpers) and
`VellumFlowUITests/PageOrientationFlowUITests.swift`.

## Launch arguments

The full table — argument, DEBUG gating, read site, and the test that depends on each
— is in `README.md` under "Launch arguments". Two rules:

- Any new launch-argument test hook goes behind `#if DEBUG`. Release configs define no
  `DEBUG` compilation condition (`xcodebuild -showBuildSettings -configuration Release`
  → no `SWIFT_ACTIVE_COMPILATION_CONDITIONS`), so the read compiles out.
- `UserDefaults` key `vellum.shapeSnapOnLift` is **not** a test hook. It is a release
  kill switch for mid-stroke shape snapping, which depends on undocumented PencilKit
  cancel semantics; it ships in every configuration on purpose
  (`Canvas/ShapeSnap/ShapeSnapController.swift`).

## Tests: commands and expected counts

```sh
# 353 tests, 14 suites, ~0.4s, no simulator — the fast loop
cd VellumCore && swift test

# 364 tests, ~19s
xcodegen generate
xcodebuild test -project Vellum.xcodeproj -scheme Vellum \
  -destination 'platform=iOS Simulator,id=9FB0400F-D7AE-4101-8543-AD49E58B09A4' \
  -derivedDataPath build/DerivedData -only-testing:VellumUITests

# Full suite, ~26 min, almost entirely VellumFlowUITests
caffeinate -i xcodebuild test -project Vellum.xcodeproj -scheme Vellum \
  -destination 'platform=iOS Simulator,id=9FB0400F-D7AE-4101-8543-AD49E58B09A4' \
  -derivedDataPath build/DerivedData
```

Run the full suite under `caffeinate -i`: a sleeping Mac suspends the run, and a
suspended run looks identical to a hung one.

Simulator `9FB0400F-D7AE-4101-8543-AD49E58B09A4` is "iPad Pro 13-inch (M5)". Pass the
UDID rather than `name:` — the device set changes.

**One pre-existing failure.**
`ShapeRecognitionFlowUITests.testDraggingASelectedShapeSettlesItOnThePageLattice`
fails deterministically on `main` with `XCTAssertTrue failed - the line was not
selected` (`ShapeRecognitionFlowUITests.swift:290`). A full run ending with **exactly
that one failure** is green. A second failure is a regression. Two split-pane tests
report as skipped via fixture-shape `XCTSkip` guards.

## The built-in agent implementations are shipping code

These were named `MockVellumAgent` / `MockAskAnswerer` until an audit agent read
the name, concluded their tests covered a test double, and proposed deleting all
167 lines. Renamed for that reason — do not reintroduce a `Mock` prefix here.

`HeuristicVellumAgent` and `HeuristicAskAnswerer` (both in
`VellumCore/Sources/VellumCore/Agent/`) are the **production** implementations of
`VellumAgent` and `AskAnswering`, constructed in `AppContainer.live(rootDirectory:)`
(`Vellum/App/AppContainer.swift:21,37`). They are deterministic on-device behavior
behind a protocol seam, not test doubles. Deleting or stubbing them breaks the
shipping app.

## Type-checker budget

Nine expressions currently exceed 150ms; the worst is `NoteSplitContainerView.body` at
1090ms. Re-measure after any large view change:

```sh
xcodebuild build -project Vellum.xcodeproj -scheme Vellum \
  -destination 'platform=iOS Simulator,id=9FB0400F-D7AE-4101-8543-AD49E58B09A4' \
  -derivedDataPath build/dd-timing \
  OTHER_SWIFT_FLAGS='-Xfrontend -warn-long-function-bodies=150 -Xfrontend -warn-long-expression-type-checking=150'
```

The per-site baseline table is in `docs/quality-baseline.md`. Anything above its
number there is a regression. (That file's *test counts* are pre-cleanup — 370/379 —
and are superseded by the 353/364 above.)

## Toolchain

Xcode 26.6 (17F113), Swift 6.3.3, XcodeGen 2.45.4.
