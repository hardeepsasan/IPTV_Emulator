import Foundation

public struct Category: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let alias: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case alias
    }
    
    // Explicit Memberwise Init (Required because init(from:) hides the default one)
    public init(id: String, title: String, alias: String) {
        self.id = id
        self.title = title
        self.alias = alias
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // ID: Handle String or Int
        if let idInt = try? container.decode(Int.self, forKey: .id) {
            self.id = String(idInt)
        } else if let idStr = try? container.decode(String.self, forKey: .id) {
            self.id = idStr.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Fallback
            self.id = try container.decode(String.self, forKey: .id)
        }
        
        // Title
        self.title = (try? container.decode(String.self, forKey: .title)) ?? "Unknown"
        self.alias = (try? container.decode(String.self, forKey: .alias)) ?? ""
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(alias, forKey: .alias)
    }
}

public struct Channel: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let number: String
    public let name: String
    public let cmd: String // The stream URL or command
    public let logo: String?
    public let categoryId: String?
    public let curPlaying: String? // EPG / Now Playing info
    
    public init(id: String, number: String, name: String, cmd: String, logo: String?, categoryId: String?, curPlaying: String?) {
        self.id = id
        self.number = number
        self.name = name
        self.cmd = cmd
        self.logo = logo
        self.categoryId = categoryId
        self.curPlaying = curPlaying
    }
    
    public func getLogoURL(baseURL: URL) -> URL? {
        guard let logo = logo, !logo.isEmpty else { return nil }
        if logo.hasPrefix("http") {
             return URL(string: logo)
        }
        // Handle relative paths
        return baseURL.appendingPathComponent(logo)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case number
        case name
        case cmd
        case logo = "logo_url" // Stalker often uses snake_case
        case categoryId = "tv_genre_id"
        case curPlaying = "cur_playing"
    }
}

