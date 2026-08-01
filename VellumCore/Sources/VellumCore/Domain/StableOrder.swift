import Foundation

/// Orderings whose ties do not depend on the order the elements arrived in.
///
/// Every list Vellum stores or shows is sorted by a key that repeats — `createdAt`,
/// `updatedAt`, a page `order`, a name. Elements sharing that key would otherwise land
/// in whatever order the directory scan produced, which differs between runs. Each
/// comparison therefore falls back to the element's UUID, and always ascending on it:
/// the tiebreak exists to be deterministic, not to be meaningful.
enum StableOrder {
    /// `true` when `lhs` sorts before `rhs` by an ascending `key`.
    static func ascending<Element, Key: Comparable>(
        _ lhs: Element,
        _ rhs: Element,
        by key: (Element) -> Key,
        tiebreak id: (Element) -> UUID
    ) -> Bool {
        let lhsKey = key(lhs)
        let rhsKey = key(rhs)
        if lhsKey == rhsKey {
            return id(lhs).uuidString < id(rhs).uuidString
        }
        return lhsKey < rhsKey
    }

    /// `true` when `lhs` sorts before `rhs` by a descending `key`. Ties still break on
    /// the ascending UUID, so reversing the key does not reverse the tiebreak.
    static func descending<Element, Key: Comparable>(
        _ lhs: Element,
        _ rhs: Element,
        by key: (Element) -> Key,
        tiebreak id: (Element) -> UUID
    ) -> Bool {
        let lhsKey = key(lhs)
        let rhsKey = key(rhs)
        if lhsKey == rhsKey {
            return id(lhs).uuidString < id(rhs).uuidString
        }
        return lhsKey > rhsKey
    }

    static func ascending<Element: Identifiable, Key: Comparable>(
        _ lhs: Element,
        _ rhs: Element,
        by key: (Element) -> Key
    ) -> Bool where Element.ID == UUID {
        ascending(lhs, rhs, by: key, tiebreak: \.id)
    }

    static func descending<Element: Identifiable, Key: Comparable>(
        _ lhs: Element,
        _ rhs: Element,
        by key: (Element) -> Key
    ) -> Bool where Element.ID == UUID {
        descending(lhs, rhs, by: key, tiebreak: \.id)
    }
}
