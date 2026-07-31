public enum PageOrientation: String, Codable, Sendable, CaseIterable {
    case portrait
    case landscape

    public var flipped: PageOrientation {
        self == .portrait ? .landscape : .portrait
    }
}
