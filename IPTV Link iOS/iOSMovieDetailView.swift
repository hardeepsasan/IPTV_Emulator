#if os(iOS)
import SwiftUI

struct iOSMovieDetailView: View {
    let movie: Movie
    @ObservedObject private var client = StalkerClient.shared
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var watchlistManager: WatchlistManager
    @Environment(\.dismiss) var dismiss
    
    @State private var detailedMovie: Movie?
    @State private var tmdbMovie: TMDBMovie?
    @State private var isLoading = true
    
    var displayMovie: Movie {
        detailedMovie ?? movie
    }
    
    var resumeTime: Double {
        playbackManager.getSavedTime(for: displayMovie) ?? 0
    }
    
    var progress: Double {
        playbackManager.getProgress(for: displayMovie)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ... Header Image (unchanged)
                ZStack(alignment: .bottomLeading) {
                    AuthenticatedImage(url: displayMovie.getPosterURL(baseURL: client.portalURL), targetSize: CGSize(width: 600, height: 900), client: client)
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 450)
                        .clipped()
                        .overlay(
                            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayMovie.name)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 12) {
                            if let year = displayMovie.year, !year.isEmpty {
                                Text(year)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            if let rating = displayMovie.rating, rating != "0" {
                                Text("★ \(rating)")
                                    .font(.subheadline)
                                    .foregroundColor(.yellow)
                            }
                            
                            if let duration = displayMovie.duration, duration > 0 {
                                Text("\(duration) min")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                }
                
                // 2. Actions
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        // Main Play/Resume Button
                        Button(action: { playMovie(restart: false) }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text(resumeTime > 0 ? "Resume" : "Play")
                            }
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                        }
                        
                        Button(action: toggleWatchlist) {
                            VStack(spacing: 4) {
                                Image(systemName: watchlistManager.inWatchlist(displayMovie) ? "checkmark" : "plus")
                                Text("My List")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .frame(width: 60)
                        }
                    }
                    
                    // Restart Button (Conditional)
                    if resumeTime > 0 {
                        Button(action: { playMovie(restart: true) }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Restart")
                            }
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    if resumeTime > 0 {
                        Button(action: { playbackManager.removeFromContinueWatching(displayMovie) }) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Mark as Watched")
                            }
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    // Progress Bar
                    if progress > 0 {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                            
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: (UIScreen.main.bounds.width - 32) * progress, height: 4)
                        }
                        .cornerRadius(2)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                
                // 3. Synopsis
                VStack(alignment: .leading, spacing: 8) {
                    Text("Synopsis")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(displayMovie.description ?? tmdbMovie?.overview ?? "No description available.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .lineSpacing(4)
                }
                .padding(.horizontal)
                
                // 4. TMDB Cast (If available)
                if let cast = tmdbMovie?.cast, !cast.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cast")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(cast.prefix(10)) { member in
                                    VStack(alignment: .center, spacing: 8) {
                                        TMDBImage(url: member.profileURL, width: 80, height: 120)
                                            .cornerRadius(6)
                                        
                                        Text(member.name)
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 80)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // 5. Metadata
                VStack(alignment: .leading, spacing: 6) {
                    if let director = displayMovie.director, !director.isEmpty {
                        MetadataRow(label: "Director", value: director)
                    }
                    if let genre = displayMovie.genresStr, !genre.isEmpty {
                        MetadataRow(label: "Genre", value: genre)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .task {
            await loadDetails()
        }
    }
    
    private func loadDetails() async {
        isLoading = true
        // 1. Fetch Server Details
        if let details = try? await client.getVodInfo(movieId: movie.id) {
            self.detailedMovie = details
        }
        
        // 2. Fetch TMDB Enrichment
        let year = movie.year ?? ""
        self.tmdbMovie = await TMDBClient.shared.fetchDetails(for: movie.name, year: year)
        
        isLoading = false
    }
    
    private func playMovie(restart: Bool = false) {
        let start = restart ? 0 : resumeTime
        let info: [String: Any] = [
            "movie": displayMovie,
            "startTime": start
        ]
        NotificationCenter.default.post(name: .init("PlayMovie"), object: nil, userInfo: info)
    }
    
    private func toggleWatchlist() {
        if watchlistManager.inWatchlist(displayMovie) {
            watchlistManager.removeFromWatchlist(displayMovie)
        } else {
            watchlistManager.addToWatchlist(displayMovie)
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}
#endif