public struct Movie: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public var description: String?
    public var comm: String? // Command/URL
    public var poster: String?
    public var year: String?
    public var rating: String?
    public var categoryId: String?
    public var isSeries: Int?
    public var seasonId: String?
    public var seriesNumber: String?
    public var isEpisode: Bool?
    
    public var director: String?
    public var actors: String?
    public var genresStr: String?
    public var added: String?
    public var seriesId: String? // Mutable to allow injection
    public var seriesName: String?
    public var duration: Int? // Duration in minutes
    
    public func getPosterURL(baseURL: URL) -> URL? {
        guard let poster = poster, !poster.isEmpty else { return nil }
        if poster.hasPrefix("http") {
             return URL(string: poster)
        }
        // Handle relative paths
        return baseURL.appendingPathComponent(poster)

    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case descr // Stalker variant 1
        case descriptionField = "description" // Stalker variant 2
        case comm = "cmd"
        case poster = "screenshot_uri"
        case year
        case rating
        case categoryId = "category_id"
        case isSeries = "is_series"
        case seasonId = "season_id"
        case seriesNumber = "series_number"
        case isEpisode = "is_episode"
        case director
        case actors
        case genresStr = "genres_str"
        case added
        case seriesId = "series_id"
        case time = "time"       // Stalker common
        case length = "length"   // Stalker variant
        case duration = "duration" // Generic fallback
    }

    // Explicit Memberwise Init (Required for Demo Data)
    public init(id: String, name: String, description: String? = nil, comm: String? = nil, poster: String? = nil, year: String? = nil, rating: String? = nil, categoryId: String? = nil, isSeries: Int? = 0, seasonId: String? = nil, seriesNumber: String? = nil, isEpisode: Bool? = false, director: String? = nil, actors: String? = nil, genresStr: String? = nil, added: String? = nil, seriesId: String? = nil, seriesName: String? = nil, duration: Int? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.comm = comm
        self.poster = poster
        self.year = year
        self.rating = rating
        self.categoryId = categoryId
        self.isSeries = isSeries
        self.seasonId = seasonId
        self.seriesNumber = seriesNumber
        self.isEpisode = isEpisode
        self.director = director
        self.actors = actors
        self.genresStr = genresStr
        self.added = added
        self.seriesId = seriesId
        self.seriesName = seriesName
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // ID Handling: Try 'id', fallback to random if missing (some streams obscure it)
        if let idString = try? container.decode(String.self, forKey: .id) {
            id = idString
        } else if let idInt = try? container.decode(Int.self, forKey: .id) {
            id = String(idInt)
        } else {
            id = UUID().uuidString
        }
        
        name = try container.decode(String.self, forKey: .name)
        
        // Description Strategy: Check 'description', then 'descr'
        if let desc = try? container.decodeIfPresent(String.self, forKey: .descriptionField) {
            description = desc
        } else {
            description = try container.decodeIfPresent(String.self, forKey: .descr)
        }
        
        comm = try container.decodeIfPresent(String.self, forKey: .comm)
        year = try container.decodeIfPresent(String.self, forKey: .year)
        rating = try container.decodeIfPresent(String.self, forKey: .rating)
        
        // Handle categoryId (String or Int)
        if let catInt = try? container.decode(Int.self, forKey: .categoryId) {
            categoryId = String(catInt)
        } else {
            categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        }
        
        director = try container.decodeIfPresent(String.self, forKey: .director)
        actors = try container.decodeIfPresent(String.self, forKey: .actors)
        genresStr = try container.decodeIfPresent(String.self, forKey: .genresStr)
        added = try container.decodeIfPresent(String.self, forKey: .added)
        seriesId = try container.decodeIfPresent(String.self, forKey: .seriesId)
        
        // Handle is_series (Stalker sends Int, sometimes String "1")
        if let seriesInt = try? container.decode(Int.self, forKey: .isSeries) {
            isSeries = seriesInt
        } else if let seriesString = try? container.decode(String.self, forKey: .isSeries), let val = Int(seriesString) {
            isSeries = val
        } else {
            isSeries = 0
        }
        
        // Handle poster being String or Bool (false)
        if let posterString = try? container.decode(String.self, forKey: .poster) {
            poster = posterString
        } else {
            poster = nil
        }
        
        // Season/Episode fields
        seasonId = try container.decodeIfPresent(String.self, forKey: .seasonId)
        seriesNumber = try container.decodeIfPresent(String.self, forKey: .seriesNumber)
        isEpisode = try container.decodeIfPresent(Bool.self, forKey: .isEpisode)

        
        // Duration Logic: Try 'time' (min), then 'length' (min), then 'duration'
        if let timeStr = try? container.decodeIfPresent(String.self, forKey: .time), let min = Int(timeStr) {
             duration = min
        } else if let timeInt = try? container.decodeIfPresent(Int.self, forKey: .time) {
             duration = timeInt
        } else if let lenStr = try? container.decodeIfPresent(String.self, forKey: .length), let min = Int(lenStr) {
             duration = min
        } else if let lenInt = try? container.decodeIfPresent(Int.self, forKey: .length) {
             duration = lenInt
        } else if let durInt = try? container.decodeIfPresent(Int.self, forKey: .duration) {
             duration = durInt
        } else {
             duration = nil
        }

    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .descriptionField) // Default write to "description"
        try container.encodeIfPresent(comm, forKey: .comm)
        try container.encodeIfPresent(poster, forKey: .poster)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(rating, forKey: .rating)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(isSeries, forKey: .isSeries)
        try container.encodeIfPresent(seasonId, forKey: .seasonId)
        try container.encodeIfPresent(seriesNumber, forKey: .seriesNumber)
        try container.encodeIfPresent(isEpisode, forKey: .isEpisode)
        try container.encodeIfPresent(director, forKey: .director)
        try container.encodeIfPresent(actors, forKey: .actors)
        try container.encodeIfPresent(genresStr, forKey: .genresStr)
        try container.encodeIfPresent(added, forKey: .added)
        try container.encodeIfPresent(seriesId, forKey: .seriesId)

        try container.encodeIfPresent(duration, forKey: .duration)
    }
    
    // Derived Metadata for UI
    public var qualityTags: [String] {
        var tags: [String] = []
        let upperName = name.uppercased()
        
        // 1. CAM / TS Detection (Low Quality Warning)
        if upperName.contains("CAM") || upperName.contains("HDCAM") || upperName.contains("TS") || upperName.contains("TELESYNC") || upperName.contains("CAMERA") {
            tags.append("CAM")
        }
        
        // 2. Resolution High to Low
        if upperName.contains("4K") || upperName.contains("UHD") || upperName.contains("2160P") {
            tags.append("4K")
        } else if upperName.contains("FHD") || upperName.contains("1080P") || upperName.contains("BLURAY") {
            tags.append("FHD")
        } else if upperName.contains("HD") || upperName.contains("720P") {
            tags.append("HD")
        }
        
        // 3. Codec / HDR
        if upperName.contains("HEVC") || upperName.contains("X265") || upperName.contains("H.265") {
            tags.append("HEVC")
        }
        if upperName.contains("HDR") {
            tags.append("HDR")
        }
        if upperName.contains("DOLBY") || upperName.contains("VISION") {
             tags.append("Dolby")
        }
        
        return tags
    }

    /// OPTIMIZATION: Returns a clean description stripped of long URLs and limited in length.
    /// This prevents the SwiftUI rendering engine from stalling on extreme strings.
    public var sanitizedDescription: String {
        guard let desc = description, !desc.isEmpty else { return "" }
        
        // 1. Efficiently remove common URL patterns to handle outliers like the 51-char URL found in Cat 6
        var clean = desc
        if let urlRange = clean.range(of: "http", options: .caseInsensitive) {
            // Cut off at the first URL. Most IPTV desc URLs are just noise/footers.
            clean = String(clean[..<urlRange.lowerBound])
        }
        
        // 2. Hard limit on length to prevent measurement overhead (1200 chars outlier in Cat 6)
        let maxChars = 600
        if clean.count > maxChars {
            clean = String(clean.prefix(maxChars)) + "..."
        }
        
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// OPTIMIZATION: Returns a clean name limited in length.
    public var cleanName: String {
        let maxLen = 100
        if name.count > maxLen {
            return String(name.prefix(maxLen)) + "..."
        }
        return name
    }
}


// extension URL: Identifiable {
//    public var id: String { absoluteString }
// }

// MARK: - Shared Helpers

/// Wrapper to allow duplicate movies (same ID) to exist in the list without SwiftUI ID conflicts.
/// Used by both iOS (Horizontal Lists) and tvOS (Grids/Lists).
public struct UniqueMovie: Identifiable, Sendable {
    public let id = UUID()
    public let movie: Movie
    
    public init(movie: Movie) {
        self.movie = movie
    }
}

/// Wrapper for URL to make it Identifiable for SwiftUI sheets/covers.
public struct IdentifiableStreamURL: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let movie: Movie?
    public let startTime: Double
    
    public init(url: URL, movie: Movie? = nil, startTime: Double = 0) {
        self.url = url
        self.movie = movie
        self.startTime = startTime
    }
}
