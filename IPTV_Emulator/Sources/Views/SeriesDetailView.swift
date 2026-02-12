import SwiftUI

struct SeriesDetailView: View {
    let series: Movie
    @ObservedObject var stalkerClient: StalkerClient
    @EnvironmentObject var watchlistManager: WatchlistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @Environment(\.presentationMode) var presentationMode
    
    // Global player binding
    @Binding var playbackContext: PlaybackContext?
    
    // State
    @State private var seasons: [Movie] = []
    @State private var selectedSeason: Movie?
    @State private var episodes: [Movie] = []
    @State private var selectedActor: String?
    @State private var isFetchingActor = false
    @State private var actorMovies: [Movie] = []
    
    @State private var isLoadingSeasons = true
    @State private var isLoadingEpisodes = false
    
    // TMDB Integration
    @State private var tmdbShow: TMDBTVShow?
    @State private var isTMDBLoading = false
    
    enum Field: Hashable {
        case watchlist
        case startSeries
        case season(String) // Added distinct focus for seasons
        case episode(String)
        case actor(Int) // Added focus for actors
    }
    
    @FocusState private var focusedField: Field?
    
    private var resumeEpisode: Movie? {
        playbackManager.watchingItems.first { item in
            item.movie.seriesId == series.id
        }?.movie
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            
                // MARK: - Header Section
                ZStack(alignment: .bottomLeading) {
                    // Scenario A: TMDB Backdrop is Handling Background (See .background modifier)
                    // We just need a spacer or transparent container here to push content down?
                    // actually, we need a consistent layout.
                    
                    // Scenario B: Fallback Header (Faded Poster)
                    // Only show this if TMDB backdrop is MISSING
                    if tmdbShow?.backdropURL == nil {
                         ZStack(alignment: .bottom) {
                             // 1. Background Layer (Blurred & Darkened)
                             AuthenticatedImage(url: series.getPosterURL(baseURL: stalkerClient.portalURL), targetSize: CGSize(width: 400, height: 600), client: stalkerClient)
                                 .aspectRatio(contentMode: .fill)
                                 .blur(radius: 50) // Heavy blur for background
                                 .overlay(Color.black.opacity(0.3)) // Darken for contrast
                                 .frame(height: 430)
                                 .clipped()
                             
                             // 2. Foreground Layer (Poser on Left, Fading Out)
                             HStack {
                                 AuthenticatedImage(url: series.getPosterURL(baseURL: stalkerClient.portalURL), targetSize: CGSize(width: 400, height: 600), client: stalkerClient)
                                     .aspectRatio(contentMode: .fill)
                                     .frame(width: 390, height: 430) // Match MoviesView dimensions
                                     .mask(
                                         LinearGradient(gradient: Gradient(stops: [
                                             .init(color: .black, location: 0.0),
                                             .init(color: .black, location: 0.5),
                                             .init(color: .black.opacity(0.8), location: 0.7),
                                             .init(color: .clear, location: 1.0)
                                         ]), startPoint: .leading, endPoint: .trailing)
                                     )
                                 Spacer()
                             }
                         }
                         .frame(height: 430)
                    } else {
                        // Spacer for TMDB Header (Backdrop is in root background)
                        Color.clear.frame(height: 400)
                    }

                    // Content Overlay (Title, Metadata)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tmdbShow?.name ?? series.name)
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(radius: 10)
                        
                        HStack(spacing: 12) {
                            if let rating = series.rating, rating != "0" {
                                Text("★ \(rating)")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                            
                            if let year = series.year {
                                Text(year)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        
                        // Description
                        if let desc = tmdbShow?.overview ?? series.description {
                            Text(desc)
                                .font(.system(size: 20)) // Slightly smaller for better fit
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(4)
                                .shadow(color: .black, radius: 2)
                        }
                        
                        // Extended Metadata (Genres, etc)
                        VStack(alignment: .leading, spacing: 4) {
                            if let genres = series.genresStr, !genres.isEmpty {
                                 Text("Genres: \(genres)")
                                    .font(.system(size: 16, weight: .semibold).italic())
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            // Show Server Director/Cast only if TMDB is valid? Or always?
                            // Let's rely on TMDB for Cast if available, else Server
                            if (tmdbShow?.cast.isEmpty ?? true), let actors = series.actors, !actors.isEmpty {
                                 Text("Cast: \(actors)")
                                    .font(.system(size: 16, weight: .semibold).italic())
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(40)
                    .padding(.bottom, 20) // Push up slightly
                    // Dynamic Leading Padding for Faded Poster Mode
                    .padding(.leading, tmdbShow?.backdropURL == nil ? 350 : 0) 
                }
                .edgesIgnoringSafeArea(.top)

                // MARK: - Action Buttons
                // MARK: - Action Buttons
                // Always show buttons to ensure focus trap works (ESC navigation)
                HStack(spacing: 20) {
                     // "PLAY" / "RESUME" Button
                    Button {
                        if let toPlay = resumeEpisode ?? episodes.first {
                            playEpisode(toPlay)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(episodes.isEmpty ? .gray : .red) // Dim if empty
                            
                            Text(resumeEpisode != nil ? "RESUME" : "PLAY")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundColor(focusedField == .startSeries ? .black : (episodes.isEmpty ? .gray : .white))
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 50)
                        .background(
                            focusedField == .startSeries ? Color(white: 0.9) : Color.white.opacity(0.1)
                        )
                        .clipShape(Capsule())
                        .scaleEffect(focusedField == .startSeries ? 1.05 : 1.0)
                        .shadow(color: focusedField == .startSeries ? .white.opacity(0.3) : .clear, radius: 10)
                        .animation(.spring(), value: focusedField)
                    }
                    .disabled(episodes.isEmpty) // Disable interaction if no episodes
                    .buttonStyle(FlatButtonStyle())
                    .focused($focusedField, equals: .startSeries)

                    // My List Button
                    Button {
                        if watchlistManager.inWatchlist(series) {
                            watchlistManager.removeFromWatchlist(series)
                        } else {
                            watchlistManager.addToWatchlist(series)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: watchlistManager.inWatchlist(series) ? "checkmark" : "plus")
                                .font(.system(size: 20, weight: .bold))
                            Text("MY LIST")
                                .font(.system(size: 20, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundColor(focusedField == .watchlist ? .black : .white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 30)
                        .background(
                            focusedField == .watchlist ? Color(white: 0.9) : Color.white.opacity(0.1)
                        )
                        .clipShape(Capsule())
                        .scaleEffect(focusedField == .watchlist ? 1.05 : 1.0)
                        .shadow(color: focusedField == .watchlist ? .white.opacity(0.3) : .clear, radius: 10)
                        .animation(.spring(), value: focusedField)
                    }
                    .buttonStyle(FlatButtonStyle())
                    .focused($focusedField, equals: .watchlist)
                    
                    Spacer() // Force HStack to span full width for focusSection
                }
                .padding(.horizontal, 40)
                // Remove negative padding if using TMDB backdrop? 
                // No, kept close to header
                .padding(.top, tmdbShow?.backdropURL == nil ? 10 : 20) // Standard spacing
                .padding(.bottom, 10) // Standard spacing
                .focusSection() // Allow focus jump to buttons

                // MARK: - Season Selector
                if !seasons.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(seasons) { season in
                                Button {
                                    withAnimation {
                                        selectedSeason = season
                                    }
                                    Task { await loadEpisodes(for: season) }
                                } label: {
                                    let isSelected = selectedSeason?.id == season.id
                                    let isFocused = focusedField == .season(season.id)
                                    // Check if ANY season is currently focused
                                    let isAnySeasonFocused = isSeasonFieldFocused(focusedField)
                                    
                                    // Highlight Rule:
                                    // 1. If this button is FOCUSED -> Highlight
                                    // 2. If this button is SELECTED and NO SEASON is focused (Focus is on Play button etc) -> Highlight
                                    // 3. Otherwise -> Gray/Default
                                    let showHighlight = isFocused || (isSelected && !isAnySeasonFocused)
                                    
                                    Text(cleanSeasonName(season.name)) // Use helper
                                        .font(.system(size: 24, weight: .heavy)) // Updated to 24
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8) // Shrink text if needed instead of clipping
                                        .frame(width: 220, height: 45) // Width 220 to match Episode Card (200 + 20 padding)
                                        .background(showHighlight ? Color.white : Color.white.opacity(0.15))
                                        .foregroundColor(showHighlight ? .black : .white)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(FlatButtonStyle()) // Use custom style to kill ALL system effects
                                .modifier(FocusWobbleModifier(isFocused: focusedField == .season(season.id))) // Added wobble effect
                                .focused($focusedField, equals: .season(season.id)) // Track focus
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                    .padding(.top, 20) // Standard spacing
                    .padding(.bottom, 10) // Standard spacing
                    .focusSection() // Allow focus jump to seasons
                }
                
                // (Cast & Crew moved to bottom)
                
                // (Cast & Crew moved to bottom)
                
                // Reduced Gap: Removed spacers and divider
                
                // MARK: - Episode List
                if isLoadingEpisodes {
                    HStack {
                        Spacer()
                        ProgressView("Loading Episodes...")
                        Spacer()
                    }
                    .padding()
                } else if episodes.isEmpty {
                    Text("No episodes found.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 20) {
                            ForEach(episodes) { episode in
                                Button {
                                    playEpisode(episode)
                                } label: {
                                    let isFocused = focusedField == .episode(episode.id)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Episode Thumbnail
                                        AuthenticatedImage(url: episode.getPosterURL(baseURL: stalkerClient.portalURL) ?? series.getPosterURL(baseURL: stalkerClient.portalURL), 
                                                           targetSize: CGSize(width: 200, height: 112),
                                                           client: stalkerClient)
                                            .frame(width: 200, height: 112) // 16:9 Aspect Ratio
                                            .cornerRadius(8)
                                            .overlay(
                                                Image(systemName: "play.circle.fill")
                                                    .font(.title)
                                                    .foregroundColor(.white.opacity(0.8))
                                            )
                                            .overlay(alignment: .bottom) {
                                                if playbackManager.getProgress(for: episode) > 0 {
                                                    GeometryReader { geo in
                                                        ZStack(alignment: .leading) {
                                                            Rectangle().fill(Color.black.opacity(0.5))
                                                            Rectangle().fill(Color.red)
                                                                .frame(width: geo.size.width * playbackManager.getProgress(for: episode))
                                                        }
                                                    }
                                                    .frame(height: 4)
                                                }
                                            }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            MarqueeText(
                                                text: episode.name,
                                                font: .system(size: 24, weight: .heavy),
                                                startDelay: 1.0,
                                                alignment: .leading,
                                                isFocused: isFocused
                                            )
                                            .foregroundColor(isFocused ? .black : .white)
                                            .frame(height: 35) // Increased height from 24 to 35 for larger font
                                        }
                                        .frame(width: 200)
                                    }
                                    .padding(10)
                                    .background(isFocused ? Color.white : Color.white.opacity(0.05)) // Background change
                                    .cornerRadius(12)
                                    .scaleEffect(isFocused ? 1.0 : 1.0) // Slight scale (should be safe if ZIndex ok, but user complained about overlap. I'll test Keeping it small OR removing it. Let's KEEP it small but rely on zIndex. actually LazyHStack zIndex is hard. I will REMOVE scale to be safe as per user request against "Overlap")
                                }
                                .buttonStyle(FlatButtonStyle()) // Kill system ring
                                .focused($focusedField, equals: .episode(episode.id))
                            }
                        }
                    }
                    .padding(.horizontal, 40) // Applied to ScrollView to enforce margins
                    .padding(.top, 20) // Standard spacing
                    .padding(.bottom, 20) // Standard spacing
                    .focusSection() // Allow focus jump to episodes
                }
                
                // MARK: - Cast & Crew (TMDB) (Moved to Bottom)
                if let tmdb = tmdbShow, !tmdb.cast.isEmpty {
                     // Divider
                     Divider().opacity(0.3).padding(.vertical, 10)
                     
                     VStack(alignment: .leading, spacing: 15) {
                         Text("Cast & Crew")
                             .font(.headline)
                             .foregroundColor(.white)
                             .padding(.horizontal, 40)
                         
                         ScrollView(.horizontal, showsIndicators: false) {
                             HStack(spacing: 20) {
                                  ForEach(tmdb.cast.prefix(15)) { member in
                                      Button {
                                          searchActor(member.name)
                                      } label: {
                                          let isFocused = focusedField == .actor(member.id)
                                          
                                          VStack(spacing: 5) {
                                              TMDBImage(url: member.profileURL, width: 120, height: 180)
                                                  .background(Color.gray.opacity(0.2))
                                                  .cornerRadius(8)
                                                  .shadow(radius: 4)
                                              
                                              RollingText(text: member.name, isActive: isFocused, maxWidth: 120)
                                                  .foregroundColor(isFocused ? .black : .white)
                                              
                                              Text(member.character ?? "Actor")
                                                  .font(.caption2)
                                                  .foregroundColor(isFocused ? .black.opacity(0.7) : .white.opacity(0.7))
                                                  .lineLimit(1)
                                          }
                                          .padding(10)
                                          .background(isFocused ? Color.white : Color.white.opacity(0.05))
                                          .cornerRadius(12)
                                          .scaleEffect(isFocused ? 1.1 : 1.0)
                                          .shadow(radius: isFocused ? 5 : 0)
                                          .animation(.spring(), value: focusedField)
                                      }
                                      .buttonStyle(FlatButtonStyle())
                                      .focused($focusedField, equals: .actor(member.id))
                                      .disabled(isFetchingActor)
                                  }
                             }
                             .padding(.top, 10) // Small top padding for focus scale room
                             .padding(.bottom, 20) // Bottom padding for focus scale room
                         }
                         .padding(.horizontal, 40) // Applied to ScrollView for consistent margins
                     }
                     .padding(.bottom, 20) // Bottom padding for scroll
                }
            }
        }
        .background(
            ZStack {
                Color.black.ignoresSafeArea()
                
                // TMDB Background Logic
                if let backdrop = tmdbShow?.backdropURL {
                    TMDBImage(url: backdrop, width: nil, height: nil, contentMode: .fill)
                        .ignoresSafeArea()
                        .overlay(
                            LinearGradient(gradient: Gradient(colors: [
                                .black.opacity(0.3),
                                .black.opacity(0.6),
                                .black.opacity(0.9),
                                .black
                            ]), startPoint: .top, endPoint: .bottom)
                        )
                        .transition(.opacity.animation(.easeInOut(duration: 0.8)))
                }
            }
        )
        .edgesIgnoringSafeArea(.all) // Ensure it covers the whole screen
        .seriesDetailOverlay(isFetching: isFetchingActor)
        .fullScreenCover(item: Binding<String?>(
            get: { selectedActor },
            set: { selectedActor = $0 }
        )) { actorName in
             ActorMoviesView(actorName: actorName, initialMovies: actorMovies, stalkerClient: stalkerClient, playbackContext: $playbackContext)
        }
        .task {
            await loadSeasons()
            // Default select Play button
            try? await Task.sleep(nanoseconds: 100_000_000) // Slight delay to let UI build
            focusedField = .startSeries
        }
        .task {
             // FETCH TMDB DATA
             isTMDBLoading = true
             // Ensure we check for year if available to improve accuracy
             let year = series.year ?? ""
             self.tmdbShow = await TMDBClient.shared.fetchTVDetails(for: series.name, year: year)
             isTMDBLoading = false
        }
        .toolbar(.hidden, for: .tabBar) // Hide Tab Bar on Detail Page
    }

    private func loadSeasons() async {
        isLoadingSeasons = true
        do {
            let fetchedSeasons = try await stalkerClient.getSeriesSeasons(seriesId: series.id)
            
            // SORT: Latest First (Season 7 -> Season 1)
            // Heuristic: Sort by name descending
            let sortedSeasons = fetchedSeasons.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
            self.seasons = sortedSeasons
            print("Loaded \(sortedSeasons.count) seasons for \(series.name)")
            
            // Auto-select logic:
            if let resume = resumeEpisode, let seasonId = resume.seasonId {
                 // Try to find season matching resume
                 if let match = sortedSeasons.first(where: { $0.id == seasonId }) {
                     self.selectedSeason = match
                     await loadEpisodes(for: match)
                     return
                 }
            }
            
            // Fallback: Select Latest Season (First in sorted list)
            if let first = sortedSeasons.first {
                self.selectedSeason = first
                await loadEpisodes(for: first)
            } else {
                self.episodes = []
            }
        } catch {
            print("Failed to load seasons for \(series.name): \(error)")
        }
        isLoadingSeasons = false
    }

    // Helper to clean season name "Season 1. Name... " -> "Season 1"
    private func cleanSeasonName(_ name: String) -> String {
        // Check for "Season X" pattern
        // Simple strategy: If it starts with "Season", take valid words until punctuation or just take first 2 words if they are "Season X"
        if name.lowercased().hasPrefix("season") {
            let components = name.components(separatedBy: CharacterSet(charactersIn: ".-:"))
            if let firstPart = components.first {
                return firstPart.trimmingCharacters(in: .whitespaces)
            }
        }
        return name // Fallback
    }
    
    private func loadEpisodes(for season: Movie) async {
        // Debounce? Or just simple state
        // In SwiftUI button action calls this, so it's fine.
        isLoadingEpisodes = true
        episodes = [] // clear old
        
        do {
            // Using season.id which is actually the unique ID of the season category/folder
            let eps = try await stalkerClient.getSeasonEpisodes(seriesId: series.id, seasonId: season.id)
            // Sort episodes Ascending (S01 E01 -> S01 E07) so auto-play works forward
            self.episodes = eps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            print("Loaded \(eps.count) episodes for season \(season.name)")
        } catch {
            print("Failed to load episodes for season \(season.name): \(error)")
        }
        
        isLoadingEpisodes = false
    }
    
    private func playEpisode(_ episode: Movie) {
        print("DEBUG: Attempting to play episode: \(episode.name) (id: \(episode.id))")
        
        Task {
            var commandToUse = episode.comm
            
            // Fallback: If no cmd, try fetching episode files (Quality/Language variants)
            if commandToUse == nil {
                print("DEBUG: No 'cmd' found. Fetching episode files (Series -> Season -> Episode -> Files)...")
                do {
                    // We need seriesId and seasonId.
                    // episode object likely has seasonId, but we also have `series.id` and `selectedSeason?.id` in scope.
                    // IMPORTANT: The API defines params as: specific movie_id (Series), season_id, episode_id
                    
                    let sId = series.id
                    let seasonId = episode.seasonId ?? selectedSeason?.id ?? "0"
                    
                    let files = try await stalkerClient.getEpisodeFiles(seriesId: sId, seasonId: seasonId, episodeId: episode.id)
                    
                    if let firstFile = files.first {
                        print("DEBUG: Found file: \(firstFile.name) with cmd: \(firstFile.comm ?? "nil")")
                        commandToUse = firstFile.comm
                    } else {
                        print("ERROR: No files found for episode \(episode.id)")
                    }
                    
                } catch {
                    print("ERROR: Failed to fetch episode files: \(error)")
                }
            }
            
            guard let cmd = commandToUse else {
                print("ERROR: Could not resolve 'cmd' for episode. Aborting playback.")
                return
            }
            
            print("DEBUG: Found cmd: \(cmd). Fetching link...")
        
            do {
                let streamLink = try await stalkerClient.createLink(type: "vod", cmd: cmd)
                print("DEBUG: Stream link generated: \(streamLink)")
                
                if let url = URL(string: streamLink) {
                    // Resolve Redirect to ensure AVPlayer gets the final URL
                    let finalURL = await stalkerClient.resolveRedirect(url: url)
                    
                    await MainActor.run {
                        print("DEBUG: Setting playbackContext to \(finalURL)")
                        let start = playbackManager.getSavedTime(for: episode) ?? 0
                        
                        // Copy episode to modify
                        var playingEpisode = episode
                        // Inject series poster if episode has none
                        if playingEpisode.poster == nil || playingEpisode.poster?.isEmpty == true {
                             playingEpisode.poster = series.poster
                        }
                        
                        // Inject Series Name (For Recovery/Search)
                        playingEpisode.seriesName = series.name
                        
                        self.playbackContext = PlaybackContext(
                            url: url,
                            title: episode.name,
                            movie: playingEpisode,
                            relatedEpisodes: self.episodes, // Pass FULL list for context
                            startTime: start
                        )
                    }
                } else {
                    print("ERROR: Stream link is not a valid URL")
                }
            } catch {
                print("ERROR: Failed to create link for episode: \(error)")
            }
        }
    }
    private func isSeasonFieldFocused(_ field: Field?) -> Bool {
        if case .season(_) = field {
            return true
        }
        return false
    }
    
    // MARK: - Actor Search
    private func searchActor(_ name: String) {
        isFetchingActor = true
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            do {
                let results = try await stalkerClient.searchMovies(query: name)
                 let visible = results.filter { movie in
                     guard let catId = movie.categoryId else { return true }
                     return PreferenceManager.shared.isCategoryVisible(catId)
                  }
                
                await MainActor.run {
                    self.actorMovies = visible
                    self.isFetchingActor = false
                    self.selectedActor = name
                }
            } catch {
                await MainActor.run {
                    self.isFetchingActor = false
                }
            }
        }
    }
}

// MARK: - Wobble Effect for Visual Focus Cue
struct FocusWobbleModifier: ViewModifier {
    let isFocused: Bool
    @State private var rotation: Double = 0
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onChange(of: isFocused) { focused in
                if focused {
                    // Trigger Wobble: rotate 2 degrees back and forth
                    withAnimation(Animation.linear(duration: 0.05).repeatCount(5, autoreverses: true)) {
                        rotation = 2
                    }
                    // Reset
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        // Ensure we are back on main thread if not already (asyncAfter is main queue by default but good practice)
                        withAnimation {
                            rotation = 0
                        }
                    }
                } else {
                    rotation = 0
                }
            }
    }
}
