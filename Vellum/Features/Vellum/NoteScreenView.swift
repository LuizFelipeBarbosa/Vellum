import PDFKit
import PencilKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VellumCore

struct NoteScreenView: View {
    @Bindable var model: NoteScreenModel
    @Bindable var app: VellumAppModel
    let paneContext: PaneContext

    @State private var isShowingActivity = false
    @State private var isConfirmingDelete = false
    @State private var lastNonNilTool: (any PKTool)?
    @State private var selectionController = CanvasSelectionController()
    @State private var shapeSnapController = ShapeSnapController()
    @State private var canvasViewport = CanvasViewport(contentOffset: .zero, zoomScale: 1)
    @State private var canvasSize: CGSize = .zero
    @State private var pageState = NotePageState()
    @State private var isShowingThumbnails = false
    @State private var thumbnailStore = PageThumbnailStore()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var exportOutput: NoteExporter.Output?
    @State private var exportDirectoryToCleanUp: URL?
    @State private var topOverlayHeight: CGFloat = 0
    @State private var leftClusterFrame: CGRect = .zero
    @State private var rightClusterFrame: CGRect = .zero
    @State private var topOverlayGlobalFrame: CGRect = .zero

    private var activeCanvasReference: NoteCanvasReference {
        paneContext.pane.canvasReference
    }

    private var selectedTool: ToolID {
        get { app.split.selectedTool }
        nonmutating set { app.split.selectedTool = newValue }
    }

    private var showsBacklinksRail: Bool {
        paneContext.fitsBacklinksRail
    }

    private var showsSuggestionsAndThumbnails: Bool {
        paneContext.fitsSuggestionsAndThumbnails && paneContext.isFocused
    }

