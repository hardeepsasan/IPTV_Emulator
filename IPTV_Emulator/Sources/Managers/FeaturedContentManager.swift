import Foundation
import Combine
import SwiftUI

class FeaturedContentManager: ObservableObject {
    static let shared = FeaturedContentManager()
    
    @Published var heroMovies: [Movie] = []
    @Published var isLoading = false
    @Published var currentSource: HeroSource = .loading
    
    enum HeroSource {
        case loading
        case featured     // Matched from external JSON
        case continueWatching
        case watchlist
        case latestAdded
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let featuredJSONURL = URL(string: "https://raw.githubusercontent.com/hardeepsasan/IPTV_Emulator/main/featured.json")!
    
    // Dependencies
    private let client: StalkerClient
    private let playbackManager: PlaybackManager
    private let watchlistManager: WatchlistManager
    
    init(client: StalkerClient = .shared,
         playbackManager: PlaybackManager = .shared,
         watchlistManager: WatchlistManager = .shared) {
        self.client = client
        self.playbackManager = playbackManager
        self.watchlistManager = watchlistManager
        
        // Re-evaluate when dependencies change
        // We listen to cacheCount since movieCache is not @Published (to avoid UI storms)
        client.$cacheCount
            .combineLatest(playbackManager.$movieHistory, watchlistManager.$watchlist)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.refreshFeaturedContent()
            }
            .store(in: &cancellables)
    }
    
    func refreshFeaturedContent() {
        // Use movieCache which is the global index
        guard !client.movieCache.isEmpty else { return }
        
        // Prevent multiple fetches if already successful or loading
        if isLoading { return }
        
        isLoading = true
        
        // 1. Fetch External JSON
        fetchExternalFeaturedList { [weak self] titles in
            guard let self = self else { return }
            
            // 2. Try matching External Titles against Global Cache
            let matchedMovies = self.findMatches(for: titles)
            
            if !matchedMovies.isEmpty {
                self.updateHero(with: matchedMovies, source: .featured)
                return
            }
            
            let allCachedMovies = Array(self.client.movieCache.values)
            
            // 3. Fallback: Continue Watching
            // Get recent history movies that are NOT finished (progress < 0.95)
            // We re-fetch from cache to ensure valid data
            let history = self.playbackManager.movieHistory
                .filter { $0.progress < 0.95 && $0.progress > 0.05 }
                .sorted { $0.lastPlayed > $1.lastPlayed }
                .prefix(5)
                .compactMap { historyItem in
                    self.client.movieCache[historyItem.id]
                }
            
            if !history.isEmpty {
                self.updateHero(with: Array(history), source: .continueWatching)
                return
            }
            
            // 4. Fallback: Watchlist
            let watchlist = self.watchlistManager.watchlist
                .prefix(5)
                .compactMap { watchlistItem in
                    self.client.movieCache[watchlistItem.id]
                }
                
            if !watchlist.isEmpty {
                self.updateHero(with: Array(watchlist), source: .watchlist)
                return
            }
            
            // 5. Fallback: Latest Added (Last 5 movies globally by ID or Added Date)
            // Sorting all movies might be heavy if cache is huge (20k items), but usually acceptible on modern iOS.
            // Optimization: If cache is huge, maybe just take random or rely on server sort?
            // For now, sorting by ID descending is a good proxy for "Latest".
            let latest = allCachedMovies.sorted {
                // Try to use 'added' date string if available, else ID
                if let d1 = $0.added, let d2 = $1.added, d1 != d2 {
                    return d1 > d2
                }
                return $0.id > $1.id
            }.prefix(5)
            
            self.updateHero(with: Array(latest), source: .latestAdded)
        }
    }
    
    private func updateHero(with movies: [Movie], source: HeroSource) {
        DispatchQueue.main.async {
            self.heroMovies = movies
            self.currentSource = source
            self.isLoading = false
        }
    }
    
    private func fetchExternalFeaturedList(completion: @escaping ([String]) -> Void) {
        print("FeaturedContentManager: Fetching from \(featuredJSONURL.absoluteString)")
        
        URLSession.shared.dataTask(with: featuredJSONURL) { data, response, error in
            if let error = error {
                print("FeaturedContentManager: Fetch error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = data else {
                completion([])
                return
            }
            
            do {
                // Decode JSON: { "last_updated": "...", "movies": ["Title 1", ...] }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let movies = json["movies"] as? [String] {
                    print("FeaturedContentManager: Fetched \(movies.count) titles.")
                    completion(movies)
                } else {
                    print("FeaturedContentManager: Invalid JSON format")
                    completion([])
                }
            } catch {
                print("FeaturedContentManager: JSON Decode error: \(error)")
                completion([])
            }
        }.resume()
    }
    
    private func findMatches(for titles: [String]) -> [Movie] {
        var matches: [Movie] = []
        let allMovies = Array(client.movieCache.values)
        
        for title in titles {
            // Find first movie that matches fuzzy criteria
            if let match = allMovies.first(where: { FuzzyMatcher.match(title: title, candidate: $0.name) }) {
                if !matches.contains(where: { $0.id == match.id }) {
                    matches.append(match)
                }
            }
        }
        
        return matches
    }
}
