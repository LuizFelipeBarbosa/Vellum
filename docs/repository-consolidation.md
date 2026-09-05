# Repository consolidation — 2026-09-04

The four outstanding branches form one linear history above `main` at `c3be8d9`.
Their work can be fast-forwarded together without conflict resolution, rebasing,
or dropping commits.

| Branch | Original tip | Included work |
|---|---|---|
| `fix/save-amplification-freeze` | `69434c6` | Append-only activity logs, coalesced workspace refreshes, bounded caches, and save-path hardening; includes `a79913e`. |
| `fix/pdf-thread-safety` | `6bc6775` | Actor-owned PDF documents and background save protection. |
| `perf/main-thread-relief` | `ce7f90f` | Drawing serialization, file reads, export rendering, and pasted-image encoding off the main actor. |
| `fix/correctness-diagnostics` | `d0052dd` | Monotonic revisions, recognition lifecycle fixes, memory-warning handling, and surfaced errors. |

The previously untracked `RealModelQAFlowUITests.swift` is preserved as a manual
evidence suite in the `VellumRealModelQA` scheme. The default `Vellum` scheme excludes
it because its attachments require human review and successful execution does not
prove the system model was available. Both schemes compile the same UI-test target.

Setup documentation now reflects the iPadOS 26 deployment target, the shipping
Foundation Models adapters and heuristic fallbacks, and test commands that work
from the repository root. Historical audit files remain historical records.

## Validation

Toolchain: Xcode 26.6 (17F113), XcodeGen 2.45.4.
Simulator: iPad Pro 13-inch (M5), iOS 26.5,
`9FB0400F-D7AE-4101-8543-AD49E58B09A4`.

| Check | Result |
|---|---|
| `swift test --package-path VellumCore` | 442 tests in 14 suites passed. |
| App-hosted `VellumUITests` | 463 tests passed. |
| `DrawingSyncFlowUITests.testModelDrivenCanvasRefreshPreservesLatestStroke` | 1 test passed; model-driven canvas refresh retained the latest ink. |
| XcodeGen scheme generation | Manual QA suite excluded from `Vellum` and selected exclusively by `VellumRealModelQA`. |

Reproduce the app checks from the repository root:

```sh
xcodegen generate
caffeinate -i xcodebuild test -project Vellum.xcodeproj -scheme Vellum \
  -destination 'platform=iOS Simulator,id=9FB0400F-D7AE-4101-8543-AD49E58B09A4' \
  -derivedDataPath build/DerivedData \
  -only-testing:VellumUITests \
  -only-testing:VellumFlowUITests/DrawingSyncFlowUITests
```

The complete UI flow suite and the manual model QA suite were not run for this
consolidation. Prior shape-selection and pasteboard failures remain documented in
`CLAUDE.md`; this record does not claim they are fixed. A wider code and performance
review remains separate from this branch consolidation.

## Local recovery files

Before changing branch references, a complete Git bundle was created and verified at
`build/repository-consolidation-2026-09-04/branches-before-cleanup.bundle`, alongside
the original branch tips and a copy of the untracked QA file. Validation logs and
`Validation.xcresult` are stored in the same ignored directory. These local recovery
files are not committed or uploaded.
