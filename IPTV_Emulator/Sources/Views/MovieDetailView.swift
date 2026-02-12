import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @ObservedObject var stalkerClient: StalkerClient
    @EnvironmentObject var watchlistManager: WatchlistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var networkMonitor: NetworkMonitor // Inject NetworkMonitor
    @Environment(\.presentationMode) var presentationMode
    
    // We bind to the global player context to trigger playback
    @Binding var playbackContext: PlaybackContext?
    
    @State private var detailedMovie: Movie?
    @State private var isLoading = false
    
    // TMDB Integration
    @State private var tmdbMovie: TMDBMovie?
    @State private var isTMDBLoading = false
    @State private var selectedActor: String?
    @State private var isFetchingActor = false
    @State private var actorMovies: [Movie] = []
    
    var displayMovie: Movie {
        detailedMovie ?? movie
    }
    
    var resumeTime: Double {
        playbackManager.getSavedTime(for: displayMovie) ?? 0
    }
    
    var progress: Double {
        playbackManager.getProgress(for: displayMovie)
    }
    
    enum Field: Hashable {
        case watchlist
        case resume
        case restart
    }
    
    @FocusState private var focusedField: Field?
    @FocusState private var focusedId: Int? // For Cast/Crew Cards
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Hero Section
                ZStack(alignment: .bottomLeading) {
                    // Backdrop / Large Poster
                    AuthenticatedImage(url: displayMovie.getPosterURL(baseURL: stalkerClient.portalURL), targetSize: CGSize(width: 1920, height: 1080), client: stalkerClient)
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                        .clipped()
                        .overlay(
                            LinearGradient(gradient: Gradient(colors: [.black.opacity(0), .black.opacity(0.8)]), startPoint: .center, endPoint: .bottom)
                        )
                        .opacity(tmdbMovie?.backdropURL != nil ? 0 : 1) // HIDE if TMDB background is active (prevents overlap)
                        .animation(.easeInOut(duration: 0.5), value: tmdbMovie?.backdropURL != nil)
                    
                    // TMDB High-Res Backdrop Overlay -> MOVED TO ROOT BACKGROUND
                    // We removed the overlapping frame here.
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text(displayMovie.name)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(radius: 5)
                        
                        HStack(spacing: 15) {
                            if let year = displayMovie.year, !year.isEmpty {
                                Badge(text: year, color: .gray)
                            }
                            if let rating = displayMovie.rating, !rating.isEmpty {
                                Badge(text: "★ \(rating)", color: .yellow)
                            }
                            
                            // Duration
                            if let duration = displayMovie.duration, duration > 0 {
                                Badge(text: "\(duration) min", color: .purple)
                            }
                            
                            if let added = displayMovie.added {
                                Text("Added: \(added.prefix(10))") // Show just date
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(30)
                }
                
                // MARK: - Description & Metadata
                VStack(alignment: .leading, spacing: 10) {
                    if let desc = displayMovie.description, !desc.isEmpty {
                        Text(desc)
                            .font(.body)
                            .foregroundColor(.gray)
                            .lineSpacing(4)
                            .lineLimit(4)
                    }
                    
                    // Small Metadata Row
                     if let genres = displayMovie.genresStr, !genres.isEmpty {
                        Text(genres)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 30)
                

                // MARK: - Action Buttons (Horizontal)
                HStack(spacing: 20) {
                    // Primary Play Button
                    Button {
                        playMovie()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(networkMonitor.isConnected ? .red : .gray) // Gray if offline
                            
                            Text(resumeTime > 0 ? "RESUME" : "PLAY")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundColor(focusedField == .resume ? .black : (networkMonitor.isConnected ? .white : .gray))
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 50)
                        .background(
                            focusedField == .resume ? Color(white: 0.9) : Color.white.opacity(0.1)
                        )
                        .clipShape(Capsule())
                        .scaleEffect(focusedField == .resume ? 1.05 : 1.0)
                        .shadow(color: focusedField == .resume ? .white.opacity(0.3) : .clear, radius: 10)
                        .animation(.spring(), value: focusedField)
                    }
                    .disabled(!networkMonitor.isConnected) // Disable if offline
                    .buttonStyle(FlatButtonStyle())
                    .focused($focusedField, equals: .resume)
                    
                    // My List
                    Button {
                        if watchlistManager.inWatchlist(displayMovie) {
                            watchlistManager.removeFromWatchlist(displayMovie)
                        } else {
                            watchlistManager.addToWatchlist(displayMovie)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: watchlistManager.inWatchlist(displayMovie) ? "checkmark" : "plus")
                                .font(.system(size: 20, weight: .bold))
                            Text("MY LIST")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 50)
                        .background(
                            focusedField == .watchlist ? Color(white: 0.9) : Color.white.opacity(0.1)
                        )
                        .clipShape(Capsule())
                        .foregroundColor(focusedField == .watchlist ? .black : .white.opacity(0.8))
                        .scaleEffect(focusedField == .watchlist ? 1.05 : 1.0)
                        .animation(.spring(), value: focusedField)
                    }
                    .buttonStyle(FlatButtonStyle())
                    .focused($focusedField, equals: .watchlist)
                    
                    // Restart (Conditional)
                    if resumeTime > 0 {
                        Button {
                            playMovie(restart: true)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 20, weight: .bold))
                                Text("RESTART")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 50)
                            .background(
                                focusedField == .restart ? Color(white: 0.9) : Color.white.opacity(0.1)
                            )
                            .clipShape(Capsule())
                            .foregroundColor(focusedField == .restart ? .black : (networkMonitor.isConnected ? .white.opacity(0.8) : .gray))
                            .scaleEffect(focusedField == .restart ? 1.05 : 1.0)
                            .animation(.spring(), value: focusedField)
                        }
                        .disabled(!networkMonitor.isConnected) // Disable if offline
                        .buttonStyle(FlatButtonStyle())
                        .focused($focusedField, equals: .restart)
                    }
                    
                    Spacer() // Force HStack to span full width for focusSection
                }
                .padding(.horizontal, 30)
                .padding(.top, 70) // Move buttons lower outside header (20 + 50)
                .focusSection() // Allow focus from anywhere below (Cast) to jump here
                
                // Progress Bar (Moved here to be with buttons)
                if progress > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                         GeometryReader { geo in
                             ZStack(alignment: .leading) {
                                 Rectangle().fill(Color.gray.opacity(0.3))
                                 Rectangle().fill(Color.red).frame(width: geo.size.width * progress)
                             }
                         }
                         .frame(height: 4)
                         .cornerRadius(2)
                    }
                    .padding(.horizontal, 30) // Align with buttons
                    .padding(.bottom, 10)
                }
                
                // MARK: - Detailed Metadata
                VStack(alignment: .leading, spacing: 10) {
                    // Show Server Director only if TMDB Director is missing (since we show Card)
                    if let director = displayMovie.director, !director.isEmpty, tmdbMovie?.directorMember == nil {
                        MetadataRow(label: "Director", value: director)
                    }
                    
                    // Show Server Cast only if TMDB Cast is missing
                    if let actors = displayMovie.actors, !actors.isEmpty, (tmdbMovie?.cast ?? []).isEmpty {
                        MetadataRow(label: "Cast", value: actors, lineLimit: 1)
                    }
                    


                    // TMDB Cast & Crew Grid
                    if let tmdb = tmdbMovie, (!tmdb.cast.isEmpty || tmdb.directorMember != nil) {
                        Color.clear.frame(height: 50) // Reduced gap by 50px as requested
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Full Cast & Crew")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.top, -30) // Moved up by 30px using negative padding
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    // 1. Director Card
                                    if let director = tmdb.directorMember {
                                        Button {
                                            searchActor(director.name)
                                        } label: {
                                            VStack(spacing: 5) {
                                                TMDBImage(url: director.profileURL, width: 120, height: 180)
                                                    .background(Color.gray.opacity(0.2))
                                                    .cornerRadius(8)
                                                    .shadow(radius: 4)
                                                
                                                RollingText(text: director.name, isActive: focusedId == director.id, maxWidth: 120)
                                                    .foregroundColor(focusedId == director.id ? .black : .white)
                                                
                                                Text("Director")
                                                    .font(.caption2)
                                                    .foregroundColor(focusedId == director.id ? .black.opacity(0.7) : .white.opacity(0.7))
                                                    .lineLimit(1)
                                            }
                                            .padding(10)
                                            .background(focusedId == director.id ? Color.white : Color.clear)
                                            .cornerRadius(12)
                                            .scaleEffect(focusedId == director.id ? 1.1 : 1.0)
                                            .shadow(radius: focusedId == director.id ? 5 : 0)
                                            .animation(.spring(), value: focusedId)
                                        }
                                        .buttonStyle(FlatButtonStyle())
                                        .focused($focusedId, equals: director.id)
                                        .disabled(isFetchingActor)
                                    }
                                    
                                    // 2. Cast Cards
                                    ForEach(tmdb.cast.prefix(15)) { member in
                                        Button {
                                            searchActor(member.name)
                                        } label: {
                                            VStack(spacing: 5) {
                                                TMDBImage(url: member.profileURL, width: 120, height: 180)
                                                    .background(Color.gray.opacity(0.2))
                                                    .cornerRadius(8)
                                                    .shadow(radius: 4)
                                                
                                                RollingText(text: member.name, isActive: focusedId == member.id, maxWidth: 120)
                                                    .foregroundColor(focusedId == member.id ? .black : .white)
                                            }
                                            .padding(10)
                                            .background(focusedId == member.id ? Color.white : Color.clear)
                                            .cornerRadius(12)
                                            .scaleEffect(focusedId == member.id ? 1.1 : 1.0)
                                            .shadow(radius: focusedId == member.id ? 5 : 0)
                                            .animation(.spring(), value: focusedId)
                                        }
                                        .buttonStyle(FlatButtonStyle())
                                        .focused($focusedId, equals: member.id)
                                        .disabled(isFetchingActor)
                                    }
                                }
                                .padding(.vertical, 20)
                                // Removed double padding to align with "Full Cast & Crew" title (inherited 30px)
                            }
                        }
                        .padding(.top, 10)
                    }                }
                .padding(.horizontal, 30) // Was .padding(30), removing top/bottom here to tighten up
                .padding(.bottom, 30)
                
                Spacer()
            }
            .padding(.bottom, 130) // Increased padding to lift content up
        }
        .edgesIgnoringSafeArea(.top)
        .edgesIgnoringSafeArea(.top)
        .seriesDetailOverlay(isFetching: isFetchingActor)
        // FULL SCREEN COVER PRESENTATION
        .fullScreenCover(item: Binding<String?>(
            get: { selectedActor },
            set: { selectedActor = $0 }
        )) { actorName in
             ActorMoviesView(actorName: actorName, initialMovies: actorMovies, stalkerClient: stalkerClient, playbackContext: $playbackContext)
        }
        .background(
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let backdrop = tmdbMovie?.backdropURL {
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
        .ignoresSafeArea()
        .task {
            await loadDetails()
        }
        .task {
             // FETCH TMDB DATA
             isTMDBLoading = true
             // Ensure we check for year if available to improve accuracy
             // Ensure we check for year if available to improve accuracy
             let year = movie.year ?? ""
             self.tmdbMovie = await TMDBClient.shared.fetchDetails(for: movie.name, year: year)
             isTMDBLoading = false
        }
        .toolbar(.hidden, for: .tabBar) // Hide Tab Bar on Detail Page
    }
    
    private func loadDetails() async {
        isLoading = true
        do {
            if let details = try await stalkerClient.getVodInfo(movieId: movie.id) {
                self.detailedMovie = details
            }
        } catch {
            print("Failed to load details for \(movie.name): \(error)")
        }
        isLoading = false
    }
    
    private func playMovie(restart: Bool = false) {
        guard let cmd = displayMovie.comm else { return }
        print("Playing movie from details: \(displayMovie.name)")
        
        Task {
            do {
                let streamLink = try await stalkerClient.createLink(type: "vod", cmd: cmd)
                if let url = URL(string: streamLink) {
                    // Resolve Redirect
                    let finalURL = await stalkerClient.resolveRedirect(url: url)
                    
                    await MainActor.run {
                        let start = restart ? 0 : resumeTime
                        self.playbackContext = PlaybackContext(
                            url: finalURL,
                            title: displayMovie.name,
                            movie: displayMovie,
                            startTime: start
                        )
                    }
                }
            } catch {
                print("Failed to create link: \(error)")
            }
        }
    }
    
    // MARK: - Actor Search
    private func searchActor(_ name: String) {
        isFetchingActor = true
        Task {
            // Small delay for UX feel (spinner appears)
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            do {
                let results = try await stalkerClient.searchMovies(query: name)
                
                 // Filter by preferences
                 let visible = results.filter { movie in
                     guard let catId = movie.categoryId else { return true }
                     return PreferenceManager.shared.isCategoryVisible(catId)
                 }
                
                await MainActor.run {
                    self.actorMovies = visible
                    self.isFetchingActor = false
                    self.selectedActor = name // Triggers Navigation
                }
            } catch {
                print("Actor search failed: \(error)")
                await MainActor.run {
                    self.isFetchingActor = false
                    // Optional: Show error alert
                }
            }
        }
    }
}

// Helper Views
private struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: 1)
            )
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String
    var lineLimit: Int? = nil
    
    var body: some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .font(.subheadline)
                .bold()
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 150, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
        }
    }
}


