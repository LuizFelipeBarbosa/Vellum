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
    @State private var pdfWindowUpdateTask: Task<Void, Never>?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

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
        // The screen's contract, applied outward from the surface: lifecycle,
        // then the observers that react to it, then presentations, then
        // animations. Each phase is its own method so the type checker solves
        // it independently — one flat chain costs ~8s to type-check.
        //
        // The animations must stay outermost or the suggestions, thumbnail and
        // paper-chooser transitions stop animating and the entity popover pops
        // instead of sliding.
        animating(
            presenting(
                observingPagination(
                    observingCanvasContent(
                        observingInteraction(
                            screenSurface
                        )
                    )
                )
            )
        )
    }

    /// The surface plus everything that establishes and tears down its wiring.
    private var screenSurface: some View {
        noteSurface
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
            .task { await establishCanvasWiring() }
            .onDisappear {
                // The only thing breaking the model -> closure -> model cycle.
                model.onScrollToPage = nil
                model.hasHiddenSelectionStrokes = nil
                model.onPageOrientationChanged = nil
                model.onOrientationFlipped = nil
            }
    }

    /// Observers for what the user is doing right now.
    private func observingInteraction(_ content: some View) -> some View {
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
            // Must stay after the selectedTool observer above, which can clear the
            // selection this one reacts to.
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
            // Must stay after the borrow observer above, which restores the borrowed tool.
            .onChange(of: paneContext.isFocused) { wasFocused, isFocused in
                if wasFocused, !isFocused {
                    selectionController.clearSelection()
                    model.isShowingSuggestions = false
                    isShowingThumbnails = false
                    app.split.isShowingPaperOptions = false
                }
            }

    }

    /// Observers for the ink and elements on the page.
    private func observingCanvasContent(_ content: some View) -> some View {
        content
            .onChange(of: model.drawingData) { _, _ in
                refreshPageCount(
                    drawingBounds: activeCanvasReference.canvasView?.drawing.bounds
                        ?? (try? PKDrawing(data: model.drawingData ?? Data()))?.bounds
                )
                thumbnailStore.markDirty()
            }
            .onChange(of: model.canvasElements.elements) { _, _ in
                refreshPageCount()
                thumbnailStore.markDirty()
            }
            .onChange(of: model.note?.backgroundStyle) { _, _ in
                thumbnailStore.markDirty()
            }
    }

    /// Observers for pagination, the viewport, and the appearance the PDF cache
    /// renders against.
    private func observingPagination(_ content: some View) -> some View {
        content
            .onChange(of: model.note?.pages.map(\.id)) { _, _ in
                pageState.pageGeometry = model.note?.pageGeometry ?? .a4
                refreshPageCount()
                thumbnailStore.markDirty()
                schedulePDFWindowUpdate()
            }
            .onChange(of: model.note?.pageGeometry) { _, geometry in
                pageState.pageGeometry = geometry ?? .a4
                selectionController.contentWidth = pageState.pageGeometry.contentWidth
                refreshPageCount()
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
            // initial: true is load-bearing — without it the PDF cache stays in
            // light mode until the first appearance change, so PDFs render wrong
            // on a dark-mode launch.
            .onChange(of: colorScheme, initial: true) { _, newValue in
                model.pdfCache.setAppearance(isDark: newValue == .dark)
            }
    }

    /// Sheets, importers and the error alert.
    private func presenting(_ content: some View) -> some View {
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
            .photosPicker(
                isPresented: $model.isShowingPhotosPicker,
                selection: $photosPickerItem,
                matching: .images
            )
            .onChange(of: photosPickerItem) {
                Task {
                    if let item = photosPickerItem,
                       let data = try? await item.loadTransferable(type: Data.self) {
                        if let id = await model.importImage(
                            data,
                            visibleContentRect: currentVisibleContentRect
                        ) {
                            selectImportedElement(id: id)
                        }
                    }
                    photosPickerItem = nil
                }
            }
            .fileImporter(
                isPresented: $model.isShowingFileImporter,
                allowedContentTypes: [.image]
            ) { result in
                guard let file = SecurityScopedFile.read(result, onFailure: {
                    model.errorMessage = $0
                }) else { return }

                Task {
                    if let id = await model.importImage(
                        file.data,
                        visibleContentRect: currentVisibleContentRect
                    ) {
                        selectImportedElement(id: id)
                    }
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

    private func animating(_ content: some View) -> some View {
        content
            .animation(.easeOut(duration: 0.18), value: model.selectedEntity?.id)
            .animation(.easeOut(duration: 0.2), value: model.isShowingSuggestions)
            .animation(.easeOut(duration: 0.2), value: isShowingThumbnails)
            .animation(.easeOut(duration: 0.2), value: model.isShowingBackgroundChooser)
    }

    private var noteSurface: some View {
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
                    NoteEntityChipsRow(
                        entities: model.noteEntities,
                        onSelect: { model.selectedEntity = $0 }
                    )
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

            // Reads top to bottom as the canvas z-order. Only adjacent children
            // sharing a zIndex are grouped, so the grouping cannot reorder anything.
            ZStack(alignment: .topLeading) {
                pageBackdrop(size: geometry.size, pageGeometry: pageGeometry)
                pencilCanvas(
                    size: geometry.size,
                    pageGeometry: pageGeometry,
                    canvasGlobalOrigin: canvasGlobalOrigin
                )
                canvasInputSurfaces(size: geometry.size)
                elementsAndSelectionOverlay(size: geometry.size, pageGeometry: pageGeometry)
                selectionActionStrip
                selectionPasteBubble
                backlinksRailOverlay
                entityPopoverOverlay
                agentLineOverlay(size: geometry.size)
                pageStatusCluster(size: geometry.size)
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

    /// Everything painted beneath the ink: page guides, PDF pages and their
    /// adornments, and the elements that sit below the drawing.
    @ViewBuilder
    private func pageBackdrop(size: CGSize, pageGeometry: PageGeometry) -> some View {
        PageGuideLayer(
            viewport: canvasViewport,
            viewportSize: canvasSize,
            pageCount: pageState.pageCount,
            geometry: pageGeometry,
            style: model.note?.backgroundStyle ?? .legacyDefault,
            pdfBands: model.pdfBands
        )
        .frame(width: size.width, height: size.height)

        PdfPagesLayer(
            cache: model.pdfCache,
            pdfBands: model.pdfBands,
            viewport: canvasViewport,
            pageCount: pageState.pageCount,
            geometry: pageGeometry
        )
        .contentViewportFrame(
            contentWidth: pageGeometry.contentWidth,
            contentHeight: pageState.contentHeight,
            zoom: canvasViewport.zoomScale,
            contentOffset: canvasViewport.contentOffset,
            viewportSize: size
        )

        PageGuideLayer(
            viewport: canvasViewport,
            viewportSize: canvasSize,
            pageCount: pageState.pageCount,
            geometry: pageGeometry,
            style: model.note?.backgroundStyle ?? .legacyDefault,
            pdfBands: model.pdfBands,
            mode: .pdfAdornments
        )
        .frame(width: size.width, height: size.height)
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
            viewportSize: size
        )
    }

    /// The PencilKit canvas itself.
    ///
    /// Must stay an unconditional direct child of the canvas ZStack. Putting it
    /// behind an `if`, or inside a view that is conditionally instantiated,
    /// re-creates the representable: that resets the PKCanvasView, drops
    /// `canvasReference.canvasView`, bumps `pane.canvasGeneration`, and loses the
    /// undo stack, the zoom and the content offset.
    private func pencilCanvas(
        size: CGSize,
        pageGeometry: PageGeometry,
        canvasGlobalOrigin: CGPoint
    ) -> some View {
        PencilCanvasView(
            drawingData: model.drawingData,
            onDrawingChanged: { data in
                model.drawingChanged(data)
                refreshPageCount()
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
                refreshPageCount()
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
        .frame(width: size.width, height: size.height)
    }

    /// The invisible gesture surfaces over the ink.
    ///
    /// Declaration order is recognizer precedence — snap, then erase, then tap
    /// selection. Reordering these reopens a tap race that was fixed once already.
    @ViewBuilder
    private func canvasInputSurfaces(size: CGSize) -> some View {
        ShapeSnapSurface(
            controller: shapeSnapController,
            isEnabled: selectedTool.isInkTool,
            inkConfig: selectedTool.inkConfigKeyPath.map {
                app.toolPreferences.preferences[keyPath: $0]
            },
            isDrawingEnabled: selectedTool.usesDrawingGesture
        )
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)

        ShapeEraserSurface(
            canvasReference: activeCanvasReference,
            elementsStore: model.canvasElements,
            eraserConfig: app.toolPreferences.preferences.eraser,
            isEnabled: selectedTool == .eraser
        )
        .frame(width: size.width, height: size.height)
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
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    /// The elements drawn above the ink, and the handles that manipulate them.
    @ViewBuilder
    private func elementsAndSelectionOverlay(
        size: CGSize,
        pageGeometry: PageGeometry
    ) -> some View {
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
            viewportSize: size
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
            viewportSize: size
        )
    }

    @ViewBuilder
    private var selectionActionStrip: some View {
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
    }

    @ViewBuilder
    private var selectionPasteBubble: some View {
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
    }

    @ViewBuilder
    private var backlinksRailOverlay: some View {
        if showsBacklinksRail {
            NoteBacklinksRail(
                backlinks: model.backlinks,
                onOpen: { noteID in Task { await app.openNote(noteID) } }
            )
            .frame(width: 184)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, topOverlayHeight + 12)
            .zIndex(2)
        }
    }

    @ViewBuilder
    private var entityPopoverOverlay: some View {
        if let entity = model.selectedEntity {
            EntityPopoverView(entity: entity, model: model, app: app)
                .frame(width: 270)
                .padding(.leading, 80)
                .padding(.top, topOverlayHeight + 12)
                .transition(.offset(y: 6).combined(with: .opacity))
                .zIndex(5)
        }
    }

    @ViewBuilder
    private func agentLineOverlay(size: CGSize) -> some View {
        if !model.pendingProposals.isEmpty {
            NoteAgentLine(model: model)
                .frame(
                    width: size.width,
                    height: size.height,
                    alignment: .bottomLeading
                )
                .padding(.leading, 80)
                .padding(.bottom, 92)
                .zIndex(3)
        }
    }

    /// The page tracker and the zoom-reset pill, pinned to the bottom leading corner.
    private func pageStatusCluster(size: CGSize) -> some View {
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
            width: size.width,
            height: size.height,
            alignment: .bottomLeading
        )
        .padding(.leading, 20)
        .padding(.bottom, 20)
        .zIndex(4)
        .animation(.easeOut(duration: 0.18), value: isZoomAtFit)
    }

    @ViewBuilder
    private var modalOverlays: some View {
        if isShowingThumbnails && showsSuggestionsAndThumbnails {
            NoteThumbnailOverlay(
                model: model,
                store: thumbnailStore,
                pageState: pageState,
                contentProvider: currentPageRendererContent,
                onScrollToPage: { scrollCanvas(toPageIndex: $0) },
                onDismiss: { isShowingThumbnails = false }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(9)
        }

        if model.isShowingSuggestions && showsSuggestionsAndThumbnails {
            NoteSuggestionsOverlay(model: model)
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

    /// Wires the canvas, selection and snap controllers to the model, loads the
    /// note, then adopts its page geometry.
    ///
    /// Ordering here is load-bearing in three ways, and none of it is covered by
    /// a test:
    ///
    /// - Every consumer is wired before any callback can fire.
    /// - `pageState.pageGeometry` is set before `selectionController.contentWidth`
    ///   reads it, and `canvasElements.canvasReference` before its undo override.
    /// - The geometry/width/page-count adoption at the end must stay *after*
    ///   `model.load()`, which is what populates `model.note`. Hoisting it renders
    ///   a landscape or PDF note at A4 on first paint.
    private func establishCanvasWiring() async {
        // Local bindings, not members: the closures below capture some of these
        // weakly, and `[weak selectionController]` on a member would silently
        // capture self instead — pinning the view struct, and through it the pane,
        // its UndoManager and the PKCanvasView, for as long as the model holds the
        // closure. Closed panes would never deallocate.
        let model = self.model
        let app = self.app
        let canvasReference = self.activeCanvasReference
        let selectionController = self.selectionController
        let shapeSnapController = self.shapeSnapController
        let pageState = self.pageState
        let thumbnailStore = self.thumbnailStore

        cacheCurrentTool()
        pageState.pageGeometry = model.note?.pageGeometry ?? .a4
        selectionController.contentWidth = pageState.pageGeometry.contentWidth
        model.canvasElements.canvasReference = canvasReference
        model.canvasElements.undoManagerOverride = paneContext.pane.undoManager
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
            refreshPageCount()
            Task { @MainActor in
                await Task.yield()
                scrollCanvas(toPageIndex: index)
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
        // One closure, assigned to both controllers, so the two snap paths can
        // never disagree about the lattice.
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
                visibleContentRect: currentVisibleContentRect,
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
        refreshPageCount()
    }

    /// Re-derives the page count from whatever is currently on the canvas.
    ///
    /// `drawingBounds` defaults to the live canvas. Only the persisted-drawing
    /// observer supplies its own, because it can fire while the canvas is still nil.
    private func refreshPageCount(drawingBounds: CGRect? = nil) {
        pageState.updateContent(
            drawingBounds: drawingBounds
                ?? activeCanvasReference.canvasView?.drawing.bounds
                ?? .null,
            elements: model.canvasElements.elements,
            minimumFilledPages: model.note?.pages.count ?? 0
        )
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
