import SwiftUI

struct ActorMoviesView: View {
    let actorName: String
    var initialMovies: [Movie]? = nil // Pre-loaded data support
    @ObservedObject var stalkerClient: StalkerClient
    @Binding var playbackContext: PlaybackContext?
    
    @State private var movies: [Movie] = []
    @State private var isLoading = true
    @State private var selectedMovie: Movie?
    @State private var selectedSeries: Movie?
    
    // Grid Setup
    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 40)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("Movies & Series featuring")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Text(actorName)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                        .padding(.bottom, 20)
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Spacer()
                        }
                        .padding(.top, 50)
                    } else if movies.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No results found in catalog.")
                                .font(.title3)
                                .foregroundColor(.gray)
                            Text("Try checking the spelling or searching for a specific movie title.")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        .padding(.top, 50)
                    } else {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(movies) { movie in
                                Button {
                                    handleSelection(movie)
                                } label: {
                                    MovieCard(movie: movie, client: stalkerClient)
                                        .frame(width: 200)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                }
                .padding(50)
            }
            .background(Color.black.ignoresSafeArea())
            .task {
                await performSearch()
            }
            // Hidden Navigation Links for Result Selection
            .background(
                VStack {
                    NavigationLink(isActive: Binding(
                        get: { selectedSeries != nil },
                        set: { if !$0 { selectedSeries = nil } }
                    )) {
                        if let series = selectedSeries {
                            SeriesDetailView(series: series, stalkerClient: stalkerClient, playbackContext: $playbackContext)
                        } else { EmptyView() }
                    } label: { EmptyView() }.hidden()
                    
                    NavigationLink(isActive: Binding(
                        get: { selectedMovie != nil },
                        set: { if !$0 { selectedMovie = nil } }
                    )) {
                        if let movie = selectedMovie {
                            MovieDetailView(movie: movie, stalkerClient: stalkerClient, playbackContext: $playbackContext)
                        } else { EmptyView() }
                    } label: { EmptyView() }.hidden()
                }
            )
        }
        .navigationViewStyle(.stack)
    }
    
    private func performSearch() async {
        // If we have pre-loaded movies, use them instantly
        if let initial = initialMovies, !initial.isEmpty {
            self.movies = initial
            self.isLoading = false
            return
        }
    
        isLoading = true
        // Add a small delay for UI transition smoothness
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        do {
            // Perform Search
            let results = try await stalkerClient.searchMovies(query: actorName)
            
            // Filter by visibility preferences
            let visible = results.filter { movie in
                guard let catId = movie.categoryId else { return true }
                return PreferenceManager.shared.isCategoryVisible(catId)
            }
            
            await MainActor.run {
                self.movies = visible
                self.isLoading = false
            }
        } catch {
            print("Actor search failed: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
    
    private func handleSelection(_ movie: Movie) {
        // 1. Check Series
        if let isSeries = movie.isSeries, isSeries == 1 {
            self.selectedSeries = movie
            return
        }
        
        // 2. Check Episode (Redirect to Series)
        if let sId = movie.seriesId, !sId.isEmpty {
             Task {
                 // Try to resolve series info for the episode
                 if let series = try? await stalkerClient.getVodInfo(movieId: sId) {
                     await MainActor.run { self.selectedSeries = series }
                 } else {
                     // Fallback: Try general search for series name if direct lookup fails
                     await MainActor.run { self.selectedMovie = movie } // Treat as movie if fail
                 }
             }
             return
        }
        
        // 3. Standard Movie
        self.selectedMovie = movie
    }
}
