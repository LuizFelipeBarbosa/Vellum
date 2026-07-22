import PencilKit
import UIKit
import VellumCore

enum NoteExportError: LocalizedError {
    case missingImageAssets([String])

    var errorDescription: String? {
        switch self {
        case .missingImageAssets(let paths):
            let imageLabel = paths.count == 1 ? "image" : "images"
            let missingPaths = paths.joined(separator: ", ")
            return "Export failed: \(paths.count) \(imageLabel) could not be loaded "
                + "(missing: \(missingPaths))."
        }
    }
}

@MainActor
enum NoteExporter {
    enum Format: String, CaseIterable {
        case pdf
        case png
        case jpeg

        var displayName: String {
            switch self {
            case .pdf: "PDF"
            case .png: "PNG"
            case .jpeg: "JPEG"
            }
        }
    }

    struct Output: Identifiable {
        let id = UUID()
        let urls: [URL]
        let directory: URL
    }

    /// Renders the export page count (an empty note produces one blank page) and
    /// writes the files into a fresh temporary directory.
    static func export(
        content: NotePageRenderer.Content,
        title: String,
        format: Format
    ) throws -> Output {
        let pageCount = exportPageCount(for: content)
        var missingAssetPaths: [String] = []
        var seenMissingAssetPaths = Set<String>()
        for element in content.elements {
            guard case .image(let imageContent) = element.content else { continue }
            let isInExportedRange = (0..<pageCount).contains { pageIndex in
                element.rotatedBoundingBox.intersects(PageLayout.pageRect(index: pageIndex))
            }
            guard isInExportedRange,
                  content.imagesByAssetPath[imageContent.assetPath] == nil,
                  seenMissingAssetPaths.insert(imageContent.assetPath).inserted else {
                continue
            }
            missingAssetPaths.append(imageContent.assetPath)
        }
        if !missingAssetPaths.isEmpty {
            throw NoteExportError.missingImageAssets(missingAssetPaths)
        }

        var renderContent = content
        renderContent.pageCount = pageCount

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VellumExport-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let urls = try write(
                content: renderContent,
                title: sanitizedTitle(title),
                format: format,
                pageCount: pageCount,
                to: directory
            )
            return Output(urls: urls, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func exportPageCount(for content: NotePageRenderer.Content) -> Int {
        let drawingBounds = content.drawing.bounds
        let drawingBottom =
            (drawingBounds.isNull || drawingBounds.isEmpty) ? 0 : drawingBounds.maxY
        let elementsBottom = content.elements
            .map { $0.effectiveBoundingBox.maxY }
            .max() ?? 0
        return PageLayout.exportPageCount(
            forContentBottom: max(drawingBottom, elementsBottom)
        )
    }

    private static func write(
        content: NotePageRenderer.Content,
        title: String,
        format: Format,
        pageCount: Int,
        to directory: URL
    ) throws -> [URL] {
        switch format {
        case .pdf:
            let url = directory.appendingPathComponent("\(title).pdf")
            let renderer = UIGraphicsPDFRenderer(
                bounds: CGRect(origin: .zero, size: PageLayout.pdfPageSize)
            )
            try renderer.writePDF(to: url) { context in
                for pageIndex in 0..<pageCount {
                    context.beginPage()
                    let scale = PageLayout.pdfPageSize.width / PageLayout.contentWidth
                    context.cgContext.saveGState()
                    context.cgContext.scaleBy(x: scale, y: scale)
                    NotePageRenderer.draw(
                        pageIndex: pageIndex,
                        content: content,
                        in: context.cgContext
                    )
                    context.cgContext.restoreGState()
                }
            }
            return [url]

        case .png, .jpeg:
            var urls: [URL] = []
            for pageIndex in 0..<pageCount {
                let image = NotePageRenderer.image(
                    pageIndex: pageIndex,
                    content: content,
                    pointSize: CGSize(
                        width: PageLayout.contentWidth,
                        height: PageLayout.pageHeight
                    ),
                    scale: 2
                )
                let data: Data?
                switch format {
                case .png:
                    data = image.pngData()
                case .jpeg:
                    data = image.jpegData(compressionQuality: 0.9)
                case .pdf:
                    data = nil
                }
                guard let data else {
                    throw CocoaError(.fileWriteUnknown)
                }

                let url = directory.appendingPathComponent(
                    "\(title) – Page \(pageIndex + 1).\(format.rawValue)"
                )
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            return urls
        }
    }

    private static func sanitizedTitle(_ title: String) -> String {
        let sanitized = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Untitled" : sanitized
    }
}
