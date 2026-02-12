import SwiftUI

struct SmartChannelLogo: View {
    let channel: Channel
    let client: StalkerClient
    var categoryName: String? = nil
    var fallbackBackground: AnyView? = nil
    var fallbackOverlay: AnyView? = nil
    
    @ObservedObject var logoService = LogoService.shared
    
    @State private var loadState: LoadState = .idle
    @State private var currentURLIndex = 0
    @State private var candidateURLs: [URL] = []
    
    enum LoadState {
        case idle
        case loading
        case success
        case failed
    }
    
    // Fallback Initial
    private var channelInitial: String {
        guard let first = channel.name.first else { return "?" }
        return String(first).uppercased()
    }
    
    // Generate Candidates with Recursive "First Word" logic
    private func generateCandidates() -> [URL] {
        var urls: [URL] = []
        
        // --- 1. Generate Name Variations ---
        // e.g. "Global News BC 4K" -> ["global news bc 4k", "global-news-bc", "global-news", "global"]
        let name = channel.name.lowercased()
        
        // Basic cleaning
        let cleanName = name
            .replacingOccurrences(of: " 4k", with: "")
            .replacingOccurrences(of: " fhd", with: "")
            .replacingOccurrences(of: " hd", with: "")
            .replacingOccurrences(of: " hevc", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        // Word-based reduction
        let words = cleanName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        
        var nameVariations: [String] = []
        
        // 1. Original (Exact match attempt)
        nameVariations.append(channel.name)
        
        // 2. Cleaned but with spaces (Critical for "Global News Toronto" match)
        // cleanName is "global news toronto" (lowercased, suffix removed)
        if cleanName != name {
            nameVariations.append(cleanName)
        }
        
        // 3. Cleaned Full Slug: "global-news-toronto"
        if !words.isEmpty {
            nameVariations.append(words.joined(separator: "-"))
        }
        
        // 3. First 2 words: "global-news"
        if words.count >= 2 {
            nameVariations.append(words.prefix(2).joined(separator: "-"))
        }
        
        // 4. First word: "global"
        if let first = words.first {
            nameVariations.append(first)
        }
        
        // --- 2. Manual Override Lookup (Check ALL variations) ---
        for variant in nameVariations {
             if let manualURL = LogoService.shared.getLogo(for: variant) {
                 print("DEBUG MANUAL: Found match for '\(variant)' (from \(channel.name)) -> \(manualURL)")
                 urls.append(manualURL)
             }
        }
        
        // --- 3. Server Logo ---
        if let logo = channel.logo, !logo.isEmpty, let url = channel.getLogoURL(baseURL: client.portalURL) {
            urls.append(url)
        }
        
        return urls
    }
    
    // Category Fallback Icon
    private var categoryIcon: String? {
        guard let cat = categoryName?.lowercased() else { return nil }
        
        if cat.contains("news") { return "newspaper" }
        if cat.contains("sport") { return "sportscourt" }
        if cat.contains("movie") || cat.contains("cinema") || cat.contains("film") { return "film" }
        if cat.contains("kid") || cat.contains("child") || cat.contains("cartoon") { return "teddybear" }
        if cat.contains("music") { return "music.note" }
        if cat.contains("doc") { return "text.book.closed" }
        if cat.contains("adult") || cat.contains("xxx") { return "hand.raised.slash" } 
        if cat.contains("entertainment") { return "tv" }
        
        return nil // Default to initial if no match
    }
    
    var body: some View {
        Group {
            if loadState == .failed || candidateURLs.isEmpty {
                 // --- FALLBACK MODE (Gradient + Icon + Name Overlay) ---
                 ZStack {
                     // 1. Background
                     if let bg = fallbackBackground {
                         bg
                     } else {
                         Color.gray.opacity(0.3)
                     }
                     
                     // 2. Icon / Initial
                     if let icon = categoryIcon {
                         Image(systemName: icon)
                             .font(.system(size: 50, weight: .light))
                             .foregroundColor(.white.opacity(0.15))
                             .rotationEffect(.degrees(-5))
                     } else {
                         Text(channelInitial)
                             .font(.system(size: 60, weight: .bold, design: .rounded))
                             .foregroundColor(.white.opacity(0.1))
                             .rotationEffect(.degrees(-10))
                     }
                     
                     // 3. Text Overlay (Name/Number) - Only shown in fallback!
                     if let overlay = fallbackOverlay {
                         overlay
                     }
                 }
            } else {
                 // --- LOGO MODE (Clean) ---
                 ZStack {
                     // Subtle dark backing
                     RoundedRectangle(cornerRadius: 12)
                         .fill(Color.black.opacity(0.6)) 
                     
                     AsyncImage(url: candidateURLs[currentURLIndex]) { phase in
                         switch phase {
                         case .empty:
                             // Show FULL fallback (bg + overlay) while loading
                             ZStack {
                                 if let bg = fallbackBackground { bg }
                                 if let overlay = fallbackOverlay { overlay }
                             }
                             
                         case .success(let image):
                             image
                                 .resizable()
                                 .aspectRatio(contentMode: .fit)
                                 .padding(10)
                                 .shadow(color: .black, radius: 4, x: 0, y: 2)
                                 .onAppear { loadState = .success }
                                 
                         case .failure(let error):
                             Color.clear.onAppear {
                                if currentURLIndex < candidateURLs.count - 1 {
                                     currentURLIndex += 1
                                 } else {
                                     loadState = .failed
                                 }
                             }
                         @unknown default:
                             EmptyView()
                         }
                     }
                     .id(candidateURLs[currentURLIndex])
                 }
            }
        }
        .onAppear {
            if candidateURLs.isEmpty {
                candidateURLs = generateCandidates()
                // Debug log only for first item to verify recursion logic
                if channel.number == "1" || currentURLIndex == -999 { 
                     print("SmartLogo: \(channel.name) -> \(candidateURLs.count) candidates")
                }
            }
        }
        .onChange(of: channel.id) { _ in
            loadState = .idle
            currentURLIndex = 0
            candidateURLs = generateCandidates()
        }
        .onChange(of: logoService.logoMap) { _ in
            // Retry when manifest loads
            loadState = .idle
            currentURLIndex = 0
            candidateURLs = generateCandidates()
        }
    }
}
