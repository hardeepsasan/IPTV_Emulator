import Foundation
import SwiftUI
import Combine

/// Manages playback progress for Movies and Series/Episodes.
/// Persists data to UserDefaults.
@MainActor
public class PlaybackManager: ObservableObject {
    @Published public var watchingItems: [WatchingItem] = []
    
    private let saveKey = "user_continue_watching"
    
    public init() {
        load()
    }
    
    // MARK: - Public API
    
    /// Updates progress for a specific movie or episode.
    /// - Parameters:
    ///   - movie: The movie object (or episode object if it has metadata).
    ///   - time: Current playback time in seconds.
    ///   - duration: Total duration in seconds.
    public func updateProgress(movie: Movie, time: Double, duration: Double) {
        guard duration > 0 else { return }
        
        // Remove existing entry for this movie if present (to re-insert at top)
        if let index = watchingItems.firstIndex(where: { $0.id == movie.id }) {
            watchingItems.remove(at: index)
        }
        
        let progress = time / duration
        
        // If finished (> 95%), don't save or remove if exists
        if progress > 0.95 {
             save()
             return
        }
        
        // Create new item
        let item = WatchingItem(
            id: movie.id,
            movie: movie,
            currentWaitTime: time,
            duration: duration,
            lastUpdated: Date()
        )
        
        // Insert at beginning (Most Recently Watched)
        watchingItems.insert(item, at: 0)
        
        // Limit list size (optional, e.g., keep last 50 items)
        if watchingItems.count > 50 {
            watchingItems = Array(watchingItems.prefix(50))
        }
        
        save()
    }
    
    /// Returns the saved playback time for a movie, if it exists.
    public func getSavedTime(for movie: Movie) -> Double? {
        if let item = watchingItems.first(where: { $0.id == movie.id }) {
            return item.currentWaitTime
        }
        return nil
    }
    
    /// Returns the progress (0.0 to 1.0) for a movie.
    public func getProgress(for movie: Movie) -> Double {
        guard let item = watchingItems.first(where: { $0.id == movie.id }), item.duration > 0 else {
            return 0.0
        }
        return item.currentWaitTime / item.duration
    }
    
    /// Explicitly removes a movie from continue watching history.
    public func removeFromContinueWatching(_ movie: Movie) {
        if let index = watchingItems.firstIndex(where: { $0.id == movie.id }) {
            watchingItems.remove(at: index)
            save()
        }
    }
    
    /// Clears all playback history.
    public func clearHistory() {
        watchingItems.removeAll()
        save()
    }
    
    // MARK: - Persistence
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(watchingItems) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([WatchingItem].self, from: data) {
            self.watchingItems = decoded.sorted(by: { $0.lastUpdated > $1.lastUpdated })
        }
    }
}

/// Helper Model for Persistence
public struct WatchingItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let movie: Movie
    public let currentWaitTime: Double
    public let duration: Double
    public let lastUpdated: Date
}

public struct PlaybackContext: Identifiable {
    public let id: UUID
    public let url: URL
    public let title: String?
    public let movie: Movie? // If set, progress will be saved
    public let relatedEpisodes: [Movie]? // For "Up Next" overlay
    public let startTime: Double
    
    public init(id: UUID = UUID(), url: URL, title: String? = nil, movie: Movie? = nil, relatedEpisodes: [Movie]? = nil, startTime: Double = 0) {
        self.id = id
        self.url = url
        self.title = title
        self.movie = movie
        self.relatedEpisodes = relatedEpisodes
        self.startTime = startTime
    }
}