    private var showsEntityChips: Bool {
        paneContext.fitsEntityChips
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if model.isLoading && model.note == nil {
                    ProgressView("Loading note…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(VellumTheme.card)
                } else if model.note != nil {
                    canvasArea
                } else {
                    ContentUnavailableView(
                        "Note Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The note could not be loaded.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VellumTheme.card)
                }
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 8) {
                NoteHeaderChips(
                    model: model,
                    app: app,
                    onShowActivity: { isShowingActivity = true },
                    onConfirmDelete: { isConfirmingDelete = true },
                    onExport: exportNote,
                    onClusterFrames: {
                        leftClusterFrame = $0
                        rightClusterFrame = $1
                    },
                    isCompact: paneContext.hasCompactHeader
                )

                if !model.noteEntities.isEmpty && showsEntityChips {
                    entityChips
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .onGeometryChange(
                for: CGRect.self,
                of: { $0.frame(in: .global) },
                action: { frame in
                    topOverlayHeight = frame.height
                    topOverlayGlobalFrame = frame
                }
            )

            modalOverlays

            if paneContext.isSplit {
                PaneFocusSurface(
                    paneContext: paneContext,
                    onFocus: { app.split.focus(paneContext.pane.id) }
                )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

                if paneContext.isFocused {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VellumTheme.accent(0.55), lineWidth: 1.5)
                        .padding(1.5)
                        .allowsHitTesting(false)
                }

                paneCloseButton(paneContext)
            }
        }
        .preference(
            key: PaneHeaderFramesKey.self,
            value: [
                paneContext.pane.id: PaneHeaderFrames(
                    leftClusterFrame: leftClusterFrame,
                    rightClusterFrame: rightClusterFrame,
                    topOverlayGlobalFrame: topOverlayGlobalFrame
                )
            ]
        )
        .background(VellumTheme.paper)
        .modifier(
            NoteScreenLifecycleModifiers(
                model: model,
                app: app,
                canvasReference: activeCanvasReference,
                paneUndoManager: paneContext.pane.undoManager,
                selectionController: selectionController,
                shapeSnapController: shapeSnapController,
                pageState: pageState,
                thumbnailStore: thumbnailStore,
                currentVisibleContentRect: { currentVisibleContentRect },
                cacheCurrentTool: cacheCurrentTool,
                scrollCanvas: scrollCanvas
            )
        )
        .modifier(
            NoteScreenPrimaryChangeObservers(
                model: model,
                app: app,
                selectionController: selectionController,
                selectedTool: selectedTool,
                cacheCurrentTool: cacheCurrentTool
            )
        )
        .onChange(of: selectionController.selection != nil) { _, hasSelection in
            // Selecting an element borrows the Select tool so shapes and photos use one edit flow.
            // Once the selection ends the tool goes back, so selecting either never costs the
            // pen you were drawing with. If the tool has moved on already, the user chose it.
            guard !hasSelection,
                  let borrowedFrom = app.split.toolBorrowedByElementSelection
            else {
                return
            }
            app.split.toolBorrowedByElementSelection = nil
            if selectedTool == .select {
                selectedTool = borrowedFrom
            }
        }
        .onChange(of: paneContext.isFocused) { wasFocused, isFocused in
            if wasFocused, !isFocused {
                selectionController.clearSelection()
                model.isShowingSuggestions = false
                isShowingThumbnails = false
                app.split.isShowingPaperOptions = false
            }
        }
        .modifier(
            NoteScreenCanvasContentChangeObservers(
                model: model,
                canvasReference: activeCanvasReference,
                pageState: pageState,
                thumbnailStore: thumbnailStore,
                isShowingThumbnails: isShowingThumbnails,
                currentPageRendererContent: currentPageRendererContent
            )
        )
        .modifier(
            NoteScreenPageViewportChangeObservers(
                model: model,
                canvasReference: activeCanvasReference,
                selectionController: selectionController,
                pageState: pageState,
                thumbnailStore: thumbnailStore,
                canvasViewport: canvasViewport,
                canvasSize: canvasSize
            )
        )
        .modifier(
            NoteScreenActivityPresentationModifiers(
                model: model,
                app: app,
                isShowingActivity: $isShowingActivity,
                exportOutput: $exportOutput,
                cleanUpExportDirectory: cleanUpExportDirectory,
                isConfirmingDelete: $isConfirmingDelete,
                deleteNote: deleteNote
            )
        )
        .modifier(
            NoteScreenPhotoImportModifiers(
                model: model,
                isShowingPhotosPicker: $model.isShowingPhotosPicker,
                photosPickerItem: $photosPickerItem,
                currentVisibleContentRect: { currentVisibleContentRect },
                onImageImported: selectImportedElement
            )
        )
        .modifier(
            NoteScreenFileImportAndAlertModifiers(
                model: model,
                isShowingFileImporter: $model.isShowingFileImporter,
                currentVisibleContentRect: { currentVisibleContentRect },
                onImageImported: selectImportedElement
            )
        )
        .modifier(
            NoteScreenAnimationModifiers(
                model: model,
                isShowingThumbnails: isShowingThumbnails
            )
        )
    }

    private var entityChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.noteEntities) { entity in
                    Button {
                        model.selectedEntity = entity
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(entityColor(for: entity.kind))
                                .frame(width: 6, height: 6)
                            Text(entity.name)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(VellumTheme.bodyMuted)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(VellumTheme.popover, in: Capsule())
                        .overlay {
                            Capsule().stroke(VellumTheme.ink(0.13), lineWidth: 1)
                        }
                        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 9)
        }
        .scrollIndicators(.hidden)
    }

    private func paneCloseButton(_ paneContext: PaneContext) -> some View {
        Button {
            Task {
                await app.closePane(paneContext.pane.id)
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(VellumTheme.mutedDark)
                .frame(width: 24, height: 24)
                .background(VellumTheme.popover, in: Circle())
                .overlay {
                    Circle().stroke(VellumTheme.ink(0.14), lineWidth: 1)
                }
                .shadow(color: VellumTheme.ink(0.1), radius: 3, y: 1)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityLabel("Close pane")
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            let canvasGlobalOrigin = geometry.frame(in: .global).origin
            let pageGeometry = model.note?.pageGeometry ?? .a4

            ZStack(alignment: .topLeading) {
                PageGuideLayer(
                    viewport: canvasViewport,
                    viewportSize: canvasSize,
                    pageCount: pageState.pageCount,
                    geometry: pageGeometry,
                    style: model.note?.backgroundStyle ?? .legacyDefault,
                    pdfBands: model.pdfBands
                )
                .frame(width: geometry.size.width, height: geometry.size.height)

                PdfPagesLayer(
                    cache: model.pdfCache,
                    pdfBands: model.pdfBands,
                    viewport: canvasViewport,
                    pageCount: pageState.pageCount,
                    geometry: pageGeometry
                )
                .frame(
                    width: pageGeometry.contentWidth,
                    height: pageState.contentHeight,
                    alignment: .topLeading
                )
                .scaleEffect(canvasViewport.zoomScale, anchor: .topLeading)
                .offset(
                    x: -canvasViewport.contentOffset.x,
                    y: -canvasViewport.contentOffset.y
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                )
                .clipped()

                PageGuideLayer(
                    viewport: canvasViewport,
                    viewportSize: canvasSize,
                    pageCount: pageState.pageCount,
                    geometry: pageGeometry,
                    style: model.note?.backgroundStyle ?? .legacyDefault,
                    pdfBands: model.pdfBands,
                    mode: .pdfAdornments
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)

                CanvasElementsBandLayer(
                    store: model.canvasElements,
                    selectionController: selectionController,
                    placement: .belowInk
                )
                .contentViewportFrame(
                    contentWidth: pageGeometry.contentWidth,
                    contentHeight: pageState.contentHeight,
                    zoom: canvasViewport.zoomScale,
                    contentOffset: canvasViewport.contentOffset,
                    viewportSize: geometry.size
                )

                PencilCanvasView(
                    drawingData: model.drawingData,
                    onDrawingChanged: { data in
                        model.drawingChanged(data)
                        pageState.updateContent(
                            drawingBounds: activeCanvasReference.canvasView?.drawing.bounds
                                ?? .null,
                            elements: model.canvasElements.elements,
                            minimumFilledPages: model.note?.pages.count ?? 0
                        )
                    },
                    isTransparent: true,
                    tool: activeTool,
                    showsSystemToolPicker: false,
                    onCanvasReady: { canvasView in
                        activeCanvasReference.canvasView = canvasView
                        Task { @MainActor in
                            paneContext.pane.canvasDidBecomeReady()
                        }
                    },
                    paneUndoManager: paneContext.pane.undoManager,
                    isDrawingEnabled: selectedTool.usesDrawingGesture,
                    contentWidth: pageGeometry.contentWidth,
                    contentHeight: pageState.contentHeight,
                    topContentInset: topOverlayGlobalFrame.maxY - canvasGlobalOrigin.y + 16,
                    onViewportChanged: { canvasViewport = $0 },
                    onExternalDrawingChange: {
                        selectionController.externalDrawingDidChange()
                        pageState.updateContent(
                            drawingBounds: activeCanvasReference.canvasView?.drawing.bounds
                                ?? .null,
                            elements: model.canvasElements.elements,
                            minimumFilledPages: model.note?.pages.count ?? 0
                        )
                    },
                    onPencilSqueeze: { phase in
                        switch phase {
                        case .began:
                            if let tool = app.split.squeezeEraser.begin(
                                current: selectedTool
                            ) {
                                selectedTool = tool
                            }
                        case .ended:
                            if let tool = app.split.squeezeEraser.end(
                                current: selectedTool
                            ) {
                                selectedTool = tool
                            }
                        }
                    },
                    onTwoFingerTap: {
                        if activeCanvasReference.canvasView?.undoManager?.canUndo == true {
                            activeCanvasReference.canvasView?.undoManager?.undo()
                        }
                    },
                    onThreeFingerTap: {
                        if activeCanvasReference.canvasView?.undoManager?.canRedo == true {
                            activeCanvasReference.canvasView?.undoManager?.redo()
                        }
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)

                ShapeSnapSurface(
                    controller: shapeSnapController,
                    isEnabled: selectedTool.isInkTool,
                    inkConfig: selectedTool.inkConfigKeyPath.map {
                        app.toolPreferences.preferences[keyPath: $0]
                    },
                    isDrawingEnabled: selectedTool.usesDrawingGesture
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)

                ShapeEraserSurface(
                    canvasReference: activeCanvasReference,
                    elementsStore: model.canvasElements,
                    eraserConfig: app.toolPreferences.preferences.eraser,
                    isEnabled: selectedTool == .eraser
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)

                ElementTapSelectionSurface(
                    canvasReference: activeCanvasReference,
                    elementsStore: model.canvasElements,
                    selectionController: selectionController,
                    // Only the ink tools borrow a tap for element selection. Shapes and photos
                    // then use the same Select-tool edit flow. While Select is already active its
                    // capture surface owns taps, including tapping away to deselect, and two tap
                    // handlers on one canvas would race; the eraser and Text answer their own taps.
                    isEnabled: selectedTool.isInkTool,
                    onElementSelected: borrowSelectTool
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)

                CanvasElementsBandLayer(
                    store: model.canvasElements,
                    selectionController: selectionController,
                    placement: .aboveInk,
                    textDefaults: app.toolPreferences.preferences.text,
                    isTextToolActive: selectedTool == .text
                )
                .contentViewportFrame(
                    contentWidth: pageGeometry.contentWidth,
                    contentHeight: pageState.contentHeight,
                    zoom: canvasViewport.zoomScale,
                    contentOffset: canvasViewport.contentOffset,
                    viewportSize: geometry.size
                )

                SelectionOverlayView(
                    controller: selectionController,
                    selectionMode: app.toolPreferences.preferences.selection.mode,
                    isActive: selectionController.selection != nil
                        || selectedTool == .select,
                    isSelectToolActive: selectedTool == .select
                )
                .contentViewportFrame(
                    contentWidth: pageGeometry.contentWidth,
                    contentHeight: pageState.contentHeight,
                    zoom: canvasViewport.zoomScale,
                    contentOffset: canvasViewport.contentOffset,
                    viewportSize: geometry.size
                )

                // Not gated on the Select tool: tapping a shape selects it while an ink tool is
                // active, and that is exactly when the actions need to be reachable.
                if selectionController.selection != nil,
                   selectionController.strokesSnapshot == nil,
                   selectionController.dragTranslation == .zero,
                   let avoidanceRect = selectionController.stripAvoidanceBounds {
                    let stripSize = SelectionActionStripView.stripSize(
                        includesStyle: selectionController.selectionSupportsStyling
                    )
                    SelectionActionStripView(controller: selectionController)
                        .position(SelectionActionStripView.position(
                            avoiding: canvasViewport.viewRect(fromContent: avoidanceRect),
                            stripSize: stripSize,
                            in: canvasSize,
                            topInset: topOverlayHeight + 12
                        ))
                        .zIndex(4.5)
                }

                if selectionController.selection == nil,
                   let target = selectionController.pendingPasteTarget {
                    let tapViewPoint = canvasViewport.viewPoint(fromContent: target)
                    if CGRect(origin: .zero, size: canvasSize)
                        .insetBy(dx: -20, dy: -20)
                        .contains(tapViewPoint) {
                        SelectionPasteBubbleView {
                            Task {
                                await selectionController.pasteFromPasteboard(at: target)
                            }
                        }
                        .position(SelectionPasteBubbleView.position(
                            forTapAt: tapViewPoint,
                            in: canvasSize
                        ))
                        .zIndex(4.5)
                    }
                }

                if showsBacklinksRail {
                    backlinksRail
                        .frame(width: 184)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, topOverlayHeight + 12)
                        .zIndex(2)
                }

                if let entity = model.selectedEntity {
                    EntityPopoverView(entity: entity, model: model, app: app)
                        .frame(width: 270)
                        .padding(.leading, 80)
                        .padding(.top, topOverlayHeight + 12)
                        .transition(.offset(y: 6).combined(with: .opacity))
                        .zIndex(5)
                }

                if !model.pendingProposals.isEmpty {
                    agentLine
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: .bottomLeading
                        )
                        .padding(.leading, 80)
                        .padding(.bottom, 92)
                        .zIndex(3)
                }

                HStack(spacing: 8) {
                    PageTrackerBadge(
                        currentPage: pageState.currentPageIndex + 1,
                        pageCount: pageState.pageCount
                    ) {
                        isShowingThumbnails.toggle()
                    }

                    if !isZoomAtFit {
                        ZoomResetPill(
                            zoomPercentOfFit: Int((canvasViewport.zoomScale
                                / fitZoomScale * 100).rounded()),
                            onTap: resetZoomToFit
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .bottomLeading
                )
                .padding(.leading, 20)
                .padding(.bottom, 20)
                .zIndex(4)
                .animation(.easeOut(duration: 0.18), value: isZoomAtFit)
            }
            .clipped()
            .onAppear {
                canvasSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
    }

    private var backlinksRail: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(model.backlinks, id: \.sourceNoteID) { backlink in
                Button {
                    Task {
                        await app.openNote(backlink.sourceNoteID)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(backlink.sourceTitle)
                            .foregroundStyle(VellumTheme.bodyMuted)
                            .lineLimit(1)
                        Text("· \(backlink.kind.rawValue)")
                            .foregroundStyle(VellumTheme.mutedCount)
                    }
                    .font(.system(size: 12.5))
                    .padding(.leading, 16)
                    .padding(.trailing, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        VellumTheme.card,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 10
                        )
                    )
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 10
                        )
                        .stroke(VellumTheme.ink(0.14), lineWidth: 1)
                    }
                    .shadow(color: VellumTheme.ink(0.06), radius: 3, x: -2, y: 2)
                }
                .buttonStyle(.plain)
            }

            Text("\(model.backlinks.count) \(model.backlinks.count == 1 ? "backlink" : "backlinks")")
                .font(.vellumMono(10.5))
                .foregroundStyle(VellumTheme.mutedCount)
                .padding(.trailing, 14)
        }
    }

    private var agentLine: some View {
        Button {
            model.isShowingSuggestions = true
        } label: {
            HStack(spacing: 3) {
                Text("\(model.pendingProposals.count) suggestions —")
                Text("review")
                    .foregroundStyle(VellumTheme.accentDark)
                    .overlay(alignment: .bottom) {
                        VellumDottedLine(color: VellumTheme.accent)
                            .frame(height: 1)
                            .offset(y: 1)
                    }
            }
            .font(.vellumNewsreader(13.5, italic: true))
            .foregroundStyle(VellumTheme.muted)
        }
        .buttonStyle(.plain)
    }

    private var suggestionsOverlay: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.isShowingSuggestions = false
                }

            suggestionsPanel
                .frame(width: 370)
                .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var modalOverlays: some View {
        if isShowingThumbnails && showsSuggestionsAndThumbnails {
            thumbnailOverlay
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(9)
        }

        if model.isShowingSuggestions && showsSuggestionsAndThumbnails {
            suggestionsOverlay
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(10)
        }

        if model.isShowingBackgroundChooser {
            PageBackgroundChooserOverlay(
                onChoose: { kind in
                    model.backgroundStyle = PageBackgroundStyle(kind: kind)
                    model.isShowingBackgroundChooser = false
                },
                onDismiss: {
                    model.isShowingBackgroundChooser = false
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .zIndex(11)
        }
    }

    private var thumbnailOverlay: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    isShowingThumbnails = false
                }

            ThumbnailPanelView(
                store: thumbnailStore,
                pages: model.note?.pages ?? [],
                pageCount: pageState.pageCount,
                currentPageIndex: pageState.currentPageIndex,
                geometry: model.note?.pageGeometry ?? .a4,
                contentProvider: currentPageRendererContent,
                onSelect: { index in
                    scrollCanvas(toPageIndex: index)
                    isShowingThumbnails = false
                },
                onMovePages: { source, destination in
                    // Remap only after the model confirms the mutation: a
                    // rejected move must leave the cache untouched or rows
                    // would show the wrong pages' thumbnails indefinitely.
                    let pageCount = pageState.pageCount
                    guard model.movePages(source: source, to: destination) else {
                        return
                    }
                    thumbnailStore.applyMove(
                        fromOffsets: source,
                        toOffset: destination,
                        pageCount: pageCount
                    )
                },
                onDeletePage: { index in
                    let pageCount = pageState.pageCount
                    guard model.deletePage(at: index) else { return }
                    thumbnailStore.applyDeletion(at: index, pageCount: pageCount)
                },
                onAddPage: {
                    model.addPageAtEnd()
                },
                onDismiss: {
                    isShowingThumbnails = false
                }
            )
            .frame(width: 250)
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestions")
                        .font(.vellumNewsreader(22, weight: .semibold))
                    Text("\(model.pendingProposals.count) ready to review")
                        .font(.vellumMono(10.5))
                        .foregroundStyle(VellumTheme.mutedCount)
                }
                Spacer()
                Button("×") {
                    model.isShowingSuggestions = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(VellumTheme.mutedCount)
                .accessibilityLabel("Close suggestions")
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.pendingProposals) { proposal in
                        suggestionCard(proposal)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
    }

    private func suggestionCard(_ proposal: AgentProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.title)
                    .font(.vellumNewsreader(16, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)
                Spacer()
                Text("\(Int((proposal.confidence * 100).rounded()))%")
                    .font(.vellumMono(10.5, weight: .medium))
                    .foregroundStyle(VellumTheme.accentDark)
            }

            Text(operationDescription(proposal.operation))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(VellumTheme.bodyMuted)

            Text(proposal.explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(VellumTheme.mutedDark)
                .lineSpacing(4)

            HStack(spacing: 10) {
                Button("Accept") {
                    Task { await model.accept(proposal) }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(VellumTheme.paper)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(VellumTheme.ink, in: Capsule())

                Button("Reject") {
                    Task { await model.reject(proposal) }
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(VellumTheme.mutedDark)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VellumTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(VellumTheme.ink(0.1), lineWidth: 1)
        }
    }

    private var activeTool: (any PKTool)? {
        NoteToolFactory.tool(
            for: selectedTool,
            preferences: app.toolPreferences.preferences
        ) ?? lastNonNilTool
    }

    private var currentVisibleContentRect: CGRect {
        canvasViewport.visibleContentRect(viewportSize: canvasSize)
    }

    private var fitZoomScale: CGFloat {
        PageLayout.minZoom(
            forViewportWidth: canvasSize.width,
            contentWidth: model.note?.pageGeometry.contentWidth
                ?? PageGeometry.a4.contentWidth
        )
    }

    private var isZoomAtFit: Bool {
        canvasSize.width <= 0 || abs(canvasViewport.zoomScale / fitZoomScale - 1) < 0.01
    }

    private func cacheCurrentTool() {
        guard let tool = NoteToolFactory.tool(
            for: selectedTool,
            preferences: app.toolPreferences.preferences
        ) else { return }
        lastNonNilTool = tool
    }

    private func borrowSelectTool() {
        if selectedTool != .select {
            app.split.toolBorrowedByElementSelection = selectedTool
        }
        selectedTool = .select
    }

    private func selectImportedElement(id: UUID) {
        selectionController.selectElement(id: id, survivesNextToolChange: true)
        borrowSelectTool()
    }

    private func entityColor(for kind: EntityKind) -> Color {
        switch kind {
        case .person: VellumTheme.accent
        case .topic: VellumTheme.thesis
        case .document: VellumTheme.spaceBlue
        }
    }

    private func operationDescription(_ operation: AgentOperation) -> String {
        switch operation {
        case .addTag(let tag):
            "Add tag “\(tag)”"
        case .suggestTitle(let title):
            "Rename note to “\(title)”"
        case .createSummary(let summary):
            "Create summary: \(summary)"
        case .fileToSpace(let spaceName, let color):
            "File in \(spaceName) · \(color.rawValue)"
        case .linkNotes(let targetNoteID, let kind):
            "Link to \(model.noteTitles[targetNoteID] ?? targetNoteID.uuidString) · \(kind.rawValue)"
        case .extractTask(let text, _):
            "Extract task: \(text)"
        case .extractEntity(let name, let kind, _, _):
            "Extract \(kind.rawValue): \(name)"
        }
    }

    private func deleteNote() {
        Task {
            do {
                try await app.deleteNote(id: model.noteID)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func scrollCanvas(toPageIndex index: Int) {
        guard let canvas = activeCanvasReference.canvasView else { return }
        let geometry = model.note?.pageGeometry ?? .a4
        let inset = canvas.contentInset.top
        let y = geometry.pageRect(index: index).minY * canvas.zoomScale - inset
        let maxY = max(-inset, canvas.contentSize.height - canvas.bounds.height)
        canvas.setContentOffset(
            CGPoint(x: canvas.contentOffset.x, y: min(max(-inset, y), maxY)),
            animated: true
        )
    }

    private func resetZoomToFit() {
        (activeCanvasReference.canvasView as? PagedCanvasView)?.snapZoomToFit()
    }

    private func currentPageRendererContent() -> NotePageRenderer.Content {
        let persistedDrawing = model.drawingData.flatMap { data in
            try? PKDrawing(data: data)
        }
        let pdfExpectedBands = model.pdfBands
        var pdfPagesByBand: [Int: PDFPage] = [:]
        for band in pdfExpectedBands where band < pageState.pageCount {
            pdfPagesByBand[band] = model.pdfCache.page(forBand: band)
        }
        let content = NotePageRenderer.Content(
            drawing: activeCanvasReference.canvasView?.drawing
                ?? persistedDrawing
                ?? PKDrawing(),
            elements: model.canvasElements.elements,
            imagesByAssetPath: model.canvasElements.imageCache,
            pageCount: pageState.pageCount,
            geometry: model.note?.pageGeometry ?? .a4,
            style: model.note?.backgroundStyle ?? .legacyDefault,
            pdfPagesByBand: pdfPagesByBand,
            pdfExpectedBands: pdfExpectedBands
        )
        assert(content.geometry == pageState.pageGeometry)
        return content
    }

    private func exportNote(_ format: NoteExporter.Format) {
        guard !model.isLoading, model.note != nil else {
            model.errorMessage = "The note must finish loading before it can be exported."
            return
        }

        Task {
            await model.flushPendingSave()
            let content = currentPageRendererContent()

            do {
                let output = try NoteExporter.export(
                    content: content,
                    title: model.title,
                    format: format,
                    minimumFilledPages: model.note?.pages.count ?? 0
                )
                exportDirectoryToCleanUp = output.directory
                exportOutput = output
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func cleanUpExportDirectory() {
        guard let directory = exportDirectoryToCleanUp else { return }
        try? FileManager.default.removeItem(at: directory)
        exportDirectoryToCleanUp = nil
    }
}

private struct ContentViewportFrameModifier: ViewModifier {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let zoom: CGFloat
    let contentOffset: CGPoint
    let viewportSize: CGSize

    func body(content: Content) -> some View {
        content
            .frame(
                width: contentWidth,
                height: contentHeight,
                alignment: .topLeading
            )
            .scaleEffect(zoom, anchor: .topLeading)
            .offset(
                x: -contentOffset.x,
                y: -contentOffset.y
            )
            .frame(
                width: viewportSize.width,
                height: viewportSize.height,
                alignment: .topLeading
            )
            .clipped()
    }
}

private extension View {
    func contentViewportFrame(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        zoom: CGFloat,
        contentOffset: CGPoint,
        viewportSize: CGSize
    ) -> some View {
        modifier(
            ContentViewportFrameModifier(
                contentWidth: contentWidth,
                contentHeight: contentHeight,
                zoom: zoom,
                contentOffset: contentOffset,
                viewportSize: viewportSize
            )
        )
    }
}

private struct NoteScreenLifecycleModifiers: ViewModifier {
    let model: NoteScreenModel
    let app: VellumAppModel
    let canvasReference: NoteCanvasReference
    let paneUndoManager: UndoManager?
    let selectionController: CanvasSelectionController
    let shapeSnapController: ShapeSnapController
    let pageState: NotePageState
    let thumbnailStore: PageThumbnailStore
    let currentVisibleContentRect: () -> CGRect
    let cacheCurrentTool: () -> Void
    let scrollCanvas: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .task {
                cacheCurrentTool()
                pageState.pageGeometry = model.note?.pageGeometry ?? .a4
                selectionController.contentWidth = pageState.pageGeometry.contentWidth
                model.canvasElements.canvasReference = canvasReference
                if let paneUndoManager {
                    model.canvasElements.undoManagerOverride = paneUndoManager
                }
                selectionController.canvasReference = canvasReference
                selectionController.elementsStore = model.canvasElements
                model.hasHiddenSelectionStrokes = { [weak selectionController] in
                    selectionController?.hasHiddenStrokes ?? false
                }
                shapeSnapController.canvasReference = canvasReference
                shapeSnapController.elementsStore = model.canvasElements
                model.canvasElements.onSnapshotApplied = { [weak selectionController] in
                    selectionController?.externalDrawingDidChange()
                }
                model.onScrollToPage = { index in
                    pageState.updateContent(
                        drawingBounds: canvasReference.canvasView?.drawing.bounds ?? .null,
                        elements: model.canvasElements.elements,
                        minimumFilledPages: model.note?.pages.count ?? 0
                    )
                    Task { @MainActor in
                        await Task.yield()
                        scrollCanvas(index)
                    }
                }
                model.onPageOrientationChanged = {
                    thumbnailStore.markDirty()
                }
                model.onOrientationFlipped = { contentY in
                    Task { @MainActor in
                        await Task.yield()
                        guard let canvas = canvasReference.canvasView as? PagedCanvasView else {
                            return
                        }
                        let offsetY = PageLayout.anchoredOffsetY(
                            visibleCenterContentY: contentY,
                            scale: canvas.zoomScale,
                            viewportHeight: canvas.bounds.height,
                            contentHeight: canvas.contentHeightInContentSpace,
                            minimumOffsetY: -canvas.topContentInset
                        )
                        canvas.setContentOffset(
                            CGPoint(x: canvas.contentOffset.x, y: offsetY),
                            animated: false
                        )
                    }
                }
                let resolveSnapGrid = { [weak model, weak pageState] (point: CGPoint) -> ShapeSnapGrid? in
                    guard let model, let pageState, let note = model.note else { return nil }
                    let geometry = pageState.pageGeometry
                    let pageIndex = geometry.pageIndex(
                        forContentY: point.y,
                        pageCount: pageState.pageCount
                    )
                    // A PDF page draws no pattern, so there is no lattice to align to there.
                    guard !model.pdfBands.contains(pageIndex) else { return nil }
                    return ShapeGridSnapper.grid(
                        for: note.backgroundStyle,
                        pageRect: geometry.pageRect(index: pageIndex)
                    )
                }
                selectionController.snapGrid = resolveSnapGrid
                shapeSnapController.snapGrid = resolveSnapGrid
                selectionController.persistImageData = { [weak model] data in
                    await model?.persistPastedImageData(data)
                }
                selectionController.importSystemImage = { [weak model] data, target in
                    await model?.importImage(
                        data,
                        visibleContentRect: currentVisibleContentRect(),
                        centeredAt: target
                    )
                }
                selectionController.onOperationFailed = { [weak model] message in
                    model?.errorMessage = message
                }
                cacheCurrentTool()
                if model.note == nil {
                    await model.load()
                    if let message = model.pdfLoadFailureMessage {
                        app.showToast(message, actionLabel: "Retry") { [weak model] in
                            Task { await model?.retryPDFLoad() }
                        }
                    }
                }
                pageState.pageGeometry = model.note?.pageGeometry ?? .a4
                selectionController.contentWidth = pageState.pageGeometry.contentWidth
                pageState.updateContent(
                    drawingBounds: canvasReference.canvasView?.drawing.bounds ?? .null,
                    elements: model.canvasElements.elements,
                    minimumFilledPages: model.note?.pages.count ?? 0
                )
            }
            .onDisappear {
                model.onScrollToPage = nil
                model.hasHiddenSelectionStrokes = nil
                model.onPageOrientationChanged = nil
                model.onOrientationFlipped = nil
            }
    }
}

private struct NoteScreenPrimaryChangeObservers: ViewModifier {
    let model: NoteScreenModel
    let app: VellumAppModel
    let selectionController: CanvasSelectionController
    let selectedTool: ToolID
    let cacheCurrentTool: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: selectedTool) { oldValue, newTool in
                if oldValue == .text, newTool != .text {
                    model.canvasElements.finishTextEditingSession(matching: nil)
                }
                selectionController.toolChanged()
                cacheCurrentTool()
            }
            .onChange(of: app.toolPreferences.preferences) {
                cacheCurrentTool()
            }
            .onChange(of: model.pendingProposals.count) { _, count in
                if count == 0 {
                    model.isShowingSuggestions = false
                }
            }
    }
}

private struct NoteScreenCanvasContentChangeObservers: ViewModifier {
    let model: NoteScreenModel
    let canvasReference: NoteCanvasReference
    let pageState: NotePageState
    let thumbnailStore: PageThumbnailStore
    let isShowingThumbnails: Bool
    let currentPageRendererContent: () -> NotePageRenderer.Content

    func body(content: Content) -> some View {
        content
            .onChange(of: model.drawingData) { _, _ in
                let drawingBounds = canvasReference.canvasView?.drawing.bounds
                    ?? (try? PKDrawing(data: model.drawingData ?? Data()))?.bounds
                    ?? .null
                pageState.updateContent(
                    drawingBounds: drawingBounds,
                    elements: model.canvasElements.elements,
                    minimumFilledPages: model.note?.pages.count ?? 0
                )
                thumbnailStore.markDirty()
            }
            .onChange(of: model.canvasElements.elements) { _, _ in
                pageState.updateContent(
                    drawingBounds: canvasReference.canvasView?.drawing.bounds ?? .null,
                    elements: model.canvasElements.elements,
                    minimumFilledPages: model.note?.pages.count ?? 0
                )
                thumbnailStore.markDirty()
            }
            .onChange(of: model.note?.backgroundStyle) { _, _ in
                thumbnailStore.markDirty()
            }
    }
}

private struct NoteScreenPageViewportChangeObservers: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var pdfWindowUpdateTask: Task<Void, Never>?

    let model: NoteScreenModel
    let canvasReference: NoteCanvasReference
    let selectionController: CanvasSelectionController
    let pageState: NotePageState
    let thumbnailStore: PageThumbnailStore
    let canvasViewport: CanvasViewport
    let canvasSize: CGSize

    func body(content: Content) -> some View {
        content
            .onChange(of: model.note?.pages.map(\.id)) { _, _ in
                pageState.pageGeometry = model.note?.pageGeometry ?? .a4
                pageState.updateContent(
                    drawingBounds: canvasReference.canvasView?.drawing.bounds ?? .null,
                    elements: model.canvasElements.elements,
                    minimumFilledPages: model.note?.pages.count ?? 0
                )
                thumbnailStore.markDirty()
                schedulePDFWindowUpdate()
            }
            .onChange(of: model.note?.pageGeometry) { _, geometry in
                pageState.pageGeometry = geometry ?? .a4
                selectionController.contentWidth = pageState.pageGeometry.contentWidth
                pageState.updateContent(
                    drawingBounds: canvasReference.canvasView?.drawing.bounds ?? .null,
                    elements: model.canvasElements.elements,
                    minimumFilledPages: model.note?.pages.count ?? 0
                )
                schedulePDFWindowUpdate()
            }
            .onChange(of: canvasViewport) { _, _ in
                pageState.updateViewport(canvasViewport, viewportSize: canvasSize)
                schedulePDFWindowUpdate()
            }
            .onChange(of: canvasSize) { _, _ in
                pageState.updateViewport(canvasViewport, viewportSize: canvasSize)
                schedulePDFWindowUpdate()
            }
            .onChange(of: colorScheme, initial: true) { _, newValue in
                model.pdfCache.setAppearance(isDark: newValue == .dark)
            }
    }

    private func schedulePDFWindowUpdate() {
        pdfWindowUpdateTask?.cancel()
        guard !model.pdfBands.isEmpty,
              canvasSize.width > 0,
              canvasSize.height > 0,
              pageState.pageCount > 0 else {
            return
        }

        let cache = model.pdfCache
        let viewport = canvasViewport
        let viewportSize = canvasSize
        let pageCount = pageState.pageCount
        let geometry = pageState.pageGeometry
        let scale = displayScale
        pdfWindowUpdateTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let visibleRect = viewport.visibleContentRect(viewportSize: viewportSize)
            let firstBand = geometry.pageIndex(
                forContentY: visibleRect.minY,
                pageCount: pageCount
            )
            let lastBand = geometry.pageIndex(
                forContentY: visibleRect.maxY,
                pageCount: pageCount
            )
            cache.updateVisibleWindow(
                bands: firstBand...lastBand,
                bucket: viewport.zoomScale > 1.5 ? .zoomed : .fit,
                displayScale: scale
            )
        }
    }
}

private struct NoteScreenActivityPresentationModifiers: ViewModifier {
    let model: NoteScreenModel
    let app: VellumAppModel
    @Binding var isShowingActivity: Bool
    @Binding var exportOutput: NoteExporter.Output?
    let cleanUpExportDirectory: () -> Void
    @Binding var isConfirmingDelete: Bool
    let deleteNote: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isShowingActivity) {
                NavigationStack {
                    ActivityView(
                        workspace: app.container.workspace,
                        noteID: model.noteID
                    )
                }
            }
            .sheet(item: $exportOutput, onDismiss: cleanUpExportDirectory) { output in
                ShareSheetView(items: output.urls)
            }
            .confirmationDialog(
                "Move to Trash?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    deleteNote()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The note moves to the Trash. You can restore it there later.")
            }
    }
}

