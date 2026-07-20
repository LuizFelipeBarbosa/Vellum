import Foundation

enum SeedContent {
    private enum ID {
        static let studioSpace = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        static let thesisSpace = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        static let teamSpace = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
        static let readingSpace = UUID(uuidString: "10000000-0000-4000-8000-000000000004")!

        static let siteNote = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        static let budgetNote = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        static let kitchenNote = UUID(uuidString: "20000000-0000-4000-8000-000000000003")!
        static let permitNote = UUID(uuidString: "20000000-0000-4000-8000-000000000004")!
        static let danaNote = UUID(uuidString: "20000000-0000-4000-8000-000000000005")!
        static let whiteboardNote = UUID(uuidString: "20000000-0000-4000-8000-000000000006")!
        static let committeeNote = UUID(uuidString: "20000000-0000-4000-8000-000000000007")!
        static let voiceMemoNote = UUID(uuidString: "20000000-0000-4000-8000-000000000008")!

        static let sitePageOne = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
        static let sitePageTwo = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!
        static let sitePageThree = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
        static let budgetPage = UUID(uuidString: "30000000-0000-4000-8000-000000000004")!
        static let kitchenPage = UUID(uuidString: "30000000-0000-4000-8000-000000000005")!
        static let permitPage = UUID(uuidString: "30000000-0000-4000-8000-000000000006")!
        static let danaPage = UUID(uuidString: "30000000-0000-4000-8000-000000000007")!
        static let whiteboardPage = UUID(uuidString: "30000000-0000-4000-8000-000000000008")!
        static let committeePage = UUID(uuidString: "30000000-0000-4000-8000-000000000009")!
        static let voiceMemoPage = UUID(uuidString: "30000000-0000-4000-8000-000000000010")!

        static let siteToBudgetLink = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
        static let siteToPermitLink = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
        static let budgetToSiteLink = UUID(uuidString: "40000000-0000-4000-8000-000000000003")!
        static let kitchenToBudgetLink = UUID(uuidString: "40000000-0000-4000-8000-000000000004")!

        static let marcoEntity = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
        static let danaEntity = UUID(uuidString: "50000000-0000-4000-8000-000000000002")!
        static let okaforEntity = UUID(uuidString: "50000000-0000-4000-8000-000000000003")!
        static let beamOptionsEntity = UUID(uuidString: "50000000-0000-4000-8000-000000000004")!

        static let siteTask = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!
        static let danaDirectorTask = UUID(uuidString: "60000000-0000-4000-8000-000000000002")!
        static let danaFeedbackTask = UUID(uuidString: "60000000-0000-4000-8000-000000000003")!
        static let budgetTask = UUID(uuidString: "60000000-0000-4000-8000-000000000004")!

        static let activityOne = UUID(uuidString: "70000000-0000-4000-8000-000000000001")!
        static let activityTwo = UUID(uuidString: "70000000-0000-4000-8000-000000000002")!
        static let activityThree = UUID(uuidString: "70000000-0000-4000-8000-000000000003")!
        static let activityFour = UUID(uuidString: "70000000-0000-4000-8000-000000000004")!
        static let activityFive = UUID(uuidString: "70000000-0000-4000-8000-000000000005")!
        static let activitySix = UUID(uuidString: "70000000-0000-4000-8000-000000000006")!
        static let activitySeven = UUID(uuidString: "70000000-0000-4000-8000-000000000007")!
        static let activityEight = UUID(uuidString: "70000000-0000-4000-8000-000000000008")!
        static let activityNine = UUID(uuidString: "70000000-0000-4000-8000-000000000009")!
        static let activityTen = UUID(uuidString: "70000000-0000-4000-8000-000000000010")!
    }

