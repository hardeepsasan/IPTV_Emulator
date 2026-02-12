import Foundation
import SwiftUI
import Combine

// Structs for GitHub API
struct GitHubTreeResponse: Decodable {
    let tree: [GitHubFile]
    let truncated: Bool
}

struct GitHubFile: Decodable {
    let path: String
    let type: String // "blob" = file, "tree" = folder
}

@MainActor
class ManifestGenerator: ObservableObject {
    static let shared = ManifestGenerator()
    
    @Published var isGenerating = false
    @Published var progressMessage = ""

    @Published var generatedJSONURL: URL?
    @Published var generatedMissingJSONURL: URL? // [NEW] For missing channels
    
    // User's Repo Details
    let repoOwner = "hardeepsasan"
    let repoName = "tv-logos"
    let branch = "main"
    
    func generateManifest(client: StalkerClient) async {
        isGenerating = true
        progressMessage = "Starting..."
        generatedJSONURL = nil
        generatedMissingJSONURL = nil
        
        do {
            // 1. Fetch All Channels (Iterating Categories)
            progressMessage = "Fetching categories..."
            let categories = try await client.getCategories(type: "itv")
            print("ManifestGen: Found \(categories.count) categories.")
            
            var uniqueChannels: [String: Channel] = [:]
            

            
            // Parallel Fetch using TaskGroup
            // We fetch arrays of channels and merge them back
            print("ManifestGen: concurrent fetch starting...")
            
            let allFetchedChannels = await withTaskGroup(of: [Channel].self) { group in
                for (_, cat) in categories.enumerated() {
                    group.addTask {
                        do {
                            // We purposefully capture 'cat' here
                            let chans = try await client.getChannels(categoryId: cat.id)
                            print("ManifestGen: Fetched \(chans.count) from \(cat.title)")
                            return chans
                        } catch {
                            print("ManifestGen: Failed to fetch cat \(cat.title): \(error)")
                            return []
                        }
                    }
                }
                
                var results: [Channel] = []
                for await channels in group {
                    results.append(contentsOf: channels)
                }
                return results
            }
            
            for ch in allFetchedChannels {
                uniqueChannels[ch.id] = ch
            }
            
            let allChannels = Array(uniqueChannels.values)
            print("ManifestGen: Found \(allChannels.count) unique channels total.")
            
            // 2. Fetch GitHub Repo Tree
            progressMessage = "Scanning GitHub Repo..."
            let filePaths = try await fetchRepoFilePaths()
            print("ManifestGen: Found \(filePaths.count) files in repo.")
            
            // 3. Match (Background Task to avoid UI Freeze)
            progressMessage = "Matching logos (Optimized)..."
            
            // Move heavy lifting to background
            let (finalLogoMap, finalMissingMap, count) = await Task.detached(priority: .userInitiated) { () -> ([String:String], [String:String], Int) in
                
                // A. Pre-compute Lookup Map for O(1) access
                // Map: "filename.png" -> ["path/to/filename.png", "other/path/filename.png"]
                var fileMap: [String: [String]] = [:]
                for path in filePaths {
                    let filename = (path as NSString).lastPathComponent.lowercased()
                    if fileMap[filename] == nil {
                        fileMap[filename] = [path]
                    } else {
                        fileMap[filename]?.append(path)
                    }
                }
                
                var tLogoMap: [String: String] = [:]
                var tMissingMap: [String: String] = [:]
                var tCount = 0
                
                let priorityFolders = [
                   "countries/united-states",
                   "countries/canada",
                   "countries/india",
                   "countries/united-kingdom",
                   "countries/australia",
                   "countries/world-europe",
                   "countries/new-zealand"
               ]
                
                func getScore(_ path: String) -> Int {
                    let lowerPath = path.lowercased()
                    for (index, folder) in priorityFolders.enumerated() {
                        if lowerPath.contains(folder) { return index }
                    }
                    return 999
                }
                
                // Helper to search using Map
                func findInMap(slug: String) -> String? {
                    // 1. Try Exact Filename Match
                    let candidates = [
                        slug + ".png",
                        slug + "-hd.png",
                        slug + "-us.png",
                        slug + "-ca.png",
                        slug + "-uk.png",
                        slug + "-au.png",
                        slug + "-nz.png",
                        slug + "-in.png"
                    ]
                    
                    var potentialPaths: [String] = []
                    
                    // Check specific candidates
                    for cand in candidates {
                        if let paths = fileMap[cand] {
                            potentialPaths.append(contentsOf: paths)
                        }
                    }
                    
                    // 2. Prefix Match (Slower, but restricted to keys starting with slug?)
                    // Iterating 10k keys is better than 10k paths * string manipulations, but still slow?
                    // Let's stick to strict suffix/candidate generation for SPEED.
                    // If we need prefix matching (e.g. "fox" finding "fox-us-4k.png"), we should add them to candidates?
                    // Actually, if we just check the most common suffixes using O(1) map, we cover 95% of cases instantly.
                    
                    if !potentialPaths.isEmpty {
                        // Sort by priority
                        potentialPaths.sort { p1, p2 in
                            let s1 = getScore(p1); let s2 = getScore(p2)
                            if s1 != s2 { return s1 < s2 }
                            return p1.count < p2.count
                        }
                        return potentialPaths.first
                    }
                    return nil
                }
                
                for channel in allChannels {
                    let name = channel.name.lowercased()
                    let cleanName = name
                        .replacingOccurrences(of: " 4k", with: "")
                        .replacingOccurrences(of: " fhd", with: "")
                        .replacingOccurrences(of: " hd", with: "")
                        .replacingOccurrences(of: " hevc", with: "")
                        .replacingOccurrences(of: " vip", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let slugExpanded = cleanName
                        .replacingOccurrences(of: "+", with: " plus")
                        .replacingOccurrences(of: "&", with: " and ")
                        .replacingOccurrences(of: " ", with: "-")
                    let safeSlugExpanded = slugExpanded.components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(.init(charactersIn: "-"))).joined()
                    
                    let slugPreserved = cleanName.replacingOccurrences(of: " ", with: "-")
                    let slugSpaced = cleanName
                    let slugCompressed = cleanName.replacingOccurrences(of: " ", with: "")
                    
                    let variations = Array(NSOrderedSet(array: [safeSlugExpanded, slugPreserved, slugSpaced, slugCompressed])).map { $0 as! String }
                    
                    var foundPath: String? = nil
                    
                    // Check variations
                    for variant in variations {
                        // Recursive fallback logic inside
                        let separators = CharacterSet(charactersIn: "- ")
                        var parts = variant.components(separatedBy: separators).filter { !$0.isEmpty }
                        
                        while !parts.isEmpty {
                            let subSlugDash = parts.joined(separator: "-")
                            let subSlugSpace = parts.joined(separator: " ")
                            
                            if let match = findInMap(slug: subSlugDash) { foundPath = match; break }
                            if let match = findInMap(slug: subSlugSpace) { foundPath = match; break }
                            
                            if parts.count > 1 {
                                parts.removeLast()
                            } else {
                                break
                            }
                        }
                        if foundPath != nil { break }
                    }
                    
                    if let matchPath = foundPath {
                        let rawURL = "https://raw.githubusercontent.com/hardeepsasan/tv-logos/main/\(matchPath)"
                        tLogoMap[channel.name.lowercased()] = rawURL
                        tCount += 1
                    } else {
                        tMissingMap[channel.name] = "https://github.com/hardeepsasan/tv-logos/blob/main/"
                    }
                }
                
                return (tLogoMap, tMissingMap, tCount)
            }.value // Await result
            
            let logoMap = finalLogoMap
            let missingMap = finalMissingMap
            let matchCount = count
            
            // 4. Sort and Serialize
            progressMessage = "Saving JSON..."

            
            // Create a sorted dictionary for pretty printing? 
            // JSONEncoder doesn't guarantee order unless we export as array, but map is standard.
            // We just encode the map.
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let jsonData = try encoder.encode(logoMap)
            
            // 5. Save Matched to Documents
            let filename = "logos_generated.json"
            if let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = docDir.appendingPathComponent(filename)
                try jsonData.write(to: fileURL)
                
                print("ManifestGen: Saved Matched to \(fileURL.path)")
                
                // PRINT MATCHED CONTENT (REMOVED per user request)
                // if let stringContent = String(data: jsonData, encoding: .utf8) { ... }
                
                self.generatedJSONURL = fileURL
                
                // 6. Save Missing content
                let missingJsonData = try encoder.encode(missingMap)
                let missingFilename = "logos_missing.json"
                let missingFileURL = docDir.appendingPathComponent(missingFilename)
                try missingJsonData.write(to: missingFileURL)
                
                print("ManifestGen: Saved Missing to \(missingFileURL.path)")
                
                // PRINT MISSING CONTENT (REMOVED per user request)
                // if let stringMissing = String(data: missingJsonData, encoding: .utf8) { ... }
                
                self.generatedMissingJSONURL = missingFileURL
                
                self.progressMessage = "Success! Matched \(matchCount)/\(allChannels.count).\nSaved generated and missing manifests(Check Console/Documents)."
            }
            
        } catch {
            print("ManifestGen: Error -> \(error)")
            progressMessage = "Error: \(error.localizedDescription)"
        }
        
