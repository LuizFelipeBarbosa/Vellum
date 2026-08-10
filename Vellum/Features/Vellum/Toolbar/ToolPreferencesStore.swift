import Foundation
import Observation
import os
import SwiftUI
import VellumCore

@MainActor
@Observable
final class ToolPreferencesStore {
    private(set) var preferences: ToolPreferences

    static let storageKey = "vellum.toolPreferences.v1"

    private let defaults: UserDefaults
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Vellum",
        category: "ToolPreferencesStore"
    )
    private var pendingSaveTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = .default

        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            preferences = try JSONDecoder().decode(ToolPreferences.self, from: data)
        } catch {
            logger.warning(
                "Tool preferences could not be decoded; using defaults: \(error.localizedDescription, privacy: .public)"
            )
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
        do {
            let data = try JSONEncoder().encode(preferences)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            logger.error(
                "Tool preferences could not be encoded: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
