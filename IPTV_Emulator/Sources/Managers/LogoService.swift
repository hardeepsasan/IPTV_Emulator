import Foundation
import Combine
import SwiftUI

@MainActor
class LogoService: ObservableObject {
    static let shared = LogoService()
    
    // The user's self-hosted manifest URL
    // We use the raw link from the user's fork
    private let manifestURL = URL(string: "https://raw.githubusercontent.com/hardeepsasan/tv-logos/refs/heads/main/logos.json")!
    
    @Published var logoMap: [String: String] = [:]
    
    init() {
        Task {
            await fetchManifest()
        }
    }
    
    func fetchManifest() async {
        print("LogoService: Fetching manifest from \(manifestURL)")
        do {
            let (data, _) = try await URLSession.shared.data(from: manifestURL)
            let rawMap = try JSONDecoder().decode([String: String].self, from: data)
            // Normalize keys to lowercase for case-insensitive lookup
            var normalized: [String: String] = [:]
            for (key, value) in rawMap {
                normalized[key.lowercased()] = value
            }
            self.logoMap = normalized
            print("LogoService: Loaded \(normalized.count) manual logo mappings (case-insensitive).")
        } catch {
            print("LogoService: Failed to fetch/parse manifest: \(error)")
        }
    }
    
    func getLogo(for channelName: String) -> URL? {
        // 1. Lowercase Match
        let key = channelName.lowercased()
        if let urlString = logoMap[key], let url = URL(string: urlString) {
            return url
        }
        
        return nil
    }
}
