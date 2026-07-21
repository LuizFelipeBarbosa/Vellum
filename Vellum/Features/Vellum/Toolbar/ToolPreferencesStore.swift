import Foundation
import Observation
import SwiftUI
import VellumCore

@MainActor
@Observable
final class ToolPreferencesStore {
    private(set) var preferences: ToolPreferences

    static let storageKey = "vellum.toolPreferences.v1"

    private let defaults: UserDefaults
    private var pendingSaveTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ToolPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = .default
        }
    }

    func update(_ mutate: (inout ToolPreferences) -> Void) {
        mutate(&preferences)
        scheduleSave()
    }

    func flush() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        writePreferences()
    }

    func setColor(_ color: CodableColor, for tool: ToolID) {
        guard let keyPath = tool.inkConfigKeyPath else { return }
        update { preferences in
            preferences[keyPath: keyPath].color = color
        }
    }

    func setWidth(_ width: Double, for tool: ToolID) {
        guard let keyPath = tool.inkConfigKeyPath else { return }
        update { preferences in
            preferences[keyPath: keyPath].width = width
        }
    }

    func setStyle(_ style: InkStyle, for tool: ToolID) {
        guard let keyPath = tool.inkConfigKeyPath else { return }
        update { preferences in
            preferences[keyPath: keyPath].style = style
        }
    }

    func addFavorite(_ color: CodableColor) {
        guard !preferences.favorites.contains(color) else { return }
        update { preferences in
            preferences.favorites.append(color)
        }
    }

    func removeFavorite(at offsets: IndexSet) {
        update { preferences in
            preferences.favorites.remove(atOffsets: offsets)
        }
    }

    func moveFavorites(fromOffsets: IndexSet, toOffset: Int) {
        update { preferences in
            preferences.favorites.move(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    func resetFavorites() {
        update { preferences in
            preferences.favorites = ToolPreferences.defaultFavorites
        }
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.writePreferences()
        }
    }

    private func writePreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
