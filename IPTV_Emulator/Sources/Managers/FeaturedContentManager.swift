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
    
    // Optimization Constants
    private let targetCategoryIDs: Set<Int> = [1, 3, 6, 12, 15, 45, 63, 65]
    private let matchCacheKey = "featured_match_cache_v4"
    
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
        
        client.$cacheCount
            .combineLatest(playbackManager.$watchingItems, watchlistManager.$watchlist)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.refreshFeaturedContent()
            }
            .store(in: &cancellables)
    }
    
    func refreshFeaturedContent() {
        guard !client.movieCache.isEmpty else { return }
        if isLoading { return }
        
        isLoading = true
        
        fetchExternalFeaturedList { [weak self] externalMovies in
            guard let self = self else { return }
            
            Task {
                // 1. Try Cached Mappings (Instant)
                let cachedMatches = self.loadMatchesFromCache(for: externalMovies)
                if cachedMatches.count >= 5 { // Require decent overlap to use cache
                    print("FeaturedContentManager: Using \(cachedMatches.count) cached matches.")
                    self.updateHero(with: cachedMatches, source: .featured)
                    return
                }
                
                // 2. Perform Optimized Search (Parallel + Category Filtered + Year Aware)
                let matchedMovies = await self.findMatches(for: externalMovies)
                
                if !matchedMovies.isEmpty {
                    self.saveMatchesToCache(matchedMovies, for: externalMovies)
                    self.updateHero(with: matchedMovies, source: .featured)
                    return
                }
                
                // 3. Fallback Chain (Async)
                let allCachedMovies = Array(self.client.movieCache.values)
                
                // Fallback: Continue Watching
                let history = self.playbackManager.watchingItems
                    .filter { 
                        let progress = $0.currentWaitTime / $0.duration
                        return progress < 0.95 && progress > 0.05 
                    }
                    .sorted { $0.lastUpdated > $1.lastUpdated }
                    .prefix(5)
                    .compactMap { self.client.movieCache[$0.movie.id] }
                
                if !history.isEmpty {
                    self.updateHero(with: Array(history), source: .continueWatching)
                    return
                }
                
                // Fallback: Watchlist
                let watchlist = self.watchlistManager.watchlist
                    .prefix(5)
                    .compactMap { self.client.movieCache[$0.id] }
                    
                if !watchlist.isEmpty {
                    self.updateHero(with: Array(watchlist), source: .watchlist)
                    return
                }
                
                // Fallback: Latest Added
                let latest = allCachedMovies.sorted {
                    if let d1 = $0.added, let d2 = $1.added, d1 != d2 {
                        return d1 > d2
                    }
                    return $0.id > $1.id
                }.prefix(5)
                
                self.updateHero(with: Array(latest), source: .latestAdded)
            }
        }
    }
    
    private func updateHero(with movies: [Movie], source: HeroSource) {
        DispatchQueue.main.async {
            self.heroMovies = movies
            self.currentSource = source
            self.isLoading = false
        }
    }
    
    private func fetchExternalFeaturedList(completion: @escaping ([(title: String, year: String?)]) -> Void) {
        URLSession.shared.dataTask(with: featuredJSONURL) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let movieDicts = json["movies"] as? [[String: Any]] else {
                completion([])
                return
            }
            
            let movies = movieDicts.compactMap { d -> (title: String, year: String?)? in
                guard let title = d["title"] as? String else { return nil }
                return (title: title, year: d["year"] as? String)
            }
            
            completion(movies)
        }.resume()
    }
    
    private func findMatches(for externalMovies: [(title: String, year: String?)]) async -> [Movie] {
        let startTime = Date()
        
        let filteredMovies = client.movieCache.values.filter { movie in
            if let catIdStr = movie.categoryId, let catId = Int(catIdStr) {
                return targetCategoryIDs.contains(catId)
            }
            return false
        }
        
        print("FeaturedContentManager: Search space: \(filteredMovies.count) movies. Target: \(externalMovies.count) titles.")
        
        let normalizedCache = filteredMovies.map { movie in
            (movie: movie, normalized: FuzzyMatcher.normalize(movie.name))
        }
        
        return await withTaskGroup(of: Movie?.self) { group in
            var foundMatches: [Movie] = []
            let limit = 10
            
            for ext in externalMovies {
                group.addTask {
                    let normalizedTitle = FuzzyMatcher.normalize(ext.title)
                    for entry in normalizedCache {
                        // Check if year matches if we have it
                        if let extYear = ext.year, let movieYear = entry.movie.year {
                            // If years are different, skip even if titles match
                            if !movieYear.contains(extYear) && !extYear.contains(movieYear) {
                                continue
                            }
                        }
                        
                        if FuzzyMatcher.quickMatch(normalizedTitle, entry.normalized) {
                            return entry.movie
                        }
                    }
                    return nil
                }
            }
            
            for await match in group {
                if let match = match, !foundMatches.contains(where: { $0.id == match.id }) {
                    foundMatches.append(match)
                    if foundMatches.count >= limit {
                        group.cancelAll()
                        break
                    }
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            print("FeaturedContentManager: Search completed in \(String(format: "%.3f", duration))s. Found \(foundMatches.count) items.")
            return foundMatches
        }
    }
    
    // MARK: - Persistent Caching
    
    private func loadMatchesFromCache(for externalMovies: [(title: String, year: String?)]) -> [Movie] {
        guard let data = UserDefaults.standard.dictionary(forKey: matchCacheKey) as? [String: String] else {
            return []
        }
        
        var matches: [Movie] = []
        for ext in externalMovies {
            if let movieId = data[ext.title], let movie = client.movieCache[movieId] {
                matches.append(movie)
            }
        }
        return matches
    }
    
    private func saveMatchesToCache(_ movies: [Movie], for originalMovies: [(title: String, year: String?)]) {
        var cacheData: [String: String] = UserDefaults.standard.dictionary(forKey: matchCacheKey) as? [String: String] ?? [:]
        
        for movie in movies {
            let normalizedMovie = FuzzyMatcher.normalize(movie.name)
            if let matchingExt = originalMovies.first(where: { FuzzyMatcher.quickMatch(FuzzyMatcher.normalize($0.title), normalizedMovie) }) {
                cacheData[matchingExt.title] = movie.id
            }
        }
        
        UserDefaults.standard.set(cacheData, forKey: matchCacheKey)
    }
}

// MARK: - Helper: Fuzzy Matcher (Optimized)
fileprivate struct FuzzyMatcher {
    static func quickMatch(_ normalizedTitle: String, _ normalizedCandidate: String, threshold: Double = 0.85) -> Bool {
        // 1. Exact match is always a win
        if normalizedCandidate == normalizedTitle { return true }
        
        // 2. Strict Substring Check
        // Only allow a 'contains' match if it represents a clear title match (word boundary)
        if normalizedCandidate.contains(normalizedTitle) {
            // High confidence if it's the beginning of the name (e.g., "Gladiator 2" matches "Gladiator 2 - 4K")
            if normalizedCandidate.hasPrefix(normalizedTitle) {
                return true
            }
            
            // If it's in the middle, check word boundaries (e.g., "GOAT" shouldn't match "Black Goat")
            // Use regex for word boundary check (\b)
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: normalizedTitle))\\b"
            if normalizedCandidate.range(of: pattern, options: .regularExpression) != nil {
                // To be safe, if the candidate is much longer than the title, it's risky
                // e.g., "The" is in "The Lord of the Rings" via word boundary but shouldn't match
                if normalizedTitle.count >= (normalizedCandidate.count / 2) || normalizedTitle.count > 5 {
                    return true
                }
            }
        }
        
        // 3. Fuzzy Levenshtein (Last Resort)
        let t1 = normalizedTitle.count
        let t2 = normalizedCandidate.count
        let maxL = max(t1, t2)
        
        // Early exit for length mismatch
        let allowedDistance = Int(Double(maxL) * (1.0 - threshold))
        if abs(t1 - t2) > allowedDistance { return false }
        
        let distance = levenshtein(normalizedTitle, normalizedCandidate)
        let similarity = 1.0 - (Double(distance) / Double(maxL))
        return similarity >= threshold
    }
    
    static func normalize(_ input: String) -> String {
        // Strip common suffixes that interfere with matching
        return input.lowercased()
            .replacingOccurrences(of: " (hindi)", with: "")
            .replacingOccurrences(of: " (4k)", with: "")
            .replacingOccurrences(of: " (dual)", with: "")
            .replacingOccurrences(of: "the ", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: "")
            .filter { !$0.isPunctuation }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let s1Chars = Array(s1), s2Chars = Array(s2)
        let s1Count = s1Chars.count, s2Count = s2Chars.count
        if s1Count == 0 { return s2Count }
        if s2Count == 0 { return s1Count }
        
        var v0 = [Int](0...s2Count)
        var v1 = [Int](repeating: 0, count: s2Count + 1)
        
        for i in 0..<s1Count {
            v1[0] = i + 1
            for j in 0..<s2Count {
                let cost = s1Chars[i] == s2Chars[j] ? 0 : 1
                v1[j + 1] = min(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost)
            }
            v0 = v1
        }
        return v0[s2Count]
    }
}
