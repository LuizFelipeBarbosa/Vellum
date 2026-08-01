# Vellum code-quality audit

Audit of `main` @ `742c23d` (27.7k lines production, 28.8k lines tests). Every
claim below was produced by a read-only agent that had to cite `file:line` and
quote the source; findings without a citation were dropped. The highest-impact
claims were then re-verified by hand, and **two did not survive** — see
"Corrections" at the end, which is the most useful section in this document.

Status legend: **FIXED** = landed on `chore/quality-audit-slop-removal`.
**OPEN** = real, not yet acted on. **REJECTED** = investigated, not a defect.

## What landed

| | |
|---|---|
| Files removed | 8; 12 added (extracted shared code + test support) |
| Real defects fixed | 4 |
| Latent traps closed | 2 (`Int(...)` overflow on large rotations; validation that would not have applied to future rules) |
| Behavior regressions caught and reverted | 1 |
| Audit findings that did not survive verification | 8 |
| Type-checker: worst expression | 1090ms → under 150ms |

The four real defects, none of which anyone was looking for:

1. **`insertNote` wrote note packages non-atomically** while its sibling
   `importNote` staged-and-renamed. `createNote` routes through it and
   `listNotes` is fail-closed, so one interrupted note creation made the
   **entire library** fail to load.
2. **An unreadable activity log was silently destroyed** — `append` read it with
   `(try? Data(contentsOf:)) ?? Data()` and then atomically wrote the result, so
   any read failure other than "absent" overwrote the user's whole history with a
   single event.
3. **Note activity written before a package existed was unreachable** through
   `list(noteID:)`, which read only the package log.
4. **Row-index math reached `Int(...)` with `+infinity`, which traps.** NaN was
   already handled by an existing `>= 0`; infinity was not.

Test counts moved from 370 / 379 / 47 to **353 / 364 / 43** (VellumCore /
VellumUITests / VellumFlowUITests). Every deletion is accounted for: 10 tests
covering deleted unreachable APIs, 2 with the SplitSpike harness, 2 with
`RotationViewportSyncUITests`, and 26 collapsed into table-driven cases without
losing a distinct scenario.

Final verification, full run of all three suites:

```
VellumCore        353 tests, 14 suites   0 failures
VellumUITests     364 tests              0 failures
VellumFlowUITests  43 tests, 2 skipped   1 failure
```

That one failure is `ShapeRecognitionFlowUITests.testDraggingASelectedShapeSettlesItOnThePageLattice`,
which fails deterministically on unmodified `main` and is recorded as the known
baseline failure in `docs/quality-baseline.md`. Exactly-that-one-failure is the
green condition, and it is met.

---

## The headline: this codebase is not typical LLM slop

The usual markers are absent. Across 137 production files: **0** `// MARK:`
sections, **0** commented-out code blocks, **1** TODO, **0** `// Note:` /
`// Important:` preambles. Comment density is under 11% nearly everywhere, and
the densest file (`SelectionCapturePolicy.swift`, 43%) is genuinely good
rationale writing. There was no redundant-comment cleanup to do.

Discipline is high in places that usually rot first:

- **Concurrency.** `SWIFT_STRICT_CONCURRENCY: complete` with **zero**
  `@preconcurrency` and no `@unchecked Sendable` outside one documented
  render-snapshot idiom. MainActor app, actor core, `Sendable` values across the
  boundary. (Correction: the audit reported zero `nonisolated`; there are two,
  one of which this cleanup introduced on `StrokeEditing`, a pure-function
  namespace. Both are legitimate.)
- **State.** `@Observable` only — zero `ObservableObject`, `@Published`,
  `@StateObject`, `@ObservedObject`, `@EnvironmentObject` anywhere.
- **Core purity.** All 52 files in `VellumCore/Sources/` import only `Foundation`
  and `CoreGraphics`. No UIKit, SwiftUI, or PencilKit.
- **Git hygiene.** `.gitignore` is correct; nothing build-related is tracked.
- **Forward compatibility.** Unknown enum raw values and unknown canvas-element
  kinds round-trip losslessly, with tests. You cannot add those after shipping a
  bad migration.

