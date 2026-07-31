import SwiftUI
import UIKit
import VellumCore

private struct ThumbnailRequestID: Hashable {
    let pageIndex: Int
    let generation: Int
}

private enum ThumbnailScrollTarget: Hashable, Sendable {
    case page(UUID)
    case virtual(Int)
}

private struct ThumbnailScrollMetrics: Equatable {
    var contentOffsetY: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var contentHeight: CGFloat = 0
}

private struct ThumbnailDragState {
    let dragID: UUID
    var draggedIndex: Int
    var grabOffsetY: CGFloat
    var fingerPanelY: CGFloat
    var proposedIndex: Int
    var isLifted: Bool
}

struct ReorderableThumbnailList: View {
    let store: PageThumbnailStore
    let pages: [NotePage]
    let pageCount: Int
    let currentPageIndex: Int
    let geometry: PageGeometry
    let contentProvider: () -> NotePageRenderer.Content
    let onSelect: (Int) -> Void
    let onMovePages: (IndexSet, Int) -> Void
    let onDeletePage: (Int) -> Void

    @State private var scrollPosition = ScrollPosition(
        idType: ThumbnailScrollTarget.self
    )
    @State private var scrollMetrics = ThumbnailScrollMetrics()
    @State private var rowHeight: CGFloat = 0
    @State private var dragState: ThumbnailDragState?
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var hasAppliedInitialScroll = false
    @State private var reorderHaptics = ReorderHaptics()

    private let edgeScrollZone: CGFloat = 60
    private let maximumScrollPerTick: CGFloat = 12

    private var estimatedRowHeight: CGFloat {
        ThumbnailLayout.width * CGFloat(geometry.aspectRatio) + 33
    }

    private var effectiveRowHeight: CGFloat {
        rowHeight > 0 ? rowHeight : estimatedRowHeight
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    row(pageIndex: index, isRealPage: true)
                        .id(ThumbnailScrollTarget.page(page.id))
                        .offset(y: displacement(for: index))
                        .opacity(dragState?.draggedIndex == index ? 0 : 1)
                }

                if pageCount > pages.count {
                    row(pageIndex: pages.count, isRealPage: false)
                        .id(ThumbnailScrollTarget.virtual(pages.count))
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .coordinateSpace(name: "panel")
        .onScrollGeometryChange(
            for: ThumbnailScrollMetrics.self,
            of: {
                ThumbnailScrollMetrics(
                    contentOffsetY: $0.contentOffset.y,
                    viewportHeight: $0.containerSize.height,
                    contentHeight: $0.contentSize.height
                )
            },
            action: { _, metrics in
                scrollMetrics = metrics
                updateProposedIndex()
            }
        )
        .gesture(
            ReorderLongPressGesture(
                shouldBeginDrag: { contentPoint in
                    let shouldBegin = ThumbnailDragMath.dragStartIndex(
                        fingerContentX: contentPoint.x,
                        fingerContentY: contentPoint.y,
                        rowWidth: ThumbnailLayout.width,
                        rowHeight: effectiveRowHeight,
                        badgeZone: ThumbnailLayout.badgeZone,
                        pageCount: pages.count
                    ) != nil
                    if shouldBegin {
                        reorderHaptics.prepare()
                    }
                    return shouldBegin
                },
                onLift: beginDrag,
                onMove: moveDrag,
                onEnd: endDrag,
                onCancel: cancelDrag
            )
        )
        .overlay(alignment: .topLeading) {
            floatingRow
        }
        .onAppear {
            guard !hasAppliedInitialScroll else { return }
            hasAppliedInitialScroll = true
            scrollPosition.scrollTo(id: initialScrollTarget, anchor: .center)
        }
        .onChange(of: pages.count) { _, _ in
            guard dragState != nil else { return }
            cancelDrag()
        }
        .onDisappear {
            stopAutoScroll()
            dragState = nil
        }
    }

    private var initialScrollTarget: ThumbnailScrollTarget {
        if pages.indices.contains(currentPageIndex) {
            return .page(pages[currentPageIndex].id)
        }
        return .virtual(currentPageIndex)
    }

