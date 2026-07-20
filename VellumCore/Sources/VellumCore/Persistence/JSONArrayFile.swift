import Foundation

struct JSONArrayFile<Element: Codable & Sendable & Identifiable> where Element.ID == UUID {
    let fileURL: URL

    func readAll() throws -> [Element] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try FilePersistence.decoder().decode(
                [Element].self,
                from: Data(contentsOf: fileURL)
            )
        } catch let error as VellumError {
            throw error
        } catch {
            throw VellumError.persistenceFailure(
                "Could not read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    func writeAll(_ elements: [Element]) throws {
        try FilePersistence.write(elements, to: fileURL)
    }

    func upsert(
        _ element: Element,
        sortedBy areInIncreasingOrder: (Element, Element) -> Bool
    ) throws {
        var elements = try readAll()
        if let index = elements.firstIndex(where: { $0.id == element.id }) {
            elements[index] = element
        } else {
            elements.append(element)
        }
        try writeAll(elements.sorted(by: areInIncreasingOrder))
    }

    func delete(
        id: UUID,
        sortedBy areInIncreasingOrder: (Element, Element) -> Bool
    ) throws {
        let elements = try readAll()
            .filter { $0.id != id }
            .sorted(by: areInIncreasingOrder)
        try writeAll(elements)
    }
}