The real residue is **duplication that later diverged**, **dead scaffolding**,
and **tests that mirror the implementation they are supposed to check**.

---

## Tier 0 — duplicates that diverged (the only findings that are defects)

Seven places where logic was copy-pasted and then only one copy got a later fix.
These matter more than any line count: the un-fixed copy is usually the shipping
path.

| # | Finding | Status |
|---|---|---|
| 0.1 | `ShapeSnapController` mid-stroke path "missing" the ink-removal guard | **REJECTED** — see Corrections |
| 0.2 | Long-press drag recognizer duplicated ~110 lines; the thumbnail copy never got three fixes (mid-scroll press refusal, `allowedTouchTypes`, `reset()` hook) | **ATTEMPTED, REVERTED** `d5a799e` → `db502d2` — see below |
| 0.3 | Row-index math duplicated; only the newer copy is infinity-safe. NaN is already rejected by the existing `>= 0`, but `+infinity` reaches `Int(...)` and **traps at runtime** | **FIXED** `8988f60` |
| 0.4 | `insertNote` never received `importNote`'s stage-then-atomically-rename. `createNote` routes through `insertNote` and `listNotes` is fail-closed, so one interrupted note creation makes the **entire library** throw | **FIXED** `a54dff4` |
| 0.5 | `CanvasElementsStore.finishTextEditingSession` — ~24-line text-commit block inlined twice with **different undo semantics** | **NOT A DEFECT** — the two paths are "active session" (collapses to one `registerEditingSessionUndo`) vs "bare finalize" (no baseline exists, so removal goes through transactional `removeElement`). The short-circuit is load-bearing and pinned by `testNonEmptyTextWithoutSessionTrimsGrowsAndIsIdempotent`. Shared construction extracted; undo handling left explicit and documented. `24e846b` |
| 0.6 | `FileActivityRepository.append` falls back to a workspace-root log when a note package does not exist; `list(noteID:)` reads **only** the package log | **FIXED** `667a6db` — and the fallback turned out to be load-bearing, not a bug: `purgeNote` logs `.notePurged` *after* deleting the package, so a purge event necessarily outlives what it describes. Fixed on the `list` side instead |
| 0.7 | `purgeNote` skips the `SchemaProbe` check `loadNote` performs | **NOT A DEFECT** — deliberate. Adding the probe would make a note written by a newer build permanently **unremovable**, which is strictly worse. Purge still fails closed on an undecodable manifest. Ladder extracted, asymmetry documented, test pins it. `d9ff0d2` |

### 0.2 in detail — the one change that had to be backed out

Unifying `ReorderLongPressGesture` and `SplitSidebarRowDragGesture` into a
generic `RowDragGesture<RowID>` (−348 lines) compiled clean and kept all 379
`VellumUITests` green — but broke thumbnail page reorder. The flow suite caught
it: `PagesPanelDragUITests.testHoldAndDragFromThumbnailCenterReordersPages`
timed out waiting for `label == "2 / 4"`; the page never moved. Reverting
restored all 4 tests in that suite.

The likely cause is the `gestureRecognizerShouldBegin` mid-scroll refusal —
correct for the sidebar, but it rejects the press on the thumbnail panel's
scroll view during a drag. Two details make this worth recording:

- The tuning constants were already identical in both copies (0.3s press, 24pt
  allowable movement, 1 touch, `cancelsTouchesInView`). Only the three guards
  differed, so this is not a "feel" change — it is one guard being wrong here.
- The landscape sibling test **passed** while the center-drag test failed, which
  initially looked like flakiness. It was not: the revert made both pass
  deterministically.

The dedup is still worth doing, but it needs a device in the loop. Gesture
behavior in this app has **no unit-test coverage at all** — pan/tap recognizers
on a `PKCanvasView` silently fail while an ink tool is active, and direct-call
tests cannot observe it. This is the clearest instance in the audit of a change
that is obviously safe by inspection and is not.