private struct NoteScreenPhotoImportModifiers: ViewModifier {
    let model: NoteScreenModel
    @Binding var isShowingPhotosPicker: Bool
    @Binding var photosPickerItem: PhotosPickerItem?
    let currentVisibleContentRect: () -> CGRect
    let onImageImported: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isShowingPhotosPicker,
                selection: $photosPickerItem,
                matching: .images
            )
            .onChange(of: photosPickerItem) {
                Task {
                    if let item = photosPickerItem,
                       let data = try? await item.loadTransferable(type: Data.self) {
                        if let id = await model.importImage(
                            data,
                            visibleContentRect: currentVisibleContentRect()
                        ) {
                            onImageImported(id)
                        }
                    }
                    photosPickerItem = nil
                }
            }
    }
}

private struct NoteScreenFileImportAndAlertModifiers: ViewModifier {
    let model: NoteScreenModel
    @Binding var isShowingFileImporter: Bool
    let currentVisibleContentRect: () -> CGRect
    let onImageImported: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.image]
            ) { result in
                switch result {
                case .success(let url):
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if isAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    do {
                        let data = try Data(contentsOf: url)
                        Task {
                            if let id = await model.importImage(
                                data,
                                visibleContentRect: currentVisibleContentRect()
                            ) {
                                onImageImported(id)
                            }
                        }
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                }
            }
            .alert(
                "Vellum",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { model.errorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.errorMessage = nil
                }
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
    }
}

private struct NoteScreenAnimationModifiers: ViewModifier {
    let model: NoteScreenModel
    let isShowingThumbnails: Bool

    func body(content: Content) -> some View {
        content
            .animation(.easeOut(duration: 0.18), value: model.selectedEntity?.id)
            .animation(.easeOut(duration: 0.2), value: model.isShowingSuggestions)
            .animation(.easeOut(duration: 0.2), value: isShowingThumbnails)
            .animation(.easeOut(duration: 0.2), value: model.isShowingBackgroundChooser)
    }
}

extension ToolID {
    var usesDrawingGesture: Bool {
        self != .text && self != .select
    }
}
