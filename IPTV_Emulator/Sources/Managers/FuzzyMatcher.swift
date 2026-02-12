import Foundation

struct FuzzyMatcher {
    /// varied threshold for matching: 0.0 to 1.0 (1.0 = exact match)
    /// We use a relaxed threshold (e.g., 0.4) because filenames often contain extra data (year, resolution, etc.)
    static func match(title: String, candidate: String, threshold: Double = 0.4) -> Bool {
        let normalizedTitle = normalize(title)
        let normalizedCandidate = normalize(candidate)
        
        // 1. Direct containment check (very common for "Dune" inside "Dune.2021.mkv")
        if normalizedCandidate.contains(normalizedTitle) {
            return true
        }
        
        // 2. Levenshtein distance for typos or slight variations
        let distance = levenshtein(normalizedTitle, normalizedCandidate)
        let maxLength = Double(max(normalizedTitle.count, normalizedCandidate.count))
        let similarity = 1.0 - (Double(distance) / maxLength)
        
        return similarity >= threshold
    }
    
    private static func normalize(_ input: String) -> String {
        return input.lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: "")
            .filter { !$0.isPunctuation }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Standard Levenshtein implementation
    private static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let s1Count = s1.count
        let s2Count = s2.count
        
        if s1Count == 0 { return s2Count }
        if s2Count == 0 { return s1Count }
        
        let s1Chars = Array(s1)
        let s2Chars = Array(s2)
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        for i in 0...s1Count { matrix[i][0] = i }
        for j in 0...s2Count { matrix[0][j] = j }
        
        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Chars[i-1] == s2Chars[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[s1Count][s2Count]
    }
}