Separately fixed: `FileActivityRepository.append` read the log with
`(try? Data(contentsOf:)) ?? Data()` and then atomically wrote the result, so any
read failure other than "absent" **silently overwrote the user's entire activity
history with a single event** (`8eeb317`).

---

## Dead code — FIXED (`5b4cbce`, −918 lines)

Verified by full-repo grep including tests; each symbol's only occurrence was its
own declaration.

- `NoteSyncing` / `SourceImporting` / `KnowledgeExporting` protocols, their three
  `Disabled*` conformers, `VellumError.featureUnavailable` (their only producer),
  and `ImportedSource` (referenced only by the deleted protocol). The README
  described these as the live extension seams. They were never instantiated.
- `WorkspaceService.addLink` / `removeLink` / `setTaskDone` — real domain logic
  with ~90 lines of good tests and no UI path to reach any of it.
- `SplitSpikeView` + `SplitSpikeUITests` (538 lines): a DEBUG two-pane mock that
  regression-tested per-pane undo isolation against a harness that is *not*
  `NoteSplitContainerView`, so it could pass while the real container was broken.
- `VellumAppModel.activityLine`, `NoteScreenModel.editorMode` + `EditorMode`,
  `VellumTheme.dottedUnderline`, `SelectionOverlayView.anchorPoint(in:)`.
- Unused imports: `PencilKit` ×3, `UIKit` ×1, `Observation` ×12.

**Kept deliberately:** `NoteScreenModel.hasEditablePage`, flagged as test-only.
Its one caller is the assertion carrying
`testMissingPDFAssetSurfacesFailureWithoutBlockingEditing`'s contract — a
behavior guarantee, not orphaned code.

**Left alone:** `ActivityKind.noteDeleted` and `EntityKind.document` are rendered
but never produced. Removing a case that may exist in persisted data is a
migration question, not a cleanup one. `EntityKind` has no `.unknown` fallback,
so legacy rows would throw.

---

## Duplication — FIXED

| What | Where it went | Commit |
|---|---|---|
| `rotated`/`inverseRotated` + a third center-compensation clone, byte-identical in `ShapeVertexEditor` and `ShapeEllipseEditor` | `ShapeGeometry`, `internal` (not public — both callers are in-module) | `d69f35d` |
| dots/ruled/grid dispatch written 3× over 3 drawing APIs | `PageBackgroundPattern.marks` — a geometry *emitter*, not a renderer; each caller keeps its own drawing body | `55a7f4a`, `8e2ec9f` |
| ISO8601 fractional-seconds coder duplicated across the module boundary; a divergence would silently corrupt cross-note paste of element timestamps | `VellumCore` `VellumJSONCoding` | `4c0cf72` |
| `copy(_:translatedBy:)` in 3 files, plus `flippedStroke` — a one-line pass-through existing only to host a speculative comment already retired by `testPKStrokeAcceptsNegativeDeterminantTransform` | `StrokeEditing` (app target — the core is PencilKit-free) | `541709c`, `30648a5` |
| 29-line verbatim `.fileImporter` clone in sidebar + library | `FileImport.swift` | `1268e22` |
| The shared shape-snap ink-removal block | extracted with the asymmetry documented | `b1f3cf4` |

**Deliberately not collapsed:** the four `ruleYs`/`gridXs`/`dotXs`/`dotYs`
forwarders. They are directly tested and `dotYs(style:pageRect:clippedTo:)` reads
better at a call site than a generic `stride(axis:firstIndex:...)`. Collapsing
them is the *excessive inlining* failure mode, not a cleanup.

**Not folded together:** the image importer in `NoteScreenView`. It differs in
content type, destination, error sink, and has a completion callback — sharing it
needs four injected closures, more indirection than the duplication costs. Only
the security-scope read is shared.

### Second pass — also FIXED

- `FileEntityRepository` / `FileSpaceRepository` / `FileTaskRepository`, which
  were byte-identical modulo the element type → one generic
  `FileCollectionRepository<Element>`; the three protocols are untouched and the
  concrete types survive as typealiases, so no call site changed (`bf3e1a3`).
