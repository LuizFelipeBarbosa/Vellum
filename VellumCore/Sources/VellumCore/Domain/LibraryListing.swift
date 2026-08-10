public struct LibraryListing: Sendable {
    public let summaries: [NoteSummary]
    public let spaces: [SpaceListing]
    public let unsupported: [UnsupportedNotePackage]

    public init(
        summaries: [NoteSummary],
        spaces: [SpaceListing],
        unsupported: [UnsupportedNotePackage]
    ) {
        self.summaries = summaries
        self.spaces = spaces
        self.unsupported = unsupported
    }
}

public struct ActivityOverview: Sendable {
    public let latestMessage: String?
    public let digest: ActivityDigest

    public init(latestMessage: String?, digest: ActivityDigest) {
        self.latestMessage = latestMessage
        self.digest = digest
    }
}