        isGenerating = false
    }
    
    private func fetchRepoFilePaths() async throws -> [String] {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/git/trees/\(branch)?recursive=1"
        guard let url = URL(string: urlString) else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(GitHubTreeResponse.self, from: data)
        
        // Filter only images (png)
        return response.tree
            .filter { $0.type == "blob" && $0.path.lowercased().hasSuffix(".png") }
            .map { $0.path }
    }
    
    private func findBestMatch(for channelName: String, in filePaths: [String]) -> String? {
        // 1. Initial Cleaning (Remove resolution tags)
        let name = channelName.lowercased()
        let cleanName = name
            .replacingOccurrences(of: " 4k", with: "")
            .replacingOccurrences(of: " fhd", with: "")
            .replacingOccurrences(of: " hd", with: "")
            .replacingOccurrences(of: " hevc", with: "")
            .replacingOccurrences(of: " vip", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        // 2. Generate Slug Variations
        // We try multiple formats to catch different repo naming conventions
        // A. Standard Hyphenated Expanded: "espn+ 10" -> "espn-plus-10"
        let slugExpanded = cleanName
            .replacingOccurrences(of: "+", with: " plus")
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: " ", with: "-")
        
        let safeSlugExpanded = slugExpanded.components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(.init(charactersIn: "-"))).joined()

        // B. Hyphenated Preserved: "espn+ 10" -> "espn+-10"
        // (Some repos use symbols in filenames)
        let slugPreserved = cleanName
            .replacingOccurrences(of: " ", with: "-")
        
        // C. Spaced Preserved: "fox sports1" -> "fox sports1" (for "FOX SPORTS1.png")
        let slugSpaced = cleanName
        
        // D. Compressed: "fox sports1" -> "foxsports1"
        let slugCompressed = cleanName.replacingOccurrences(of: " ", with: "")

        // Prioritize them
        // We will try to match full slugs first, then fall back progressively for EACH variation
        let variations = [safeSlugExpanded, slugPreserved, slugSpaced, slugCompressed]
        // Remove duplicates
        let uniqueVariations = Array(NSOrderedSet(array: variations)).map { $0 as! String }
        
        
        // 3. Helper to Search for a specific slug (Strict & Suffix)
        func searchForSlug(_ currentSlug: String) -> String? {
            // A. Exact Match
            let exactFiles = [
                currentSlug + ".png",
                currentSlug + "-hd.png",
                currentSlug + "-us.png",
                currentSlug + "-ca.png"
            ]
            
            // Fast check
            for path in filePaths {
                let filename = (path as NSString).lastPathComponent.lowercased()
                if exactFiles.contains(filename) { return path }
            }
            
            // B. Priority Folder Check (Prefix)
            // If checking "fox", match "fox-us-4k.png" but be careful
            // Only strictly if not generic?
            // Let's iterate paths and check prefix
            var candidates: [String] = []
            
            for path in filePaths {
                let filename = (path as NSString).lastPathComponent.lowercased()
                
                // Prefix check: "fox-us..." starts with "fox-"
                // Handle space separator too? "fox us..." starts with "fox "
                if filename.hasPrefix(currentSlug + "-") || filename.hasPrefix(currentSlug + " ") {
                     if filename.hasSuffix(".png") {
                         candidates.append(path)
                     }
                }
            }
            
            // Sort and return best
            if !candidates.isEmpty {
                 let priorityFolders = [
                    "countries/united-states",
                    "countries/canada",
                    "countries/india",
                    "countries/united-kingdom",
                    "countries/australia",
                    "countries/world-europe",
                    "countries/new-zealand"
                ]
                
                func score(_ path: String) -> Int {
                    let lowerPath = path.lowercased()
                    for (index, folder) in priorityFolders.enumerated() {
                        if lowerPath.contains(folder) { return index }
                    }
                    return 999
                }
                
                let sorted = candidates.sorted { (p1, p2) -> Bool in
                    let s1 = score(p1); let s2 = score(p2)
                    if s1 != s2 { return s1 < s2 }
                    return p1.count < p2.count
                }
                return sorted.first
            }
            return nil
        }

        // 4. Primary Search Loop (Full Name)
        for variant in uniqueVariations {
            if let match = searchForSlug(variant) { return match }
        }
        
        // 5. Progressive Fallback Loop (Shortening)
        // We iterate each variation and shorten it independently
        // e.g. "espn-plus-10" removes "10" -> "espn-plus"
        // e.g. "espn+ 10" removes "10" -> "espn+"
        
        for variant in uniqueVariations {
            // Split by space or dash depending on what the variant looks like?
            // Actually, just split by common separators
            let separators = CharacterSet(charactersIn: "- ")
            var parts = variant.components(separatedBy: separators).filter { !$0.isEmpty }
            
            // Progressively remove last part
            while parts.count > 1 {
                parts.removeLast()
                
                // Reconstruct slug using the original separator style?
                // This is tricky. simpler to just try joining with "-" and " "
                let subSlugDash = parts.joined(separator: "-")
                let subSlugSpace = parts.joined(separator: " ")
                
                if let match = searchForSlug(subSlugDash) { return match }
                if let match = searchForSlug(subSlugSpace) { return match }
                
                // Also try + preserved if it was stripped?
                // The variant logic already handles the base char set, so just shortening is enough.
            }
        }
        
        return nil
    }
}