- Three implementations of "snap an angle to the nearest quarter turn" → one
  (`6becbb1`). They agreed at the boundaries, but two differed in ways worth
  recording: one let an *infinite* tolerance snap every angle, and
  `ShapeGridSnapper` computed `Int(abs(quarterTurns))`, which **traps** on a
  rotation large enough to overflow `Int`. Both resolved toward the safe copy.
- `sortPages`, identical in two services → `NotePage.byOrder` (`adebc76`).
- The `createdAt`-then-`uuidString` tiebreak comparator — **15** hand-written
  instances, not 11 → `StableOrder` (`affe3ad`). This was a correctness surface
  as much as duplication: 15 chances to get a tiebreak subtly wrong.
- `bounds(of:)` + `PointBounds` ×3 → one (`6b7aa36`). The copies had diverged;
  the **validating** one was kept, because the other depended on a
  `finitePoints(...)` call ~700 lines upstream that no future caller could know
  about.
- `WorkspaceService`'s proposal-accept mutation duplication → routed through
  `createSpace` (`3372c1e`). **The audit overstated this one:** the bypass is
  latent, not live — the validation it skips sits inside `if let parentID`, and
  the proposal path hardcodes `parentID: nil`. Real risk was that any future rule
  added to `createSpace` would silently not apply to agent-filed spaces.

---

## Defensive over-engineering — FIXED (`e56c78c`, `5df0707`, `09d1b3a`)

81 `isFinite` checks across 17 files. The cluster is real but the diagnosis
matters: `JSONDecoder`'s default `.throw` strategy means non-finite geometry
**cannot survive a note-package round-trip**, so most of this armor guards
against a state that persistence already excludes.

`ToolbarDockPolicy.swift` is the worst case: its private `Geometry` struct
sanitizes all nine fields in `init`, which makes **7 of its 8** subsequent
`isFinite` checks unreachable. It carries three overlapping sanitizer helpers
(`finite(_:fallback:)`, `clampedUnitValue(_:)`, `nonnegativeFinite(_:)`) plus a
`distance(_:_:)` that exists only to convert a non-finite `abs()` into
`.greatestFiniteMagnitude`; one line, `fraction.isFinite ? clampedUnitValue(fraction) : 0.5`,
re-implements `clampedUnitValue`'s own opening guard. `SplitLayoutPolicy.swift`
re-implements `nonnegativeFinite` inline.

One nuance worth preserving: in `FileNoteRepository`, `isRegularFile == true &&
isDirectory != true` is genuinely redundant — but the **parallel block a few
lines up is not**, because a symlink-to-directory can report `isDirectory == true`
and following it would let the purge delete outside the package. Only the
redundant clause was dropped; both blocks now carry a comment saying which is
which.

**Outcome:** `ToolbarDockPolicy` went from 8 `isFinite` occurrences to 3, each
with a genuinely reachable non-finite input (the two values that actually arrive
from callers, plus the boundary sanitizer in `Geometry.init` that makes
everything downstream safe). Every removal came with an explicit unreachability
proof rather than a plausibility argument — e.g. `insetLength` is a finite value
minus non-negatives, so it can only overflow *downward*, and NaN would need an
`inf − inf` that no operand can supply; the adjacent `> minimumAxisLength` check
already rejects `−inf`. One check was kept-as-inlined rather than deleted because
it was provably *unobservable* rather than unreachable: `distance`'s result feeds
only `<` comparisons, which order `+inf` exactly as they order
`greatestFiniteMagnitude`.

`SplitLayoutPolicy`'s inline re-implementation now shares one
`CGFloat.nonnegativeFinite`.

---

## Naming — partly FIXED

`VellumTheme.color(for:)` mapped hue enum cases to constants named after seed
content, and **all four were mismatched** against actual seed usage: `studio`
→`.orange` while `studioSpace` is `.teal`; `thesis`→`.green` while `thesisSpace`
is `.purple`; `team`→`.purple` while `teamSpace` is `.orange`; `reading`
→`.yellow` while `readingSpace` is `.green`. Renamed to hue names with **zero
visual change** — every case still resolves to the same hex pair (`6f11ba0`).

