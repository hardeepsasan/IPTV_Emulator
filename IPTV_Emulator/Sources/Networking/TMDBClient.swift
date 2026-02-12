import Foundation

actor TMDBClient {
    static let shared = TMDBClient()
    
    private let apiKey = "8a2379aeed908cded747b51bc0b28f31" // Hardcoded for now per user input
    private let baseURL = "https://api.themoviedb.org/3"
    
    // Cache: Sanitized Movie Name -> TMDB ID
    private var idCache: [String: Int] = [:]
    
    // Cache: TMDB ID -> Full Details
    private var detailsCache: [Int: TMDBMovie] = [:]
    private var tvDetailsCache: [Int: TMDBTVShow] = [:]
    
    private var cacheFileURL: URL? {
        // Use .cachesDirectory for guaranteed write access
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let appCacheDir = cachesDir.appendingPathComponent("IPTVLink_Cache", isDirectory: true)
        return appCacheDir.appendingPathComponent("tmdb_mapping.json")
    }
    
    private init() {
        Task {
            await loadCache()
        }
    }
    
    // MARK: - Public API
    
    func fetchDetails(for movieName: String, year: String?) async -> TMDBMovie? {
        let sanitized = sanitize(movieName)
        
        // 1. Check Memory Cache
        if let id = idCache[sanitized], let details = detailsCache[id] {
            return details
        }
        
        // 2. Resolve ID (Search)
        guard let id = await resolveID(name: sanitized, year: year) else {
            return nil
        }
        
        // 3. Fetch Full Details
        return await fetchDetails(id: id, nameKey: sanitized)
    }

    func fetchTVDetails(for showName: String, year: String?) async -> TMDBTVShow? {
        let sanitized = sanitize(showName)
        
        // 1. Check Memory Cache (Reusing idCache but maybe colliding? Ideally separate, but names are unique enough usually or we scope keys)
        // Let's scope keys for TV: "TV_showName"
        let key = "TV_" + sanitized
        
        if let id = idCache[key], let details = tvDetailsCache[id] {
             return details
        }
        
        // 2. Resolve ID
        guard let id = await resolveTVID(name: sanitized, year: year) else {
            return nil
        }
        
        // 3. Fetch Details
        return await fetchTVDetails(id: id, key: key)
    }
    
    // MARK: - Internal Logic
    
    private func resolveID(name: String, year: String?) async -> Int? {
        // Check cache first
        if let cachedId = idCache[name] { return cachedId }
        
        print("TMDB: Searching for original: '\(name)'")
        
        // Network Search
        var components = URLComponents(string: "\(baseURL)/search/movie")!
        var queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "page", value: "1")
        ]
        
        // Improve accuracy with year if available (and looks like a year)
        if let y = year, y.count == 4, Int(y) != nil {
             queryItems.append(URLQueryItem(name: "year", value: y))
             print("TMDB: Included Year Filter: \(y)")
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else { return nil }
        
        // Mask API Key for logs
        let logURL = url.absoluteString.replacingOccurrences(of: apiKey, with: "API_KEY")
        print("TMDB: Request URL: \(logURL)")
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(TMDBSearchResult.self, from: data)
            
            if let first = result.results.first {
                print("TMDB: Found Match! ID: \(first.id)")
                idCache[name] = first.id
                saveCache() // Persist mapping
                return first.id
            } else {
                print("TMDB: No results found for query: '\(name)'")
            }
        } catch {
            print("TMDB: Search Error for '\(name)': \(error)")
        }
        return nil
    }
    
    private func fetchDetails(id: Int, nameKey: String) async -> TMDBMovie? {
        if let details = detailsCache[id] { return details }
        
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)&append_to_response=credits,images"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let movie = try decoder.decode(TMDBMovie.self, from: data)
            
            detailsCache[id] = movie
            return movie
        } catch {
            print("TMDB: Details Error for ID \(id): \(error)")
        }
        return nil
    }

    private func resolveTVID(name: String, year: String?) async -> Int? {
        let key = "TV_" + name
        if let cachedId = idCache[key] { return cachedId }
        
        print("TMDB: Searching for TV Show: '\(name)'")
        
        var components = URLComponents(string: "\(baseURL)/search/tv")!
        var queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "page", value: "1")
        ]
        
        if let y = year, y.count == 4, Int(y) != nil {
             queryItems.append(URLQueryItem(name: "first_air_date_year", value: y))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(TMDBSearchResult.self, from: data) // Reusing result struct as it has 'results' list with 'id'
            
            if let first = result.results.first {
                print("TMDB: Found TV Match! ID: \(first.id)")
                idCache[key] = first.id
                saveCache()
                return first.id
            }
        } catch {
            print("TMDB: TV Search Error for '\(name)': \(error)")
        }
        return nil
    }

    private func fetchTVDetails(id: Int, key: String) async -> TMDBTVShow? {
        if let details = tvDetailsCache[id] { return details }
        
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)&append_to_response=credits,images"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let show = try decoder.decode(TMDBTVShow.self, from: data)
            
            tvDetailsCache[id] = show
            return show
        } catch {
            print("TMDB: TV Details Error for ID \(id): \(error)")
        }
        return nil
    }
    
    // MARK: - Utilities
    
    private func sanitize(_ name: String) -> String {
        // 1. Replace dots with spaces
        var s = name.replacingOccurrences(of: ".", with: " ")
        
        // 2. Remove File extensions (simple check for end of string)
        let extensions = ["mkv", "mp4", "avi"]
        for ext in extensions {
            if s.lowercased().hasSuffix(".\(ext)") {
                s = String(s.dropLast(ext.count + 1))
            }
        }
        
        // 3. Regex Patterns to remove (Quality, Source, Audio, etc.)
        // Added: CAM, TS, TELESYNC, HINDI, HQ, HD, HC, HDTC, PRE, RIP, SCREENER
        let patterns = [
            "\\(.*?\\)", "\\[.*?\\]", // Brackets
            "\\b4K\\b", "\\b1080p\\b", "\\b720p\\b", "\\bHDR\\b", "\\bHEVC\\b",
            "\\bAAC\\b", "\\bH264\\b", "\\bWEB-DL\\b", "\\bBluRay\\b", "\\bDVDRip\\b",
            "\\bCAM\\b", "\\bTS\\b", "\\bTELESYNC\\b", "\\bHINDI\\b", "\\bHQ\\b", "\\bHD\\b",
            "\\bHC\\b", "\\bHDTC\\b", "\\bPRE\\b", "\\bRIP\\b", "\\bSCREENER\\b", "\\bXviD\\b"
        ]
        
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: s.utf16.count)
                s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
            }
        }
        
        // 4. Remove trailing hyphens or empty dashes often left after removal
        // e.g. "Movie Name - " -> "Movie Name"
        s = s.replacingOccurrences(of: " - ", with: " ")
        
        // 5. Trim whitespace
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func saveCache() {
        guard let url = cacheFileURL else { return }
        do {
            // Ensure directory exists
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
            
            let data = try JSONEncoder().encode(idCache)
            try data.write(to: url)
        } catch {
            print("Failed to save TMDB cache: \(error)")
        }
    }
    
    private func loadCache() async {
        guard let url = cacheFileURL, let data = try? Data(contentsOf: url) else { return }
        if let loaded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.idCache = loaded
        }
    }
}