    @ViewBuilder
    private var floatingRow: some View {
        if let dragState,
           pages.indices.contains(dragState.draggedIndex) {
            ThumbnailRowView(
                store: store,
                pageIndex: dragState.draggedIndex,
                currentPageIndex: currentPageIndex,
                geometry: geometry,
                contentProvider: contentProvider,
                isRealPage: true,
                canDelete: pages.count > 1,
                onSelect: onSelect,
                onDelete: onDeletePage
            )
            .frame(height: effectiveRowHeight, alignment: .top)
            .offset(
                y: dragState.fingerPanelY - dragState.grabOffsetY
            )
            .scaleEffect(dragState.isLifted ? 1.05 : 1)
            .shadow(
                color: VellumTheme.ink(dragState.isLifted ? 0.2 : 0),
                radius: dragState.isLifted ? 10 : 0,
                y: dragState.isLifted ? 6 : 0
            )
            .animation(
                .spring(response: 0.25, dampingFraction: 0.7),
                value: dragState.isLifted
            )
            .allowsHitTesting(false)
        }
    }

    private func row(pageIndex: Int, isRealPage: Bool) -> some View {
        ThumbnailRowView(
            store: store,
            pageIndex: pageIndex,
            currentPageIndex: currentPageIndex,
            geometry: geometry,
            contentProvider: contentProvider,
            isRealPage: isRealPage,
            canDelete: isRealPage && pages.count > 1,
            onSelect: onSelect,
            onDelete: onDeletePage
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { measuredHeight in
            if rowHeight == 0, measuredHeight > 0 {
                rowHeight = measuredHeight
            }
        }
        .frame(height: effectiveRowHeight, alignment: .top)
    }

    private func displacement(for index: Int) -> CGFloat {
        guard let dragState else { return 0 }
        return ThumbnailDragMath.displacement(
            forRow: index,
            draggedIndex: dragState.draggedIndex,
            proposedIndex: dragState.proposedIndex,
            rowHeight: effectiveRowHeight
        )
    }

    private func beginDrag(_ fingerPanelY: CGFloat) {
        let height = effectiveRowHeight
        let fingerContentY = fingerPanelY + scrollMetrics.contentOffsetY
        guard let draggedIndex = ThumbnailDragMath.liftedIndex(
            fingerContentY: fingerContentY,
            rowHeight: height,
            pageCount: pages.count
        ) else {
            return
        }

        let dragID = UUID()
        dragState = ThumbnailDragState(
            dragID: dragID,
            draggedIndex: draggedIndex,
            grabOffsetY: ThumbnailDragMath.grabOffsetY(
                fingerPanelY: fingerPanelY,
                contentOffsetY: scrollMetrics.contentOffsetY,
                draggedIndex: draggedIndex,
                rowHeight: height
            ),
            fingerPanelY: fingerPanelY,
            proposedIndex: draggedIndex,
            isLifted: false
        )
        reorderHaptics.liftOccurred()

        Task { @MainActor in
            guard dragState?.dragID == dragID else { return }
            dragState?.isLifted = true
        }
        updateAutoScroll()
    }

    private func moveDrag(_ fingerPanelY: CGFloat) {
        guard dragState != nil else { return }

        dragState?.fingerPanelY = fingerPanelY
        updateProposedIndex()
        updateAutoScroll()
    }

    private func updateProposedIndex() {
        guard let dragState else { return }

        let proposedIndex = ThumbnailDragMath.proposedIndex(
            fingerPanelY: dragState.fingerPanelY,
            contentOffsetY: scrollMetrics.contentOffsetY,
            grabOffsetY: dragState.grabOffsetY,
            rowHeight: effectiveRowHeight,
            pageCount: pages.count
        )
        guard proposedIndex != dragState.proposedIndex else { return }
        reorderHaptics.selectionChanged()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            self.dragState?.proposedIndex = proposedIndex
        }
    }

    private func endDrag() {
        stopAutoScroll()
        guard let dragState else { return }
        guard dragState.proposedIndex != dragState.draggedIndex else {
            cancelDrag()
            return
        }

        let targetFingerPanelY = CGFloat(dragState.proposedIndex) * effectiveRowHeight
            - scrollMetrics.contentOffsetY
            + dragState.grabOffsetY
        let animation = Animation.spring(response: 0.3, dampingFraction: 0.75)

        withAnimation(animation, completionCriteria: .logicallyComplete) {
            self.dragState?.fingerPanelY = targetFingerPanelY
        } completion: {
            guard self.dragState?.dragID == dragState.dragID else {
                return
            }
            reorderHaptics.dropOccurred()
            onMovePages(
                IndexSet(integer: dragState.draggedIndex),
                ThumbnailDragMath.dropDestination(
                    draggedIndex: dragState.draggedIndex,
                    proposedIndex: dragState.proposedIndex
                )
            )
            self.dragState = nil
        }
    }