**FIXED:** `MockVellumAgent` and `MockAskAnswerer` are the app's only *shipping*
implementations (`AppContainer.swift:21,37`). The `Mock` prefix caused a false
"delete these tests" finding in this very audit, so they are now
`HeuristicVellumAgent` / `HeuristicAskAnswerer`.

**OPEN:** `deleteNote` means opposite things one layer apart.

---

## Tests — 28.8k lines, 1.04:1 with production

### Mirror tests — 12 found, all OPEN

The single worst category. These re-implement the production formula, including
its magic constants, then assert production matches the copy. They cannot catch a
regression — only a typo — and they make the implementation impossible to change
without editing both sides in lockstep.

- `PageLayoutTests.swift:439` asserts `overviewMinZoom(x) == overviewZoomFactor * minZoom(x)`
  — literally `f(x) == body_of_f(x)`. The real constant `0.25` appears in **no**
  test, so the zoom-out floor can move silently.
- `SelectionResizeMathTests.swift:479` contains a character-for-character copy of
  the **private** production helper `SelectionResizeMath.rotation(_:about:)`,
  feeding three tests — one named `matchesExistingComposite`.
- `TextEditingSessionTests.swift:251` recomputes a production expression *by
  calling the production function*.
- Plus `PageGeometryTests`, `SelectionFlipTests`, `ShapeVertexEditorTests`,
  `SelectionTransformTests`, `NoteToolFactoryTests`, `SelectionPasteboardTests`,
  and two in `SelectionActionStripPositionTests`.

### Vacuously-passing tests — OPEN

- `SelectionActionStripPositionTests` — `XCTAssertFalse(aboveFits)` /
  `XCTAssertTrue(belowFits)` are arithmetic over literals declared four lines
  above. They can never fail.
- `PhotoInteractionFlowUITests.swift:90` asserts a `"Paste selection"` button
  does not exist. That string appears **nowhere else in the repo** — it guards a
  removed feature.
- `RotationViewportSyncUITests` — four `zoomResetPill.exists == false`
  assertions with **no positive control anywhere**; the predicate
  `label MATCHES "[0-9]+%"` appears exactly once, in the helper being negated. If
  the label format ever changes, these pass forever with zero coverage. 86 lines
  and two app launches to assert nothing happened.

### Duplicated scaffolding — OPEN

34 files in `VellumUITests/`, **zero** shared helper file. `makeStroke` defined
**12×**, `makeElement` **11×**, `Harness`+`makeHarness` **7×** (5 byte-identical),
a temp-directory helper **8×**, `makeLoadedModel` **4×**. The entire
pixel-comparison toolkit (6 functions + 2 structs, ~180 lines) is duplicated
wholesale between `NoteExporterTests` and `NotePageRendererTests`, so the
tolerance constant `4` now lives in two places.

`VellumFlowUITests/ShapeFlowTestHelpers.swift` is the counter-example and the
model to copy: every helper is used 4–40 times.

### Fixture-dependent skips — mostly FIXED

Eight `XCTSkip` sites, five depending on **seed-data shape** rather than device
capability, two of them skipping in every run. Now **three**: two legitimate
capability gates (the private `XCPointerEventPath` API being unavailable), now
commented as such, and one documented hole.

The interesting one: `testDropRefusesWhenSplitCapacityIsFull` was skipping every
run because it tried to fill `maxColumns × maxRows` (12 panes) from an 8-note
seed. Reading `SplitGridPolicy.dropTargets` shows a drop ranks only two targets —
the best horizontal and vertical edge of the pane under the finger — so refusal
needs just `maxRows + maxColumns - 1` panes (6). The fixture requirement dropped
to 7 notes, which the seed always satisfies. **That test also had a latent bug:**
its drop point was computed as a *window* fraction and landed inside the sidebar
cancel zone, so it would have resolved to `cancelZone` rather than a capacity
refusal — it could not have passed even with enough notes.

