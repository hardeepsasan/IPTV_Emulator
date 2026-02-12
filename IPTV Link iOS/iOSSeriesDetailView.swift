#if os(iOS)
import SwiftUI

struct iOSSeriesDetailView: View {
    let series: Movie
    @ObservedObject private var client = StalkerClient.shared
    @EnvironmentObject var watchlistManager: WatchlistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @Environment(\.dismiss) var dismiss
    
    @State private var seasons: [Movie] = []
    @State private var selectedSeason: Movie?
    @State private var episodes: [Movie] = []
    @State private var isLoading = true
    @State private var isLoadingEpisodes = false
    @State private var tmdbShow: TMDBTVShow?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Header Image
                ZStack(alignment: .bottomLeading) {
                    AuthenticatedImage(url: series.getPosterURL(baseURL: client.portalURL), targetSize: CGSize(width: 600, height: 900), client: client)
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 350)
                        .clipped()
                        .overlay(
                            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(series.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 12) {
                            if let rating = series.rating, rating != "0" {
                                Text("★ \(rating)")
                                    .font(.subheadline)
                                    .foregroundColor(.yellow)
                            }
                            if let year = series.year {
                                Text(year)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                }
                
                // 2. Actions
                HStack(spacing: 20) {
                    Button(action: toggleWatchlist) {
                        HStack {
                            Image(systemName: watchlistManager.inWatchlist(series) ? "checkmark" : "plus")
                            Text("My List")
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                // 3. Synopsis
                if let overview = tmdbShow?.overview ?? series.description {
                    Text(overview)
                        .font(.body)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                        .lineLimit(4)
                }
                
                // 4. Season Picker
                if !seasons.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Seasons")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(seasons) { season in
                                    Button {
                                        Task {
                                            await selectSeason(season)
                                        }
                                    } label: {
                                        Text(season.name)
                                            .font(.subheadline)
                                            .fontWeight(selectedSeason?.id == season.id ? .bold : .regular)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(selectedSeason?.id == season.id ? Color.white : Color.white.opacity(0.1))
                                            .foregroundColor(selectedSeason?.id == season.id ? .black : .white)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // 5. Episode List
                if isLoadingEpisodes {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if !episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(episodes) { episode in
                            Button {
                                playEpisode(episode)
                            } label: {
                                HStack(spacing: 12) {
                                    // Thumbnail
                                    ZStack(alignment: .bottom) {
                                        AuthenticatedImage(url: episode.getPosterURL(baseURL: client.portalURL) ?? series.getPosterURL(baseURL: client.portalURL), targetSize: CGSize(width: 240, height: 135), client: client)
                                            .frame(width: 120, height: 68)
                                            .cornerRadius(4)
                                        
                                        let epProgress = playbackManager.getProgress(for: episode)
                                        if epProgress > 0 {
                                            ZStack(alignment: .leading) {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.3))
                                                    .frame(height: 2)
                                                
                                                Rectangle()
                                                    .fill(Color.red)
                                                    .frame(width: 120 * epProgress, height: 2)
                                            }
                                            .frame(width: 120)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(episode.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        
                                        let epResume = playbackManager.getSavedTime(for: episode) ?? 0
                                        if epResume > 0 {
                                            HStack {
                                                Text("Resume from \(formatTime(epResume))")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                
                                                Spacer()
                                                
                                                Button {
                                                    playbackManager.removeFromContinueWatching(episode)
                                                } label: {
                                                    Image(systemName: "binoculars.fill")
                                                        .foregroundColor(.green)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "play.circle")
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        isLoading = true
        // 1. Load Seasons
        do {
            let fetchedSeasons = try await client.getSeriesSeasons(seriesId: series.id)
            self.seasons = fetchedSeasons.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
            
            if let first = seasons.first {
                await selectSeason(first)
            }
        } catch {
            print("Failed to load seasons: \(error)")
        }
        
        // 2. Fetch TMDB
        let year = series.year ?? ""
        self.tmdbShow = await TMDBClient.shared.fetchTVDetails(for: series.name, year: year)
        
        isLoading = false
    }
    
    private func selectSeason(_ season: Movie) async {
        selectedSeason = season
        isLoadingEpisodes = true
        do {
            let eps = try await client.getSeasonEpisodes(seriesId: series.id, seasonId: season.id)
            self.episodes = eps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            print("Failed to load episodes: \(error)")
        }
        isLoadingEpisodes = false
    }
    
    private func playEpisode(_ episode: Movie) {
        // We need to fetch the cmd first if it's nil
        Task {
            var episodeWithCmd = episode
            if episodeWithCmd.comm == nil {
                if let files = try? await client.getEpisodeFiles(seriesId: series.id, seasonId: selectedSeason?.id ?? "", episodeId: episode.id),
                   let first = files.first {
                    episodeWithCmd.comm = first.comm
                }
            }
            
            // Inject series info for player
            episodeWithCmd.seriesName = series.name
            if episodeWithCmd.poster == nil || episodeWithCmd.poster?.isEmpty == true {
                episodeWithCmd.poster = series.poster
            }
            
            NotificationCenter.default.post(
                name: .init("PlayMovie"),
                object: nil,
                userInfo: [
                    "movie": episodeWithCmd,
                    "startTime": playbackManager.getSavedTime(for: episodeWithCmd) ?? 0
                ]
            )
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func toggleWatchlist() {
        if watchlistManager.inWatchlist(series) {
            watchlistManager.removeFromWatchlist(series)
        } else {
            watchlistManager.addToWatchlist(series)
        }
    }
}
#endif