    private func cancelDrag() {
        stopAutoScroll()
        guard let dragState else { return }

        let originFingerPanelY = CGFloat(dragState.draggedIndex) * effectiveRowHeight
            - scrollMetrics.contentOffsetY
            + dragState.grabOffsetY
        let animation = Animation.spring(response: 0.3, dampingFraction: 0.75)

        withAnimation(animation, completionCriteria: .logicallyComplete) {
            self.dragState?.fingerPanelY = originFingerPanelY
        } completion: {
            guard self.dragState?.dragID == dragState.dragID else {
                return
            }
            self.dragState = nil
        }
    }

    private func updateAutoScroll() {
        let speed = autoScrollSpeed()
        let maximumOffset = max(scrollMetrics.contentHeight - scrollMetrics.viewportHeight, 0)
        let canScroll = (speed < 0 && scrollMetrics.contentOffsetY > 0)
            || (speed > 0 && scrollMetrics.contentOffsetY < maximumOffset)

        guard speed != 0, canScroll else {
            stopAutoScroll()
            return
        }
        guard autoScrollTask == nil else { return }

        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .nanoseconds(16_666_667))
                guard !Task.isCancelled else { return }
                autoScrollTick()
            }
        }
    }

    private func autoScrollTick() {
        guard dragState != nil else {
            stopAutoScroll()
            return
        }

        let speed = autoScrollSpeed()
        let maximumOffset = max(scrollMetrics.contentHeight - scrollMetrics.viewportHeight, 0)
        let newOffset = min(
            max(scrollMetrics.contentOffsetY + speed, 0),
            maximumOffset
        )
        guard speed != 0, newOffset != scrollMetrics.contentOffsetY else {
            stopAutoScroll()
            return
        }

        scrollPosition.scrollTo(y: newOffset)
        scrollMetrics.contentOffsetY = newOffset
        updateProposedIndex()
    }

    private func autoScrollSpeed() -> CGFloat {
        guard let fingerY = dragState?.fingerPanelY,
              scrollMetrics.viewportHeight > 0 else {
            return 0
        }

        if fingerY < edgeScrollZone {
            let edgeDistance = max(fingerY, 0)
            return -maximumScrollPerTick * (1 - edgeDistance / edgeScrollZone)
        }

        let bottomZoneStart = scrollMetrics.viewportHeight - edgeScrollZone
        if fingerY > bottomZoneStart {
            let edgeDistance = max(scrollMetrics.viewportHeight - fingerY, 0)
            return maximumScrollPerTick * (1 - edgeDistance / edgeScrollZone)
        }

        return 0
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }
}

private struct ThumbnailRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let store: PageThumbnailStore
    let pageIndex: Int
    let currentPageIndex: Int
    let geometry: PageGeometry
    let contentProvider: () -> NotePageRenderer.Content
    let isRealPage: Bool
    let canDelete: Bool
    let onSelect: (Int) -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        Button {
            onSelect(pageIndex)
        } label: {
            VStack(spacing: 6) {
                thumbnail

                Text("\(pageIndex + 1)")
                    .font(.vellumMono(10.5))
                    .foregroundStyle(
                        pageIndex == currentPageIndex
                            ? VellumTheme.accentDark
                            : VellumTheme.mutedCount
                    )
            }
            .frame(width: ThumbnailLayout.width)
        }
        .buttonStyle(.plain)
        .accessibilityValue(store.images[pageIndex] == nil ? "Loading" : "")
        .overlay(alignment: .topTrailing) {
            if isRealPage, canDelete {
                deleteBadge
            }
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .task(
            id: ThumbnailRequestID(
                pageIndex: pageIndex,
                generation: store.generation
            )
        ) {
            var content = contentProvider()
            content.interfaceStyle = colorScheme == .dark ? .dark : .light
            await store.requestImage(for: pageIndex, content: content)
        }
    }

    private var deleteBadge: some View {
        Button {
            onDelete(pageIndex)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(VellumTheme.mutedDark)
                .frame(width: 24, height: 24)
                .background(VellumTheme.popover, in: Circle())
                .overlay {
                    Circle().stroke(VellumTheme.ink(0.14), lineWidth: 1)
                }
                .shadow(color: VellumTheme.ink(0.1), radius: 3, y: 1)
                // Padding inside the label + rectangular content shape: a 44pt
                // hit target that intercepts near-misses instead of letting them
                // fall through to the page-select button underneath.
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete page \(pageIndex + 1)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let image = store.images[pageIndex] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(VellumTheme.paper)
                    ProgressView()
                }
            }
        }
        .frame(
            width: ThumbnailLayout.width,
            height: ThumbnailLayout.width * CGFloat(geometry.aspectRatio)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if pageIndex == currentPageIndex {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(VellumTheme.accent, lineWidth: 2)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(VellumTheme.ink(0.10), lineWidth: 1)
            }
        }
    }
}