// MARK: - Models

struct TMDBSearchResult: Codable, Sendable {
    let results: [TMDBResultItem]
}

struct TMDBResultItem: Codable, Sendable {
    let id: Int
}

struct TMDBMovie: Codable, Identifiable, Sendable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let releaseDate: String?
    let credits: TMDBCredits?
    let images: TMDBImages?
    
    var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/original\(path)")
    }
    
    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
    
    var director: String? {
        directorMember?.name
    }
    
    var directorMember: TMDBCrewMember? {
        credits?.crew.first(where: { $0.job == "Director" })
    }
    
    var cast: [TMDBCastMember] {
        credits?.cast ?? []
    }
}

struct TMDBCredits: Codable, Sendable {
    let cast: [TMDBCastMember]
    let crew: [TMDBCrewMember]
}

struct TMDBCastMember: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    
    var profileURL: URL? {
        guard let path = profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w200\(path)")
    }
}

struct TMDBCrewMember: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let job: String
    let profilePath: String?
    
    var profileURL: URL? {
        guard let path = profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w200\(path)")
    }
}

struct TMDBImages: Codable, Sendable {
    let backdrops: [TMDBImageInfo]?
    let logos: [TMDBImageInfo]?
}

struct TMDBImageInfo: Codable, Sendable {
    let filePath: String
}

struct TMDBTVShow: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let firstAirDate: String?
    let credits: TMDBCredits?
    let images: TMDBImages?
    
    var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/original\(path)")
    }
    
    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
    
    var creator: String? {
        // TV shows define 'created_by' but usually showrunner is in crew or creator list
        // Simplified: use credits crew Job 'Executive Producer' or 'Series Director'?
        // Or just omit distinct 'director' for TV
        nil
    }
    
    var cast: [TMDBCastMember] {
        credits?.cast ?? []
    }
}
