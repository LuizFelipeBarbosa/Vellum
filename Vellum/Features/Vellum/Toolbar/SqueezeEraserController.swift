/// Transient "hold to erase" state machine for Apple Pencil Pro squeeze.
/// Pass the current selected tool into each transition; a non-nil return
/// is the tool the caller should switch to.
struct SqueezeEraserController: Sendable {
    private var savedTool: ToolID?

    mutating func begin(current: ToolID) -> ToolID? {
        guard current != .eraser else { return nil }
        if savedTool == nil { savedTool = current }
        return .eraser
    }

    // Tapping the eraser toolbar button while squeezing still restores the prior tool.
    mutating func end(current: ToolID) -> ToolID? {
        defer { savedTool = nil }
        guard let savedTool, current == .eraser else { return nil }
        return savedTool
    }
}
