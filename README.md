# Vellum

Vellum is a native iPad note-taking app built with SwiftUI and PencilKit. It keeps
typed text, Apple Pencil ink, shapes, photos, and imported PDF pages together on a
paged canvas, and offers explicit, reviewable organization suggestions instead of
running analysis on every edit.

## Layout

| Path | What it is |
|---|---|
| `VellumCore/` | Local SwiftPM package: domain models, workspace/graph/ask services, file-backed repositories, and the mock agent. 52 files, importing only `Foundation` and `CoreGraphics` — no UIKit, SwiftUI, or PencilKit. |
| `Vellum/` | The iPad app: `App/` (entry point + container), `Features/Vellum/` (library, note editor, canvas, split panes, toolbar, export, PDF), `Platform/` (PencilKit bridge), `Resources/`. 94 files. |
| `VellumUITests/` | **Unit tests, despite the name.** XcodeGen `type: bundle.unit-test` with a `TEST_HOST`, so it runs in-process against the app target. 364 XCTest functions, zero `XCUIApplication`. |
| `VellumFlowUITests/` | The real UI-test target (`type: bundle.ui-testing`). 43 XCUITest functions driving the simulator; owns every launch-argument contract below. |
| `docs/` | `quality-baseline.md` (measured test counts and type-checker costs) and `quality-report.md` (audit findings, open issues). |

The project makes two deliberate layout deviations from the original brief: the core
is a SwiftPM package so it can be tested without Xcode or a simulator, and
`HeuristicVellumAgent` lives in that package rather than under `Platform/`.

## Prerequisites

- Xcode 26.6 (Swift 6.3.3) — the toolchain this is developed and verified against
- XcodeGen 2.45.4 or newer (`brew install xcodegen`)

## Build and run

`*.xcodeproj` is gitignored, so a fresh clone has no project file:

```sh
xcodegen generate
open Vellum.xcodeproj
```

Re-run `xcodegen generate` after adding or removing **any** file under `Vellum/`,
`VellumUITests/`, or `VellumFlowUITests/` — `project.yml` declares directory-based
`sources:`, so new files are invisible to the build until the project is regenerated.

Select an iPad simulator running **iPadOS 18.0 or newer** (all three targets set
`deploymentTarget: "18.0"`), then build and run the `Vellum` scheme. `VellumCore`
itself declares `.iOS(.v17)` / `.macOS(.v14)` so that `swift test` runs on the Mac
without a simulator; the app requires 18.

## Tests

```sh
# Core package — 353 tests, ~0.4s, no simulator needed
cd VellumCore && swift test

# App-hosted unit tests — 364 tests, ~19s
xcodegen generate
xcodebuild test -project Vellum.xcodeproj -scheme Vellum \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath build/DerivedData -only-testing:VellumUITests

# Everything, including the simulator-driving flow tests — ~26 minutes
caffeinate -i xcodebuild test -project Vellum.xcodeproj -scheme Vellum \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath build/DerivedData
```

`VellumFlowUITests` accounts for essentially all of the full-suite runtime. One test
in it, `ShapeRecognitionFlowUITests.testDraggingASelectedShapeSettlesItOnThePageLattice`,
fails deterministically on `main`; a run with exactly that one failure is green. See
`docs/quality-baseline.md`.

On a Mac with only Command Line Tools installed, Swift Testing sits in a non-default
framework search path and plain `swift test` fails with `no such module 'Testing'`.
Use the wrapper instead:

```sh
cd VellumCore && ./test-clt.sh
```

## Launch arguments

The app reads these from `ProcessInfo.processInfo.arguments` at launch. "DEBUG" means
the read is behind `#if DEBUG` and compiles out of release builds.

| Argument | Gated | Read in | Used by |
|---|---|---|---|
| `-vellum-split-panes <count>` | DEBUG | `VellumAppModel.swift` | `SplitPaneFlowUITests` — opens N panes at launch |
| `-vellum-split-grid <r1,r2,…>` | DEBUG | `VellumAppModel.swift` | `SplitPaneFlowUITests` — opens a pane grid with the given rows per column |
| `-vellum-pdf-fixture-note` | DEBUG | `VellumAppModel.swift` | `PageOrientationFlowUITests` — opens a note seeded with an imported PDF page |
| `-vellum-auto-open-note` | DEBUG | `VellumAppModel.swift` | no test; manual convenience — opens the most recent note at launch |
| `-askQuestion "<text>"` | DEBUG | `VellumAppModel.swift` | no test; combine with `-prototypeStartView ask` to land on a submitted answer |
| `-vellum-force-pencil-only` | DEBUG + simulator | `PencilCanvasView.swift`, `SelectionCaptureSurface.swift`, `ShapeEraserSurface.swift`, `ShapeSnapSurface.swift` | `ShapeRecognitionFlowUITests`, `ShapeFlowTestHelpers`, `PhotoInteractionFlowUITests` — makes the simulator treat finger input as touch, not ink, so a synthesized drag is a drag |
| `-thumbnail-slow-render` | DEBUG | `PageThumbnailStore.swift` | `PagesPanelDragUITests` — stretches thumbnail debounce from 500ms to 3000ms so the loading placeholder can be asserted against |
| `-vellum-shape-snap-on-lift` | DEBUG | `ShapeSnapController.swift` | no test; shape-snap tests inject `policy:` directly |
| `-prototypeStartView library\|canvas\|graph\|ask` | ungated | `VellumAppModel.swift` | no test; selects the screen shown at launch |

Separately, `UserDefaults` key `vellum.shapeSnapOnLift` is a **release kill switch**,
not a test hook: mid-stroke shape snapping depends on undocumented PencilKit cancel
semantics, so an OS update that breaks it has to be recoverable without a hotfix. It
ships in all configurations (`ShapeSnapController.swift`).

## Wired workspace

The Library, note editor/canvas, Graph, and Ask screens are backed end-to-end by
`VellumCore`. Spaces, links, entities, tasks, the knowledge graph, and Ask all operate
on real persisted notes rather than fixture data. On first run the app seeds a demo
workspace; delete the app from the simulator or device to reseed from scratch.

Export and PDF import are real, not stubs. `NoteExporter` renders notes to PDF, PNG,
or JPEG and is wired through `NoteHeaderChips` / `NoteScreenView`; `PDFImportService`
builds notes from imported PDFs and is wired through `LibraryScreenModel`.

## Built-in agent implementations

`HeuristicVellumAgent` (implementing `VellumAgent`) and `HeuristicAskAnswerer` (implementing
`AskAnswering`) are **shipping implementations**, not test doubles — deterministic
on-device behavior behind protocol seams, constructed in
`AppContainer.live(rootDirectory:)`. To use a real provider, implement the protocol in
`VellumCore` and swap the constructor call there. No AI-provider code is bundled.

## Known behavior

`WorkspaceService.saveNote` is last-write-wins for user saves. The "never silently
overwrite" guarantee applies to the agent-proposal path (revision guard plus stale
marking), not to concurrent user edits — which is fine for a single-editor app.

Open quality issues and the rationale behind recent structural work are tracked in
`docs/quality-report.md`.
