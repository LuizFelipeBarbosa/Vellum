import SwiftUI
import UIKit
import VellumCore

struct CanvasElementsBandLayer: View {
    let store: CanvasElementsStore
    let selectionController: CanvasSelectionController
    let placement: LayerPlacement
    var textDefaults: TextConfig? = nil
    var isTextToolActive = false

    @Environment(\.inkDisplayStyle) private var inkDisplayStyle
    @FocusState private var focusedElementID: UUID?

    private var shapeCount: Int {
        store.elements.reduce(into: 0) { count, element in
            if case .shape = element.content {
                count += 1
            }
        }
    }

    var body: some View {
        if placement == .belowInk {
            bandContent
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("vellum-shape-element-count")
                .accessibilityValue("\(shapeCount)")
        } else {
            bandContent
                .allowsHitTesting(isTextToolActive)
        }
    }

    private var bandContent: some View {
        ZStack(alignment: .topLeading) {
            if placement == .aboveInk, isTextToolActive, let textDefaults {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        // content-space: no conversion needed, see spec
                        let element = CanvasElement(
                            content: .text(
                                TextBoxContent(
                                    text: "",
                                    fontSize: textDefaults.fontSize,
                                    color: textDefaults.color
                                )
                            ),
                            frame: CanvasRect(
                                x: Double(location.x),
                                y: Double(location.y),
                                width: 220,
                                height: 44
                            )
                        )
                        store.addElement(element)
                        focusedElementID = element.id
                    }
                    .accessibilityLabel("Add text box")
            }

            ForEach(store.elements) { element in
                switch element.content {
                case .image(let content):
                    if element.effectivePlacement == placement {
                        image(for: content)
                            .frame(
                                width: CGFloat(element.frame.width),
                                height: CGFloat(element.frame.height)
                            )
                            .scaleEffect(
                                x: content.flippedHorizontally ? -1 : 1,
                                y: content.flippedVertically ? -1 : 1
                            )
                            .rotationEffect(.radians(element.rotation))
                            .position(
                                x: CGFloat(element.frame.x + element.frame.width / 2),
                                y: CGFloat(element.frame.y + element.frame.height / 2)
                            )
                            .transformEffect(
                                selectionController.liveTransform(forElementWith: element.id)
                            )
                            .allowsHitTesting(false)
                    }
                case .shape(let content):
                    if element.effectivePlacement == placement {
                        Path(
                            ShapeGeometry.path(
                                for: content,
                                in: element.frame,
                                rotation: element.rotation
                            )
                        )
                        .stroke(
                            Color(
                                InkAppearance.displayColor(
                                    for: content.strokeColor,
                                    style: inkDisplayStyle
                                )
                            ),
                            style: StrokeStyle(
                                lineWidth: CGFloat(content.strokeWidth),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .transformEffect(
                            selectionController.liveTransform(forElementWith: element.id)
                        )
                        .allowsHitTesting(false)
                    }
                case .text:
                    let belongsInBand = placement == .aboveInk
                        ? element.effectivePlacement == .aboveInk || isTextToolActive
                        : element.effectivePlacement == .belowInk && !isTextToolActive
                    if belongsInBand {
                        TextBoxElementView(
                            element: element,
                            store: store,
                            isActive: isTextToolActive,
                            focusedID: $focusedElementID
                        )
                    }
                case .unknown:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func image(for content: ImageContent) -> some View {
        if let image = store.imageCache[content.assetPath] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(VellumTheme.ink(0.06))
        }
    }
}

private struct TextBoxElementView: View {
    let element: CanvasElement
    let store: CanvasElementsStore
    let isActive: Bool
    var focusedID: FocusState<UUID?>.Binding

    @Environment(\.inkDisplayStyle) private var inkDisplayStyle
    @State private var text: String
    @State private var dragOffset: CGSize = .zero
    @State private var renderedHeight: CGFloat
    @State private var hasMeasuredRenderedHeight = false

    init(
        element: CanvasElement,
        store: CanvasElementsStore,
        isActive: Bool,
        focusedID: FocusState<UUID?>.Binding
    ) {
        self.element = element
        self.store = store
        self.isActive = isActive
        self.focusedID = focusedID

        if case .text(let content) = element.content {
            _text = State(initialValue: content.text)
        } else {
            _text = State(initialValue: "")
        }
        _renderedHeight = State(initialValue: CGFloat(element.frame.height))
    }

    @ViewBuilder
    var body: some View {
        if case .text(let content) = element.content {
            TextField("", text: $text, axis: .vertical)
                .font(.vellumNewsreader(CGFloat(content.fontSize)))
                .foregroundStyle(
                    Color(
                        InkAppearance.displayColor(
                            for: content.color,
                            style: inkDisplayStyle
                        )
                    )
                )
                .focused(focusedID, equals: element.id)
                .padding(6)
                .frame(width: CGFloat(element.frame.width), alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    renderedHeight = newHeight
                    hasMeasuredRenderedHeight = true
                }
                .background(Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(VellumTheme.ink(0.15), lineWidth: 1)
                        .opacity(isActive ? 1 : 0)
                }
                .position(
                    x: CGFloat(element.frame.x + element.frame.width / 2) + dragOffset.width,
                    y: CGFloat(element.frame.y)
                        + max(renderedHeight, CGFloat(element.frame.height)) / 2
                        + dragOffset.height
                )
                .rotationEffect(.radians(element.rotation))
                .disabled(!isActive)
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard isActive else { return }
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            guard isActive else { return }
                            var moved = element
                            moved.frame.x += Double(value.translation.width)
                            moved.frame.y += Double(value.translation.height)
                            dragOffset = .zero
                            store.performTransaction("Move Text") {
                                store.updateElement(moved)
                            }
                        }
                )
                .onChange(of: focusedID.wrappedValue) { oldValue, newValue in
                    if oldValue != element.id, newValue == element.id {
                        store.beginTextEditingSession(for: element.id)
                    }
                    if oldValue == element.id, newValue != element.id {
                        store.finishTextEditingSession(matching: element.id)
                    }
                }
                .onChange(of: text) { _, newValue in
                    updateLiveText(newValue, content: content)
                }
                .onChange(of: element.frame.height) { _, newHeight in
                    // Before the first geometry pass, keep the fallback current. Once measured,
                    // the intrinsic height remains valid because persisted height does not size
                    // this view; position combines both values above.
                    guard !hasMeasuredRenderedHeight else { return }
                    renderedHeight = CGFloat(newHeight)
                }
                .onChange(of: content.text) { _, newValue in
                    // Undo/redo can replace the model text under the same element
                    // identity; adopt it unless the user is actively editing.
                    guard focusedID.wrappedValue != element.id, text != newValue else { return }
                    text = newValue
                }
                .onSubmit {
                    store.finishTextEditingSession(matching: element.id)
                }
                .accessibilityLabel("Text box")
        }
    }

    private func updateLiveText(_ newValue: String, content: TextBoxContent) {
        var updated = element
        updated.content = .text(
            TextBoxContent(
                text: newValue,
                fontSize: content.fontSize,
                color: content.color
            )
        )
        store.updateElementLive(updated)
    }
}
