# Quality-audit baseline

Captured before any cleanup, on branch `chore/quality-audit-slop-removal` off `main` @ `742c23d`.
Toolchain: Xcode 26.6 (17F113), Swift 6.3.3, XcodeGen 2.45.4.
Simulator: iPad Pro 13-inch (M5), `9FB0400F-D7AE-4101-8543-AD49E58B09A4`.

Every later wave must diff against these numbers. `TEST SUCCEEDED` alone is not
evidence — compare the **test counts**, because a stale `DerivedData` after
`xcodegen generate` can report success while silently running fewer tests.

## Test counts

| Target | Framework | Tests | Result |
|---|---|---|---|
| `VellumCore` (`swift test`) | swift-testing | **370** in 14 suites | all pass (0.4s) |
| `VellumUITests` (unit tests, misnamed) | XCTest | **379** | all pass (18.7s) |
| `VellumFlowUITests` (real XCUITest) | XCTest | **47** | 1 failure, 2 skipped (1518s) |
| **Total** | | **796** | |

Reproduce:

```sh
cd VellumCore && swift test

xcodegen generate
xcodebuild test -project Vellum.xcodeproj -scheme Vellum \
  -destination 'platform=iOS Simulator,id=9FB0400F-D7AE-4101-8543-AD49E58B09A4' \
  -derivedDataPath build/DerivedData
```

The full app-target run takes **~26 minutes**, almost entirely in
`VellumFlowUITests` (1518s of the 1537s total). Run it under `caffeinate -i`:
a sleeping Mac suspends the run.

## Known-failing — pre-existing, NOT caused by this work

```
VellumFlowUITests/ShapeRecognitionFlowUITests.swift:318: error:
  -[ShapeRecognitionFlowUITests testDraggingASelectedShapeSettlesItOnThePageLattice]
  XCTAssertTrue failed - the line was not selected
```

Deterministic and reproducible on a clean `main`. Any wave that ends with
**exactly this one failure** is green. A second failure is a regression.

Two tests report as skipped, both in the split-pane suite via fixture-shape
`XCTSkip` guards (see the Wave 5 notes on why these are a silent-coverage hole).

## Type-checker cost

Captured with:

```sh
xcodebuild build -project Vellum.xcodeproj -scheme Vellum \
  -destination 'platform=iOS Simulator,id=9FB0400F-D7AE-4101-8543-AD49E58B09A4' \
  -derivedDataPath build/dd-timing \
  OTHER_SWIFT_FLAGS='-Xfrontend -warn-long-function-bodies=150 -Xfrontend -warn-long-expression-type-checking=150'
```

Nine expressions exceed the 150ms threshold:

| ms | Site |
|---:|---|
| **1090** | `Split/NoteSplitContainerView.swift:38` — `body` |
| 317 | `NoteHeaderChips.swift:56` — `leftCluster` |
| 241 | `Canvas/SelectionOverlayView.swift:327` — `vertexHandles(for:)` |
| 212 | `NoteScreenView.swift:53` — `body` |
| 210 | `ThumbnailPanelView.swift:20` — `body` |
| 190 | `NoteScreenView.swift:292` — `canvasArea` |
| 161 | `EntityPopoverView.swift:10` — `body` |
| 160 | `VellumLibraryView.swift:12` — `body` |
| 151 | `Canvas/CanvasElementLayers.swift:36` — `bandContent` |

### This refutes a planning assumption

The plan asserted `NoteScreenView.canvasArea` was "the heaviest expression in the
codebase" and that inlining the eight `ViewModifier` structs back into `body`
risked blowing the type-checker budget. Measured, that is wrong:

- `canvasArea` costs **190ms** and `NoteScreenView.body` **212ms** — both barely
  over the threshold, with ample headroom.
- The genuine hot spot is `NoteSplitContainerView.body` at **1090ms**, 3.4× the
  next-worst expression and 5× `canvasArea`.

Consequences for Wave 6:
1. Dissolving the eight modifier structs is **lower risk than planned**. The
   `noteSurface` extraction is still worth doing first, but the `.stage(_:)`
   contingency is unlikely to be needed.
2. `NoteSplitContainerView` decomposition is the **highest-value** type-checker
   work, not a follow-on to `NoteScreenView`. Its 20-binding prologue and 3-deep
   `ForEach` are where the second is going.
3. `NoteHeaderChips.leftCluster` (317ms) and `SelectionOverlayView.vertexHandles`
   (241ms) were not in the plan at all and both outrank `canvasArea`.

Re-run this build after every Wave 6 step. Any expression exceeding its number
above is a regression to fix before proceeding.
