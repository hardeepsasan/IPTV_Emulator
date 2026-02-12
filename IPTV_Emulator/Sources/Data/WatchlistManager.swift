import Foundation
import SwiftUI
import Combine

@MainActor
public class WatchlistManager: ObservableObject {
    public static let shared = WatchlistManager()
    @Published public var watchlist: [Movie] = []
    
    private let saveKey = "user_watchlist"
    
    public init() {
        load()
    }
    
    // MARK: - Public API
    
    /// Adds a movie/series to the watchlist.
    public func addToWatchlist(_ movie: Movie) {
        // Prevent duplicates
        guard !watchlist.contains(where: { $0.id == movie.id }) else { return }
        
        // Add to top
        watchlist.insert(movie, at: 0)
        save()
    }
    
    /// Removes a movie/series from the watchlist.
    public func removeFromWatchlist(_ movie: Movie) {
        if let index = watchlist.firstIndex(where: { $0.id == movie.id }) {
            watchlist.remove(at: index)
            save()
        }
    }
    
    /// Checks if a movie/series is in the watchlist.
    public func inWatchlist(_ movie: Movie) -> Bool {
        return watchlist.contains(where: { $0.id == movie.id })
    }
    
    /// Toggles the watchlist status for a movie.
    public func toggle(_ movie: Movie) {
        if inWatchlist(movie) {
            removeFromWatchlist(movie)
        } else {
            addToWatchlist(movie)
        }
    }
    
    /// Clears the entire watchlist.
    public func clearWatchlist() {
        watchlist.removeAll()
        save()
    }
    
    // MARK: - Persistence
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(watchlist) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Movie].self, from: data) {
            self.watchlist = decoded
        }
    }
}