**Still open, deliberately:** `testSidebarScrollsDuringAndAfterADrag` needs ~24
sidebar rows to overflow a 1289pt viewport; the seed provides 8. The fix is a
DEBUG note-count launch argument in the shape of `-vellum-split-panes`. It was
*not* done because the flow-test workspace **persists on disk between runs**, so
seeding ~16 extra notes would push the "Site notes" card below the fold of the
library grid and break `ShapeFlowTestHelpers.openSiteNotes`, used by ~30 other
tests. The same lift-vs-scroll arbitration is covered by `PagesPanelDragUITests`,
which builds its own fixture.

### Flake — OPEN

`NoteSplitStateTests` sleeps 400ms and 300ms against a **250ms** production
debounce, in a file that already defines a correct `waitUntil` helper used
properly by three siblings. `PagesPanelDragUITests` has a 2s unconditional
`RunLoop.run` whose own comment admits it is cross-test coupling via
autosave-to-disk.

### Structure — OPEN

Only 14 of 36 `VellumCore/Tests` files use `@Suite`; the rest declare bare
module-scope `@Test` functions, which has already produced two name collisions
(`analyze`, `cleanup` each defined twice).

### Tests that earn their keep — do not touch

Forward-compat/migration tests (unknown canvas-element kinds, legacy spaces
without `parentID`, unknown `ActivityKind`, `ToolPreferences` unknown raws);
`JSONValueTests` (Int64.min / 2^53+1 precision); `ShapeRecognizerTests` (seeded
jitter against ground-truth vertices); `ShapeSnapOrchestrationTests` (encodes a
real PencilKit cancellation race); `FileNoteRepositoryTests` (path traversal,
torn writes, stale-manifest GC, atomicity); `ElementUndoTransactionTests` (three
two-finger gesture collisions that permanently destroy ink);
`NotePageRendererTests`' 14 independent-oracle tests.

`NotePageRendererTests` at 1768 lines is **justified** — renderer bugs are only
observable in pixels, and 310 of those lines are a reusable harness. But 9 of its
35 tests only assert `differingPixelCount(rendered, reference) > 0` where both
sides come from `render()`: they prove *something* changed, not that the right
thing changed.

---

## Cross-cutting — OPEN

- **Test hooks shipping in release builds.** `-thumbnail-slow-render` in
  `PageThumbnailStore` is ungated; its comment claims "production keeps the 500ms
  coalescing," true only because nobody passes the flag. `-vellum-shape-snap-on-lift`
  in `ShapeSnapController` is also ungated — its `UserDefaults` half is a
  documented release kill switch that must ship, but the `ProcessInfo` half has
  **no test consumer at all**.
- **README is wrong on the points that matter most.** It claims iPadOS 17 (the
  deployment target is 18.0 everywhere); it describes `VellumUITests` as UI tests
  (it is `type: bundle.unit-test`, 379 XCTest funcs, zero `XCUIApplication`); it
  omits `VellumFlowUITests` — the actual UI-test target and owner of every
  launch-argument contract — **entirely**; and it calls export "a disabled stub"
  when `NoteExporter` and `PDFImportService` are real and wired.
- **The two documented launch arguments are the two nothing uses.** The six that
  carry live test contracts are undocumented.
- **`vellum-split-state` is the most fragile implicit contract in the repo.** Its
  accessibility value is length-truncated and its field *order* was chosen
  deliberately; appending or reordering a field silently truncates `grid:` and
  `preview:` and produces failures that impersonate drag-resolution bugs. Three
  test files parse it. One comment records this.
- **27 of 32 UI-test selectors are user-facing English**, including a full
  sentence with terminal punctuation and a `Text("Add page")` with no
  accessibility label. They break on any copy edit or localization.
- **No CI, no lint, no formatter.** 796 tests and nothing runs them but a human.
  `swift test` alone is 364 tests in 0.4s.
- **Five error channels with three presentation styles**, and
  `library.errorMessage` is written from the owning model, an unrelated app
  model, and two different views. `PKDrawing(data:)` decode failure is swallowed
  in 5 places and surfaced with a user-facing message in 1.
