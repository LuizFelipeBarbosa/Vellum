import Foundation

public enum NoteType: String, Codable, Sendable, CaseIterable {
    case note
    case pdf
    case deck
    case image
    case audio
}

public struct Note: Identifiable, Codable, Sendable {
    public static let currentSchemaVersion = 6
    public static let currentLayoutVersion = 2

    public let id: UUID
    public var schemaVersion: Int
    public var revision: Int
    public var layoutVersion: Int
    public var title: String
    public var tags: [String]
    public let createdAt: Date
    public var updatedAt: Date
    /// Page metadata indexed by visual band: `pages[i]` describes band `i`. Any
    /// mutation of this array rewrites `order` to `0..<pages.count`. The continuous
    /// drawing, elements, and plain text are always referenced from `pages[0]`.
    /// Bands beyond `pages.count` are virtual, not-yet-materialized notebook pages.
    public var pages: [NotePage]
    public var noteType: NoteType
    public var spaceID: UUID?
    public var links: [NoteLink]
    public var backgroundStyle: PageBackgroundStyle
    public var pageAspectRatio: Double = PageLayout.a4AspectRatio
    public var pageOrientation: PageOrientation = .portrait
    public var deletedAt: Date?

    public var isTrashed: Bool { deletedAt != nil }
    public var pageGeometry: PageGeometry {
        PageGeometry(
            portraitAspectRatio: pageAspectRatio,
            orientation: pageOrientation
        )
    }

    public init(
        id: UUID,
        schemaVersion: Int,
        revision: Int,
        layoutVersion: Int = Note.currentLayoutVersion,
        title: String,
        tags: [String],
        createdAt: Date,
        updatedAt: Date,
        pages: [NotePage],
        noteType: NoteType = .note,
        spaceID: UUID? = nil,
        links: [NoteLink] = [],
        backgroundStyle: PageBackgroundStyle = .legacyDefault,
        pageAspectRatio: Double = PageLayout.a4AspectRatio,
        pageOrientation: PageOrientation = .portrait,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.layoutVersion = layoutVersion
        self.title = title
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pages = pages
        self.noteType = noteType
        self.spaceID = spaceID
        self.links = links
        self.backgroundStyle = backgroundStyle
        self.pageAspectRatio = PageGeometry.clampedAspectRatio(pageAspectRatio)
        self.pageOrientation = pageOrientation
        self.deletedAt = deletedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decode(Int.self, forKey: .revision)
        layoutVersion = try container.decodeIfPresent(Int.self, forKey: .layoutVersion) ?? 1
        title = try container.decode(String.self, forKey: .title)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pages = try container.decode([NotePage].self, forKey: .pages)
        noteType = try container.decodeIfPresent(NoteType.self, forKey: .noteType) ?? .note
        spaceID = try container.decodeIfPresent(UUID.self, forKey: .spaceID)
        links = try container.decodeIfPresent([NoteLink].self, forKey: .links) ?? []
        backgroundStyle = try container.decodeIfPresent(
            PageBackgroundStyle.self,
            forKey: .backgroundStyle
        ) ?? .legacyDefault
        pageAspectRatio = PageGeometry.clampedAspectRatio(
            try container.decodeIfPresent(
                Double.self,
                forKey: .pageAspectRatio
            ) ?? PageLayout.a4AspectRatio
        )
        pageOrientation = (try container.decodeIfPresent(
            String.self,
            forKey: .pageOrientation
        )).flatMap(PageOrientation.init(rawValue:)) ?? .portrait
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

extension Note {
    /// nil when the page renders its own content (background == .pdf or .image); else the notebook style.
    public func resolvedBackgroundStyle(forPageAt index: Int) -> PageBackgroundStyle? {
        guard index >= 0 else { return nil }
        guard pages.indices.contains(index) else { return backgroundStyle }

        switch pages[index].background {
        case .pdf, .image:
            return nil
        case .blank, .ruled, .grid:
            return backgroundStyle
        }
    }
}

public struct PDFPageReference: Codable, Sendable, Equatable {
    public var assetPath: String
    public var pageIndex: Int

    public init(assetPath: String, pageIndex: Int) {
        self.assetPath = assetPath
        self.pageIndex = pageIndex
    }
}

public struct NotePage: Identifiable, Codable, Sendable {
    public let id: UUID
    public var order: Int
    public var plainText: String
    public var drawingAssetPath: String
    public var background: PageBackground
    /// The source PDF page when `background == .pdf`; otherwise nil.
    public var pdfPage: PDFPageReference?
    /// Rendering composites elements whose effective placement is below ink in array order,
    /// then the page's ink drawing, then elements above ink in array order. Array order is
    /// significant across element kinds within each placement. A missing placement uses the
    /// kind default: text above ink and image, shape, or unknown content below ink. If no
    /// element has an explicit placement, readers must apply `zOrderNormalized()` before
    /// painting to preserve the legacy stable band order. Writers that reorder elements must
    /// materialize a placement on every element so that legacy normalization cannot recur.
    public var elements: [CanvasElement]

    public init(
        id: UUID,
        order: Int,
        plainText: String,
        drawingAssetPath: String,
        background: PageBackground,
        pdfPage: PDFPageReference? = nil,
        elements: [CanvasElement] = []
    ) {
        self.id = id
        self.order = order
        self.plainText = plainText
        self.drawingAssetPath = drawingAssetPath
        self.background = background
        self.pdfPage = pdfPage
        self.elements = elements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        plainText = try container.decode(String.self, forKey: .plainText)
        drawingAssetPath = try container.decode(String.self, forKey: .drawingAssetPath)
        background = try container.decode(PageBackground.self, forKey: .background)
        pdfPage = try container.decodeIfPresent(PDFPageReference.self, forKey: .pdfPage)
        elements = try container.decodeIfPresent([CanvasElement].self, forKey: .elements) ?? []
    }
}

public enum PageBackground: String, Codable, Sendable {
    case blank
    case ruled
    case grid
    case pdf
    case image
}