struct ReorderLongPressGesture: UIGestureRecognizerRepresentable {
    let shouldBeginDrag: (CGPoint) -> Bool
    let onLift: (CGFloat) -> Void
    let onMove: (CGFloat) -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var shouldBeginDrag: ((CGPoint) -> Bool)?
        private weak var scrollView: UIScrollView?
        private weak var lockedScrollView: UIScrollView?
        private var wasScrollEnabled: Bool?

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // Gating happens before the recognizer owns the touch, so the
            // SwiftUI converter is unusable here. The backing scroll view
            // supplies content-space, interface-oriented coordinates that
            // remain correct when the iPad rotates.
            var probe = touch.view
            while let view = probe, !(view is UIScrollView) {
                probe = view.superview
            }
            guard let scrollView = probe as? UIScrollView else { return false }
            self.scrollView = scrollView
            return shouldBeginDrag?(touch.location(in: scrollView)) ?? false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // Row selection is a SwiftUI Button whose tap recognizer would
        // otherwise claim thumbnail touches outright; requiring it to wait
        // for the long press to fail is what makes hold-to-lift win while
        // quick taps still select. Scroll pans stay exempt and recognize
        // simultaneously, so ordinary scrolling starts immediately; the
        // scroll view is locked only after the long press lifts a row.
        // Invariant: every non-pan recognizer in this subtree waits out the
        // long press — if a new row interaction (context menu, pinch,
        // DragGesture) feels dead, check here first.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            !(other is UIPanGestureRecognizer)
        }

        func lockScrolling() {
            guard lockedScrollView == nil, let scrollView else { return }
            lockedScrollView = scrollView
            wasScrollEnabled = scrollView.isScrollEnabled
            scrollView.isScrollEnabled = false
        }

        func restoreScrolling() {
            if let wasScrollEnabled {
                lockedScrollView?.isScrollEnabled = wasScrollEnabled
            }
            lockedScrollView = nil
            wasScrollEnabled = nil
        }
    }

    func makeCoordinator(
        converter: CoordinateSpaceConverter
    ) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(
        context: Context
    ) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        context.coordinator.shouldBeginDrag = shouldBeginDrag
        recognizer.delegate = context.coordinator
        configure(recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        context.coordinator.shouldBeginDrag = shouldBeginDrag
        configure(recognizer)
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .began:
            context.coordinator.lockScrolling()
            onLift(convertedPanelY(for: recognizer, context: context))
        case .changed:
            onMove(convertedPanelY(for: recognizer, context: context))
        case .ended:
            context.coordinator.restoreScrolling()
            onEnd()
        case .cancelled, .failed:
            context.coordinator.restoreScrolling()
            onCancel()
        case .possible:
            break
        @unknown default:
            context.coordinator.restoreScrolling()
            onCancel()
        }
    }

    private func configure(_ recognizer: UILongPressGestureRecognizer) {
        recognizer.minimumPressDuration = 0.3
        recognizer.allowableMovement = 24
        recognizer.numberOfTouchesRequired = 1
        recognizer.cancelsTouchesInView = true
    }

    private func convertedPanelY(
        for recognizer: UILongPressGestureRecognizer,
        context: Context
    ) -> CGFloat {
        context.converter.location(in: .named("panel")).y
    }
}
