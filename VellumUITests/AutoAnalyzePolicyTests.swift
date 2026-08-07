import Foundation
@testable import Vellum
import VellumCore
import XCTest

private actor CountingVellumAgent: VellumAgent {
    private let delay: Duration
    private var callCount = 0

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func analyze(
        event: WorkspaceEvent,
        context: AgentContext
    ) async throws -> [AgentProposal] {
        callCount += 1
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return []
    }

    func numberOfCalls() -> Int {
        callCount
    }
}

@MainActor
final class AutoAnalyzePolicyTests: XCTestCase {
    private let eligibleText = String(
        repeating: "A thoughtful sentence for organization. ",
        count: 3
    )
    private var rootDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: SettingsKeys.autoOrganizeEnabled)
        rootDirectory = try TemporaryDirectory.make()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: SettingsKeys.autoOrganizeEnabled)
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
        try await super.tearDown()
    }

    func testToggleOffSkipsEligibleNote() async throws {
        let fixture = try await makeModel(text: eligibleText)
        UserDefaults.standard.set(false, forKey: SettingsKeys.autoOrganizeEnabled)

        await fixture.model.autoAnalyzeIfNeeded()

        let callCount = await fixture.agent.numberOfCalls()
        XCTAssertEqual(callCount, 0)
    }

    func testTextUnderMinimumLengthSkipsAnalysis() async throws {
        let fixture = try await makeModel(text: "  Too short after trimming.  \n")
        UserDefaults.standard.set(true, forKey: SettingsKeys.autoOrganizeEnabled)

        await fixture.model.autoAnalyzeIfNeeded()

        let callCount = await fixture.agent.numberOfCalls()
        XCTAssertEqual(callCount, 0)
    }

    func testFirstEligibleCallRunsAndWritesSidecar() async throws {
        let fixture = try await makeModel(text: eligibleText)
        UserDefaults.standard.set(true, forKey: SettingsKeys.autoOrganizeEnabled)

        await fixture.model.autoAnalyzeIfNeeded()

        let callCount = await fixture.agent.numberOfCalls()
        XCTAssertEqual(callCount, 1)
        let loadedData = try await fixture.container.notes.loadAsset(
            noteID: fixture.note.id,
            relativePath: AgentStateSidecar.relativePath
        )
        let data = try XCTUnwrap(loadedData)
        let state = try VellumJSONCoding.decoder().decode(
            AgentAnalysisState.self,
            from: data
        )
        XCTAssertEqual(state.schemaVersion, AgentStateSidecar.schemaVersion)
        XCTAssertEqual(
            state.lastAnalyzedTextHash,
            AgentStateSidecar.textHash(
                for: eligibleText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    func testUnchangedTextDoesNotRunAgain() async throws {
        let fixture = try await makeModel(text: eligibleText)
        UserDefaults.standard.set(true, forKey: SettingsKeys.autoOrganizeEnabled)

        await fixture.model.autoAnalyzeIfNeeded()
        await fixture.model.autoAnalyzeIfNeeded()

        let callCount = await fixture.agent.numberOfCalls()
        XCTAssertEqual(callCount, 1)
    }

    func testChangedTextRunsAgain() async throws {
        let fixture = try await makeModel(text: eligibleText)
        UserDefaults.standard.set(true, forKey: SettingsKeys.autoOrganizeEnabled)
        await fixture.model.autoAnalyzeIfNeeded()

        fixture.model.plainText = String(
            repeating: "A different body should receive fresh suggestions. ",
            count: 3
        )
        let didSave = await fixture.model.flushPendingSave()
        XCTAssertTrue(didSave)
        await fixture.model.autoAnalyzeIfNeeded()

        let callCount = await fixture.agent.numberOfCalls()
        XCTAssertEqual(callCount, 2)
    }

    func testManualOrganizeUpdatesSidecarAndPreventsAutomaticRerun() async throws {
        let fixture = try await makeModel(text: eligibleText)

        await fixture.model.organize()

        let manualCallCount = await fixture.agent.numberOfCalls()
        XCTAssertEqual(manualCallCount, 1)
        let sidecar = try await fixture.container.notes.loadAsset(
            noteID: fixture.note.id,
            relativePath: AgentStateSidecar.relativePath
        )
        XCTAssertNotNil(sidecar)

        UserDefaults.standard.set(true, forKey: SettingsKeys.autoOrganizeEnabled)
        await fixture.model.autoAnalyzeIfNeeded()

        let finalCallCount = await fixture.agent.numberOfCalls()
        XCTAssertEqual(finalCallCount, 1)
    }

    func testRapidCallsJoinSingleInFlightAnalysis() async throws {
        let fixture = try await makeModel(
            text: eligibleText,
            analysisDelay: .milliseconds(25)
        )
        UserDefaults.standard.set(true, forKey: SettingsKeys.autoOrganizeEnabled)

        let first = Task { await fixture.model.autoAnalyzeIfNeeded() }
        let second = Task { await fixture.model.autoAnalyzeIfNeeded() }
        await first.value
        await second.value

        let callCount = await fixture.agent.numberOfCalls()
        XCTAssertEqual(callCount, 1)
    }

    private func makeModel(
        text: String,
        analysisDelay: Duration = .zero
    ) async throws -> (
        container: AppContainer,
        note: Note,
        model: NoteScreenModel,
        agent: CountingVellumAgent
    ) {
        UserDefaults.standard.set(false, forKey: SettingsKeys.autoOrganizeEnabled)

        let notes = FileNoteRepository(rootDirectory: rootDirectory)
        let proposals = FileProposalRepository(rootDirectory: rootDirectory)
        let activity = FileActivityRepository(rootDirectory: rootDirectory)
        let agent = CountingVellumAgent(delay: analysisDelay)
        let spaces = FileSpaceRepository(rootDirectory: rootDirectory)
        let entities = FileEntityRepository(rootDirectory: rootDirectory)
        let tasks = FileTaskRepository(rootDirectory: rootDirectory)
        let workspace = WorkspaceService(
            notes: notes,
            proposals: proposals,
            activity: activity,
            agent: agent,
            spaces: spaces,
            entities: entities,
            tasks: tasks
        )
        let graph = KnowledgeGraphService(
            notes: notes,
            spaces: spaces,
            entities: entities
        )
        let container = AppContainer(
            rootDirectory: rootDirectory,
            notes: notes,
            proposals: proposals,
            activity: activity,
            agent: agent,
            spaces: spaces,
            entities: entities,
            tasks: tasks,
            workspace: workspace,
            graph: graph,
            askService: AskService(
                notes: notes,
                answerer: HeuristicAskAnswerer(),
                activity: activity
            )
        )

        var note = try await notes.createNote(title: "Auto analyze")
        note.pages[0].plainText = text
        try await notes.saveNote(note)

        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()
        await model.autoAnalyzeIfNeeded()
        for _ in 0..<3 {
            await Task.yield()
        }

        return (container, note, model, agent)
    }
}
