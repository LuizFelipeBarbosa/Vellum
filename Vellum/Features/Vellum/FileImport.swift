import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SecurityScopedFile {
    /// Reads a `.fileImporter` result inside its security scope, reporting any failure — the
    /// picker's own or the read's — through `onFailure` and returning `nil`.
    static func read(
        _ result: Result<URL, Error>,
        onFailure: (String) -> Void
    ) -> (url: URL, data: Data)? {
        switch result {
        case .success(let url):
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                return (url, try Data(contentsOf: url))
            } catch {
                onFailure(error.localizedDescription)
                return nil
            }
        case .failure(let error):
            onFailure(error.localizedDescription)
            return nil
        }
    }
}

extension View {
    /// Presents a PDF picker that imports the chosen file as a new note and opens it.
    func pdfImporter(isPresented: Binding<Bool>, model: VellumAppModel) -> some View {
        modifier(PDFImportModifier(isPresented: isPresented, model: model))
    }
}

fileprivate struct PDFImportModifier: ViewModifier {
    @Binding var isPresented: Bool
    let model: VellumAppModel

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.pdf]
        ) { result in
            guard let file = SecurityScopedFile.read(result, onFailure: {
                model.library.errorMessage = $0
            }) else { return }

            let suggestedTitle = file.url.deletingPathExtension().lastPathComponent
            Task {
                guard let noteID = await model.library.createNoteFromPDF(
                    data: file.data,
                    suggestedTitle: suggestedTitle
                ) else { return }
                await model.refreshStats()
                await model.openNote(noteID)
            }
        }
    }
}
