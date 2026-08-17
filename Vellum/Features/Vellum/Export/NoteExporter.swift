import UIKit
import VellumCore

enum NoteExportError: LocalizedError {
    case missingImageAssets([String])
    case missingPDFPages([Int])

    var errorDescription: String? {
        switch self {
        case .missingImageAssets(let paths):
            let imageLabel = paths.count == 1 ? "image" : "images"
            let missingPaths = paths.joined(separator: ", ")
            return "Export failed: \(paths.count) \(imageLabel) could not be loaded "
                + "(missing: \(missingPaths))."
        case .missingPDFPages(let bands):
            let pageLabel = bands.count == 1 ? "PDF page" : "PDF pages"
            let missingLabel = bands.count == 1 ? "page" : "pages"
            let pageNumbers = bands.map { String($0 + 1) }.joined(separator: ", ")
            return "Export failed: \(bands.count) \(pageLabel) could not be loaded "
                + "(missing \(missingLabel): \(pageNumbers))."
        }
    }
}

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

    struct Output: Identifiable, Sendable {
        let id = UUID()
        let urls: [URL]
        let directory: URL
    }

    private static let renderer = NoteExportRenderer()

    /// Renders the export page count (an empty note produces one blank page) and
    /// writes the files into a fresh temporary directory.
    static func export(
        content: NotePageRenderer.Content,
        title: String,
        format: Format,
        minimumFilledPages: Int = 0
    ) async throws -> Output {
        let pageCount = exportPageCount(
            for: content,
            minimumFilledPages: minimumFilledPages
        )
        let missingPDFBands = content.pdfExpectedBands
            .filter { (0..<pageCount).contains($0) && content.pdfBandRefs[$0] == nil }
            .sorted()
        if !missingPDFBands.isEmpty {
            throw NoteExportError.missingPDFPages(missingPDFBands)
        }

        var missingAssetPaths: [String] = []
        var seenMissingAssetPaths = Set<String>()
        for element in content.elements {
            guard case .image(let imageContent) = element.content else { continue }
            let isInExportedRange = (0..<pageCount).contains { pageIndex in
                element.drawnBoundingBox.intersects(
                    content.geometry.pageRect(index: pageIndex)
                )
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
            let urls = try await write(
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

    private static func exportPageCount(
        for content: NotePageRenderer.Content,
        minimumFilledPages: Int
    ) -> Int {
        let drawingBounds = content.drawing.bounds
        let drawingBottom =
            (drawingBounds.isNull || drawingBounds.isEmpty) ? 0 : drawingBounds.maxY
        // drawnBoundingBox, not effectiveBoundingBox: a shape whose stroke is the only
        // content reaching the next page still needs that page to be exported.
        let elementsBottom = content.elements
            .map { $0.drawnBoundingBox.maxY }
            .max() ?? 0
        return content.geometry.exportPageCount(
            forContentBottom: max(drawingBottom, elementsBottom),
            minimumFilledPages: minimumFilledPages
        )
    }

    private static func write(
        content: NotePageRenderer.Content,
        title: String,
        format: Format,
        pageCount: Int,
        to directory: URL
    ) async throws -> [URL] {
        switch format {
        case .pdf:
            let url = directory.appendingPathComponent("\(title).pdf")
            let pdfPageSize = content.geometry.pdfPageSize
            var prefetchedBands: [Int: ResolvedPdfBand] = [:]
            for pageIndex in 0..<pageCount {
                guard let pdfBandRef = content.pdfBandRefs[pageIndex] else { continue }
                guard let data = await content.pdfSource?.vectorPageData(
                    assetPath: pdfBandRef.assetPath,
                    pageIndex: pdfBandRef.pageIndex
                ) else {
                    throw NoteExportError.missingPDFPages([pageIndex])
                }
                prefetchedBands[pageIndex] = .vector(data)
            }
            let result = try await renderer.renderPDF(
                PDFExportRenderRequest(
                    content: content,
                    prefetchedBands: prefetchedBands,
                    pageCount: pageCount,
                    url: url,
                    pageSize: pdfPageSize
                )
            )
            return result.urls

        case .png, .jpeg:
            var prefetchedBands: [Int: ResolvedPdfBand] = [:]
            for pageIndex in 0..<pageCount {
                guard let pdfBandRef = content.pdfBandRefs[pageIndex] else { continue }
                let targetPixelSize = CGSize(
                    width: pdfBandRef.displayedSize.width * 2,
                    height: pdfBandRef.displayedSize.height * 2
                )
                guard let raster = await content.pdfSource?.raster(
                    assetPath: pdfBandRef.assetPath,
                    pageIndex: pdfBandRef.pageIndex,
                    targetPixelSize: targetPixelSize,
                    invertsColors: content.pdfInterfaceStyle == .dark
                ) else {
                    throw NoteExportError.missingPDFPages([pageIndex])
                }
                prefetchedBands[pageIndex] = .raster(raster)
            }

            let result = try await renderer.renderRasterPages(
                RasterExportRenderRequest(
                    content: content,
                    prefetchedBands: prefetchedBands,
                    pageCount: pageCount,
                    directory: directory,
                    title: title,
                    format: format
                )
            )
            return result.urls
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

/// Immutable render snapshot handed to the private serial export actor.
private struct PDFExportRenderRequest: @unchecked Sendable {
    let content: NotePageRenderer.Content
    let prefetchedBands: [Int: ResolvedPdfBand]
    let pageCount: Int
    let url: URL
    let pageSize: CGSize
}

/// Immutable render snapshot handed to the private serial export actor.
private struct RasterExportRenderRequest: @unchecked Sendable {
    let content: NotePageRenderer.Content
    let prefetchedBands: [Int: ResolvedPdfBand]
    let pageCount: Int
    let directory: URL
    let title: String
    let format: NoteExporter.Format
}

/// Immutable render result handed back from the private serial export actor.
private struct NoteExportRenderResult: @unchecked Sendable {
    let urls: [URL]
}

private actor NoteExportRenderer {
    func renderPDF(_ request: PDFExportRenderRequest) throws -> NoteExportRenderResult {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: request.pageSize)
        )
        try renderer.writePDF(to: request.url) { context in
            for pageIndex in 0..<request.pageCount {
                context.beginPage()
                let scale = request.pageSize.width / request.content.geometry.contentWidth
                context.cgContext.saveGState()
                context.cgContext.scaleBy(x: scale, y: scale)
                NotePageRenderer.draw(
                    pageIndex: pageIndex,
                    content: request.content,
                    resolvedPdf: request.prefetchedBands[pageIndex],
                    in: context.cgContext
                )
                context.cgContext.restoreGState()
            }
        }
        return NoteExportRenderResult(urls: [request.url])
    }

    func renderRasterPages(
        _ request: RasterExportRenderRequest
    ) async throws -> NoteExportRenderResult {
        var urls: [URL] = []
        for pageIndex in 0..<request.pageCount {
            let image = await NotePageRenderer.image(
                pageIndex: pageIndex,
                content: request.content,
                resolvedPdf: request.prefetchedBands[pageIndex],
                pointSize: CGSize(
                    width: request.content.geometry.contentWidth,
                    height: request.content.geometry.pageHeight
                ),
                scale: 2
            )
            let data: Data?
            switch request.format {
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

            let url = request.directory.appendingPathComponent(
                "\(request.title) – Page \(pageIndex + 1).\(request.format.rawValue)"
            )
            try data.write(to: url, options: .atomic)
            urls.append(url)
        }
        return NoteExportRenderResult(urls: urls)
    }
}