- **No `CLAUDE.md`.** The non-obvious facts — `xcodegen generate` is mandatory
  because sources are directory-based and `*.xcodeproj` is gitignored; the
  UITests/FlowUITests naming inversion; core purity; `@Observable`-only; the
  PencilKit gesture-coexistence trap — are learnable only by failing.

---

## Corrections — findings that did NOT survive verification

Recorded because they are the most instructive part of the audit: three separate
agents each produced a confident, well-cited claim that was wrong.

**1. `ShapeSnapController` was not missing a guard.** The audit found the same
ink-removal block in `commitShapeOnLift` (which tracks `didRemoveInkedStroke` and
bails) and `performMidStrokeSnap` (which does not), noted `.snapMidStroke` is the
default policy, and concluded the shipping path could stack a duplicate shape on
the user's sketch. It reads as an obvious missing guard.

It is deliberate. Mid-stroke, `drawingGestureRecognizer.isEnabled = false` is set
*before* the deferred removal — that is what makes PencilKit cancel the in-flight
stroke, so the ink never lands and "removed nothing" is the **ordinary** outcome.
On the lift path the recognizer is never disabled, the stroke *will* land, and
"removed nothing" genuinely means "inserting now would duplicate it." Applying
the guard to both paths disables mid-stroke snapping in the common case and fails
5 `ShapeSnapOrchestrationTests`. That was measured, not argued.

The duplication was still real, so the block was extracted with the asymmetry
documented on the shared helper (`b1f3cf4`) — the missing knowledge that caused
the misread is now in the code.

**2. `MockVellumAgentTests` is not testing a test double.** `MockVellumAgent` is
instantiated at `AppContainer.swift:21` as the app's shipping analysis engine.
Those 167 lines cover production behavior. The `Mock` name is the actual defect.

**3. `PasteAffordanceFlowUITests` is correct.** Flagged as vacuously-passing
negative assertions; every negation is in fact `waitForNonExistence` preceded by
a matching `waitForExistence`.

Also corrected: `.gitignore` and git hygiene are clean (an assumed problem that
did not exist); `TheBrain.xcodeproj/` is untracked, so removing it is local-disk
cleanup, not a commit; and `VellumUITests` has 379 test functions, not 411.

**4. The eight single-use `ViewModifier` structs in `NoteScreenView` were not
pure slop.** They looked like textbook over-abstraction: eight types, each
applied exactly once, each re-declaring 4–10 stored properties purely to
re-plumb state already in scope. The plan was to dissolve them into a flat
~45-line `body` reading top-to-bottom.

Measured, that flat chain costs **8699ms** to type-check — 40× the 212ms it
replaced. The structs were solving a real problem; what was wrong was the
*arbitrary grouping* (two `.onChange` handlers were left inline doing the same
job as the extracted "ChangeObservers") and the re-plumbing.

The fix keeps six seams but as **private methods returning `some View`** — an
identical inference barrier to a `ViewModifier`'s `body`, with zero re-plumbing,
because a method on the view can read the view's `private` state directly. Result:
`NoteScreenView` 1436→1061 lines, and both `body` and `canvasArea` dropped off
the >150ms list entirely (from 212ms and 190ms). The cost of a flat `body` is
paid in one place; the benefit of the seams is kept.

**5. `vellum-split-state` is parsed by two flow-test files, not three.**
`VellumUITests/NoteSplitStateTests.swift` matches on `grid:` but is testing
`NoteSplitState` resolution, not the readout string.

**The measured type-checker baseline refuted a planning assumption too.**
`NoteScreenView.canvasArea` was assumed to be the heaviest expression in the
codebase; it costs 190ms. The real hot spot is `NoteSplitContainerView.body` at
**1090ms**, 3.4× the next-worst. Two expressions that outrank `canvasArea`
(`NoteHeaderChips.leftCluster` at 317ms, `SelectionOverlayView.vertexHandles` at
241ms) were not in the plan at all. See `docs/quality-baseline.md`.
