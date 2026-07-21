public struct UnsupportedNotePackage: Equatable, Sendable {
    public let packageName: String
    public let schemaVersion: Int

    public init(packageName: String, schemaVersion: Int) {
        self.packageName = packageName
        self.schemaVersion = schemaVersion
    }
}