    static func demo(now: Date) -> SeedBundle {
        let day: TimeInterval = 86_400
        let hour: TimeInterval = 3_600

        let sitePageOneText = "Walkthrough with Marco Reyes this morning to look at the mid-span support before we close up the ceiling. He'll email the structural sign-off once his engineer reviews the load calcs. Kitchen sightlines look great with the wall gone — need to loop in the tile guy next week."
        let sitePageTwoText = "Beam options: sistered LVL joists vs a single steel W8x24 spanning the opening. Steel = faster inspection, ~$4.2k more. Also go steel if quote < $5k — that's the rule we set with the contractor. Either way this affects the budget line for structural work."
        let sitePageThreeText = "Permit #2231 needs stamped drawings by Friday. Quick follow up: confirm the city portal shows the updated status by Wednesday. The remaining paperwork is ready for submission."
        let budgetText = "The latest budget review puts demolition, electrical, and plumbing close to plan. Beam options remain the single largest swing item, followed by cabinetry and tile. Hold the ten-percent contingency until the city review is complete, then reconcile committed costs against the contractor schedule."
        let kitchenText = "Keep the sink centered on the garden window and move the dishwasher to the left for a cleaner unloading path. Warm oak fronts would soften the pale stone counters, while handmade tile could add texture behind the range. Test the island at thirty-nine inches deep before locking the cabinet plan."
        let permitText = "Permit #2231 application for the Studio Renovation project. The city reviewer requires stamped structural drawings required by Friday before scheduling inspection. Structural engineer Marco Reyes submitted pricing for the beam replacement: Quote: $4,850 installed including shoring for the steel beam option, replacing the sistered joists originally proposed. Marco confirmed the steel beam quote is valid through end of month and includes engineer sign-off for the stamped drawings."
        let danaText = "1:1 with Dana — July 10. Dana's promo case needs two more artifacts before the committee review: a design-led project she owned end-to-end, and peer feedback from a cross-team partner. Action: follow up with the design director about nominating her for the cross-team review. Second action: follow up with Dana next week to confirm the peer feedback request went out."
        let whiteboardText = "Photo transcription from the architecture sync: ingestion flows into a local index, then fans out to search and suggestions. The group circled offline recovery as the riskiest path and added ownership beside each boundary. Next session should resolve retry behavior and define the smallest useful telemetry set."
        let committeeText = "The committee-review draft now opens with the chapter's central claim before moving into the evidence map. Prof. Okafor asked for a clearer transition between the interview findings and the methodological limitation. Add one visual that contrasts the early coding scheme with the final categories."
        let voiceMemoText = "Reading recap, week two: the most useful thread was how attention shifts when tools preserve context across interruptions. The case studies disagreed on whether categorization should happen during capture or later reflection. Revisit the final chapter and compare its examples with the margin notes from Monday."

        let spaces = [
            Space(id: ID.studioSpace, name: "Studio Renovation", color: .teal, createdAt: now.addingTimeInterval(-14 * day)),
            Space(id: ID.thesisSpace, name: "Thesis — Ch. 3", color: .purple, createdAt: now.addingTimeInterval(-13.5 * day)),
            Space(id: ID.teamSpace, name: "Team 1:1s", color: .orange, createdAt: now.addingTimeInterval(-13 * day)),
            Space(id: ID.readingSpace, name: "Reading", color: .green, createdAt: now.addingTimeInterval(-12.5 * day)),
        ]

        let notes = [
            Note(
                id: ID.siteNote,
                schemaVersion: Note.currentSchemaVersion,
                revision: 1,
                title: "Site notes — walkthrough",
                tags: [],
                createdAt: now.addingTimeInterval(-12 * day),
                updatedAt: now.addingTimeInterval(-1 * day),
                pages: [
                    page(id: ID.sitePageOne, order: 0, text: sitePageOneText),
                    page(id: ID.sitePageTwo, order: 1, text: sitePageTwoText),
                    page(id: ID.sitePageThree, order: 2, text: sitePageThreeText),
                ],
                noteType: .note,
                spaceID: ID.studioSpace,
                links: [
                    NoteLink(
                        id: ID.siteToBudgetLink,
                        targetNoteID: ID.budgetNote,
                        kind: .related,
                        createdAt: now.addingTimeInterval(-8 * day)
                    ),
                    NoteLink(
                        id: ID.siteToPermitLink,
                        targetNoteID: ID.permitNote,
                        kind: .mention,
                        createdAt: now.addingTimeInterval(-7.5 * day)
                    ),
                ]
            ),
            Note(
                id: ID.budgetNote,
                schemaVersion: Note.currentSchemaVersion,
                revision: 1,
                title: "Budget v3",
                tags: [],
                createdAt: now.addingTimeInterval(-11 * day),
                updatedAt: now.addingTimeInterval(-2 * day),
                pages: [page(id: ID.budgetPage, order: 0, text: budgetText)],
                noteType: .note,
                spaceID: ID.studioSpace,
                links: [
                    NoteLink(
                        id: ID.budgetToSiteLink,
                        targetNoteID: ID.siteNote,
                        kind: .related,
                        createdAt: now.addingTimeInterval(-8 * day)
                    )
                ]
            ),
            Note(
                id: ID.kitchenNote,
                schemaVersion: Note.currentSchemaVersion,
                revision: 1,
                title: "Kitchen ideas",
                tags: [],
                createdAt: now.addingTimeInterval(-10 * day),
                updatedAt: now.addingTimeInterval(-3 * day),
                pages: [page(id: ID.kitchenPage, order: 0, text: kitchenText)],
                noteType: .note,
                spaceID: ID.studioSpace,
                links: [
                    NoteLink(
                        id: ID.kitchenToBudgetLink,
                        targetNoteID: ID.budgetNote,
                        kind: .mention,
                        createdAt: now.addingTimeInterval(-7 * day)
                    )
                ]
            ),
            Note(
                id: ID.permitNote,
                schemaVersion: Note.currentSchemaVersion,
                revision: 1,
                title: "Permit application #2231",
                tags: [],
                createdAt: now.addingTimeInterval(-9 * day),
                updatedAt: now.addingTimeInterval(-1.5 * day),
                pages: [page(id: ID.permitPage, order: 0, text: permitText)],
                noteType: .pdf,
                spaceID: ID.studioSpace,
                links: []
            ),
            Note(
                id: ID.danaNote,
                schemaVersion: Note.currentSchemaVersion,
                revision: 1,
                title: "Dana 1:1 — July 10",
                tags: [],
                createdAt: now.addingTimeInterval(-8 * day),
                updatedAt: now.addingTimeInterval(-2.5 * day),
                pages: [page(id: ID.danaPage, order: 0, text: danaText)],
                noteType: .note,
                spaceID: ID.teamSpace,
                links: []
            ),
            Note(
                id: ID.whiteboardNote,
                schemaVersion: Note.currentSchemaVersion,
                revision: 1,
                title: "Whiteboard — arch sync",
                tags: [],
                createdAt: now.addingTimeInterval(-6 * day),
                updatedAt: now.addingTimeInterval(-2.25 * day),
                pages: [page(id: ID.whiteboardPage, order: 0, text: whiteboardText)],
                noteType: .image,
                spaceID: ID.teamSpace,
                links: []
            ),
            Note(
                id: ID.committeeNote,
                schemaVersion: Note.currentSchemaVersion,
                revision: 1,
                title: "Committee review — draft",
                tags: [],
                createdAt: now.addingTimeInterval(-5 * day),
                updatedAt: now.addingTimeInterval(-1.75 * day),
                pages: [page(id: ID.committeePage, order: 0, text: committeeText)],
                noteType: .deck,
                spaceID: ID.thesisSpace,
                links: []
            ),
            Note(
                id: ID.voiceMemoNote,
                schemaVersion: Note.currentSchemaVersion,
                revision: 1,
                title: "Voice memo — reading recap",
                tags: [],
                createdAt: now.addingTimeInterval(-4 * day),
                updatedAt: now.addingTimeInterval(-1.25 * day),
                pages: [page(id: ID.voiceMemoPage, order: 0, text: voiceMemoText)],
                noteType: .audio,
                spaceID: ID.readingSpace,
                links: []
            ),
        ]

        let entities = [
            Entity(
                id: ID.marcoEntity,
                name: "Marco Reyes",
                kind: .person,
                sources: [
                    EntitySource(
                        noteID: ID.siteNote,
                        pageID: ID.sitePageOne,
                        excerpt: "Walkthrough with Marco Reyes this morning to look at the mid-span support before we close up the ceiling."
                    ),
                    EntitySource(
                        noteID: ID.permitNote,
                        pageID: ID.permitPage,
                        excerpt: "Structural engineer Marco Reyes submitted pricing for the beam replacement: Quote: $4,850 installed including shoring for the steel beam option, replacing the sistered joists originally proposed."
                    ),
                ],
                createdAt: now.addingTimeInterval(-7 * day)
            ),
            Entity(
                id: ID.danaEntity,
                name: "Dana",
                kind: .person,
                sources: [
                    EntitySource(
                        noteID: ID.danaNote,
                        pageID: ID.danaPage,
                        excerpt: "Dana's promo case needs two more artifacts before the committee review: a design-led project she owned end-to-end, and peer feedback from a cross-team partner."
                    )
                ],
                createdAt: now.addingTimeInterval(-6 * day)
            ),
            Entity(
                id: ID.okaforEntity,
                name: "Prof. Okafor",
                kind: .person,
                sources: [
                    EntitySource(
                        noteID: ID.committeeNote,
                        pageID: ID.committeePage,
                        excerpt: "Prof. Okafor asked for a clearer transition between the interview findings and the methodological limitation."
                    )
                ],
                createdAt: now.addingTimeInterval(-4 * day)
            ),
            Entity(
                id: ID.beamOptionsEntity,
                name: "Beam options",
                kind: .topic,
                sources: [
                    EntitySource(
                        noteID: ID.siteNote,
                        pageID: ID.sitePageTwo,
                        excerpt: "Beam options: sistered LVL joists vs a single steel W8x24 spanning the opening."
                    ),
                    EntitySource(
                        noteID: ID.budgetNote,
                        pageID: ID.budgetPage,
                        excerpt: "Beam options remain the single largest swing item, followed by cabinetry and tile."
                    ),
                ],
                createdAt: now.addingTimeInterval(-6.5 * day)
            ),
        ]

        let tasks = [
            TaskItem(
                id: ID.siteTask,
                noteID: ID.siteNote,
                pageID: ID.sitePageThree,
                text: "Send stamped drawings to the city — due Friday",
                isDone: false,
                createdAt: now.addingTimeInterval(-5 * day),
                completedAt: nil
            ),
            TaskItem(
                id: ID.danaDirectorTask,
                noteID: ID.danaNote,
                pageID: ID.danaPage,
                text: "Follow up with the design director about nominating Dana for the cross-team review",
                isDone: false,
                createdAt: now.addingTimeInterval(-4.5 * day),
                completedAt: nil
            ),
            TaskItem(
                id: ID.danaFeedbackTask,
                noteID: ID.danaNote,
                pageID: ID.danaPage,
                text: "Follow up with Dana to confirm the peer feedback request went out",
                isDone: false,
                createdAt: now.addingTimeInterval(-4 * day),
                completedAt: nil
            ),
            TaskItem(
                id: ID.budgetTask,
                noteID: ID.budgetNote,
                pageID: ID.budgetPage,
                text: "Reconcile committed costs against the contractor schedule",
                isDone: true,
                createdAt: now.addingTimeInterval(-6 * day),
                completedAt: now.addingTimeInterval(-3 * day)
            ),
        ]

        let activity = [
            ActivityEvent(
                id: ID.activityOne,
                noteID: ID.siteNote,
                createdAt: now.addingTimeInterval(-72 * hour),
                kind: .noteFiledToSpace,
                message: "Filed Site notes — walkthrough to Studio Renovation."
            ),
            ActivityEvent(
                id: ID.activityTwo,
                noteID: ID.kitchenNote,
                createdAt: now.addingTimeInterval(-64 * hour),
                kind: .noteFiledToSpace,
                message: "Filed Kitchen ideas to Studio Renovation."
            ),
            ActivityEvent(
                id: ID.activityThree,
                noteID: ID.siteNote,
                createdAt: now.addingTimeInterval(-56 * hour),
                kind: .notesLinked,
                message: "Linked Site notes — walkthrough to Budget v3."
            ),
            ActivityEvent(
                id: ID.activityFour,
                noteID: ID.permitNote,
                createdAt: now.addingTimeInterval(-49 * hour),
                kind: .entityExtracted,
                message: "Extracted entity 'Marco Reyes'."
            ),
            ActivityEvent(
                id: ID.activityFive,
                noteID: ID.danaNote,
                createdAt: now.addingTimeInterval(-43 * hour),
                kind: .taskExtracted,
                message: "Extracted a task from Dana 1:1 — July 10."
            ),
            ActivityEvent(
                id: ID.activitySix,
                noteID: ID.siteNote,
                createdAt: now.addingTimeInterval(-35 * hour),
                kind: .entityExtracted,
                message: "Extracted entity 'Beam options'."
            ),
            ActivityEvent(
                id: ID.activitySeven,
                noteID: ID.budgetNote,
                createdAt: now.addingTimeInterval(-28 * hour),
                kind: .taskExtracted,
                message: "Extracted a budget reconciliation task."
            ),
            ActivityEvent(
                id: ID.activityEight,
                noteID: ID.permitNote,
                createdAt: now.addingTimeInterval(-20 * hour),
                kind: .proposalAccepted,
                message: "Accepted a filing proposal for Permit application #2231."
            ),
            ActivityEvent(
                id: ID.activityNine,
                noteID: ID.kitchenNote,
                createdAt: now.addingTimeInterval(-12 * hour),
                kind: .notesLinked,
                message: "Linked Kitchen ideas to Budget v3."
            ),
            ActivityEvent(
                id: ID.activityTen,
                noteID: ID.committeeNote,
                createdAt: now.addingTimeInterval(-6 * hour),
                kind: .entityExtracted,
                message: "Extracted entity 'Prof. Okafor'."
            ),
        ]

        return SeedBundle(
            spaces: spaces,
            notes: notes,
            entities: entities,
            tasks: tasks,
            activity: activity
        )
    }

    private static func page(id: UUID, order: Int, text: String) -> NotePage {
        NotePage(
            id: id,
            order: order,
            plainText: text,
            drawingAssetPath: "pages/\(id.uuidString)/drawing.data",
            background: .blank
        )
    }
}

struct SeedBundle: Sendable {
    let spaces: [Space]
    let notes: [Note]
    let entities: [Entity]
    let tasks: [TaskItem]
    let activity: [ActivityEvent]
}
