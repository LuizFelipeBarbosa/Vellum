import SwiftUI
import VellumCore

struct ImageElementsLayer: View {
    let store: CanvasElementsStore
    let viewport: CanvasViewport

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(store.elements) { element in
                if case .image(let content) = element.content {
                    image(for: content)
                        .frame(
                            width: CGFloat(element.frame.width),
                            height: CGFloat(element.frame.height)
                        )
                        .position(
                            x: CGFloat(element.frame.x + element.frame.width / 2),
                            y: CGFloat(element.frame.y + element.frame.height / 2)
                        )
                        .rotationEffect(.radians(element.rotation))
                }
            }
        }
        .allowsHitTesting(false)
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

struct TextElementsLayer: View {
    let store: CanvasElementsStore
    let textDefaults: TextConfig
    let viewport: CanvasViewport
    let isActive: Bool

    @FocusState private var focusedElementID: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isActive {
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
                if case .text = element.content {
                    TextBoxElementView(
                        element: element,
                        store: store,
                        isActive: isActive,
                        focusedID: $focusedElementID
                    )
                }
            }
        }
        .allowsHitTesting(isActive)
    }
}

private struct TextBoxElementView: View {
    let element: CanvasElement
    let store: CanvasElementsStore
    let isActive: Bool
    var focusedID: FocusState<UUID?>.Binding

    @State private var text: String
    @State private var dragOffset: CGSize = .zero
    @State private var sessionBaseline: [CanvasElement]?

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
    }

    @ViewBuilder
    var body: some View {
        if case .text(let content) = element.content {
            TextField("", text: $text, axis: .vertical)
                .font(.vellumNewsreader(CGFloat(content.fontSize)))
                .foregroundStyle(content.color.swiftUIColor)
                .focused(focusedID, equals: element.id)
                .padding(6)
                .frame(width: CGFloat(element.frame.width), alignment: .topLeading)
                .background(Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(VellumTheme.ink(0.15), lineWidth: 1)
                        .opacity(isActive ? 1 : 0)
                }
                .position(
                    x: CGFloat(element.frame.x + element.frame.width / 2) + dragOffset.width,
                    y: CGFloat(element.frame.y + element.frame.height / 2) + dragOffset.height
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
                        sessionBaseline = store.elements
                    }
                    if oldValue == element.id, newValue != element.id {
                        finishEditingSession(content: content)
                    }
                }
                .onChange(of: text) { _, newValue in
                    updateLiveText(newValue, content: content)
                }
                .onChange(of: content.text) { _, newValue in
                    // Undo/redo can replace the model text under the same element
                    // identity; adopt it unless the user is actively editing.
                    guard focusedID.wrappedValue != element.id, text != newValue else { return }
                    text = newValue
                }
                .onSubmit {
                    finishEditingSession(content: content)
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

    private func finishEditingSession(content: TextBoxContent) {
        defer { sessionBaseline = nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if let sessionBaseline {
                store.removeElementLive(id: element.id)
                store.registerEditingSessionUndo(from: sessionBaseline, label: "Remove Text Box")
            } else {
                store.removeElement(id: element.id)
            }
            return
        }

        if trimmed != text {
            updateLiveText(trimmed, content: content)
        }
        if let sessionBaseline {
            store.registerEditingSessionUndo(
                from: sessionBaseline,
                label: "Edit Text"
            )
        }
    }
}
