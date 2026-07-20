# Vellum

Vellum is a native iPad note-taking MVP built with SwiftUI and PencilKit. It keeps typed text and Apple Pencil drawings together, then offers explicit, reviewable organization suggestions without running analysis on every edit.

## Layout

- `VellumCore/` is the local Swift package containing the domain models, workspace services, persistence repositories, and mock agent.
- `Vellum/` is the iPad app shell: library navigation, note editor, PencilKit bridge, proposal review, and activity history.
- `VellumUITests/` contains the Xcode-hosted persistence and note-screen model tests.

The project intentionally makes two layout deviations from the original brief: the core is split into a SwiftPM package so it can be tested without Xcode, and `MockVellumAgent` lives in that core package rather than under `Platform/`.

## Prerequisites

- Xcode 16 or newer
- XcodeGen (`brew install xcodegen`)

## Build and run

```sh
xcodegen generate
open Vellum.xcodeproj
```

Select an iPad simulator running iPadOS 17 or newer, then build and run the `Vellum` scheme.

## Wired workspace

The design-handoff Library, Canvas/note editor, Graph, and Ask screens are backed end-to-end by `VellumCore`. Spaces, links, entities, tasks, the knowledge graph, and Ask all operate on real persisted notes rather than canned fixture data.

On first run, the app automatically seeds a demo workspace. Delete the app from the simulator or device to reseed it from scratch.

Ask and the organize/proposal agent use deterministic on-device mocks behind protocol seams: `MockAskAnswerer` implements `AskAnswering`, and `MockVellumAgent` implements `VellumAgent`. To use real providers, replace the implementations constructed in `AppContainer.live(rootDirectory:)`.

Launch arguments support focused testing:

- `-prototypeStartView library|canvas|graph|ask` selects the top-level screen shown at launch.
- In DEBUG builds only, `-askQuestion "<question text>"` loads and auto-submits an Ask query on launch. Combine it with `-prototypeStartView ask` to open directly on the submitted question.

With a full Xcode install, run the core tests directly:

```sh
cd VellumCore
swift test
```

On a Mac with only Command Line Tools installed, use `./test-clt.sh` instead. Swift Testing is in a non-default framework search path in that configuration, so plain `swift test` fails with `no such module 'Testing'`.

```sh
cd VellumCore
./test-clt.sh
```

## Pending first-device verification

The core package and Xcode-hosted tests pass, but these interactions are still worth confirming on a physical iPad:

1. `Vellum/Platform/PencilCanvasView.swift` — the update guard compares incoming data against `drawing.dataRepresentation()` on every SwiftUI update. Verify strokes are not interrupted while drawing and that large drawings stay responsive.
2. Revision policy: `WorkspaceService.saveNote` is last-write-wins for user saves. The "never silently overwrite" guarantee applies to the agent-proposal path (revision guard + stale marking), not to concurrent user edits — fine for a single-editor MVP.

## Replacing the mock agent

Implement the `VellumAgent` protocol in the core package, then replace the `let agent = MockVellumAgent()` line in `AppContainer.live(rootDirectory:)` with your implementation. No AI-provider code is included in this app shell.

Sync, import, and export adapters are intentionally disabled stubs for this MVP.
